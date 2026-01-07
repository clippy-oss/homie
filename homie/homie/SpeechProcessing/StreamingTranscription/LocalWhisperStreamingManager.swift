//
//  LocalWhisperStreamingManager.swift
//  homie
//
//  Streaming transcription manager using local Whisper.cpp
//  Processes audio in chunks for real-time interim results (free tier)
//

import Foundation

/// Streaming transcription manager using local Whisper.cpp model
/// Buffers audio and processes in chunks for semi-real-time transcription
final class LocalWhisperStreamingManager: StreamingTranscriptionManager, @unchecked Sendable {

    // MARK: - Configuration

    /// Duration of audio to buffer before processing (in seconds)
    private let chunkDurationSeconds: TimeInterval = 2.0

    /// Sample rate expected by Whisper (16kHz)
    private let whisperSampleRate: Int = 16000

    /// Input sample rate from AVAudioEngine (48kHz)
    private let inputSampleRate: Int = 48000

    /// Bytes per sample for Float32 audio
    private let bytesPerSample: Int = MemoryLayout<Float>.size

    // MARK: - State

    /// Whether streaming is currently active
    private var _isConnected: Bool = false
    var isConnected: Bool { _isConnected }

    /// Buffer for accumulating audio chunks
    private var audioBuffer: Data = Data()

    /// Accumulated transcription from all processed chunks
    private var accumulatedTranscription: String = ""

    /// Continuation for the async stream
    private var streamContinuation: AsyncStream<StreamingTranscriptChunk>.Continuation?

    /// Lock for thread-safe buffer access
    private let bufferLock = NSLock()

    /// Reference to the local whisper manager
    private var whisperManager: LocalWhisperManager?

    /// Processing task
    private var processingTask: Task<Void, Never>?

    // MARK: - AsyncStream

    /// Stream of transcription results
    private(set) lazy var transcriptionStream: AsyncStream<StreamingTranscriptChunk> = {
        AsyncStream { [weak self] continuation in
            self?.streamContinuation = continuation
        }
    }()

    // MARK: - Initialization

    init() {
        // Whisper manager will be initialized on startStreaming
    }

    // MARK: - StreamingTranscriptionManager Protocol

    func startStreaming() async throws {
        Logger.info("🎤 LocalWhisperStreamingManager: Starting streaming", module: "Speech")

        // Initialize whisper manager with model path
        guard let modelPath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") else {
            Logger.error("❌ LocalWhisperStreamingManager: Model not found", module: "Speech")
            throw StreamingTranscriptionError.processingFailed("Whisper model not found")
        }

        whisperManager = LocalWhisperManager(modelPath: modelPath)

        guard whisperManager?.isModelLoaded() == true else {
            Logger.error("❌ LocalWhisperStreamingManager: Failed to load model", module: "Speech")
            throw StreamingTranscriptionError.processingFailed("Failed to load Whisper model")
        }

        // Reset state
        bufferLock.lock()
        audioBuffer = Data()
        accumulatedTranscription = ""
        bufferLock.unlock()

        _isConnected = true

        // Force stream initialization
        _ = transcriptionStream

        Logger.info("✅ LocalWhisperStreamingManager: Streaming started", module: "Speech")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard _isConnected else {
            throw StreamingTranscriptionError.notConnected
        }

        // Add chunk to buffer (thread-safe)
        bufferLock.lock()
        audioBuffer.append(data)
        let currentBufferSize = audioBuffer.count
        bufferLock.unlock()

        // Calculate how many bytes we need for the chunk duration
        // Input is 48kHz Float32, so bytes needed = duration * sampleRate * bytesPerSample
        let bytesNeeded = Int(chunkDurationSeconds * Double(inputSampleRate) * Double(bytesPerSample))

        // Process when we have enough audio
        if currentBufferSize >= bytesNeeded {
            await processBufferedAudio(finalizing: false)
        }
    }

    func stopStreaming() async throws -> String? {
        Logger.info("🛑 LocalWhisperStreamingManager: Stopping streaming", module: "Speech")

        _isConnected = false

        // Process any remaining audio
        await processBufferedAudio(finalizing: true)

        // Cancel any pending processing
        processingTask?.cancel()
        processingTask = nil

        // Finish the stream
        streamContinuation?.finish()

        // Clean up whisper manager
        whisperManager?.cleanup()
        whisperManager = nil

        let finalText = accumulatedTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("✅ LocalWhisperStreamingManager: Stopped, final: \(finalText)", module: "Speech")

        return finalText.isEmpty ? nil : finalText
    }

    func cancelStreaming() {
        Logger.error("❌ LocalWhisperStreamingManager: Cancelling streaming", module: "Speech")

        _isConnected = false

        // Cancel processing
        processingTask?.cancel()
        processingTask = nil

        // Clear buffer
        bufferLock.lock()
        audioBuffer = Data()
        bufferLock.unlock()

        // Finish stream
        streamContinuation?.finish()

        // Clean up
        whisperManager?.cleanup()
        whisperManager = nil
    }

    // MARK: - Private Methods

    /// Process buffered audio through Whisper
    private func processBufferedAudio(finalizing: Bool) async {
        bufferLock.lock()
        let dataToProcess = audioBuffer
        if !finalizing {
            // Keep processing in chunks, clear the buffer for next chunk
            audioBuffer = Data()
        }
        bufferLock.unlock()

        guard !dataToProcess.isEmpty else { return }

        // Convert raw Float32 samples to WAV format for Whisper
        guard let wavData = createWAVData(from: dataToProcess) else {
            Logger.error("⚠️ LocalWhisperStreamingManager: Failed to create WAV data", module: "Speech")
            return
        }

        // Process with Whisper (on background thread to avoid blocking)
        let transcription = await Task.detached { [weak self] () -> String? in
            return self?.whisperManager?.transcribe(audioData: wavData)
        }.value

        guard let text = transcription, !text.isEmpty else { return }

        // Clean up the transcription (remove common noise annotations)
        let cleanedText = cleanTranscription(text)
        guard !cleanedText.isEmpty else { return }

        // Update accumulated transcription
        if !accumulatedTranscription.isEmpty {
            accumulatedTranscription += " "
        }
        accumulatedTranscription += cleanedText

        // Yield result to stream
        let chunk = StreamingTranscriptChunk(
            text: cleanedText,
            isFinal: finalizing,
            confidence: nil,
            speechFinal: finalizing
        )

        await MainActor.run { [weak self] in
            self?.streamContinuation?.yield(chunk)
        }
    }

    /// Create WAV data from raw Float32 samples (48kHz input)
    private func createWAVData(from rawAudioData: Data) -> Data? {
        // WAV file format constants (matching SpeechManager format)
        let sampleRate: UInt32 = UInt32(inputSampleRate) // 48kHz - Whisper will resample
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 32 // Float32
        let bytesPerSample: UInt16 = bitsPerSample / 8
        let bytesPerFrame: UInt16 = numChannels * bytesPerSample
        let bytesPerSecond: UInt32 = sampleRate * UInt32(bytesPerFrame)

        let audioDataSize = UInt32(rawAudioData.count)
        let fileSize = 36 + audioDataSize

        var wavData = Data()

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        wavData.append(withUnsafeBytes(of: UInt16(3).littleEndian) { Data($0) })   // format (3 = IEEE float)
        wavData.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bytesPerSecond.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bytesPerFrame.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: audioDataSize.littleEndian) { Data($0) })
        wavData.append(rawAudioData)

        return wavData
    }

    /// Clean up transcription by removing noise annotations
    private func cleanTranscription(_ text: String) -> String {
        var cleaned = text

        // Remove common noise annotations from Whisper
        let noisePatterns = [
            "\\[.*?\\]",           // [music], [background noise], etc.
            "\\(.*?\\)",           // (music), (inaudible), etc.
            "\\*.*?\\*",           // *music*, *cough*, etc.
            "<.*?>",               // <music>, <silence>, etc.
            "♪.*?♪"               // ♪ music ♪
        ]

        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    options: [],
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }

        // Clean up extra whitespace
        cleaned = cleaned.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

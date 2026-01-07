//
//  TranscriptionStore.swift
//  homie
//
//  Observable store for transcription state
//  Owns transcription state, delegates to streaming managers, buffers for chunked UI updates
//

import Foundation
import Combine

// MARK: - Transcription Mode

/// Current transcription mode for UI indication
enum TranscriptionMode: Equatable {
    case idle
    case local      // Free tier - local Whisper.cpp
    case cloud      // Premium - Deepgram streaming API
}

// MARK: - Transcription Error

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case notRecording
    case managerNotInitialized
    case streamingFailed(String)
    case audioProcessingFailed
    case unauthorized
    case notPremium

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "Not currently recording"
        case .managerNotInitialized:
            return "Transcription manager not initialized"
        case .streamingFailed(let message):
            return "Streaming failed: \(message)"
        case .audioProcessingFailed:
            return "Audio processing failed"
        case .unauthorized:
            return "Not authenticated"
        case .notPremium:
            return "Premium subscription required for cloud transcription"
        }
    }
}

// MARK: - TranscriptionStore

@MainActor
final class TranscriptionStore: ObservableObject {

    // MARK: - Singleton

    static let shared = TranscriptionStore()

    // MARK: - Published Properties (transcription-only scope)

    /// Whether recording/transcription is currently active
    @Published private(set) var isRecording: Bool = false

    /// Current interim transcription (buffered, updates in chunks)
    @Published private(set) var currentTranscription: String = ""

    /// Final completed transcription
    @Published private(set) var finalTranscription: String = ""

    /// Current error state, if any
    @Published private(set) var error: TranscriptionError?

    /// Current transcription mode (idle, local, cloud)
    @Published private(set) var transcriptionMode: TranscriptionMode = .idle

    // MARK: - Buffering Configuration

    /// Number of words to buffer before updating UI
    private let wordThreshold: Int = 3

    /// Maximum time between UI updates
    private let timeThreshold: TimeInterval = 0.5

    /// Buffer for accumulating words before UI update
    private var wordBuffer: [String] = []

    /// Accumulated text from flushed buffers
    private var accumulatedText: String = ""

    /// Last time the buffer was flushed
    private var lastBufferFlush: Date = Date()

    /// Timer for periodic buffer flushes
    private var bufferTimer: Timer?

    // MARK: - Dependencies

    /// Active streaming transcription manager
    private var activeManager: (any StreamingTranscriptionManager)?

    /// Task for consuming transcription stream
    private var transcriptionTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Start recording and transcription
    /// - Parameter isPremium: Whether the user has premium access (determines cloud vs local)
    func startRecording(isPremium: Bool) async throws {
        Logger.info("🎙️ TranscriptionStore: Starting recording (premium: \(isPremium))", module: "Speech")

        // Reset state
        resetState()

        // Select and initialize appropriate manager based on tier
        if isPremium {
            activeManager = DeepgramStreamingManager()
            transcriptionMode = .cloud
            Logger.info("☁️ TranscriptionStore: Using cloud transcription (Deepgram)", module: "Speech")
        } else {
            activeManager = LocalWhisperStreamingManager()
            transcriptionMode = .local
            Logger.info("📱 TranscriptionStore: Using local transcription (Whisper.cpp)", module: "Speech")
        }

        // Start streaming
        do {
            try await activeManager?.startStreaming()
            isRecording = true

            // Start consuming transcription stream
            startTranscriptionConsumer()

            // Start buffer flush timer
            startBufferTimer()

            Logger.info("✅ TranscriptionStore: Recording started", module: "Speech")
        } catch {
            Logger.error("❌ TranscriptionStore: Failed to start streaming: \(error)", module: "Speech")
            self.error = .streamingFailed(error.localizedDescription)
            transcriptionMode = .idle
            throw error
        }
    }

    /// Process an audio chunk during recording
    /// - Parameter data: Raw audio data (Float32 samples)
    func processAudioChunk(_ data: Data) async {
        guard isRecording, let manager = activeManager else { return }

        do {
            try await manager.sendAudioChunk(data)
        } catch {
            Logger.error("⚠️ TranscriptionStore: Failed to send audio chunk: \(error)", module: "Speech")
            // Don't set error state for individual chunk failures - continue recording
        }
    }

    /// Stop recording and finalize transcription
    func stopRecording() async {
        Logger.info("🛑 TranscriptionStore: Stopping recording", module: "Speech")

        guard isRecording else {
            Logger.warning("⚠️ TranscriptionStore: Not recording, nothing to stop", module: "Speech")
            return
        }

        isRecording = false
        stopBufferTimer()

        // Flush any remaining buffered words
        flushBuffer()

        // Stop streaming and get final result
        do {
            let finalText = try await activeManager?.stopStreaming()
            if let text = finalText, !text.isEmpty {
                handleFinalResult(text)
            } else if !accumulatedText.isEmpty {
                // Use accumulated text as final if no explicit final result
                finalTranscription = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Logger.info("✅ TranscriptionStore: Recording stopped, final: \(finalTranscription)", module: "Speech")
        } catch {
            Logger.error("❌ TranscriptionStore: Error stopping streaming: \(error)", module: "Speech")
            // Still finalize with accumulated text
            if !accumulatedText.isEmpty {
                finalTranscription = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Cancel transcription consumer task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Clear current transcription (it's now in final)
        currentTranscription = ""
        transcriptionMode = .idle
        activeManager = nil
    }

    /// Cancel recording without finalizing
    func cancelRecording() {
        Logger.error("❌ TranscriptionStore: Cancelling recording", module: "Speech")

        isRecording = false
        stopBufferTimer()

        // Cancel streaming
        activeManager?.cancelStreaming()

        // Cancel transcription consumer task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Reset all state
        resetState()

        Logger.info("✅ TranscriptionStore: Recording cancelled", module: "Speech")
    }

    /// Clear any error state
    func clearError() {
        error = nil
    }

    // MARK: - Private Methods

    /// Reset all state for a new recording session
    private func resetState() {
        currentTranscription = ""
        finalTranscription = ""
        error = nil
        wordBuffer = []
        accumulatedText = ""
        lastBufferFlush = Date()
    }

    /// Start consuming the transcription stream from the active manager
    private func startTranscriptionConsumer() {
        guard let manager = activeManager else { return }

        transcriptionTask = Task { [weak self] in
            for await chunk in manager.transcriptionStream {
                guard let self = self else { break }

                await MainActor.run {
                    if chunk.isFinal {
                        self.handleFinalResult(chunk.text)
                    } else {
                        self.handleInterimResult(chunk.text)
                    }
                }
            }
        }
    }

    /// Handle an interim (partial) transcription result
    private func handleInterimResult(_ text: String) {
        guard !text.isEmpty else { return }

        // Parse words from the new text
        let newWords = text.split(separator: " ").map(String.init)

        // Add to buffer
        wordBuffer.append(contentsOf: newWords)

        // Check if we should flush
        let timeSinceLastFlush = Date().timeIntervalSince(lastBufferFlush)

        if wordBuffer.count >= wordThreshold || timeSinceLastFlush >= timeThreshold {
            flushBuffer()
        }
    }

    /// Handle a final transcription result
    private func handleFinalResult(_ text: String) {
        // Flush any remaining buffer first
        flushBuffer()

        // Append to final transcription
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if finalTranscription.isEmpty {
            finalTranscription = trimmedText
        } else {
            finalTranscription += " " + trimmedText
        }

        // Reset accumulated text since it's now in final
        accumulatedText = ""
        currentTranscription = ""
    }

    /// Flush the word buffer to update UI
    private func flushBuffer() {
        guard !wordBuffer.isEmpty else { return }

        let newText = wordBuffer.joined(separator: " ")

        if accumulatedText.isEmpty {
            accumulatedText = newText
        } else {
            accumulatedText += " " + newText
        }

        // Update UI with smooth chunked update
        currentTranscription = accumulatedText

        wordBuffer = []
        lastBufferFlush = Date()
    }

    /// Start the periodic buffer flush timer
    private func startBufferTimer() {
        stopBufferTimer()

        bufferTimer = Timer.scheduledTimer(withTimeInterval: timeThreshold, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushBuffer()
            }
        }
    }

    /// Stop the buffer flush timer
    private func stopBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = nil
    }
}

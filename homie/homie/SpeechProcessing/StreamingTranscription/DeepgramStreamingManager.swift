//
//  DeepgramStreamingManager.swift
//  homie
//
//  Streaming transcription manager using Deepgram via Supabase Edge Function
//  WebSocket-based real-time transcription for premium users
//

import Foundation
import Supabase

/// Streaming transcription manager using Deepgram API
/// Connects to Supabase Edge Function which proxies to Deepgram (keeps API key secure)
///
/// NOTE: This is a "dumb executor" - auth/tier checks are handled by FeatureGateway/TranscriptionStore
final class DeepgramStreamingManager: NSObject, StreamingTranscriptionManager, @unchecked Sendable {

    // MARK: - Configuration

    /// Input sample rate from AVAudioEngine (48kHz)
    private let inputSampleRate: Int = 48000

    /// Deepgram expects 16kHz Linear16 PCM
    private let outputSampleRate: Int = 16000

    // MARK: - State

    /// Whether connected to the streaming service
    private var _isConnected: Bool = false
    var isConnected: Bool { _isConnected }

    /// WebSocket task
    private var webSocket: URLSessionWebSocketTask?

    /// URL session for WebSocket
    private var urlSession: URLSession?

    /// Continuation for the async stream
    private var streamContinuation: AsyncStream<StreamingTranscriptChunk>.Continuation?

    /// Lock for thread-safe state access
    private let stateLock = NSLock()

    /// Accumulated final transcription
    private var accumulatedFinalText: String = ""

    /// Ready state - edge function connected to Deepgram
    private var isReady: Bool = false

    // MARK: - AsyncStream

    /// Stream of transcription results
    private(set) lazy var transcriptionStream: AsyncStream<StreamingTranscriptChunk> = {
        AsyncStream { [weak self] continuation in
            self?.streamContinuation = continuation
        }
    }()

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - StreamingTranscriptionManager Protocol

    func startStreaming() async throws {
        Logger.info("☁️ DeepgramStreamingManager: Starting streaming", module: "Speech")

        // Get access token from Supabase session (caller already verified auth via FeatureGateway)
        guard let session = try? await supabase.auth.session else {
            Logger.error("❌ DeepgramStreamingManager: No active session", module: "Speech")
            throw StreamingTranscriptionError.authenticationFailed
        }
        let accessToken = session.accessToken

        // Build WebSocket URL for edge function
        // Convert https:// to wss:// for WebSocket
        let httpsURL = Config.supabaseURL
        let wssURL = httpsURL.replacingOccurrences(of: "https://", with: "wss://")
        let edgeFunctionPath = "/functions/v1/stream-transcribe-deepgram"

        guard let url = URL(string: wssURL + edgeFunctionPath) else {
            Logger.error("❌ DeepgramStreamingManager: Invalid URL", module: "Speech")
            throw StreamingTranscriptionError.connectionFailed("Invalid URL")
        }

        // Create WebSocket request with auth headers
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // Create URL session
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: request)

        // Force stream initialization
        _ = transcriptionStream

        // Start WebSocket connection
        webSocket?.resume()

        // Wait for ready signal (with timeout)
        try await waitForReady(timeout: 10.0)

        stateLock.lock()
        _isConnected = true
        accumulatedFinalText = ""
        stateLock.unlock()

        // Start receiving messages
        startReceiving()

        Logger.info("✅ DeepgramStreamingManager: Streaming started", module: "Speech")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard _isConnected, let webSocket = webSocket else {
            throw StreamingTranscriptionError.notConnected
        }

        // Convert from 48kHz Float32 to 16kHz Linear16 PCM
        guard let pcmData = convertToLinear16PCM(data) else {
            Logger.error("⚠️ DeepgramStreamingManager: Failed to convert audio", module: "Speech")
            return
        }

        // Send as binary message
        do {
            try await webSocket.send(.data(pcmData))
        } catch {
            Logger.error("⚠️ DeepgramStreamingManager: Failed to send chunk: \(error)", module: "Speech")
            throw StreamingTranscriptionError.connectionFailed(error.localizedDescription)
        }
    }

    func stopStreaming() async throws -> String? {
        Logger.info("🛑 DeepgramStreamingManager: Stopping streaming", module: "Speech")

        stateLock.lock()
        _isConnected = false
        let finalText = accumulatedFinalText
        stateLock.unlock()

        // Close WebSocket gracefully
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Finish the stream
        streamContinuation?.finish()

        Logger.info("✅ DeepgramStreamingManager: Stopped, final: \(finalText)", module: "Speech")
        return finalText.isEmpty ? nil : finalText
    }

    func cancelStreaming() {
        Logger.error("❌ DeepgramStreamingManager: Cancelling streaming", module: "Speech")

        stateLock.lock()
        _isConnected = false
        stateLock.unlock()

        // Close WebSocket
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Finish stream
        streamContinuation?.finish()
    }

    // MARK: - Private Methods

    /// Wait for the edge function to signal it's ready
    private func waitForReady(timeout: TimeInterval) async throws {
        let startTime = Date()

        while !isReady {
            if Date().timeIntervalSince(startTime) > timeout {
                throw StreamingTranscriptionError.timeout
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    /// Start receiving messages from WebSocket
    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving if still connected
                if self._isConnected {
                    self.startReceiving()
                }

            case .failure(let error):
                Logger.error("❌ DeepgramStreamingManager: Receive error: \(error)", module: "Speech")
                self.stateLock.lock()
                self._isConnected = false
                self.stateLock.unlock()
                self.streamContinuation?.finish()
            }
        }
    }

    /// Handle incoming WebSocket message
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseJSONMessage(text)

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseJSONMessage(text)
            }

        @unknown default:
            break
        }
    }

    /// Parse JSON message from Deepgram (via edge function)
    private func parseJSONMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            // Try to parse as our custom message first
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Handle ready signal from edge function
                if let type = json["type"] as? String, type == "ready" {
                    isReady = true
                    return
                }

                // Handle error from edge function
                if let type = json["type"] as? String, type == "error" {
                    let message = json["message"] as? String ?? "Unknown error"
                    Logger.error("❌ DeepgramStreamingManager: Server error: \(message)", module: "Speech")
                    return
                }

                // Parse Deepgram response
                if let response = try? JSONDecoder().decode(DeepgramResponse.self, from: data) {
                    handleDeepgramResponse(response)
                }
            }
        } catch {
            Logger.error("⚠️ DeepgramStreamingManager: Failed to parse message: \(error)", module: "Speech")
        }
    }

    /// Handle parsed Deepgram response
    private func handleDeepgramResponse(_ response: DeepgramResponse) {
        // Get transcription from first alternative
        guard let transcript = response.channel?.alternatives?.first?.transcript,
              !transcript.isEmpty else {
            return
        }

        // Track final transcriptions
        if response.isFinal == true {
            stateLock.lock()
            if !accumulatedFinalText.isEmpty {
                accumulatedFinalText += " "
            }
            accumulatedFinalText += transcript
            stateLock.unlock()
        }

        // Create chunk and yield to stream
        let chunk = StreamingTranscriptChunk(
            text: transcript,
            isFinal: response.isFinal ?? false,
            confidence: response.channel?.alternatives?.first?.confidence,
            speechFinal: response.speechFinal ?? false
        )

        streamContinuation?.yield(chunk)
    }

    /// Convert 48kHz Float32 audio to 16kHz Linear16 PCM
    private func convertToLinear16PCM(_ inputData: Data) -> Data? {
        // Input: 48kHz Float32 samples
        // Output: 16kHz Linear16 (Int16) samples

        let inputSamples = inputData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }

        guard !inputSamples.isEmpty else { return nil }

        // Resample from 48kHz to 16kHz (ratio of 3)
        let ratio: Float = Float(inputSampleRate) / Float(outputSampleRate)
        let outputLength = Int(Float(inputSamples.count) / ratio)

        guard outputLength > 0 else { return nil }

        var outputSamples = [Int16](repeating: 0, count: outputLength)

        // Linear interpolation resampling and convert to Int16
        for i in 0..<outputLength {
            let sourceIndex = Float(i) * ratio
            let index = Int(sourceIndex)
            let fraction = sourceIndex - Float(index)

            var sample: Float
            if index + 1 < inputSamples.count {
                sample = inputSamples[index] * (1.0 - fraction) + inputSamples[index + 1] * fraction
            } else if index < inputSamples.count {
                sample = inputSamples[index]
            } else {
                sample = 0
            }

            // Clamp and convert to Int16
            sample = max(-1.0, min(1.0, sample))
            outputSamples[i] = Int16(sample * 32767.0)
        }

        // Convert to Data
        return outputSamples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension DeepgramStreamingManager: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Logger.info("✅ DeepgramStreamingManager: WebSocket opened", module: "Speech")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Logger.info("🔌 DeepgramStreamingManager: WebSocket closed, code: \(closeCode)", module: "Speech")
        stateLock.lock()
        _isConnected = false
        stateLock.unlock()
        streamContinuation?.finish()
    }
}

// MARK: - Deepgram Response Models

/// Deepgram streaming transcription response
private struct DeepgramResponse: Codable {
    let type: String?
    let isFinal: Bool?
    let speechFinal: Bool?
    let channel: DeepgramChannel?

    enum CodingKeys: String, CodingKey {
        case type
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case channel
    }
}

private struct DeepgramChannel: Codable {
    let alternatives: [DeepgramAlternative]?
}

private struct DeepgramAlternative: Codable {
    let transcript: String?
    let confidence: Float?
}

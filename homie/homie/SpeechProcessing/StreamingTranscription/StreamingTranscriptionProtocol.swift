//
//  StreamingTranscriptionProtocol.swift
//  homie
//
//  Protocol defining the interface for streaming transcription managers
//  Both local (Whisper.cpp) and cloud (Deepgram) implementations conform to this
//

import Foundation

// MARK: - Streaming Transcript Chunk

/// Represents a chunk of transcribed text from a streaming session
struct StreamingTranscriptChunk: Equatable, Sendable {
    /// The transcribed text for this chunk
    let text: String

    /// Whether this is a final result (won't change) or interim (may be revised)
    let isFinal: Bool

    /// Confidence score from 0.0 to 1.0, if available
    let confidence: Float?

    /// Whether this marks the end of a speech segment (pause detected)
    let speechFinal: Bool

    init(
        text: String,
        isFinal: Bool = false,
        confidence: Float? = nil,
        speechFinal: Bool = false
    ) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.speechFinal = speechFinal
    }
}

// MARK: - Streaming Transcription Manager Protocol

/// Protocol for streaming transcription implementations
/// Supports real-time audio chunk processing with interim results
protocol StreamingTranscriptionManager: AnyObject, Sendable {

    /// Start a streaming transcription session
    /// - Throws: Error if streaming cannot be started (auth, connection, etc.)
    func startStreaming() async throws

    /// Send an audio chunk for processing
    /// - Parameter data: Raw audio data (format depends on implementation)
    /// - Throws: Error if chunk cannot be sent
    func sendAudioChunk(_ data: Data) async throws

    /// Stop the streaming session and get final result
    /// - Returns: Final transcription text, or nil if no speech detected
    /// - Throws: Error if stopping fails
    func stopStreaming() async throws -> String?

    /// Cancel the streaming session immediately without finalizing
    func cancelStreaming()

    /// Stream of transcription results (interim and final)
    /// Yields chunks as they become available from the transcription engine
    var transcriptionStream: AsyncStream<StreamingTranscriptChunk> { get }

    /// Whether the streaming session is currently active/connected
    var isConnected: Bool { get }
}

// MARK: - Streaming Transcription Error

/// Errors that can occur during streaming transcription
enum StreamingTranscriptionError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case authenticationFailed
    case premiumRequired
    case invalidAudioFormat
    case processingFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to transcription service"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "Authentication failed"
        case .premiumRequired:
            return "Premium subscription required"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .timeout:
            return "Connection timed out"
        }
    }
}

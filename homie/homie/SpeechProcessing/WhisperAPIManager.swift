import Foundation
import Supabase

/// Manages transcription using OpenAI's Whisper API via Supabase Edge Function
/// SECURE: API key stays on server, client only sends audio data
///
/// Supports both batch transcription (OpenAI Whisper) and streaming (Deepgram)
/// NOTE: This is a "dumb executor" - auth/tier checks are handled by FeatureGateway
class WhisperAPIManager {

    // MARK: - Streaming Support

    /// Streaming manager for real-time transcription (uses Deepgram)
    private lazy var streamingManager = DeepgramStreamingManager()

    init() {
        // No API key needed - it stays on the server
    }

    // MARK: - Streaming Methods

    /// Start streaming transcription session
    /// Uses Deepgram via edge function for real-time results
    /// - Returns: AsyncStream of transcription chunks
    func startStreamTranscription() async throws -> AsyncStream<StreamingTranscriptChunk> {
        Logger.info("🌐 WhisperAPIManager: Starting streaming transcription...", module: "Speech")
        try await streamingManager.startStreaming()
        return streamingManager.transcriptionStream
    }

    /// Send audio chunk during streaming session
    /// - Parameter data: Raw Float32 audio data (48kHz)
    func sendAudioChunk(_ data: Data) async throws {
        try await streamingManager.sendAudioChunk(data)
    }

    /// Stop streaming transcription and get final result
    /// - Returns: Final accumulated transcription text
    func stopStreamTranscription() async throws -> String? {
        Logger.info("🌐 WhisperAPIManager: Stopping streaming transcription...", module: "Speech")
        return try await streamingManager.stopStreaming()
    }

    /// Cancel streaming transcription without finalizing
    func cancelStreamTranscription() {
        Logger.info("🌐 WhisperAPIManager: Cancelling streaming transcription...", module: "Speech")
        streamingManager.cancelStreaming()
    }

    /// Whether streaming is currently active
    var isStreaming: Bool {
        streamingManager.isConnected
    }

    // MARK: - Batch Transcription

    /// Transcribe audio data using OpenAI Whisper API (via secure Edge Function)
    /// NOTE: Auth/tier checks are handled by FeatureGateway - this is a dumb executor
    /// - Parameter audioData: WAV format audio data
    /// - Returns: Transcribed text or nil if transcription fails
    func transcribe(audioData: Data) async throws -> String? {
        Logger.info("🌐 WhisperAPIManager: Starting secure API transcription...", module: "Speech")
        Logger.info("📊 Audio data size: \(audioData.count) bytes", module: "Speech")

        // Get access token from Supabase session (caller already verified auth)
        guard let session = try? await supabase.auth.session else {
            Logger.error("❌ WhisperAPIManager: No active session", module: "Speech")
            throw WhisperAPIError.noSession
        }
        let accessToken = session.accessToken
        
        // Call Supabase Edge Function (API key stays on server)
        let supabaseURL = Config.supabaseURL
        let edgeFunctionURL = "\(supabaseURL)/functions/v1/transcribe-with-whisper"
        
        guard let url = URL(string: edgeFunctionURL) else {
            throw WhisperAPIError.invalidURL
        }
        
        // Create multipart form data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart form data
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Note: Language parameter is omitted to allow auto-detection
        // Whisper API supports 99+ languages and will auto-detect the language
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Make API request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperAPIError.invalidResponse
        }
        
        Logger.info("🌐 WhisperAPIManager: API response status: \(httpResponse.statusCode)", module: "Speech")
        
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
            // This shouldn't happen if FeatureGateway is used correctly
            Logger.error("❌ WhisperAPIManager: Auth error (status \(httpResponse.statusCode)) - caller should use FeatureGateway", module: "Speech")
            throw WhisperAPIError.noSession
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ WhisperAPIManager: API error: \(errorMessage)", module: "Speech")
            throw WhisperAPIError.apiError(errorMessage)
        }
        
        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            Logger.error("❌ WhisperAPIManager: Failed to parse API response", module: "Speech")
            throw WhisperAPIError.invalidResponse
        }
        
        let transcription = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("✅ WhisperAPIManager: Transcription successful: \(transcription)", module: "Speech")
        
        return transcription
    }
}

enum WhisperAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case noSession

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .apiError(let message):
            return "API error: \(message)"
        case .noSession:
            return "No active session"
        }
    }
}


//
//  LLMServiceProtocol.swift
//  homie
//
//  Provider-agnostic protocol for LLM services.
//  Implementations: OpenAIServiceImpl (premium), LocalLLMServiceImpl (free tier)
//

import Foundation

/// Provider-agnostic protocol for LLM services
/// Supports both streaming and non-streaming text generation
protocol LLMServiceProtocol {
    /// Display name of the provider (e.g., "OpenAI", "Local")
    var providerName: String { get }

    /// Name of the model being used (e.g., "gpt-4o-mini", "Gemma 3 Nano 2B")
    var modelName: String { get }

    /// Generate a response without streaming (for backward compatibility)
    /// - Parameters:
    ///   - messages: Conversation messages in format [["role": "user", "content": "..."]]
    ///   - userInstructions: Optional system instructions
    /// - Returns: The complete response text
    func generateResponse(
        messages: [[String: String]],
        userInstructions: String?
    ) async throws -> String

    /// Generate a streaming response
    /// - Parameters:
    ///   - messages: Conversation messages in format [["role": "user", "content": "..."]]
    ///   - userInstructions: Optional system instructions
    /// - Returns: AsyncThrowingStream of accumulated text as it's generated
    func generateResponseStream(
        messages: [[String: String]],
        userInstructions: String?
    ) -> AsyncThrowingStream<String, Error>
}

/// Errors that can occur during LLM operations
/// Shared across all LLM service implementations
enum LLMError: LocalizedError {
    case apiError(String)
    case networkError
    case invalidResponse
    case noSession
    case maxToolCallsExceeded
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "API Error: \(message)"
        case .networkError:
            return "Network error"
        case .invalidResponse:
            return "Invalid API response"
        case .noSession:
            return "No active session"
        case .maxToolCallsExceeded:
            return "Maximum tool call iterations exceeded"
        case .modelNotLoaded:
            return "Model not loaded"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}

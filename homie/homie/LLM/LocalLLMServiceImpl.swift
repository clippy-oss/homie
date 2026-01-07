//
//  LocalLLMServiceImpl.swift
//  homie
//
//  Local LLM implementation using SwiftAIMLX for on-device inference.
//  Uses Gemma 3 Nano 2B model for fast, private text generation.
//  Supports both streaming and non-streaming generation.
//

import Foundation
import SwiftAI
import SwiftAIMLX
import MLXLLM

/// Local LLM service using MLX for on-device inference
/// Provides fast, private text generation without network dependency
@MainActor
final class LocalLLMServiceImpl: LLMServiceProtocol {

    // MARK: - Singleton

    static let shared = LocalLLMServiceImpl()

    // MARK: - LLMServiceProtocol Properties

    var providerName: String { "Local" }
    var modelName: String { "Gemma 3 Nano 2B" }

    // MARK: - Private Properties

    /// Lazy-loaded LLM instance - only created when preference is enabled
    private var _llm: MlxLLM?

    /// Computed property that lazily initializes the LLM when accessed
    private var llm: MlxLLM {
        if _llm == nil {
            _llm = Self.modelManager.llm(withConfiguration: LLMRegistry.gemma3n_E2B_it_lm_4bit)
            Logger.info("🧠 LocalLLMServiceImpl: LLM instance created (lazy init)", module: "LLM")
        }
        return _llm!
    }

    // Custom model manager using Application Support instead of Documents
    // This avoids the macOS permission prompt for Documents folder access
    private static let modelManager: MlxModelManager = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("homie/mlx-models", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        return MlxModelManager(storageDirectory: modelDir)
    }()

    // MARK: - Preference Check

    /// Check if Local LLM is enabled in user preferences
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "local_llm_enabled")
    }

    // MARK: - Initialization

    private init() {
        // Don't initialize the LLM here - it will be lazily loaded when needed and enabled
        Logger.info("🧠 LocalLLMServiceImpl: Service initialized (LLM will be lazy loaded)", module: "LLM")
    }

    // MARK: - Model Availability

    /// Check if the model is available and ready for inference
    var isModelAvailable: Bool {
        guard Self.isEnabled else { return false }
        return llm.isAvailable
    }

    /// Get the current model availability status
    var modelAvailability: String {
        guard Self.isEnabled else {
            return "unavailable: localLLMDisabled"
        }
        switch llm.availability {
        case .available:
            return "available"
        case .downloading(let progress):
            return "downloading (\(Int(progress * 100))%)"
        case .unavailable(let reason):
            return "unavailable: \(reason)"
        }
    }

    // MARK: - LLMServiceProtocol Methods

    /// Generate a complete response without streaming
    /// - Parameters:
    ///   - messages: Conversation messages in format [["role": "user", "content": "..."]]
    ///   - userInstructions: Optional system instructions
    /// - Returns: The complete response text
    func generateResponse(
        messages: [[String: String]],
        userInstructions: String?
    ) async throws -> String {
        // Check model availability first
        guard llm.isAvailable else {
            let status = modelAvailability
            Logger.info("🧠 LocalLLMServiceImpl: Model not available - \(status)", module: "LLM")
            throw LLMError.modelNotLoaded
        }

        let prompt = buildPrompt(messages: messages, userInstructions: userInstructions)

        Logger.info("🧠 LocalLLMServiceImpl: Generating response for prompt (\(prompt.count) chars)", module: "LLM")

        do {
            let response = try await llm.reply(to: prompt)
            Logger.info("🧠 LocalLLMServiceImpl: Generated response (\(response.content.count) chars)", module: "LLM")
            return response.content
        } catch {
            Logger.error("🧠 LocalLLMServiceImpl: Generation failed - \(error)", module: "LLM")
            Logger.error("🧠 LocalLLMServiceImpl: Error type: \(type(of: error))", module: "LLM")
            throw LLMError.generationFailed("\(error)")
        }
    }

    /// Generate a streaming response
    /// - Parameters:
    ///   - messages: Conversation messages in format [["role": "user", "content": "..."]]
    ///   - userInstructions: Optional system instructions
    /// - Returns: AsyncThrowingStream of accumulated text as it's generated
    func generateResponseStream(
        messages: [[String: String]],
        userInstructions: String?
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = buildPrompt(messages: messages, userInstructions: userInstructions)

        Logger.info("🧠 LocalLLMServiceImpl: Starting streaming response for prompt (\(prompt.count) chars)", module: "LLM")

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                // Check model availability first
                guard self.llm.isAvailable else {
                    let status = self.modelAvailability
                    Logger.info("🧠 LocalLLMServiceImpl: Model not available for streaming - \(status)", module: "LLM")
                    continuation.finish(throwing: LLMError.modelNotLoaded)
                    return
                }

                var accumulatedText = ""

                do {
                    let stream = self.llm.replyStream(to: prompt)

                    for try await partialText in stream {
                        accumulatedText = partialText
                        continuation.yield(accumulatedText)
                    }

                    Logger.info("🧠 LocalLLMServiceImpl: Streaming complete (\(accumulatedText.count) chars)", module: "LLM")
                    continuation.finish()
                } catch {
                    Logger.error("🧠 LocalLLMServiceImpl: Streaming failed - \(error)", module: "LLM")
                    continuation.finish(throwing: LLMError.generationFailed("\(error)"))
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Build a prompt string from messages and system instructions
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - userInstructions: Optional system instructions
    /// - Returns: Combined prompt string for the LLM
    private func buildPrompt(
        messages: [[String: String]],
        userInstructions: String?
    ) -> String {
        var promptParts: [String] = []

        // Add system instructions if provided
        if let instructions = userInstructions, !instructions.isEmpty {
            promptParts.append("System: \(instructions)")
        }

        // Add messages
        for message in messages {
            guard let role = message["role"],
                  let content = message["content"] else {
                continue
            }

            switch role {
            case "system":
                promptParts.append("System: \(content)")
            case "user":
                promptParts.append("User: \(content)")
            case "assistant":
                promptParts.append("Assistant: \(content)")
            default:
                promptParts.append("\(role.capitalized): \(content)")
            }
        }

        // Add assistant prompt to indicate response expected
        promptParts.append("Assistant:")

        return promptParts.joined(separator: "\n\n")
    }

    // MARK: - Prewarm

    /// Trigger model preloading for faster first response
    /// Call this during app launch or before the user is likely to need the LLM
    func prewarm() async {
        Logger.info("🧠 LocalLLMServiceImpl: Prewarming model...", module: "LLM")

        do {
            // Trigger a minimal generation to load the model into memory
            _ = try await llm.reply(to: "Hello").content
            Logger.info("🧠 LocalLLMServiceImpl: Model prewarmed successfully", module: "LLM")
        } catch {
            Logger.error("🧠 LocalLLMServiceImpl: Prewarm failed - \(error.localizedDescription)", module: "LLM")
        }
    }
}

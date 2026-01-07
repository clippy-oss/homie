//
//  LLMSessionStore.swift
//  homie
//
//  Observable store for LLM session state.
//  Publishes streaming text, provider info, and generation status.
//  Used by UI to display real-time response generation.
//

import Foundation
import Combine

/// Observable store that manages LLM session state
/// Publishes streaming updates for UI binding
@MainActor
final class LLMSessionStore: ObservableObject {

    // MARK: - Singleton

    static let shared = LLMSessionStore()

    // MARK: - Published Properties

    /// Whether text is currently being generated
    @Published private(set) var isGenerating: Bool = false

    /// The current streamed/accumulated text response
    @Published private(set) var currentStreamedText: String = ""

    /// Name of the current LLM provider (e.g., "OpenAI", "Local")
    @Published private(set) var currentProvider: String = ""

    /// Name of the current model (e.g., "gpt-4o-mini", "Gemma 3 Nano 2B")
    @Published private(set) var currentModelName: String = ""

    /// Any error that occurred during generation
    @Published private(set) var error: Error?

    // MARK: - Private Properties

    /// The currently active LLM service
    private var currentService: (any LLMServiceProtocol)?

    /// Task for current generation (for cancellation)
    private var generationTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        Logger.info("📊 LLMSessionStore: Initialized", module: "LLM")
    }

    // MARK: - Service Management

    /// Set the active LLM service
    /// Called by FeatureGateway when routing based on tier
    /// - Parameter service: The LLM service to use
    func setService(_ service: any LLMServiceProtocol) {
        currentService = service
        currentProvider = service.providerName
        currentModelName = service.modelName
        Logger.info("📊 LLMSessionStore: Service set to \(service.providerName) (\(service.modelName))", module: "LLM")
    }

    // MARK: - Generation Methods

    /// Generate a streaming response
    /// Updates `currentStreamedText` as chunks arrive
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - userInstructions: Optional system instructions
    func generateStreaming(
        messages: [[String: String]],
        userInstructions: String?
    ) async {
        guard let service = currentService else {
            error = LLMError.modelNotLoaded
            return
        }

        // Reset state
        isGenerating = true
        currentStreamedText = ""
        error = nil

        Logger.info("📊 LLMSessionStore: Starting streaming generation with \(service.providerName)", module: "LLM")

        do {
            let stream = service.generateResponseStream(
                messages: messages,
                userInstructions: userInstructions
            )

            for try await text in stream {
                currentStreamedText = text
            }

            Logger.info("📊 LLMSessionStore: Streaming complete (\(currentStreamedText.count) chars)", module: "LLM")
        } catch {
            Logger.error("📊 LLMSessionStore: Streaming error - \(error.localizedDescription)", module: "LLM")
            self.error = error
        }

        isGenerating = false
    }

    /// Generate a non-streaming response
    /// Returns the complete response at once
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - userInstructions: Optional system instructions
    /// - Returns: The complete response text
    func generate(
        messages: [[String: String]],
        userInstructions: String?
    ) async throws -> String {
        guard let service = currentService else {
            throw LLMError.modelNotLoaded
        }

        // Reset state
        isGenerating = true
        currentStreamedText = ""
        error = nil

        Logger.info("📊 LLMSessionStore: Starting generation with \(service.providerName)", module: "LLM")

        do {
            let response = try await service.generateResponse(
                messages: messages,
                userInstructions: userInstructions
            )

            currentStreamedText = response
            isGenerating = false

            Logger.info("📊 LLMSessionStore: Generation complete (\(response.count) chars)", module: "LLM")
            return response
        } catch {
            self.error = error
            isGenerating = false
            throw error
        }
    }

    /// Consume an external stream and update published properties
    /// Use this when receiving a stream from LLMRouter/FeatureGateway
    /// - Parameters:
    ///   - stream: The AsyncThrowingStream of accumulated text
    ///   - onComplete: Callback with final text when stream completes
    func generateFromStream(
        _ stream: AsyncThrowingStream<String, Error>,
        onComplete: @escaping (String) -> Void
    ) async {
        // Reset state
        isGenerating = true
        currentStreamedText = ""
        error = nil

        Logger.info("📊 LLMSessionStore: Consuming external stream", module: "LLM")

        do {
            for try await text in stream {
                currentStreamedText = text
            }

            Logger.info("📊 LLMSessionStore: External stream complete (\(currentStreamedText.count) chars)", module: "LLM")
            onComplete(currentStreamedText)
        } catch {
            Logger.error("📊 LLMSessionStore: External stream error - \(error.localizedDescription)", module: "LLM")
            self.error = error
        }

        isGenerating = false
    }

    /// Cancel any ongoing generation
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        Logger.info("📊 LLMSessionStore: Generation cancelled", module: "LLM")
    }

    /// Reset the session state
    func reset() {
        cancelGeneration()
        currentStreamedText = ""
        error = nil
        Logger.info("📊 LLMSessionStore: State reset", module: "LLM")
    }

    /// Clear the current response text
    /// Used to dismiss the response bubble before starting a new action
    func clearResponse() {
        currentStreamedText = ""
        error = nil
        Logger.info("📊 LLMSessionStore: Response cleared", module: "LLM")
    }

    /// Set the streamed text directly
    /// Used when receiving a complete response (non-streaming) to display in the bubble
    func setStreamedText(_ text: String) {
        currentStreamedText = text
        Logger.info("📊 LLMSessionStore: Streamed text set (\(text.count) chars)", module: "LLM")
    }
}

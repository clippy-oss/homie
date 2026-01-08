//
//  FeatureGateway.swift
//  homie
//
//  Central gateway that owns ALL auth/tier gating logic.
//  Services become "dumb executors" with no auth checks.
//  Single entry point for feature access requests.
//

import Foundation

// MARK: - Result Types

/// Result type for feature access requests
enum FeatureAccessResult<T> {
    case success(T)
    case accessDenied(FeatureAccessDenialReason)
    case error(Error)
}

/// Reasons why feature access may be denied
enum FeatureAccessDenialReason {
    case notAuthenticated
    case premiumRequired(Feature)
    case featureUnavailable(String)
    case localLLMDisabled
}

// MARK: - UI Delegate Protocol

/// Delegate protocol for UI callbacks on access denial
@MainActor
protocol FeatureGatewayUIDelegate: AnyObject {
    func showLoginRequired()
    func showUpgradeRequired(for feature: Feature)
    func showFeatureUnavailable(reason: String)
}

// MARK: - FeatureGateway

/// Central gateway for all feature access requests.
/// Handles authentication checks, feature entitlement verification,
/// and routes to appropriate implementations (premium vs free).
@MainActor
final class FeatureGateway {

    // MARK: - Singleton

    static let shared = FeatureGateway()

    // MARK: - Properties

    /// Delegate for UI callbacks on access denial
    weak var uiDelegate: FeatureGatewayUIDelegate?

    /// WhisperAPIManager instance for premium transcription
    private lazy var whisperAPIManager = WhisperAPIManager()

    /// LocalWhisperManager instance for free tier transcription
    private lazy var localWhisperManager: LocalWhisperManager = {
        let modelPath = Bundle.main.path(forResource: "ggml-base.en", ofType: "bin") ?? ""
        return LocalWhisperManager(modelPath: modelPath)
    }()

    /// OpenAI service for premium chat
    private var openAIService: OpenAIServiceImpl { OpenAIServiceImpl.shared }

    /// Local LLM service for free tier chat
    private var localLLMService: LocalLLMServiceImpl { LocalLLMServiceImpl.shared }

    // MARK: - Initialization

    private init() {
        Logger.info("🚪 FeatureGateway: Initialized", module: "Feature")
    }

    // MARK: - Chat Processing

    /// Process a chat request, routing to premium (OpenAI) or free (Local LLM) based on entitlement.
    /// - Parameters:
    ///   - messages: Conversation messages in format [["role": "user", "content": "..."]]
    ///   - context: Optional context for the request
    ///   - tools: Optional MCP tools for premium users (OpenAI format)
    ///   - userInstructions: Optional system instructions
    ///   - toolConfirmationHandler: Optional handler to confirm/modify tool calls before execution
    /// - Returns: FeatureAccessResult containing the response string or denial reason
    func processChat(
        messages: [[String: String]],
        context: String? = nil,
        tools: [[String: Any]]? = nil,
        userInstructions: String? = nil,
        toolConfirmationHandler: OpenAIServiceImpl.ToolCallConfirmationHandler? = nil
    ) async -> FeatureAccessResult<String> {

        // Step 1: Check authentication
        guard AuthSessionStore.shared.isAuthenticated else {
            Logger.info("🚪 FeatureGateway: Chat denied - not authenticated", module: "Feature")
            uiDelegate?.showLoginRequired()
            return .accessDenied(.notAuthenticated)
        }

        // Step 2: Determine which service to use and update LLMSessionStore
        let canUseOpenAI = FeatureEntitlementStore.shared.canUseOpenAI
        let isLocalLLMEnabled = LocalLLMServiceImpl.isEnabled

        // Check if user can use any LLM service
        if !canUseOpenAI && !isLocalLLMEnabled {
            Logger.info("🚪 FeatureGateway: Chat denied - no LLM available (local disabled, not premium)", module: "Feature")
            return .accessDenied(.localLLMDisabled)
        }

        let service: any LLMServiceProtocol = canUseOpenAI ? openAIService : localLLMService

        // Update session store with current service info
        LLMSessionStore.shared.setService(service)

        if canUseOpenAI {
            // Premium path: Route to OpenAI (with tool support)
            Logger.info("🚪 FeatureGateway: Routing chat to OpenAI (premium)", module: "Feature")
            do {
                let response = try await openAIService.generateResponseWithTools(
                    messages: messages,
                    tools: tools,
                    userInstructions: userInstructions,
                    toolConfirmationHandler: toolConfirmationHandler
                )
                return .success(response)
            } catch {
                Logger.error("🚪 FeatureGateway: OpenAI error - \(error.localizedDescription)", module: "Feature")
                return .error(error)
            }
        } else {
            // Free path: Route to Local LLM (no tool support)
            Logger.info("🚪 FeatureGateway: Routing chat to LocalLLM (free)", module: "Feature")

            do {
                let response = try await localLLMService.generateResponse(
                    messages: messages,
                    userInstructions: userInstructions
                )
                return .success(response)
            } catch {
                Logger.error("🚪 FeatureGateway: LocalLLM error - \(error.localizedDescription)", module: "Feature")
                return .error(error)
            }
        }
    }

    // MARK: - Streaming Chat Processing

    /// Process a chat request with streaming, routing to premium (OpenAI) or free (Local LLM) based on entitlement.
    /// NOTE: Does not support tool calling - use processChat for MCP tool scenarios.
    /// - Parameters:
    ///   - messages: Conversation messages in format [["role": "user", "content": "..."]]
    ///   - userInstructions: Optional system instructions
    /// - Returns: FeatureAccessResult containing AsyncThrowingStream of response text or denial reason
    func processChatStreaming(
        messages: [[String: String]],
        userInstructions: String? = nil
    ) async -> FeatureAccessResult<AsyncThrowingStream<String, Error>> {

        // Step 1: Check authentication
        guard AuthSessionStore.shared.isAuthenticated else {
            Logger.info("🚪 FeatureGateway: Streaming chat denied - not authenticated", module: "Feature")
            uiDelegate?.showLoginRequired()
            return .accessDenied(.notAuthenticated)
        }

        // Step 2: Determine which service to use and update LLMSessionStore
        let canUseOpenAI = FeatureEntitlementStore.shared.canUseOpenAI
        let isLocalLLMEnabled = LocalLLMServiceImpl.isEnabled

        // Check if user can use any LLM service
        if !canUseOpenAI && !isLocalLLMEnabled {
            Logger.info("🚪 FeatureGateway: Streaming chat denied - no LLM available (local disabled, not premium)", module: "Feature")
            return .accessDenied(.localLLMDisabled)
        }

        let service: any LLMServiceProtocol = canUseOpenAI ? openAIService : localLLMService

        // Update session store with current service info
        LLMSessionStore.shared.setService(service)

        Logger.info("🚪 FeatureGateway: Routing streaming chat to \(service.providerName)", module: "Feature")

        // Return the stream - both services implement generateResponseStream
        let stream = service.generateResponseStream(
            messages: messages,
            userInstructions: userInstructions
        )

        return .success(stream)
    }

    // MARK: - Transcription

    /// Transcribe audio data, routing to premium (WhisperAPI) or free (LocalWhisper) based on entitlement.
    /// - Parameter audioData: WAV format audio data
    /// - Returns: FeatureAccessResult containing transcribed text or denial reason
    func transcribe(audioData: Data) async -> FeatureAccessResult<String> {

        // Step 1: Check authentication
        guard AuthSessionStore.shared.isAuthenticated else {
            Logger.info("🚪 FeatureGateway: Transcription denied - not authenticated", module: "Feature")
            uiDelegate?.showLoginRequired()
            return .accessDenied(.notAuthenticated)
        }

        // Step 2: Route based on entitlement
        let canUseWhisperAPI = FeatureEntitlementStore.shared.canUseWhisperAPI

        if canUseWhisperAPI {
            // Premium path: Route to WhisperAPIManager
            Logger.info("🚪 FeatureGateway: Routing transcription to WhisperAPI (premium)", module: "Feature")
            do {
                if let transcription = try await whisperAPIManager.transcribe(audioData: audioData) {
                    return .success(transcription)
                } else {
                    // API returned nil, fallback to local
                    Logger.info("🚪 FeatureGateway: WhisperAPI returned nil, falling back to local", module: "Feature")
                    return await transcribeWithLocal(audioData: audioData)
                }
            } catch {
                // API failed, fallback to local
                Logger.error("🚪 FeatureGateway: WhisperAPI error - \(error.localizedDescription), falling back to local", module: "Feature")
                return await transcribeWithLocal(audioData: audioData)
            }
        } else {
            // Free path: Route to LocalWhisperManager
            Logger.info("🚪 FeatureGateway: Routing transcription to LocalWhisper (free)", module: "Feature")
            return await transcribeWithLocal(audioData: audioData)
        }
    }

    /// Internal method to transcribe using local Whisper (on-device)
    private func transcribeWithLocal(audioData: Data) async -> FeatureAccessResult<String> {
        // Run on background queue since LocalWhisperManager is synchronous
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: .error(FeatureGatewayError.transcriptionFailed))
                    return
                }

                if let transcription = self.localWhisperManager.transcribe(audioData: audioData) {
                    Logger.info("🚪 FeatureGateway: Local Whisper transcription successful", module: "Feature")
                    continuation.resume(returning: .success(transcription))
                } else {
                    Logger.error("🚪 FeatureGateway: Local Whisper transcription failed", module: "Feature")
                    continuation.resume(returning: .error(FeatureGatewayError.transcriptionFailed))
                }
            }
        }
    }

    // MARK: - Feature Guard

    /// Check if a feature is available and trigger appropriate UI if not.
    /// Use this for simple feature gating before accessing premium features.
    /// - Parameter feature: The feature to check
    /// - Returns: True if access is granted, false otherwise
    func guardFeature(_ feature: Feature) async -> Bool {

        // Step 1: Check authentication
        guard AuthSessionStore.shared.isAuthenticated else {
            Logger.info("🚪 FeatureGateway: Feature '\(feature.displayName)' denied - not authenticated", module: "Feature")
            uiDelegate?.showLoginRequired()
            return false
        }

        // Step 2: Check feature entitlement
        guard FeatureEntitlementStore.shared.isFeatureAvailable(feature) else {
            Logger.info("🚪 FeatureGateway: Feature '\(feature.displayName)' denied - premium required", module: "Feature")
            uiDelegate?.showUpgradeRequired(for: feature)
            return false
        }

        Logger.info("🚪 FeatureGateway: Feature '\(feature.displayName)' access granted", module: "Feature")
        return true
    }

    // MARK: - Convenience Methods

    /// Check authentication status without triggering UI.
    /// Use this for silent checks where you want to handle the UI yourself.
    var isAuthenticated: Bool {
        AuthSessionStore.shared.isAuthenticated
    }

    /// Get current subscription tier.
    var currentTier: SubscriptionTier {
        FeatureEntitlementStore.shared.currentTier
    }

    /// Check if a feature is available without triggering UI.
    /// Use this for silent checks where you want to handle the UI yourself.
    /// - Parameter feature: The feature to check
    /// - Returns: True if the feature is available
    func isFeatureAvailable(_ feature: Feature) -> Bool {
        guard AuthSessionStore.shared.isAuthenticated else { return false }
        return FeatureEntitlementStore.shared.isFeatureAvailable(feature)
    }

    // MARK: - Resource Cleanup

    /// Clean up resources (e.g., local Whisper model)
    func cleanup() {
        localWhisperManager.cleanup()
        Logger.info("🚪 FeatureGateway: Resources cleaned up", module: "Feature")
    }
}

// MARK: - Error Types

enum FeatureGatewayError: LocalizedError {
    case invalidRequest(String)
    case transcriptionFailed
    case featureUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .transcriptionFailed:
            return "Transcription failed"
        case .featureUnavailable(let reason):
            return "Feature unavailable: \(reason)"
        }
    }
}

//
//  LLMRouter.swift
//  homie
//
//  Routes LLM queries via FeatureGateway which handles auth/tier checks
//  Supports MCP tool calling for premium users with connected integrations
//
//  NOTE: Auth/tier routing is handled by FeatureGateway - this class provides
//  a convenient interface for building messages and system instructions.
//

import Foundation

/// Error type for LLMRouter operations
enum LLMRouterError: LocalizedError {
    case accessDenied(FeatureAccessDenialReason)
    case processingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let reason):
            switch reason {
            case .notAuthenticated:
                return "Please sign in to continue"
            case .premiumRequired(let feature):
                return "Premium required for \(feature.displayName)"
            case .featureUnavailable(let reason):
                return "Feature unavailable: \(reason)"
            case .localLLMDisabled:
                return "Local AI is disabled. Enable it in Preferences or upgrade to Premium."
            }
        case .processingFailed(let error):
            return "Processing failed: \(error.localizedDescription)"
        }
    }
}

class LLMRouter {
    static let shared = LLMRouter()

    // Cached system instructions with user info embedded
    private var cachedSystemInstructions: String = ""

    private init() {
        buildSystemInstructions()
    }
    
    /// Build system instructions with user info embedded at the correct location
    private func buildSystemInstructions() {
        let userInfo = UserPersonalizationManager.shared.getUserInformationBlock()
        
        // Base instructions before user info insertion point
        let beforeUserInfo = """
        You are a helpful assistant that processes text content. When the user provides context (the content they're working with) and a request, you should process that content according to their request. The context is the material the user wants you to work with - it could be code, documents, emails, articles, or any other text content. Your job is to help the user with any request using the provided context or even without that if the user has a request without a context.
        Be very direct, you are talking like gen-z. And don't forget, you are not an assistant writing anything like "Sure, here is the output..." or "Feel free to edit it..." No fluff, just the requested output!!!
        Don't add unnecessary explanations or formalities - Just provide the requested content. Always think about the fact that the user has a text box available and only wants to paste there the main text they are working with and no extra text.
        Bad example: User request: "Write a reply to this email" Assitant: "Sure, here is the email..."
        Bad example: User request: "Write a reply to this email" Assitant: "Subject: An email response to..."
        Good example: User request: "Write a reply to this email" Assitant: "Dear xyz,..."
        
        You receive information to the user, so if you need to include anything, like the user's name, email address, or anything that is mentioned, use the info. Always remember that if you sign emails, sign them with the user's name. Always use the Primary email and phone number of the user, unless requested differently.
        """
        
        // Instructions after user info
        let afterUserInfo = """
        
        Use simple formatting without markdown unless specifically requested.
        Your response will be pasted directly into the user's text field and the user will work with that text directly, so under no circumstances use any unnecessary formating!! If the user asks you to summarize a text, don't write "Sure, here is the summary..." but place the summary, and just the summary, diretly in the text field. If the user asks you to write a response to an email, don't or "Here is the email..." but place the email and nothing else.
        For emails format them as an email would be formated, with an adressing of the recipient and at the end a signature, but don't include a subject line. Those belong in a differnt text field.
        
        Always process the user's request using the context they provide and ignore the history. The context is the content they want you to work with, not personal information about them. The personal information is there to give any guidance on what the user's name or so are.
        """
        
        // Combine: before + user info + after
        cachedSystemInstructions = beforeUserInfo + userInfo + afterUserInfo
    }
    
    /// Refresh system instructions when user info changes
    func refreshSystemInstructions() {
        buildSystemInstructions()
        Logger.info("🔄 LLMRouter: System instructions refreshed with updated user info", module: "LLM")
    }
    
    /// Get the current system instructions (for logging/debugging)
    func getSystemInstructions() -> String {
        return cachedSystemInstructions
    }
    
    /// Process a query using FeatureGateway which handles auth/tier routing
    func processQuery(
        _ query: String,
        context: String?,
        toolConfirmationHandler: OpenAIServiceImpl.ToolCallConfirmationHandler? = nil
    ) async throws -> String {
        Logger.info("🎯 LLMRouter: Processing query via FeatureGateway", module: "LLM")

        // Build messages array
        var messages: [[String: String]] = []

        // Add context if available
        if let context = context, !context.isEmpty {
            messages.append([
                "role": "system",
                "content": "Context: \(context)"
            ])
        }

        // Add user query
        messages.append([
            "role": "user",
            "content": query
        ])

        // Get available MCP tools if any servers are connected (for premium users)
        let tools: [[String: Any]]? = getAvailableMCPTools()

        if let tools = tools, !tools.isEmpty {
            Logger.info("🔧 LLMRouter: \(tools.count) MCP tools available", module: "LLM")
        }

        // Delegate to FeatureGateway - it handles auth/tier checks and routing
        let result = await MainActor.run {
            Task {
                await FeatureGateway.shared.processChat(
                    messages: messages,
                    context: context,
                    tools: tools,
                    userInstructions: cachedSystemInstructions,
                    toolConfirmationHandler: toolConfirmationHandler
                )
            }
        }

        let accessResult = await result.value

        // Convert FeatureAccessResult to throwing pattern for backwards compatibility
        switch accessResult {
        case .success(let response):
            return response
        case .accessDenied(let reason):
            throw LLMRouterError.accessDenied(reason)
        case .error(let error):
            throw LLMRouterError.processingFailed(error)
        }
    }
    
    // MARK: - Streaming Query

    /// Process a query with streaming via FeatureGateway
    /// NOTE: Does not support MCP tool calling - use processQuery when tools are connected
    /// - Parameters:
    ///   - query: The user's query text
    ///   - context: Optional context for the request
    /// - Returns: AsyncThrowingStream of accumulated response text
    func processQueryStreaming(_ query: String, context: String?) async throws -> AsyncThrowingStream<String, Error> {
        Logger.info("🎯 LLMRouter: Processing streaming query via FeatureGateway", module: "LLM")

        // Build messages array
        var messages: [[String: String]] = []

        // Add context if available
        if let context = context, !context.isEmpty {
            messages.append([
                "role": "system",
                "content": "Context: \(context)"
            ])
        }

        // Add user query
        messages.append([
            "role": "user",
            "content": query
        ])

        // Delegate to FeatureGateway streaming method
        let result = await MainActor.run {
            Task {
                await FeatureGateway.shared.processChatStreaming(
                    messages: messages,
                    userInstructions: cachedSystemInstructions
                )
            }
        }

        let accessResult = await result.value

        // Convert FeatureAccessResult to throwing pattern
        switch accessResult {
        case .success(let stream):
            return stream
        case .accessDenied(let reason):
            throw LLMRouterError.accessDenied(reason)
        case .error(let error):
            throw LLMRouterError.processingFailed(error)
        }
    }

    // MARK: - MCP Tools

    /// Get available MCP tools in OpenAI format
    private func getAvailableMCPTools() -> [[String: Any]]? {
        let mcpManager = MCPManager.shared
        
        // Only return tools if there are connected servers
        guard mcpManager.hasConnectedServers else {
            return nil
        }
        
        let tools = mcpManager.getToolsForOpenAI()
        return tools.isEmpty ? nil : tools
    }
}


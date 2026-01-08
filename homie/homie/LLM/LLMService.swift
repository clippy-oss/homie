//
//  OpenAIServiceImpl.swift
//  homie
//
//  OpenAI API integration via Supabase Edge Function
//  SECURE: API key stays on server, client only sends requests
//  Supports MCP tool calling for premium features
//
//  NOTE: This is a "dumb executor" - auth/tier checks are handled by FeatureGateway
//

import Foundation

class OpenAIServiceImpl: LLMServiceProtocol {
    static let shared = OpenAIServiceImpl()

    // MARK: - LLMServiceProtocol Properties

    var providerName: String { "OpenAI" }
    var modelName: String { "gpt-4o-mini" }
    
    /// Maximum number of tool call iterations to prevent infinite loops
    private let maxToolCallIterations = 10
    
    private init() {}

    // MARK: - LLMServiceProtocol Methods

    /// Simple chat without tool support (backward compatible)
    func generateResponse(messages: [[String: String]], userInstructions: String?) async throws -> String {
        return try await generateResponseWithTools(messages: messages, tools: nil, userInstructions: userInstructions)
    }

    /// Real streaming response via SSE from streaming edge function
    func generateResponseStream(
        messages: [[String: String]],
        userInstructions: String?
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get access token from Supabase session
                    guard let session = try? await supabase.auth.session else {
                        Logger.error("❌ OpenAIManager: No active session for streaming", module: "LLM")
                        continuation.finish(throwing: LLMError.noSession)
                        return
                    }

                    let supabaseURL = Config.supabaseURL
                    let edgeFunctionURL = "\(supabaseURL)/functions/v1/stream-chat-openai"

                    guard let url = URL(string: edgeFunctionURL) else {
                        continuation.finish(throwing: LLMError.networkError)
                        return
                    }

                    Logger.info("🤖 OpenAIManager: Starting streaming request", module: "LLM")

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

                    // Build messages with system instructions
                    var allMessages: [[String: Any]] = []
                    if let instructions = userInstructions {
                        allMessages.append(["role": "system", "content": instructions])
                    }
                    for message in messages {
                        allMessages.append(message as [String: Any])
                    }

                    let body: [String: Any] = [
                        "messages": allMessages,
                        "model": "gpt-4o-mini",
                        "temperature": 0.7,
                        "max_tokens": 2000
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    // Use URLSession bytes API for streaming
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.networkError)
                        return
                    }

                    if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                        Logger.error("❌ OpenAIManager: Auth error in streaming (status \(httpResponse.statusCode))", module: "LLM")
                        continuation.finish(throwing: LLMError.noSession)
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        Logger.error("❌ OpenAIManager: Streaming API error (status \(httpResponse.statusCode))", module: "LLM")
                        continuation.finish(throwing: LLMError.apiError("HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    var accumulatedText = ""
                    var chunkCount = 0

                    // Parse SSE stream line by line
                    for try await line in bytes.lines {
                        // SSE format: "data: {...}" or "data: [DONE]"
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        // Check for stream end
                        if jsonString == "[DONE]" {
                            Logger.info("✅ OpenAIManager: Stream complete (\(accumulatedText.count) chars, \(chunkCount) chunks)", module: "LLM")
                            break
                        }

                        // Parse JSON and extract content delta
                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            accumulatedText += content
                            chunkCount += 1

                            // Debug: Log first few chunks to verify streaming
                            if chunkCount <= 3 {
                                Logger.debug("📡 Chunk \(chunkCount): +\(content.count) chars, total: \(accumulatedText.count)", module: "LLM")
                            }

                            continuation.yield(accumulatedText)
                        }
                    }

                    continuation.finish()
                } catch {
                    Logger.error("❌ OpenAIManager: Streaming error - \(error.localizedDescription)", module: "LLM")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Chat with MCP Tools
    
    /// Callback for tool call confirmation
    /// Returns the (potentially modified) tool call to execute, or nil to cancel
    typealias ToolCallConfirmationHandler = (MCPToolCall) async -> MCPToolCall?
    
    /// Chat with MCP tool support
    /// NOTE: Auth/tier checks are handled by FeatureGateway - this is a dumb executor
    /// - Parameters:
    ///   - messages: The conversation messages
    ///   - tools: Optional array of tools in OpenAI format
    ///   - userInstructions: System instructions
    ///   - toolConfirmationHandler: Optional handler to confirm/modify tool calls before execution
    /// - Returns: The final response content
    func generateResponseWithTools(
        messages: [[String: String]],
        tools: [[String: Any]]?,
        userInstructions: String? = nil,
        toolConfirmationHandler: ToolCallConfirmationHandler? = nil
    ) async throws -> String {
        // Get access token from Supabase session (caller already verified auth)
        guard let session = try? await supabase.auth.session else {
            Logger.error("❌ OpenAIManager: No active session", module: "LLM")
            throw LLMError.noSession
        }
        let accessToken = session.accessToken
        
        // Build initial messages with system instructions
        var conversationMessages: [[String: Any]] = []
        
        if let instructions = userInstructions {
            conversationMessages.append([
                "role": "system",
                "content": instructions
            ])
        }
        
        // Add tool usage instructions if tools are available
        if let tools = tools, !tools.isEmpty {
            let toolNames = tools.compactMap { tool -> String? in
                guard let function = tool["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                return name
            }
            
            let toolInstruction = """
            
            You have access to the following tools: \(toolNames.joined(separator: ", ")).
            Use these tools when the user's request requires accessing external services like Linear or Google Calendar.
            When you need to use a tool, call it with the appropriate parameters.
            After receiving tool results, provide a helpful response to the user based on the information.
            """
            
            if var lastSystem = conversationMessages.last, lastSystem["role"] as? String == "system" {
                lastSystem["content"] = (lastSystem["content"] as? String ?? "") + toolInstruction
                conversationMessages[conversationMessages.count - 1] = lastSystem
            } else {
                conversationMessages.append([
                    "role": "system",
                    "content": toolInstruction
                ])
            }
        }
        
        // Add user messages
        for message in messages {
            conversationMessages.append(message as [String: Any])
        }
        
        // Tool calling loop
        var iterations = 0
        
        while iterations < maxToolCallIterations {
            iterations += 1
            
            let response = try await makeOpenAIRequest(
                messages: conversationMessages,
                tools: tools,
                accessToken: accessToken
            )
            
            // Check if we have tool calls
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                Logger.info("🔧 OpenAIManager: Processing \(toolCalls.count) tool call(s)", module: "LLM")
                
                // Add assistant message with tool calls
                var assistantMessage: [String: Any] = [
                    "role": "assistant"
                ]
                if let content = response.content {
                    assistantMessage["content"] = content
                }
                assistantMessage["tool_calls"] = toolCalls.map { call in
                    return [
                        "id": call.id,
                        "type": call.type,
                        "function": [
                            "name": call.function.name,
                            "arguments": call.function.arguments
                        ]
                    ]
                }
                conversationMessages.append(assistantMessage)
                
                // If confirmation handler is provided, get user approval for each tool call
                var confirmedToolCalls: [MCPToolCall] = []
                if let confirmationHandler = toolConfirmationHandler {
                    for toolCall in toolCalls {
                        if let confirmedCall = await confirmationHandler(toolCall) {
                            confirmedToolCalls.append(confirmedCall)
                        } else {
                            // User cancelled this tool call
                            Logger.info("🚫 Tool call cancelled by user: \(toolCall.function.name)", module: "LLM")
                            // Add a cancelled result
                            let cancelledResult = MCPToolResult(
                                toolCallID: toolCall.id,
                                result: "Tool call was cancelled by the user.",
                                isError: false
                            )
                            conversationMessages.append(cancelledResult.toOpenAIMessage())
                        }
                    }
                } else {
                    // No confirmation needed, execute all
                    confirmedToolCalls = toolCalls
                }
                
                // Execute confirmed tool calls via MCPManager
                if !confirmedToolCalls.isEmpty {
                    let results = await MCPManager.shared.execute(toolCalls: confirmedToolCalls)
                    
                    // Add tool results to conversation
                    for result in results {
                        conversationMessages.append(result.toOpenAIMessage())
                    }
                }
                
                // Continue loop to get next response
                continue
            }
            
            // No tool calls, return final response
            if let content = response.content {
                Logger.info("✅ OpenAIManager: Received final response (\(content.count) chars)", module: "LLM")
                return content
            } else {
                throw LLMError.invalidResponse
            }
        }
        
        throw LLMError.maxToolCallsExceeded
    }
    
    // MARK: - API Request
    
    private func makeOpenAIRequest(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        accessToken: String
    ) async throws -> OpenAIResponse {
        let supabaseURL = Config.supabaseURL
        let edgeFunctionURL = "\(supabaseURL)/functions/v1/chat-with-openai"
        
        guard let url = URL(string: edgeFunctionURL) else {
            throw LLMError.networkError
        }
        
        Logger.info("🤖 OpenAIManager: Calling secure Edge Function", module: "LLM")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        var body: [String: Any] = [
            "messages": messages,
            "model": "gpt-4o-mini",
            "temperature": 0.7,
            "max_tokens": 2000  // Increased for tool responses
        ]
        
        // Add tools if available
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError
        }
        
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
            // This shouldn't happen if FeatureGateway is used correctly
            Logger.error("❌ OpenAIManager: Auth error (status \(httpResponse.statusCode)) - caller should use FeatureGateway", module: "LLM")
            throw LLMError.noSession
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ OpenAIManager: API error: \(errorBody)", module: "LLM")
            throw LLMError.apiError(errorBody)
        }
        
        // Parse response
        return try parseOpenAIResponse(data: data)
    }
    
    private func parseOpenAIResponse(data: Data) throws -> OpenAIResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        
        let content = message["content"] as? String
        
        // Parse tool calls if present
        var toolCalls: [MCPToolCall]? = nil
        if let toolCallsArray = message["tool_calls"] as? [[String: Any]] {
            toolCalls = toolCallsArray.compactMap { callDict -> MCPToolCall? in
                guard let id = callDict["id"] as? String,
                      let type = callDict["type"] as? String,
                      let function = callDict["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let arguments = function["arguments"] as? String else {
                    return nil
                }
                
                return MCPToolCall(
                    id: id,
                    type: type,
                    function: MCPFunctionCall(name: name, arguments: arguments)
                )
            }
        }
        
        return OpenAIResponse(content: content, toolCalls: toolCalls)
    }
}

// MARK: - Response Models

/// Internal response model for OpenAI API
struct OpenAIResponse {
    let content: String?
    let toolCalls: [MCPToolCall]?
}

/// Legacy response model (kept for backward compatibility)
struct OpenAIChatResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String?
        let tool_calls: [ToolCall]?
    }
    
    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall
    }
    
    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

struct EdgeFunctionErrorResponse: Codable {
    let error: String
    let message: String?
}

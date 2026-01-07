//
//  MCPManager.swift
//  homie
//
//  Central manager for all MCP server connections and tool execution
//

import Foundation
import Combine

class MCPManager: ObservableObject {
    static let shared = MCPManager()
    
    /// All registered MCP servers
    @Published private(set) var servers: [String: any MCPServerProtocol] = [:]
    
    /// Combined tools from all connected servers
    @Published private(set) var availableTools: [MCPTool] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Register all available servers
        registerServer(LinearMCPServer())
        registerServer(GoogleCalendarMCPServer())
        
        // Update tools when connection status changes
        updateAvailableTools()
    }
    
    // MARK: - Server Management
    
    /// Register an MCP server
    func registerServer(_ server: any MCPServerProtocol) {
        servers[server.serverID] = server
        
        // Observe connection status changes
        server.connectionStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAvailableTools()
            }
            .store(in: &cancellables)
        
        Logger.info("📦 MCPManager: Registered server \(server.serverID)", module: "MCP")
    }
    
    /// Get a specific server by ID
    func server(for serverID: String) -> (any MCPServerProtocol)? {
        return servers[serverID]
    }
    
    /// Get all server configurations
    var allServerConfigs: [MCPServerConfig] {
        return MCPServerConfig.allServers
    }
    
    /// Check if a specific server is connected
    func isConnected(serverID: String) -> Bool {
        return servers[serverID]?.isConnected ?? false
    }
    
    /// Get connection status for a server
    func connectionStatus(for serverID: String) -> MCPConnectionStatus {
        return servers[serverID]?.connectionStatus ?? .disconnected
    }
    
    // MARK: - Tool Management
    
    /// Update the list of available tools from all connected servers
    private func updateAvailableTools() {
        var tools: [MCPTool] = []
        
        for (_, server) in servers {
            if server.isConnected {
                tools.append(contentsOf: server.tools)
            }
        }
        
        availableTools = tools
        Logger.info("🔧 MCPManager: \(tools.count) tools available from \(connectedServerCount) servers", module: "MCP")
    }
    
    /// Number of connected servers
    var connectedServerCount: Int {
        servers.values.filter { $0.isConnected }.count
    }
    
    /// Check if any servers are connected
    var hasConnectedServers: Bool {
        connectedServerCount > 0
    }
    
    /// Get tools in OpenAI function calling format
    func getToolsForOpenAI() -> [[String: Any]] {
        return availableTools.map { $0.toOpenAIFormat() }
    }
    
    // MARK: - Tool Execution
    
    /// Execute a tool call from the LLM
    /// - Parameter toolCall: The tool call from OpenAI response
    /// - Returns: Result to send back to the LLM
    func execute(toolCall: MCPToolCall) async throws -> MCPToolResult {
        let toolName = toolCall.function.name
        
        // Find the tool and its server
        guard let tool = availableTools.first(where: { $0.name == toolName }) else {
            return MCPToolResult(
                toolCallID: toolCall.id,
                result: "Error: Tool '\(toolName)' not found",
                isError: true
            )
        }
        
        guard let server = servers[tool.serverID] else {
            return MCPToolResult(
                toolCallID: toolCall.id,
                result: "Error: Server for tool '\(toolName)' not available",
                isError: true
            )
        }
        
        // Parse arguments
        let arguments = toolCall.function.parseArguments() ?? [:]
        
        Logger.info("🔧 MCPManager: Executing \(toolName) on \(server.serverID)", module: "MCP")
        
        do {
            let result = try await server.execute(tool: toolName, arguments: arguments)
            return MCPToolResult(
                toolCallID: toolCall.id,
                result: result,
                isError: false
            )
        } catch {
            Logger.error("❌ MCPManager: Tool execution failed: \(error)", module: "MCP")
            return MCPToolResult(
                toolCallID: toolCall.id,
                result: "Error executing tool: \(error.localizedDescription)",
                isError: true
            )
        }
    }
    
    /// Execute multiple tool calls
    func execute(toolCalls: [MCPToolCall]) async -> [MCPToolResult] {
        var results: [MCPToolResult] = []
        
        for call in toolCalls {
            do {
                let result = try await execute(toolCall: call)
                results.append(result)
            } catch {
                results.append(MCPToolResult(
                    toolCallID: call.id,
                    result: "Error: \(error.localizedDescription)",
                    isError: true
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Connection Management
    
    /// Connect a server using OAuth credentials
    func connectServer(_ serverID: String, credentials: MCPStoredCredentials) {
        guard let server = servers[serverID] else {
            Logger.error("❌ MCPManager: Server \(serverID) not found", module: "MCP")
            return
        }
        server.setCredentials(credentials)
        objectWillChange.send()
    }
    
    /// Disconnect a server
    func disconnectServer(_ serverID: String) {
        guard let server = servers[serverID] else { return }
        server.disconnect()
        objectWillChange.send()
    }
}




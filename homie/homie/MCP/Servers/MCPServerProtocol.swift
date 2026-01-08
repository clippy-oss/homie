//
//  MCPServerProtocol.swift
//  homie
//
//  Protocol defining the interface for MCP server implementations
//

import Foundation
import Combine

/// Protocol that all MCP server implementations must conform to
protocol MCPServerProtocol: AnyObject {
    /// Unique identifier for this server type
    var serverID: String { get }
    
    /// Configuration for this server
    var config: MCPServerConfig { get }
    
    /// Current connection status
    var connectionStatus: MCPConnectionStatus { get }
    
    /// Publisher for connection status changes
    var connectionStatusPublisher: AnyPublisher<MCPConnectionStatus, Never> { get }
    
    /// Whether the server is currently connected
    var isConnected: Bool { get }
    
    /// The tools this server provides
    var tools: [MCPTool] { get }
    
    /// Set credentials for this server (called after OAuth)
    func setCredentials(_ credentials: MCPStoredCredentials)
    
    /// Clear credentials and disconnect
    func disconnect()
    
    /// Execute a tool with the given arguments
    /// - Parameters:
    ///   - toolName: Name of the tool to execute
    ///   - arguments: Arguments as a dictionary
    /// - Returns: Result string to send back to LLM
    func execute(tool toolName: String, arguments: [String: Any]) async throws -> String
    
    /// Refresh the access token if needed
    func refreshTokenIfNeeded() async throws
}

/// Base class providing common functionality for MCP servers
class BaseMCPServer: MCPServerProtocol, ObservableObject {
    let serverID: String
    let config: MCPServerConfig
    
    @Published private(set) var connectionStatus: MCPConnectionStatus = .disconnected
    
    var connectionStatusPublisher: AnyPublisher<MCPConnectionStatus, Never> {
        $connectionStatus.eraseToAnyPublisher()
    }
    
    var isConnected: Bool {
        connectionStatus.isConnected
    }
    
    var tools: [MCPTool] {
        fatalError("Subclasses must override tools")
    }
    
    var credentials: MCPStoredCredentials?
    
    init(serverID: String, config: MCPServerConfig) {
        self.serverID = serverID
        self.config = config
        loadStoredCredentials()
    }
    
    func setCredentials(_ credentials: MCPStoredCredentials) {
        self.credentials = credentials
        saveCredentials(credentials)
        connectionStatus = .connected(email: credentials.userEmail)
        Logger.info("✅ \(serverID): Credentials set, connected", module: "MCP")
    }
    
    func disconnect() {
        credentials = nil
        clearStoredCredentials()
        connectionStatus = .disconnected
        Logger.info("🔌 \(serverID): Disconnected", module: "MCP")
    }
    
    func execute(tool toolName: String, arguments: [String: Any]) async throws -> String {
        fatalError("Subclasses must override execute(tool:arguments:)")
    }
    
    func refreshTokenIfNeeded() async throws {
        // Subclasses can override if they need token refresh
    }
    
    // MARK: - Connection Status (Protected)
    
    /// Allow subclasses to set connection status (for servers that don't require OAuth)
    func setConnectionStatus(_ status: MCPConnectionStatus) {
        connectionStatus = status
    }
    
    // MARK: - Credential Storage

    private func keychainKey(for serverID: String) -> KeychainManager.KeychainKey? {
        switch serverID {
        case "linear": return .linearCredentials
        case "google_calendar": return .googleCalendarCredentials
        default: return nil
        }
    }

    private func loadStoredCredentials() {
        guard let key = keychainKey(for: serverID) else {
            Logger.warning("⚠️ \(serverID): No keychain key configured for this server", module: "MCP")
            return
        }

        guard let stored: MCPStoredCredentials = KeychainManager.shared.get(key) else {
            return
        }

        // Check if token is expired
        if stored.isExpired {
            Logger.warning("⚠️ \(serverID): Stored token expired", module: "MCP")
            return
        }

        self.credentials = stored
        connectionStatus = .connected(email: stored.userEmail)
        Logger.info("✅ \(serverID): Loaded stored credentials from Keychain", module: "MCP")
    }

    private func saveCredentials(_ credentials: MCPStoredCredentials) {
        guard let key = keychainKey(for: serverID) else {
            Logger.warning("⚠️ \(serverID): No keychain key configured for this server", module: "MCP")
            return
        }

        let success = KeychainManager.shared.save(credentials, for: key)
        if !success {
            Logger.error("❌ \(serverID): Failed to save credentials to Keychain", module: "MCP")
        }
    }

    private func clearStoredCredentials() {
        guard let key = keychainKey(for: serverID) else {
            Logger.warning("⚠️ \(serverID): No keychain key configured for this server", module: "MCP")
            return
        }

        KeychainManager.shared.delete(key)
    }
    
    // MARK: - HTTP Helpers
    
    /// Make an authenticated API request
    func makeAuthenticatedRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        guard let credentials = credentials else {
            throw MCPError.notConnected(serverID: serverID)
        }
        
        // Check if we need to refresh
        if credentials.isExpired {
            try await refreshTokenIfNeeded()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            // Token might be expired, try refresh
            try await refreshTokenIfNeeded()
            // Retry the request with new token
            return try await makeAuthenticatedRequest(url: url, method: method, body: body, contentType: contentType)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MCPError.executionFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        return data
    }
}


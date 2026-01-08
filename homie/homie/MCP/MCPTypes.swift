//
//  MCPTypes.swift
//  homie
//
//  Core types for MCP (Model Context Protocol) tool integration
//

import Foundation

// MARK: - Tool Definition Types (OpenAI Function Calling Format)

/// Represents a tool that can be called by the LLM
struct MCPTool: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let parameters: MCPToolParameters
    let serverID: String  // Which MCP server provides this tool
    
    /// Convert to OpenAI function calling format
    func toOpenAIFormat() -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters.toDictionary()
            ]
        ]
    }
}

/// Parameters schema for a tool (JSON Schema format)
struct MCPToolParameters: Codable {
    let type: String  // Usually "object"
    let properties: [String: MCPToolProperty]
    let required: [String]?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "properties": properties.mapValues { $0.toDictionary() }
        ]
        if let required = required {
            dict["required"] = required
        }
        return dict
    }
}

/// Box wrapper for indirect storage of recursive types
final class Box<T: Codable>: Codable {
    let value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(T.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// A single property in the tool parameters
struct MCPToolProperty: Codable {
    let type: String
    let description: String?
    let enumValues: [String]?
    private let _items: Box<MCPToolProperty>?  // For array types (boxed for indirect storage)
    
    var items: MCPToolProperty? {
        _items?.value
    }
    
    init(type: String, description: String?, enumValues: [String]?, items: MCPToolProperty?) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self._items = items.map { Box($0) }
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case _items = "items"
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let description = description {
            dict["description"] = description
        }
        if let enumValues = enumValues {
            dict["enum"] = enumValues
        }
        if let items = items {
            dict["items"] = items.toDictionary()
        }
        return dict
    }
}

// MARK: - Tool Call Types (from OpenAI response)

/// Represents a tool call requested by the LLM
struct MCPToolCall: Codable {
    let id: String
    let type: String
    let function: MCPFunctionCall
}

/// The function details in a tool call
struct MCPFunctionCall: Codable {
    let name: String
    let arguments: String  // JSON string
    
    /// Parse arguments as dictionary
    func parseArguments() -> [String: Any]? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Result of executing a tool
struct MCPToolResult {
    let toolCallID: String
    let result: String
    let isError: Bool
    
    /// Convert to OpenAI message format
    func toOpenAIMessage() -> [String: Any] {
        return [
            "role": "tool",
            "tool_call_id": toolCallID,
            "content": result
        ]
    }
}

// MARK: - MCP Server Configuration

/// Configuration for an MCP server connection
struct MCPServerConfig: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let iconName: String  // SF Symbol name
    let authURL: String
    let tokenURL: String
    let scopes: [String]
    let redirectPath: String  // e.g., "oauth/linear"
}

/// Connection status for an MCP server
enum MCPConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(email: String?)
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - OAuth Types

/// OAuth token response from token exchange
struct MCPOAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

/// Stored OAuth credentials for an MCP server
struct MCPStoredCredentials: Codable {
    let serverID: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let userEmail: String?
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - Error Types

enum MCPError: LocalizedError {
    case notConnected(serverID: String)
    case authenticationFailed(String)
    case tokenExchangeFailed(String)
    case toolNotFound(String)
    case executionFailed(String)
    case networkError(Error)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConnected(let serverID):
            return "Not connected to \(serverID)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Predefined Server Configurations

extension MCPServerConfig {
    static let linear = MCPServerConfig(
        id: "linear",
        name: "Linear",
        description: "Manage issues and projects",
        iconName: "square.stack.3d.up",
        authURL: "https://linear.app/oauth/authorize",
        tokenURL: "https://api.linear.app/oauth/token",
        scopes: ["read", "write"],
        redirectPath: "oauth/linear"
    )
    
    static let googleCalendar = MCPServerConfig(
        id: "google_calendar",
        name: "Google Calendar",
        description: "View and create calendar events",
        iconName: "calendar",
        authURL: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenURL: "https://oauth2.googleapis.com/token",
        scopes: ["https://www.googleapis.com/auth/calendar.events"],
        redirectPath: "oauth/google"
    )

    static let whatsapp = MCPServerConfig(
        id: "whatsapp",
        name: "WhatsApp",
        description: "Send and receive WhatsApp messages",
        iconName: "message.fill",
        authURL: "",  // Local service - no OAuth
        tokenURL: "",
        scopes: [],
        redirectPath: ""
    )

    /// All available MCP server configurations
    static let allServers: [MCPServerConfig] = [.linear, .googleCalendar, .whatsapp]
}


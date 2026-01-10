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

// MARK: - MCP-Specific Error Types

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


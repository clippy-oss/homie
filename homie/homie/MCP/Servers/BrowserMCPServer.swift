//
//  BrowserMCPServer.swift
//  homie
//
//  MCP server implementation for opening webpages in the browser
//

import Foundation
import Combine

class BrowserMCPServer: BaseMCPServer {
    
    init() {
        super.init(serverID: "browser", config: .browser)
        // Browser server is always "connected" since it doesn't require OAuth
        setConnectionStatus(.connected(email: nil))
    }
    
    // MARK: - Tools
    
    override var tools: [MCPTool] {
        return [
            MCPTool(
                name: "open_browser",
                description: "Open a webpage in the default browser. Accepts either a full URL (e.g., 'https://linkedin.com') or a site name (e.g., 'linkedin' which will open 'https://www.linkedin.com'). If the input doesn't start with 'http://' or 'https://', it will be treated as a site name and converted to a URL.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "url": MCPToolProperty(
                            type: "string",
                            description: "The URL to open (e.g., 'https://linkedin.com') or a site name (e.g., 'linkedin', 'github', 'twitter')",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["url"]
                ),
                serverID: serverID
            )
        ]
    }
    
    // MARK: - Tool Execution
    
    override func execute(tool toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "open_browser":
            return try await openBrowser(arguments: arguments)
        default:
            throw MCPError.toolNotFound(toolName)
        }
    }
    
    // MARK: - Browser Methods
    
    private func openBrowser(arguments: [String: Any]) async throws -> String {
        guard let urlInput = arguments["url"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: url")
        }
        
        // Normalize the URL
        let url = normalizeURL(urlInput)
        
        // Execute the 'open' command via terminal
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return "Opened \(url) in browser"
            } else {
                throw MCPError.executionFailed("Failed to open browser (exit code: \(process.terminationStatus))")
            }
        } catch {
            Logger.error("❌ BrowserMCPServer: Failed to open browser: \(error)", module: "MCP")
            throw MCPError.executionFailed("Failed to open browser: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    /// Normalize URL input - if it doesn't start with http:// or https://, treat it as a site name
    private func normalizeURL(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it already starts with http:// or https://, return as is
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        
        // Otherwise, treat as site name and construct URL
        // Remove common prefixes/suffixes if present
        var siteName = trimmed.lowercased()
        
        // Remove trailing slashes
        if siteName.hasSuffix("/") {
            siteName = String(siteName.dropLast())
        }
        
        // Remove www. prefix if present
        if siteName.hasPrefix("www.") {
            siteName = String(siteName.dropFirst(4))
        }
        
        // Construct URL - try www. first, fallback to direct
        return "https://www.\(siteName)"
    }
}


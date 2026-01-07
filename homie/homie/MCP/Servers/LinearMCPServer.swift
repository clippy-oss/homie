//
//  LinearMCPServer.swift
//  homie
//
//  MCP server implementation for Linear issue tracking
//

import Foundation
import Combine

class LinearMCPServer: BaseMCPServer {
    
    private let apiURL = "https://api.linear.app/graphql"
    
    init() {
        super.init(serverID: "linear", config: .linear)
    }
    
    // MARK: - Tools
    
    override var tools: [MCPTool] {
        return [
            MCPTool(
                name: "linear_list_issues",
                description: "List issues from Linear. Can filter by assignee, team, or state.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "assignee": MCPToolProperty(
                            type: "string",
                            description: "Filter by assignee email or 'me' for current user",
                            enumValues: nil,
                            items: nil
                        ),
                        "team": MCPToolProperty(
                            type: "string",
                            description: "Filter by team name",
                            enumValues: nil,
                            items: nil
                        ),
                        "state": MCPToolProperty(
                            type: "string",
                            description: "Filter by state (e.g., 'In Progress', 'Todo', 'Done')",
                            enumValues: nil,
                            items: nil
                        ),
                        "limit": MCPToolProperty(
                            type: "integer",
                            description: "Maximum number of issues to return (default 10)",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: nil
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "linear_create_issue",
                description: "Create a new issue in Linear",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "title": MCPToolProperty(
                            type: "string",
                            description: "The title of the issue",
                            enumValues: nil,
                            items: nil
                        ),
                        "description": MCPToolProperty(
                            type: "string",
                            description: "The description of the issue (markdown supported)",
                            enumValues: nil,
                            items: nil
                        ),
                        "teamId": MCPToolProperty(
                            type: "string",
                            description: "The ID of the team to create the issue in",
                            enumValues: nil,
                            items: nil
                        ),
                        "priority": MCPToolProperty(
                            type: "integer",
                            description: "Priority: 0=none, 1=urgent, 2=high, 3=medium, 4=low",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["title", "teamId"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "linear_update_issue",
                description: "Update an existing issue in Linear",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "issueId": MCPToolProperty(
                            type: "string",
                            description: "The ID of the issue to update",
                            enumValues: nil,
                            items: nil
                        ),
                        "title": MCPToolProperty(
                            type: "string",
                            description: "New title for the issue",
                            enumValues: nil,
                            items: nil
                        ),
                        "description": MCPToolProperty(
                            type: "string",
                            description: "New description for the issue",
                            enumValues: nil,
                            items: nil
                        ),
                        "stateId": MCPToolProperty(
                            type: "string",
                            description: "New state ID for the issue",
                            enumValues: nil,
                            items: nil
                        ),
                        "priority": MCPToolProperty(
                            type: "integer",
                            description: "New priority: 0=none, 1=urgent, 2=high, 3=medium, 4=low",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["issueId"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "linear_get_teams",
                description: "Get all teams the user has access to in Linear",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                ),
                serverID: serverID
            )
        ]
    }
    
    // MARK: - Tool Execution
    
    override func execute(tool toolName: String, arguments: [String: Any]) async throws -> String {
        guard isConnected else {
            throw MCPError.notConnected(serverID: serverID)
        }
        
        switch toolName {
        case "linear_list_issues":
            return try await listIssues(arguments: arguments)
        case "linear_create_issue":
            return try await createIssue(arguments: arguments)
        case "linear_update_issue":
            return try await updateIssue(arguments: arguments)
        case "linear_get_teams":
            return try await getTeams()
        default:
            throw MCPError.toolNotFound(toolName)
        }
    }
    
    // MARK: - API Methods
    
    private func listIssues(arguments: [String: Any]) async throws -> String {
        let limit = arguments["limit"] as? Int ?? 10
        let assignee = arguments["assignee"] as? String
        let team = arguments["team"] as? String
        let state = arguments["state"] as? String
        
        var filterParts: [String] = []
        
        if let assignee = assignee {
            if assignee.lowercased() == "me" {
                filterParts.append("assignee: { isMe: { eq: true } }")
            } else {
                filterParts.append("assignee: { email: { eq: \"\(assignee)\" } }")
            }
        }
        
        if let team = team {
            filterParts.append("team: { name: { eq: \"\(team)\" } }")
        }
        
        if let state = state {
            filterParts.append("state: { name: { eq: \"\(state)\" } }")
        }
        
        let filter = filterParts.isEmpty ? "" : "filter: { \(filterParts.joined(separator: ", ")) },"
        
        let query = """
        {
            issues(first: \(limit), \(filter) orderBy: updatedAt) {
                nodes {
                    id
                    identifier
                    title
                    description
                    priority
                    state { name }
                    assignee { name email }
                    team { name }
                    createdAt
                    updatedAt
                }
            }
        }
        """
        
        let data = try await executeGraphQL(query: query)
        
        // Parse and format response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let issues = dataDict["issues"] as? [String: Any],
              let nodes = issues["nodes"] as? [[String: Any]] else {
            return "No issues found."
        }
        
        if nodes.isEmpty {
            return "No issues found matching the criteria."
        }
        
        var result = "Found \(nodes.count) issue(s):\n\n"
        
        for issue in nodes {
            let identifier = issue["identifier"] as? String ?? "?"
            let title = issue["title"] as? String ?? "Untitled"
            let state = (issue["state"] as? [String: Any])?["name"] as? String ?? "Unknown"
            let assignee = (issue["assignee"] as? [String: Any])?["name"] as? String ?? "Unassigned"
            let team = (issue["team"] as? [String: Any])?["name"] as? String ?? "No team"
            let priority = issue["priority"] as? Int ?? 0
            let priorityStr = ["None", "Urgent", "High", "Medium", "Low"][min(priority, 4)]
            
            result += "• [\(identifier)] \(title)\n"
            result += "  State: \(state) | Priority: \(priorityStr) | Team: \(team)\n"
            result += "  Assignee: \(assignee)\n\n"
        }
        
        return result
    }
    
    private func createIssue(arguments: [String: Any]) async throws -> String {
        guard let title = arguments["title"] as? String,
              let teamId = arguments["teamId"] as? String else {
            throw MCPError.executionFailed("Missing required parameters: title and teamId")
        }
        
        let description = arguments["description"] as? String ?? ""
        let priority = arguments["priority"] as? Int ?? 0
        
        let mutation = """
        mutation {
            issueCreate(input: {
                title: "\(escapeGraphQLString(title))"
                description: "\(escapeGraphQLString(description))"
                teamId: "\(teamId)"
                priority: \(priority)
            }) {
                success
                issue {
                    id
                    identifier
                    title
                    url
                }
            }
        }
        """
        
        let data = try await executeGraphQL(query: mutation)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let issueCreate = dataDict["issueCreate"] as? [String: Any],
              let success = issueCreate["success"] as? Bool,
              success,
              let issue = issueCreate["issue"] as? [String: Any] else {
            
            // Check for errors
            if let errors = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["message"] as? String {
                throw MCPError.executionFailed(message)
            }
            
            throw MCPError.executionFailed("Failed to create issue")
        }
        
        let identifier = issue["identifier"] as? String ?? "?"
        let url = issue["url"] as? String ?? ""
        
        return "Created issue [\(identifier)] \"\(title)\"\nURL: \(url)"
    }
    
    private func updateIssue(arguments: [String: Any]) async throws -> String {
        guard let issueId = arguments["issueId"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: issueId")
        }
        
        var inputParts: [String] = []
        
        if let title = arguments["title"] as? String {
            inputParts.append("title: \"\(escapeGraphQLString(title))\"")
        }
        if let description = arguments["description"] as? String {
            inputParts.append("description: \"\(escapeGraphQLString(description))\"")
        }
        if let stateId = arguments["stateId"] as? String {
            inputParts.append("stateId: \"\(stateId)\"")
        }
        if let priority = arguments["priority"] as? Int {
            inputParts.append("priority: \(priority)")
        }
        
        if inputParts.isEmpty {
            return "No updates specified."
        }
        
        let mutation = """
        mutation {
            issueUpdate(id: "\(issueId)", input: { \(inputParts.joined(separator: ", ")) }) {
                success
                issue {
                    identifier
                    title
                    state { name }
                }
            }
        }
        """
        
        let data = try await executeGraphQL(query: mutation)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let issueUpdate = dataDict["issueUpdate"] as? [String: Any],
              let success = issueUpdate["success"] as? Bool,
              success,
              let issue = issueUpdate["issue"] as? [String: Any] else {
            throw MCPError.executionFailed("Failed to update issue")
        }
        
        let identifier = issue["identifier"] as? String ?? "?"
        let title = issue["title"] as? String ?? ""
        let state = (issue["state"] as? [String: Any])?["name"] as? String ?? ""
        
        return "Updated issue [\(identifier)] \"\(title)\" - State: \(state)"
    }
    
    private func getTeams() async throws -> String {
        let query = """
        {
            teams {
                nodes {
                    id
                    name
                    key
                    states {
                        nodes {
                            id
                            name
                        }
                    }
                }
            }
        }
        """
        
        let data = try await executeGraphQL(query: query)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let teams = dataDict["teams"] as? [String: Any],
              let nodes = teams["nodes"] as? [[String: Any]] else {
            return "No teams found."
        }
        
        var result = "Teams:\n\n"
        
        for team in nodes {
            let id = team["id"] as? String ?? "?"
            let name = team["name"] as? String ?? "Unnamed"
            let key = team["key"] as? String ?? "?"
            
            result += "• \(name) [\(key)]\n"
            result += "  ID: \(id)\n"
            
            if let states = team["states"] as? [String: Any],
               let stateNodes = states["nodes"] as? [[String: Any]] {
                let stateNames = stateNodes.compactMap { $0["name"] as? String }
                result += "  States: \(stateNames.joined(separator: ", "))\n"
            }
            result += "\n"
        }
        
        return result
    }
    
    // MARK: - Helpers
    
    private func executeGraphQL(query: String) async throws -> Data {
        guard let url = URL(string: apiURL) else {
            throw MCPError.executionFailed("Invalid API URL")
        }
        
        let body = try JSONSerialization.data(withJSONObject: ["query": query])
        
        return try await makeAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body,
            contentType: "application/json"
        )
    }
    
    private func escapeGraphQLString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}




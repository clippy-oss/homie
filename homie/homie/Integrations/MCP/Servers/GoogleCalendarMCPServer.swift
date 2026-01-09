//
//  GoogleCalendarMCPServer.swift
//  homie
//
//  MCP server implementation for Google Calendar
//

import Foundation
import Combine

class GoogleCalendarMCPServer: BaseMCPServer {
    
    private let apiBaseURL = "https://www.googleapis.com/calendar/v3"
    
    init() {
        super.init(serverID: "google_calendar", config: .googleCalendar)
    }
    
    // MARK: - Tools
    
    override var tools: [MCPTool] {
        return [
            MCPTool(
                name: "calendar_list_events",
                description: "List upcoming events from Google Calendar",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "maxResults": MCPToolProperty(
                            type: "integer",
                            description: "Maximum number of events to return (default 10, max 100)",
                            enumValues: nil,
                            items: nil
                        ),
                        "timeMin": MCPToolProperty(
                            type: "string",
                            description: "Start time filter in ISO 8601 format (e.g., '2024-01-01T00:00:00Z'). Defaults to now.",
                            enumValues: nil,
                            items: nil
                        ),
                        "timeMax": MCPToolProperty(
                            type: "string",
                            description: "End time filter in ISO 8601 format",
                            enumValues: nil,
                            items: nil
                        ),
                        "query": MCPToolProperty(
                            type: "string",
                            description: "Search term to filter events by",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: nil
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "calendar_create_event",
                description: "Create a new event in Google Calendar",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "summary": MCPToolProperty(
                            type: "string",
                            description: "Title/summary of the event",
                            enumValues: nil,
                            items: nil
                        ),
                        "description": MCPToolProperty(
                            type: "string",
                            description: "Description of the event",
                            enumValues: nil,
                            items: nil
                        ),
                        "startDateTime": MCPToolProperty(
                            type: "string",
                            description: "Start date and time in ISO 8601 format (e.g., '2024-01-15T10:00:00')",
                            enumValues: nil,
                            items: nil
                        ),
                        "endDateTime": MCPToolProperty(
                            type: "string",
                            description: "End date and time in ISO 8601 format",
                            enumValues: nil,
                            items: nil
                        ),
                        "location": MCPToolProperty(
                            type: "string",
                            description: "Location of the event",
                            enumValues: nil,
                            items: nil
                        ),
                        "attendees": MCPToolProperty(
                            type: "array",
                            description: "List of attendee email addresses",
                            enumValues: nil,
                            items: MCPToolProperty(type: "string", description: nil, enumValues: nil, items: nil)
                        )
                    ],
                    required: ["summary", "startDateTime", "endDateTime"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "calendar_update_event",
                description: "Update an existing event in Google Calendar",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "eventId": MCPToolProperty(
                            type: "string",
                            description: "The ID of the event to update",
                            enumValues: nil,
                            items: nil
                        ),
                        "summary": MCPToolProperty(
                            type: "string",
                            description: "New title/summary of the event",
                            enumValues: nil,
                            items: nil
                        ),
                        "description": MCPToolProperty(
                            type: "string",
                            description: "New description of the event",
                            enumValues: nil,
                            items: nil
                        ),
                        "startDateTime": MCPToolProperty(
                            type: "string",
                            description: "New start date and time in ISO 8601 format",
                            enumValues: nil,
                            items: nil
                        ),
                        "endDateTime": MCPToolProperty(
                            type: "string",
                            description: "New end date and time in ISO 8601 format",
                            enumValues: nil,
                            items: nil
                        ),
                        "location": MCPToolProperty(
                            type: "string",
                            description: "New location of the event",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["eventId"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "calendar_delete_event",
                description: "Delete an event from Google Calendar",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "eventId": MCPToolProperty(
                            type: "string",
                            description: "The ID of the event to delete",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["eventId"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "calendar_get_free_busy",
                description: "Check free/busy status for a time range",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "timeMin": MCPToolProperty(
                            type: "string",
                            description: "Start of time range in ISO 8601 format",
                            enumValues: nil,
                            items: nil
                        ),
                        "timeMax": MCPToolProperty(
                            type: "string",
                            description: "End of time range in ISO 8601 format",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["timeMin", "timeMax"]
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
        case "calendar_list_events":
            return try await listEvents(arguments: arguments)
        case "calendar_create_event":
            return try await createEvent(arguments: arguments)
        case "calendar_update_event":
            return try await updateEvent(arguments: arguments)
        case "calendar_delete_event":
            return try await deleteEvent(arguments: arguments)
        case "calendar_get_free_busy":
            return try await getFreeBusy(arguments: arguments)
        default:
            throw MCPError.toolNotFound(toolName)
        }
    }
    
    // MARK: - API Methods
    
    private func listEvents(arguments: [String: Any]) async throws -> String {
        var queryItems: [URLQueryItem] = []
        
        let maxResults = arguments["maxResults"] as? Int ?? 10
        queryItems.append(URLQueryItem(name: "maxResults", value: String(min(maxResults, 100))))
        
        // Default to now if no timeMin specified
        let timeMin = arguments["timeMin"] as? String ?? ISO8601DateFormatter().string(from: Date())
        queryItems.append(URLQueryItem(name: "timeMin", value: timeMin))
        
        if let timeMax = arguments["timeMax"] as? String {
            queryItems.append(URLQueryItem(name: "timeMax", value: timeMax))
        }
        
        if let query = arguments["query"] as? String {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        
        queryItems.append(URLQueryItem(name: "singleEvents", value: "true"))
        queryItems.append(URLQueryItem(name: "orderBy", value: "startTime"))
        
        var components = URLComponents(string: "\(apiBaseURL)/calendars/primary/events")!
        components.queryItems = queryItems
        
        let data = try await makeAuthenticatedRequest(url: components.url!)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return "No events found."
        }
        
        if items.isEmpty {
            return "No upcoming events found."
        }
        
        var result = "Found \(items.count) event(s):\n\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for event in items {
            let eventId = event["id"] as? String ?? "?"
            let summary = event["summary"] as? String ?? "Untitled Event"
            let location = event["location"] as? String
            let description = event["description"] as? String
            
            // Parse start time
            var startStr = "Unknown time"
            if let start = event["start"] as? [String: Any] {
                if let dateTime = start["dateTime"] as? String {
                    if let date = ISO8601DateFormatter().date(from: dateTime) {
                        startStr = dateFormatter.string(from: date)
                    } else {
                        startStr = dateTime
                    }
                } else if let date = start["date"] as? String {
                    startStr = date + " (All day)"
                }
            }
            
            // Parse end time
            var endStr = ""
            if let end = event["end"] as? [String: Any] {
                if let dateTime = end["dateTime"] as? String {
                    if let date = ISO8601DateFormatter().date(from: dateTime) {
                        endStr = " - " + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
                    }
                }
            }
            
            result += "• \(summary)\n"
            result += "  📅 \(startStr)\(endStr)\n"
            if let location = location, !location.isEmpty {
                result += "  📍 \(location)\n"
            }
            result += "  ID: \(eventId)\n"
            if let description = description, !description.isEmpty {
                let truncated = description.count > 100 ? String(description.prefix(100)) + "..." : description
                result += "  📝 \(truncated)\n"
            }
            result += "\n"
        }
        
        return result
    }
    
    private func createEvent(arguments: [String: Any]) async throws -> String {
        guard let summary = arguments["summary"] as? String,
              let startDateTime = arguments["startDateTime"] as? String,
              let endDateTime = arguments["endDateTime"] as? String else {
            throw MCPError.executionFailed("Missing required parameters: summary, startDateTime, endDateTime")
        }
        
        // Get timezone
        let timeZone = TimeZone.current.identifier
        
        var eventBody: [String: Any] = [
            "summary": summary,
            "start": [
                "dateTime": formatDateTime(startDateTime),
                "timeZone": timeZone
            ],
            "end": [
                "dateTime": formatDateTime(endDateTime),
                "timeZone": timeZone
            ]
        ]
        
        if let description = arguments["description"] as? String {
            eventBody["description"] = description
        }
        
        if let location = arguments["location"] as? String {
            eventBody["location"] = location
        }
        
        if let attendees = arguments["attendees"] as? [String] {
            eventBody["attendees"] = attendees.map { ["email": $0] }
        }
        
        let url = URL(string: "\(apiBaseURL)/calendars/primary/events")!
        let body = try JSONSerialization.data(withJSONObject: eventBody)
        
        let data = try await makeAuthenticatedRequest(url: url, method: "POST", body: body)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.executionFailed("Failed to parse response")
        }
        
        let eventId = json["id"] as? String ?? "?"
        let htmlLink = json["htmlLink"] as? String ?? ""
        
        return "Created event \"\(summary)\"\nID: \(eventId)\nLink: \(htmlLink)"
    }
    
    private func updateEvent(arguments: [String: Any]) async throws -> String {
        guard let eventId = arguments["eventId"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: eventId")
        }
        
        // First, get the existing event
        let getURL = URL(string: "\(apiBaseURL)/calendars/primary/events/\(eventId)")!
        let existingData = try await makeAuthenticatedRequest(url: getURL)
        
        guard var eventBody = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
            throw MCPError.executionFailed("Failed to fetch existing event")
        }
        
        // Update fields
        if let summary = arguments["summary"] as? String {
            eventBody["summary"] = summary
        }
        if let description = arguments["description"] as? String {
            eventBody["description"] = description
        }
        if let location = arguments["location"] as? String {
            eventBody["location"] = location
        }
        if let startDateTime = arguments["startDateTime"] as? String {
            let timeZone = TimeZone.current.identifier
            eventBody["start"] = [
                "dateTime": formatDateTime(startDateTime),
                "timeZone": timeZone
            ]
        }
        if let endDateTime = arguments["endDateTime"] as? String {
            let timeZone = TimeZone.current.identifier
            eventBody["end"] = [
                "dateTime": formatDateTime(endDateTime),
                "timeZone": timeZone
            ]
        }
        
        let body = try JSONSerialization.data(withJSONObject: eventBody)
        _ = try await makeAuthenticatedRequest(url: getURL, method: "PUT", body: body)
        
        let summary = eventBody["summary"] as? String ?? "Event"
        return "Updated event \"\(summary)\""
    }
    
    private func deleteEvent(arguments: [String: Any]) async throws -> String {
        guard let eventId = arguments["eventId"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: eventId")
        }
        
        let url = URL(string: "\(apiBaseURL)/calendars/primary/events/\(eventId)")!
        _ = try await makeAuthenticatedRequest(url: url, method: "DELETE")
        
        return "Event deleted successfully"
    }
    
    private func getFreeBusy(arguments: [String: Any]) async throws -> String {
        guard let timeMin = arguments["timeMin"] as? String,
              let timeMax = arguments["timeMax"] as? String else {
            throw MCPError.executionFailed("Missing required parameters: timeMin, timeMax")
        }
        
        let url = URL(string: "\(apiBaseURL)/freeBusy")!
        
        let requestBody: [String: Any] = [
            "timeMin": formatDateTime(timeMin),
            "timeMax": formatDateTime(timeMax),
            "items": [["id": "primary"]]
        ]
        
        let body = try JSONSerialization.data(withJSONObject: requestBody)
        let data = try await makeAuthenticatedRequest(url: url, method: "POST", body: body)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let calendars = json["calendars"] as? [String: Any],
              let primary = calendars["primary"] as? [String: Any],
              let busy = primary["busy"] as? [[String: Any]] else {
            return "Unable to retrieve free/busy information"
        }
        
        if busy.isEmpty {
            return "You are free during this time period!"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        var result = "Busy times:\n\n"
        
        for period in busy {
            guard let start = period["start"] as? String,
                  let end = period["end"] as? String else { continue }
            
            let startDate = ISO8601DateFormatter().date(from: start) ?? Date()
            let endDate = ISO8601DateFormatter().date(from: end) ?? Date()
            
            result += "• \(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))\n"
        }
        
        return result
    }
    
    // MARK: - Token Refresh

    override func refreshTokenIfNeeded() async throws {
        guard let credentials = credentials,
              let refreshToken = credentials.refreshToken else {
            throw MCPError.authenticationFailed("No refresh token available")
        }

        // Check if token needs refresh (within 60 seconds of expiry)
        if let expiresAt = credentials.expiresAt, Date() < expiresAt.addingTimeInterval(-60) {
            return // Token still valid
        }

        Logger.info("🔄 GoogleCalendarMCPServer: Refreshing token via edge function...", module: "MCP")

        // Use MCPOAuthManager to refresh via edge function
        let tokenResponse = try await MCPOAuthManager.shared.refreshToken(
            for: serverID,
            refreshToken: refreshToken
        )

        var expiresAt: Date? = nil
        if let expiresIn = tokenResponse.expiresIn {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }

        let newCredentials = MCPStoredCredentials(
            serverID: serverID,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: expiresAt,
            userEmail: credentials.userEmail
        )

        setCredentials(newCredentials)
        Logger.info("✅ GoogleCalendarMCPServer: Token refreshed", module: "MCP")
    }
    
    // MARK: - Helpers
    
    private func formatDateTime(_ dateTime: String) -> String {
        // If already in ISO 8601 format with timezone, return as is
        if dateTime.contains("Z") || dateTime.contains("+") || dateTime.contains("-", at: dateTime.index(dateTime.endIndex, offsetBy: -6)) {
            return dateTime
        }
        
        // Otherwise, append timezone offset
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        // Try parsing various formats
        let inputFormatters = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm"
        ]
        
        for format in inputFormatters {
            let df = DateFormatter()
            df.dateFormat = format
            df.timeZone = TimeZone.current
            
            if let date = df.date(from: dateTime) {
                return formatter.string(from: date)
            }
        }
        
        // Return original if parsing fails
        return dateTime
    }
}

// Helper extension
private extension String {
    func contains(_ string: String, at index: String.Index) -> Bool {
        guard index < endIndex else { return false }
        return self[index...].hasPrefix(string)
    }
}




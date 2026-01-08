//
//  LocalRemindersMCPServer.swift
//  homie
//
//  MCP server implementation for local macOS Reminders using EventKit
//

import Foundation
import Combine
import EventKit

class LocalRemindersMCPServer: BaseMCPServer {
    
    private let eventStore = EKEventStore()
    @Published private var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    init() {
        super.init(serverID: "local_reminders", config: .localReminders)
        // Local reminders server is always "connected" once authorized
        checkAuthorizationStatus()
    }
    
    // MARK: - Tools
    
    override var tools: [MCPTool] {
        // Only provide tools if we have authorization
        guard authorizationStatus == .authorized else {
            return []
        }
        
        return [
            MCPTool(
                name: "reminder_create",
                description: "Create a new reminder in the macOS Reminders app. Today is \(todayDateString), tomorrow is \(tomorrowDateString).",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "title": MCPToolProperty(
                            type: "string",
                            description: "The title of the reminder (required)",
                            enumValues: nil,
                            items: nil
                        ),
                        "notes": MCPToolProperty(
                            type: "string",
                            description: "Additional notes or description for the reminder",
                            enumValues: nil,
                            items: nil
                        ),
                        "dueDate": MCPToolProperty(
                            type: "string",
                            description: "Due date and time in ISO 8601 format (e.g., '\(todayDateString)T15:00:00'). Today is \(todayDateString). If not provided, reminder has no due date.",
                            enumValues: nil,
                            items: nil
                        ),
                        "priority": MCPToolProperty(
                            type: "integer",
                            description: "Priority level: 0 = none, 1-4 = low, 5 = medium, 6-9 = high. Default is 0.",
                            enumValues: nil,
                            items: nil
                        ),
                        "alarmOffset": MCPToolProperty(
                            type: "integer",
                            description: "Alarm offset in seconds before due date (negative value, e.g., -900 for 15 minutes before). If not provided but a due date is set, a default alarm will be added at the due date time.",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["title"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "reminder_list",
                description: "List reminders from the macOS Reminders app",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "completed": MCPToolProperty(
                            type: "boolean",
                            description: "Whether to include completed reminders (default: false)",
                            enumValues: nil,
                            items: nil
                        ),
                        "limit": MCPToolProperty(
                            type: "integer",
                            description: "Maximum number of reminders to return (default: 20, max: 100)",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: nil
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "reminder_complete",
                description: "Mark a reminder as completed",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "reminderId": MCPToolProperty(
                            type: "string",
                            description: "The calendarItemIdentifier of the reminder to complete",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["reminderId"]
                ),
                serverID: serverID
            )
        ]
    }
    
    // MARK: - Tool Execution
    
    override func execute(tool toolName: String, arguments: [String: Any]) async throws -> String {
        // Ensure we have authorization
        try await ensureAuthorization()
        
        switch toolName {
        case "reminder_create":
            return try await createReminder(arguments: arguments)
        case "reminder_list":
            return try await listReminders(arguments: arguments)
        case "reminder_complete":
            return try await completeReminder(arguments: arguments)
        default:
            throw MCPError.toolNotFound(toolName)
        }
    }
    
    // MARK: - Authorization
    
    private func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        if authorizationStatus == .authorized {
            setConnectionStatus(.connected(email: nil))
        } else {
            setConnectionStatus(.disconnected)
        }
    }
    
    func ensureAuthorization() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        
        // Update our internal status
        await MainActor.run {
            authorizationStatus = status
        }
        
        // If already authorized, just ensure connection status is set
        if status == .authorized {
            await MainActor.run {
                setConnectionStatus(.connected(email: nil))
            }
            return
        }
        
        // If previously denied or restricted, throw error with instructions
        if status == .denied || status == .restricted {
            throw MCPError.authenticationFailed("Reminders access denied. Please enable it in System Settings > Privacy & Security > Reminders.")
        }
        
        // Status is .notDetermined - request access
        let granted = try await eventStore.requestAccess(to: .reminder)
        
        // Update status after request
        let newStatus = EKEventStore.authorizationStatus(for: .reminder)
        await MainActor.run {
            authorizationStatus = newStatus
            if granted && newStatus == .authorized {
                setConnectionStatus(.connected(email: nil))
                Logger.info("✅ LocalRemindersMCPServer: Authorization granted", module: "MCP")
            } else {
                setConnectionStatus(.disconnected)
            }
        }
        
        // Throw error only if access was denied
        if !granted {
            throw MCPError.authenticationFailed("Reminders access denied by user")
        }
    }
    
    // MARK: - Reminder Methods
    
    private func createReminder(arguments: [String: Any]) async throws -> String {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw MCPError.executionFailed("Missing required parameter: title")
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        
        // Set notes if provided
        if let notes = arguments["notes"] as? String, !notes.isEmpty {
            reminder.notes = notes
        }
        
        // Set due date if provided
        var hasDueDate = false
        var dueDate: Date?
        if let dueDateString = arguments["dueDate"] as? String {
            if let parsedDate = parseDateTimeString(dueDateString) {
                dueDate = parsedDate
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: parsedDate)
                reminder.dueDateComponents = components
                hasDueDate = true
            }
        }
        
        // Set priority if provided (EventKit uses 0-9, we'll map it)
        if let priority = arguments["priority"] as? Int {
            reminder.priority = min(max(priority, 0), 9)
        }
        
        // Set alarm if provided
        if let alarmOffset = arguments["alarmOffset"] as? Int {
            let alarm = EKAlarm(relativeOffset: TimeInterval(alarmOffset))
            reminder.addAlarm(alarm)
        } else if hasDueDate, let dueDate = dueDate {
            // If due date is set but no alarmOffset provided, add default alarm at due date time
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }
        
        // Set calendar (use default)
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        // Save the reminder
        do {
            try eventStore.save(reminder, commit: true)
            Logger.info("✅ LocalRemindersMCPServer: Created reminder '\(title)'", module: "MCP")
            
            var result = "Created reminder \"\(title)\""
            if let dueDate = reminder.dueDateComponents?.date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                result += "\nDue: \(formatter.string(from: dueDate))"
            }
            if reminder.hasAlarms {
                if let alarmDate = reminder.alarms?.first?.absoluteDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    result += "\nAlarm: \(formatter.string(from: alarmDate))"
                } else {
                    result += "\nAlarm: Set"
                }
            }
            return result
        } catch {
            Logger.error("❌ LocalRemindersMCPServer: Failed to save reminder: \(error)", module: "MCP")
            throw MCPError.executionFailed("Failed to create reminder: \(error.localizedDescription)")
        }
    }
    
    private func listReminders(arguments: [String: Any]) async throws -> String {
        let includeCompleted = arguments["completed"] as? Bool ?? false
        let limit = min(arguments["limit"] as? Int ?? 20, 100)
        
        // Get all reminder calendars
        let calendars = eventStore.calendars(for: .reminder)
        
        // Create predicate
        var predicate = eventStore.predicateForReminders(in: calendars)
        
        // Fetch reminders
        var reminders: [EKReminder] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        eventStore.fetchReminders(matching: predicate) { fetchedReminders in
            guard let fetched = fetchedReminders else {
                semaphore.signal()
                return
            }
            
            // Filter by completion status
            reminders = fetched.filter { reminder in
                if reminder.isCompleted {
                    return includeCompleted
                }
                return true
            }
            
            // Sort by due date (incomplete first, then by due date)
            reminders.sort { r1, r2 in
                if r1.isCompleted != r2.isCompleted {
                    return !r1.isCompleted // Incomplete first
                }
                
                if let date1 = r1.dueDateComponents?.date,
                   let date2 = r2.dueDateComponents?.date {
                    return date1 < date2
                }
                
                if r1.dueDateComponents?.date != nil {
                    return true // r1 has date, r2 doesn't
                }
                if r2.dueDateComponents?.date != nil {
                    return false // r2 has date, r1 doesn't
                }
                
                return false
            }
            
            // Limit results
            reminders = Array(reminders.prefix(limit))
            
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if reminders.isEmpty {
            return "No reminders found."
        }
        
        var result = "Found \(reminders.count) reminder(s):\n\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for reminder in reminders {
            let status = reminder.isCompleted ? "✅" : "⏳"
            result += "\(status) \(reminder.title)\n"
            
            if let dueDate = reminder.dueDateComponents?.date {
                result += "  📅 Due: \(dateFormatter.string(from: dueDate))\n"
            }
            
            if reminder.priority > 0 {
                let priorityText = reminder.priority >= 6 ? "High" : reminder.priority >= 5 ? "Medium" : "Low"
                result += "  ⚠️ Priority: \(priorityText)\n"
            }
            
            if let notes = reminder.notes, !notes.isEmpty {
                let truncated = notes.count > 50 ? String(notes.prefix(50)) + "..." : notes
                result += "  📝 \(truncated)\n"
            }
            
            result += "  ID: \(reminder.calendarItemIdentifier)\n\n"
        }
        
        return result
    }
    
    private func completeReminder(arguments: [String: Any]) async throws -> String {
        guard let reminderId = arguments["reminderId"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: reminderId")
        }
        
        // Find the reminder
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw MCPError.executionFailed("Reminder not found with ID: \(reminderId)")
        }
        
        reminder.isCompleted = true
        reminder.completionDate = Date()
        
        do {
            try eventStore.save(reminder, commit: true)
            Logger.info("✅ LocalRemindersMCPServer: Completed reminder '\(reminder.title)'", module: "MCP")
            return "Marked reminder \"\(reminder.title)\" as completed"
        } catch {
            Logger.error("❌ LocalRemindersMCPServer: Failed to complete reminder: \(error)", module: "MCP")
            throw MCPError.executionFailed("Failed to complete reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    /// Today's date in YYYY-MM-DD format
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    /// Tomorrow's date in YYYY-MM-DD format
    private var tomorrowDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return formatter.string(from: tomorrow)
    }
    
    private func parseDateTimeString(_ dateTime: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: dateTime) {
                return date
            }
        }
        
        // Try ISO8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateTime) {
            return date
        }
        
        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: dateTime)
    }
}


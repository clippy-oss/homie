//
//  NotchManager.swift
//  homie
//
//  Created by Maximilian Prokopp on 07.01.26.
//

import SwiftUI
import DynamicNotchKit

/// The different expansion modes for the notch
enum NotchExpansionMode: String, CaseIterable {
    case sideOnly = "Side Only"
    case downOnly = "Down Only"
    case wide = "Wide"
    
    var icon: String {
        switch self {
        case .sideOnly: return "arrow.left.and.right"
        case .downOnly: return "arrow.down"
        case .wide: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// Voice processing states for the voice notch
enum VoiceNotchState {
    case listening
    case thinking    // For VoiceGPT AI processing
    case processing  // For raw dictation processing
    case toolConfirmation  // For showing tool call confirmation
}

/// Manages the Dynamic Notch UI for displaying content in the MacBook notch area.
/// Uses DynamicNotchKit under the hood.
@MainActor
final class NotchManager: ObservableObject {
    static let shared = NotchManager()
    
    @Published private(set) var isExpanded: Bool = false
    @Published private(set) var currentMode: NotchExpansionMode?
    
    // Separate notch instances for each mode (different content types)
    private var sideNotch: DynamicNotch<NotchSideView, EmptyView, EmptyView>?
    private var downNotch: DynamicNotch<NotchDownView, EmptyView, EmptyView>?
    private var wideNotch: DynamicNotch<NotchWideView, EmptyView, EmptyView>?
    
    // Single voice notch with dynamic state
    private var voiceNotch: DynamicNotch<NotchVoiceView, EmptyView, EmptyView>?
    
    /// Current voice state (nil when not active)
    @Published var voiceState: VoiceNotchState? = nil
    
    /// Whether the voice notch is currently visible
    @Published private(set) var isVoiceNotchVisible: Bool = false
    
    // MARK: - Tool Confirmation State
    
    /// Pending tool call awaiting user confirmation
    @Published var pendingToolCall: MCPToolCall? = nil
    
    /// Editable tool call arguments (JSON dictionary)
    @Published var editableToolArguments: [String: String] = [:]
    
    /// Callbacks for tool confirmation
    var onToolApproved: ((MCPToolCall) -> Void)?
    var onToolCancelled: (() -> Void)?
    
    /// UI state for dropdowns
    @Published var showStatusDropdown: Bool = false
    @Published var showPriorityDropdown: Bool = false
    
    private init() {}
    
    /// Toggles a specific notch mode
    func toggle(mode: NotchExpansionMode) {
        if isExpanded && currentMode == mode {
            hide()
        } else {
            expand(mode: mode)
        }
    }
    
    /// Expands the notch with a specific mode
    func expand(mode: NotchExpansionMode) {
        // If already expanded with a different mode, hide first
        if isExpanded {
            hideImmediately()
        }
        
        currentMode = mode
        isExpanded = true
        
        Task {
            switch mode {
            case .sideOnly:
                if sideNotch == nil {
                    sideNotch = DynamicNotch(
                        hoverBehavior: .all,
                        style: .auto
                    ) {
                        NotchSideView()
                    }
                }
                await sideNotch?.expand()
                
            case .downOnly:
                if downNotch == nil {
                    downNotch = DynamicNotch(
                        hoverBehavior: .all,
                        style: .auto
                    ) {
                        NotchDownView()
                    }
                }
                await downNotch?.expand()
                
            case .wide:
                if wideNotch == nil {
                    wideNotch = DynamicNotch(
                        hoverBehavior: .all,
                        style: .auto
                    ) {
                        NotchWideView()
                    }
                }
                await wideNotch?.expand()
            }
        }
    }
    
    /// Hides the notch with animation
    func hide() {
        guard isExpanded, let mode = currentMode else { return }
        
        isExpanded = false
        
        Task {
            switch mode {
            case .sideOnly:
                await sideNotch?.hide()
            case .downOnly:
                await downNotch?.hide()
            case .wide:
                await wideNotch?.hide()
            }
            currentMode = nil
        }
    }
    
    /// Hides immediately without waiting (for mode switching)
    private func hideImmediately() {
        guard let mode = currentMode else { return }
        
        Task {
            switch mode {
            case .sideOnly:
                await sideNotch?.hide()
            case .downOnly:
                await downNotch?.hide()
            case .wide:
                await wideNotch?.hide()
            }
        }
        
        isExpanded = false
        currentMode = nil
    }
    
    // MARK: - Voice Notch (unified for all voice states)
    
    /// Shows the voice notch with the specified state
    func showVoiceNotch(state: VoiceNotchState) {
        // Hide any expanded notch first
        if isExpanded {
            hideImmediately()
        }
        
        // If notch is already visible, just update the state (smooth transition)
        if isVoiceNotchVisible {
            voiceState = state
            return
        }
        
        // First time showing, create and expand the notch
        isVoiceNotchVisible = true
        voiceState = state
        
        Task {
            if voiceNotch == nil {
                voiceNotch = DynamicNotch(
                    hoverBehavior: .all,
                    style: .auto
                ) {
                    NotchVoiceView()
                }
            }
            await voiceNotch?.expand()
        }
    }
    
    /// Hides the voice notch
    func hideVoiceNotch() {
        guard isVoiceNotchVisible else { return }
        
        isVoiceNotchVisible = false
        voiceState = nil
        
        Task {
            await voiceNotch?.hide()
        }
    }
    
    // MARK: - Convenience methods for specific states
    
    func showListening() {
        showVoiceNotch(state: .listening)
    }
    
    func showThinking() {
        showVoiceNotch(state: .thinking)
    }
    
    func showProcessing() {
        showVoiceNotch(state: .processing)
    }
    
    func hideListening() {
        hideVoiceNotch()
    }
    
    func hideThinking() {
        hideVoiceNotch()
    }
    
    func hideProcessing() {
        hideVoiceNotch()
    }
    
    // MARK: - Tool Confirmation Methods
    
    /// Shows tool confirmation notch with editable parameters
    func showToolConfirmation(
        toolCall: MCPToolCall,
        onApproved: @escaping (MCPToolCall) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        // Store the pending tool call
        self.pendingToolCall = toolCall
        self.onToolApproved = onApproved
        self.onToolCancelled = onCancelled
        
        // Parse arguments into editable format
        if let args = toolCall.function.parseArguments() {
            self.editableToolArguments = args.mapValues { value in
                if let str = value as? String {
                    return str
                } else if let num = value as? NSNumber {
                    return num.stringValue
                } else if let arr = value as? [String] {
                    // Convert string arrays (like attendees) to comma-separated
                    return arr.joined(separator: ", ")
                } else {
                    return String(describing: value)
                }
            }
        }
        
        // Ensure all Linear issue fields exist (even if empty)
        if toolCall.function.name == "linear_create_issue" {
            if editableToolArguments["title"] == nil {
                editableToolArguments["title"] = ""
            }
            if editableToolArguments["description"] == nil {
                editableToolArguments["description"] = ""
            }
            if editableToolArguments["priority"] == nil {
                editableToolArguments["priority"] = "0"
            }
        }
        
        // Ensure all Calendar event fields exist (even if empty)
        if toolCall.function.name == "calendar_create_event" {
            if editableToolArguments["summary"] == nil {
                editableToolArguments["summary"] = ""
            }
            if editableToolArguments["description"] == nil {
                editableToolArguments["description"] = ""
            }
            if editableToolArguments["startDateTime"] == nil {
                editableToolArguments["startDateTime"] = ""
            }
            if editableToolArguments["endDateTime"] == nil {
                editableToolArguments["endDateTime"] = ""
            }
            if editableToolArguments["location"] == nil {
                editableToolArguments["location"] = ""
            }
            if editableToolArguments["attendees"] == nil {
                editableToolArguments["attendees"] = ""
            }
        }
        
        // Show tool confirmation notch
        showVoiceNotch(state: .toolConfirmation)
    }
    
    /// User approved the tool call
    func approveToolCall() {
        guard let toolCall = pendingToolCall else { return }
        
        // Prepare arguments - handle special conversions
        var finalArguments: [String: Any] = [:]
        
        for (key, value) in editableToolArguments {
            // Convert attendees back to array for calendar events
            if key == "attendees" && toolCall.function.name.contains("calendar") {
                let attendeesArray = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if !attendeesArray.isEmpty && !attendeesArray[0].isEmpty {
                    finalArguments[key] = attendeesArray
                }
            } else if key == "priority" {
                // Convert priority to integer
                finalArguments[key] = Int(value) ?? 0
            } else {
                finalArguments[key] = value
            }
        }
        
        // Reconstruct tool call with edited arguments
        let editedArgumentsJSON = try? JSONSerialization.data(
            withJSONObject: finalArguments,
            options: []
        )
        let editedArgumentsString = editedArgumentsJSON.flatMap { String(data: $0, encoding: .utf8) } ?? toolCall.function.arguments
        
        let updatedToolCall = MCPToolCall(
            id: toolCall.id,
            type: toolCall.type,
            function: MCPFunctionCall(
                name: toolCall.function.name,
                arguments: editedArgumentsString
            )
        )
        
        // Call the approval callback
        onToolApproved?(updatedToolCall)
        
        // Clean up
        clearToolConfirmation()
        hideVoiceNotch()
    }
    
    /// User cancelled the tool call
    func cancelToolCall() {
        onToolCancelled?()
        clearToolConfirmation()
        hideVoiceNotch()
    }
    
    /// Clear tool confirmation state
    private func clearToolConfirmation() {
        pendingToolCall = nil
        editableToolArguments = [:]
        onToolApproved = nil
        onToolCancelled = nil
    }
    
    // MARK: - Debug Methods
    
    /// Debug method to show tool confirmation with mock Linear data
    func debugShowLinearToolConfirmation() {
        // Create mock Linear tool call
        let mockArguments = """
        {
            "title": "Test Linear Issue",
            "description": "This is a test description for debugging the UI",
            "teamId": "mock-team-id-123",
            "priority": 2
        }
        """
        
        let mockToolCall = MCPToolCall(
            id: "debug-call-123",
            type: "function",
            function: MCPFunctionCall(
                name: "linear_create_issue",
                arguments: mockArguments
            )
        )
        
        showToolConfirmation(
            toolCall: mockToolCall,
            onApproved: { confirmedCall in
                Logger.info("🐛 Debug: Tool call approved with args: \(confirmedCall.function.arguments)", module: "Debug")
                NotchManager.shared.hideVoiceNotch()
            },
            onCancelled: {
                Logger.info("🐛 Debug: Tool call cancelled", module: "Debug")
                NotchManager.shared.hideVoiceNotch()
            }
        )
    }
    
    /// Debug method to show tool confirmation with mock Calendar data
    func debugShowCalendarToolConfirmation() {
        // Create mock Calendar tool call
        let mockArguments = """
        {
            "summary": "Team Sync Meeting",
            "description": "Weekly team sync to discuss project progress",
            "startDateTime": "2025-01-15T10:00:00",
            "endDateTime": "2025-01-15T11:00:00",
            "location": "Conference Room A",
            "attendees": ["alice@example.com", "bob@example.com"]
        }
        """
        
        let mockToolCall = MCPToolCall(
            id: "debug-call-456",
            type: "function",
            function: MCPFunctionCall(
                name: "calendar_create_event",
                arguments: mockArguments
            )
        )
        
        showToolConfirmation(
            toolCall: mockToolCall,
            onApproved: { confirmedCall in
                Logger.info("🐛 Debug: Calendar tool approved with args: \(confirmedCall.function.arguments)", module: "Debug")
                NotchManager.shared.hideVoiceNotch()
            },
            onCancelled: {
                Logger.info("🐛 Debug: Calendar tool cancelled", module: "Debug")
                NotchManager.shared.hideVoiceNotch()
            }
        )
    }
}

// MARK: - Notch Content Views

/// Side-only expansion: Wide but short (horizontal emphasis)
struct NotchSideView: View {
    var body: some View {
        HStack(spacing: 20) {
            // Left section
            HStack(spacing: 12) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.yellow)
                
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            // Divider
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: 20)
            
            // Center - Title
            Text("Side Expansion")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            
            // Divider
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: 20)
            
            // Right section
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                
                Image(systemName: "airplayaudio")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

/// Down-only expansion: Narrow but tall (vertical emphasis)
struct NotchDownView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "paperclip")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)
            
            Text("Homie")
                .font(.headline)
                .foregroundStyle(.white)
            
            Text("Your AI assistant")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            
            Divider()
                .background(.white.opacity(0.2))
            
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.yellow)
                    Text("Ready to listen")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 160)
    }
}

/// Unified voice notch view that displays different states
struct NotchVoiceView: View {
    @ObservedObject private var notchManager = NotchManager.shared
    
    var body: some View {
        Group {
            if notchManager.voiceState == .toolConfirmation {
                // Show expanded tool confirmation UI
                ToolConfirmationNotchView()
            } else {
                // Show compact voice state
                HStack(spacing: 6) {
                    // Shader animation on the left (blue for normal states)
                    ShaderAnimationView(size: 50, color: .blue)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Dynamic text based on state with fixed width
                    ZStack {
                        // Hidden placeholder text to set the width (longest text)
                        Text("Processing")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0)
                        
                        // Actual visible text
                        Text(stateText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notchManager.voiceState)
    }
    
    private var stateText: String {
        switch notchManager.voiceState {
        case .listening:
            return "Listening"
        case .thinking:
            return "Thinking"
        case .processing:
            return "Processing"
        case .toolConfirmation:
            return ""
        case nil:
            return ""
        }
    }
}

/// Wide expansion: Both wide and tall (full content)
struct NotchWideView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Header row
            HStack {
                Image(systemName: "paperclip")
                    .font(.system(size: 24))
                    .foregroundStyle(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homie")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Your AI assistant")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Status indicators
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Online")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            
            Divider()
                .background(.white.opacity(0.2))
            
            // Content grid
            HStack(spacing: 20) {
                // Quick actions
                VStack(spacing: 12) {
                    QuickActionButton(icon: "mic.fill", label: "Voice", color: .yellow)
                    QuickActionButton(icon: "keyboard", label: "Type", color: .blue)
                }
                
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                
                // Recent activity
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    
                    RecentItem(text: "Draft email reply", time: "2m ago")
                    RecentItem(text: "Summarize document", time: "15m ago")
                    RecentItem(text: "Code review", time: "1h ago")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Tool Confirmation View

struct ToolConfirmationNotchView: View {
    @ObservedObject private var notchManager = NotchManager.shared
    
    private var isCalendarTool: Bool {
        notchManager.pendingToolCall?.function.name.contains("calendar") ?? false
    }
    
    var body: some View {
        Group {
            if isCalendarTool {
                CalendarToolConfirmationView()
            } else {
                LinearToolConfirmationView()
            }
        }
    }
}

// MARK: - Linear Tool Confirmation View

struct LinearToolConfirmationView: View {
    @ObservedObject private var notchManager = NotchManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title field
            TextField("Add title...", text: Binding(
                get: { notchManager.editableToolArguments["title"] ?? "" },
                set: { notchManager.editableToolArguments["title"] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.clear)
            
            // Description field
            TextField("Add description...", text: Binding(
                get: { notchManager.editableToolArguments["description"] ?? "" },
                set: { notchManager.editableToolArguments["description"] = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.9))
            .padding(8)
            .background(.clear)
            .frame(minHeight: 60, alignment: .topLeading)
            
            // Status, Priority, and Action buttons
            HStack(spacing: 8) {
                // Status dropdown
                Menu {
                    Button(action: { selectStatus(1) }) {
                        Label("Backlog", systemImage: "circle.dotted")
                    }
                    Button(action: { selectStatus(2) }) {
                        Label("Todo", systemImage: "circle")
                    }
                    Button(action: { selectStatus(3) }) {
                        Label("In Progress", systemImage: "circle.lefthalf.filled")
                    }
                    Button(action: { selectStatus(4) }) {
                        Label("In Review", systemImage: "checkmark.circle")
                    }
                    Button(action: { selectStatus(5) }) {
                        Label("Done", systemImage: "checkmark.circle.fill")
                    }
                    Button(action: { selectStatus(6) }) {
                        Label("Canceled", systemImage: "xmark.circle")
                    }
                    Button(action: { selectStatus(7) }) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor)
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                
                // Priority dropdown
                Menu {
                    Button(action: { selectPriority(0) }) {
                        Label("No priority", systemImage: "minus")
                    }
                    Button(action: { selectPriority(1) }) {
                        Label("Urgent", systemImage: "exclamationmark.square.fill")
                    }
                    Button(action: { selectPriority(2) }) {
                        Label("High", systemImage: "equal.square.fill")
                    }
                    Button(action: { selectPriority(3) }) {
                        Label("Medium", systemImage: "equal.square")
                    }
                    Button(action: { selectPriority(4) }) {
                        Label("Low", systemImage: "equal")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: priorityIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(priorityText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                // Cancel button
                Button(action: {
                    notchManager.cancelToolCall()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                // Execute button
                Button(action: {
                    notchManager.approveToolCall()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.indigo)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 350)
    }
    
    // MARK: - Status Properties
    
    private var statusText: String { "Backlog" }
    private var statusIcon: String { "circle.dotted" }
    private var statusColor: Color { .white.opacity(0.5) }
    
    private func selectStatus(_ status: Int) {
        Logger.info("Selected status: \(status)", module: "UI")
    }
    
    // MARK: - Priority Properties
    
    private var priorityText: String {
        guard let priorityStr = notchManager.editableToolArguments["priority"],
              let priority = Int(priorityStr) else {
            return "No priority"
        }
        switch priority {
        case 0: return "No priority"
        case 1: return "Urgent"
        case 2: return "High"
        case 3: return "Medium"
        case 4: return "Low"
        default: return "No priority"
        }
    }
    
    private var priorityIcon: String {
        guard let priorityStr = notchManager.editableToolArguments["priority"],
              let priority = Int(priorityStr) else {
            return "minus"
        }
        switch priority {
        case 0: return "minus"
        case 1: return "exclamationmark.square.fill"
        case 2: return "equal.square.fill"
        case 3: return "equal.square"
        case 4: return "equal"
        default: return "minus"
        }
    }
    
    private func selectPriority(_ priority: Int) {
        notchManager.editableToolArguments["priority"] = String(priority)
    }
}

// MARK: - Calendar Tool Confirmation View

struct CalendarToolConfirmationView: View {
    @ObservedObject private var notchManager = NotchManager.shared
    
    // State for date/time pickers
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var startTimeText: String = "10:00"
    @State private var endTimeText: String = "11:00"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary field (like title)
            TextField("Add event title...", text: Binding(
                get: { notchManager.editableToolArguments["summary"] ?? "" },
                set: { notchManager.editableToolArguments["summary"] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.clear)
            
            // Description field
            TextField("Add description...", text: Binding(
                get: { notchManager.editableToolArguments["description"] ?? "" },
                set: { notchManager.editableToolArguments["description"] = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.9))
            .padding(8)
            .background(.clear)
            .frame(minHeight: 40, alignment: .topLeading)
            
            // Start Date/Time row
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                
                // Start Date picker button
                DatePickerButton(
                    date: $startDate,
                    showPicker: $showStartDatePicker,
                    onDateChanged: { updateStartDateTime() }
                )
                
                // Start Time input
                TimeInputField(timeText: $startTimeText, onChanged: { updateStartDateTime() })
            }
            
            // End Date/Time row
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red.opacity(0.8))
                
                // End Date picker button
                DatePickerButton(
                    date: $endDate,
                    showPicker: $showEndDatePicker,
                    onDateChanged: { updateEndDateTime() }
                )
                
                // End Time input
                TimeInputField(timeText: $endTimeText, onChanged: { updateEndDateTime() })
            }
            
            // Location field
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Add location...", text: Binding(
                    get: { notchManager.editableToolArguments["location"] ?? "" },
                    set: { notchManager.editableToolArguments["location"] = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.05))
            .cornerRadius(6)
            
            // Attendees and Action buttons
            HStack(spacing: 8) {
                // Attendees field
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Attendees...", text: Binding(
                        get: { notchManager.editableToolArguments["attendees"] ?? "" },
                        set: { notchManager.editableToolArguments["attendees"] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.05))
                .cornerRadius(6)
                
                Spacer()
                
                // Cancel button
                Button(action: {
                    notchManager.cancelToolCall()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                // Execute button
                Button(action: {
                    notchManager.approveToolCall()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.indigo)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            parseInitialDateTimes()
        }
    }
    
    // MARK: - Date/Time Management
    
    private func parseInitialDateTimes() {
        // Parse start datetime
        if let startDT = notchManager.editableToolArguments["startDateTime"],
           let date = parseDateTimeString(startDT) {
            startDate = date
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            startTimeText = formatter.string(from: date)
        }
        
        // Parse end datetime
        if let endDT = notchManager.editableToolArguments["endDateTime"],
           let date = parseDateTimeString(endDT) {
            endDate = date
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            endTimeText = formatter.string(from: date)
        }
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
            if let date = formatter.date(from: dateTime) {
                return date
            }
        }
        
        // Try ISO8601
        if let date = ISO8601DateFormatter().date(from: dateTime) {
            return date
        }
        
        return nil
    }
    
    private func updateStartDateTime() {
        let dateTimeString = combineDateAndTime(date: startDate, timeText: startTimeText)
        notchManager.editableToolArguments["startDateTime"] = dateTimeString
    }
    
    private func updateEndDateTime() {
        let dateTimeString = combineDateAndTime(date: endDate, timeText: endTimeText)
        notchManager.editableToolArguments["endDateTime"] = dateTimeString
    }
    
    private func combineDateAndTime(date: Date, timeText: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        // Parse time text (HH:mm format)
        let timeParts = timeText.split(separator: ":")
        let hour = timeParts.count > 0 ? String(timeParts[0]) : "00"
        let minute = timeParts.count > 1 ? String(timeParts[1]) : "00"
        
        return "\(dateString)T\(hour):\(minute):00"
    }
}

// MARK: - Date Picker Button

struct DatePickerButton: View {
    @Binding var date: Date
    @Binding var showPicker: Bool
    var onDateChanged: () -> Void
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        Button(action: {
            showPicker.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text(dateText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack {
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .onChange(of: date) { _ in
                            onDateChanged()
                        }
                }
                .padding(8)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
// MARK: - Time Input Field

struct TimeInputField: View {
    @Binding var timeText: String
    var onChanged: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
            TextField("HH:mm", text: $timeText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 40)
                .onChange(of: timeText) { _ in
                    onChanged()
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.08))
        .cornerRadius(5)
    }
}

// MARK: - Helper Views

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 60, height: 50)
        .background(.white.opacity(0.1))
        .cornerRadius(8)
    }
}

struct RecentItem: View {
    let text: String
    let time: String
    
    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(time)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Previews

#Preview("Side View") {
    NotchSideView()
        .background(.black)
}

#Preview("Down View") {
    NotchDownView()
        .background(.black)
}

#Preview("Wide View") {
    NotchWideView()
        .background(.black)
}

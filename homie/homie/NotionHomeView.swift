//
//  NotionHomeView.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import SwiftUI
import AppKit

// Helper view for content background material - using ultrathin material
struct ContentBackgroundMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow  // Most translucent/ultrathin material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // No updates needed
    }
}

// Custom wrapper view that handles mouse clicks to resign first responder
class FocusableScrollView: NSScrollView {
    var textView: NSTextView? {
        return documentView as? NSTextView
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}

// Background view that handles clicks to resign first responder
struct ClickableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> ClickableBackgroundView {
        let view = ClickableBackgroundView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: ClickableBackgroundView, context: Context) {
        // No updates needed
    }
}


// Custom view class that handles mouse clicks
class ClickableBackgroundView: NSView {
    override func mouseDown(with event: NSEvent) {
        // Check if the click is on a text view
        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)
        
        // Find the view at this location
        if let viewAtPoint = hitTest(locationInView) {
            // Check if it's a text view or inside a text view
            var currentView: NSView? = viewAtPoint
            var isTextView = false
            while let view = currentView {
                if view is NSTextView {
                    isTextView = true
                    break
                }
                if let scrollView = view as? NSScrollView, scrollView.documentView is NSTextView {
                    isTextView = true
                    break
                }
                currentView = view.superview
            }
            
            // If not clicking on a text view, resign first responder
            if !isTextView {
                window?.makeFirstResponder(nil)
            }
        } else {
            // Clicked on empty space, resign first responder
            window?.makeFirstResponder(nil)
        }
        
        super.mouseDown(with: event)
    }
}

// Custom NSTextView with placeholder support
class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw placeholder if text is empty
        if string.isEmpty && !placeholderString.isEmpty {
            guard let textContainer = self.textContainer,
                  let layoutManager = textContainer.layoutManager,
                  let textStorage = layoutManager.textStorage else {
                return
            }
            
            let placeholderAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? .systemFont(ofSize: 14)
            ]
            
            let placeholderAttributedString = NSMutableAttributedString(
                string: placeholderString,
                attributes: placeholderAttributes
            )
            
            // Create a temporary layout manager and text container for the placeholder
            let tempLayoutManager = NSLayoutManager()
            let tempTextContainer = NSTextContainer(containerSize: textContainer.containerSize)
            let tempTextStorage = NSTextStorage(attributedString: placeholderAttributedString)
            
            tempTextContainer.lineFragmentPadding = textContainer.lineFragmentPadding
            tempTextContainer.widthTracksTextView = textContainer.widthTracksTextView
            tempTextContainer.heightTracksTextView = textContainer.heightTracksTextView
            
            tempLayoutManager.addTextContainer(tempTextContainer)
            tempTextStorage.addLayoutManager(tempLayoutManager)
            
            // Ensure layout is complete
            tempLayoutManager.ensureLayout(for: tempTextContainer)
            
            // Get the glyph range
            let glyphRange = tempLayoutManager.glyphRange(for: tempTextContainer)
            if glyphRange.location != NSNotFound && glyphRange.length > 0 {
                let textContainerInset = textContainerInset
                let point = NSPoint(
                    x: textContainerInset.width,
                    y: textContainerInset.height
                )
                
                // Draw the placeholder glyphs
                tempLayoutManager.drawGlyphs(forGlyphRange: glyphRange, at: point)
            }
        }
    }
    
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

// Custom TextEditor
struct YellowCursorTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    
    func makeNSView(context: Context) -> FocusableScrollView {
        let scrollView = FocusableScrollView()
        let textView = PlaceholderTextView()
        textView.placeholderString = placeholder
        
        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        
        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        // Set initial text
        textView.string = text
        
        // Store text view in context
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ nsView: FocusableScrollView, context: Context) {
        guard let textView = nsView.textView as? PlaceholderTextView else { return }
        
        // Update placeholder
        textView.placeholderString = placeholder
        
        // Update text if it changed externally
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: YellowCursorTextEditor
        var textView: NSTextView?
        
        init(_ parent: YellowCursorTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
        }
    }
}

// Custom NSTextField subclass
class YellowCursorTextField: NSTextField {
    // No custom cursor color - use system default
}

// SwiftUI wrapper for TextField with yellow cursor
struct YellowCursorTextFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    
    func makeNSView(context: Context) -> YellowCursorTextField {
        let textField = YellowCursorTextField()
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 14)
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.focusRingType = .none
        textField.stringValue = text
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: YellowCursorTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: YellowCursorTextFieldWrapper
        
        init(_ parent: YellowCursorTextFieldWrapper) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

struct NotionHomeView: View {
    @State private var selectedSection: String? = "Home"
    @State private var homeText: String = ""
    @State private var textEditingText: String = ""
    @ObservedObject private var authStore = AuthSessionStore.shared
    @ObservedObject private var entitlementStore = FeatureEntitlementStore.shared
    @ObservedObject private var localLLMStore = LocalLLMModelStore.shared
    @ObservedObject private var notchManager = NotchManager.shared
    @ObservedObject private var gestureDetector = TouchGestureDetector.shared
    @State private var shortcuts: [ShortcutInfo] = []
    @State private var touchVisualizationWindowController: TouchVisualizationWindowController?
    
    struct ShortcutInfo: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let formattedShortcut: String
    }
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                // Sidebar
                sidebarView
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            } detail: {
                // Main Content Area
                mainContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 800, minHeight: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: entitlementStore.currentTier) { _ in
                // If user is viewing premium features but is no longer entitled, redirect to Home
                if selectedSection == "Personalize" && !entitlementStore.canUsePersonalize {
                    selectedSection = "Home"
                }
                if selectedSection == "Integrations" && !entitlementStore.canUseMCPIntegrations {
                    selectedSection = "Home"
                }
            }
            .onAppear {
                // Start listening for touch gestures
                gestureDetector.startListening()
            }
            .onDisappear {
                // Stop listening when view disappears
                gestureDetector.stopListening()
            }
            .onChange(of: gestureDetector.isGestureDetected) { detected in
                if detected {
                    SlidingPanelWindowController.shared.showPanel()
                }
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Workspace Header
            HStack {
                Image(systemName: "paperclip")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Homie")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            
            Divider()
                .padding(.vertical, 8)
            
            // Navigation Items
            VStack(alignment: .leading, spacing: 4) {
                sidebarButton(title: "Home", icon: "house", value: "Home")

                // Only show premium features for entitled users
                if entitlementStore.canUsePersonalize {
                    sidebarButton(title: "Personalize", icon: "person.fill", value: "Personalize")
                }
                if entitlementStore.canUseMCPIntegrations {
                    sidebarButton(title: "Integrations", icon: "link.circle", value: "Integrations")
                }

                sidebarButton(title: "Keyboard Shortcuts", icon: "keyboard", value: "Keyboard Shortcuts")
                sidebarButton(title: "Preferences", icon: "gearshape", value: "Preferences")
            }
            .padding(.horizontal, 8)

            Spacer()
            
            Divider()
                .padding(.vertical, 8)
            
            // Account Section
            VStack(alignment: .leading, spacing: 4) {
                sidebarButton(title: authStore.userName ?? "Profile", icon: "person.crop.circle", value: "Profile")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func sidebarButton(title: String, icon: String, value: String) -> some View {
        Button(action: {
            selectedSection = value
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selectedSection == value ? .blue : .primary)
                    .frame(width: 20)
                
                Text(title)
                    .foregroundStyle(selectedSection == value ? .blue : .primary)
                    .font(.system(size: 14))
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedSection == value ? Color.gray.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Main Content
    
    private var mainContentView: some View {
        ZStack {
            // Background material for the canvas - extends to all edges
            ContentBackgroundMaterial()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if selectedSection == "Home" {
                        homeView
                    } else if selectedSection == "Personalize" && entitlementStore.canUsePersonalize {
                        PersonalizeView()
                    } else if selectedSection == "Integrations" && entitlementStore.canUseMCPIntegrations {
                        MCPSettingsView()
                    } else if selectedSection == "Keyboard Shortcuts" {
                        KeyboardShortcutsView()
                    } else if selectedSection == "Preferences" {
                        PreferencesView()
                    } else if selectedSection == "Profile" {
                        ProfileSettingsView()
                    } else if selectedSection == "Personalize" || selectedSection == "Integrations" {
                        // If user somehow gets to premium features but isn't entitled, redirect to Home
                        homeView
                            .onAppear {
                                selectedSection = "Home"
                            }
                    }
                }
                .padding(.top, 8) // Small top padding to avoid window controls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            // Local LLM download progress overlay (bottom-right)
            LocalLLMDownloadOverlayContainer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Home View
    
    private var homeView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Welcome message
            HStack {
                Text("Welcome to Clippy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Notch expansion mode buttons
                HStack(spacing: 8) {
                    ForEach(NotchExpansionMode.allCases, id: \.self) { mode in
                        NotchModeButton(
                            mode: mode,
                            isActive: notchManager.isExpanded && notchManager.currentMode == mode,
                            action: { notchManager.toggle(mode: mode) }
                        )
                    }
                    
                    // Close button (only shown when expanded)
                    if notchManager.isExpanded {
                        Button(action: {
                            notchManager.hide()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .padding(8)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Touch Visualization card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Touch Visualization")
                            .font(.headline)
                        
                        Text("Test real-time trackpad touch visualization. This shows touch positions, pressure, and gestures on your trackpad.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            openTouchVisualization()
                        }) {
                            HStack {
                                Image(systemName: "hand.point.up.left.fill")
                                Text("Open Touch Visualization")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // How to Use Homie card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to Use Homie")
                            .font(.headline)
                        
                        Text("Just click any text field and dictate. The output will appear right away. For the GPT functions, select any text, call the shortcut, and you can work with the selected text as context. Whatever textfield you actively click, your output will appear there. And if no text field is active, the output will be copied to your clipboard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(shortcuts) { shortcut in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(shortcut.formattedShortcut)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shortcut.name)
                                            .font(.subheadline)
                                        Text(shortcut.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Text("You can try all these shortcuts in the text field below. The output will appear wherever your cursor is positioned.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Text entry box card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try Dictation")
                            .font(.headline)
                        
                        YellowCursorTextEditor(
                            text: $homeText,
                            placeholder: getDictationPlaceholderText()
                        )
                        .frame(minHeight: 150)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Text editing box card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try Text Editing")
                            .font(.headline)
                        
                        Text("Select the email below, call the popup with \(getVoiceGPTShortcutText()) and say \"Write a reply to this email suggesting Thursday\" and hit the shortcut again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        YellowCursorTextEditor(
                            text: $textEditingText,
                            placeholder: ""
                        )
                        .frame(minHeight: 150)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            loadShortcuts()
            if textEditingText.isEmpty {
                textEditingText = getPrePopulatedEmailText()
            }
        }
    }
    
    private func loadShortcuts() {
        let userDefaults = UserDefaults.standard
        
        // Define default shortcuts
        let defaultShortcuts = [
            ("VoiceGPT", "Edit any text with your voice", "voicegpt", "i", GlobalKeyboardShortcutManager.controlKeyModifier | GlobalKeyboardShortcutManager.shiftKeyModifier),
            ("Dictation", "Dictate any text on the fly", "dictation", "o", GlobalKeyboardShortcutManager.shiftKeyModifier | GlobalKeyboardShortcutManager.controlKeyModifier),
            ("Text GPT", "Edit any text you select with GPT", "textentry", "k", GlobalKeyboardShortcutManager.controlKeyModifier | GlobalKeyboardShortcutManager.shiftKeyModifier)
        ]
        
        var loadedShortcuts: [ShortcutInfo] = []
        
        for (name, description, identifier, defaultKey, defaultModifiers) in defaultShortcuts {
            let keyKey = "shortcut_\(identifier)_key"
            let modifiersKey = "shortcut_\(identifier)_modifiers"
            
            let key = userDefaults.string(forKey: keyKey) ?? defaultKey
            let modifiers = UInt32(userDefaults.integer(forKey: modifiersKey))
            
            let finalModifiers = modifiers == 0 ? defaultModifiers : modifiers
            let formattedShortcut = formatShortcut(key: key, modifiers: finalModifiers)
            
            loadedShortcuts.append(ShortcutInfo(
                name: name,
                description: description,
                formattedShortcut: formattedShortcut
            ))
        }
        
        shortcuts = loadedShortcuts
    }
    
    private func formatShortcut(key: String, modifiers: UInt32) -> String {
        var parts: [String] = []
        
        if modifiers & GlobalKeyboardShortcutManager.controlKeyModifier != 0 {
            parts.append("⌃")
        }
        if modifiers & GlobalKeyboardShortcutManager.shiftKeyModifier != 0 {
            parts.append("⇧")
        }
        if modifiers & GlobalKeyboardShortcutManager.optionKeyModifier != 0 {
            parts.append("⌥")
        }
        if modifiers & GlobalKeyboardShortcutManager.cmdKeyModifier != 0 {
            parts.append("⌘")
        }
        
        parts.append(key.uppercased())
        
        return parts.joined(separator: " ")
    }
    
    private func getDictationPlaceholderText() -> String {
        // Find the dictation shortcut
        if let dictationShortcut = shortcuts.first(where: { $0.name == "Dictation" }) {
            return "Click here and press the keyboard shortcut \(dictationShortcut.formattedShortcut) to dictate. Click it again and then your dictation should appear."
        }
        // Fallback if shortcut not found yet
        return "Click here and press the keyboard shortcut to dictate. Click it again and then your dictation should appear."
    }
    
    private func getVoiceGPTShortcutText() -> String {
        // Find the VoiceGPT shortcut
        if let voiceGPTShortcut = shortcuts.first(where: { $0.name == "VoiceGPT" }) {
            return voiceGPTShortcut.formattedShortcut
        }
        // Fallback if shortcut not found yet
        return "⌃ ⇧ I"
    }
    
    private func getPrePopulatedEmailText() -> String {
        let userName = authStore.userName ?? "there"
        return "Hey \(userName),\n\nDo you want to go for a coffee later this week?\nWould love to share more insights about Clippy with you.\n\nBest,\nMax"
    }
    
    private func openTouchVisualization() {
        // Create or reuse the window controller
        if touchVisualizationWindowController == nil {
            touchVisualizationWindowController = TouchVisualizationWindowController()
        }
        touchVisualizationWindowController?.showWindow()
    }
    
}

// MARK: - Notch Mode Button

struct NotchModeButton: View {
    let mode: NotchExpansionMode
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12))
                Text(mode.rawValue)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.blue : Color.blue.opacity(0.15))
            .foregroundColor(isActive ? .white : .blue)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NotionHomeView()
        .frame(width: 1000, height: 700)
}


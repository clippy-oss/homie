//
//  AppDelegate.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import Cocoa
import SwiftUI
import Carbon
import ApplicationServices

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSControlTextEditingDelegate {

    private var floatingWindowController: FloatingWindowController?
    private var notionHomeWindowController: NotionHomeWindowController?
    private var loginWindowController: NSWindowController?
    private var permissionsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    
    // Update manager for automatic updates
    private let updateManager = UpdateManager.shared

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set NSApplication delegate to catch all text field editing events
        NSApp.delegate = self
        
        // Initialize yellow caret manager - this will handle all text fields and text views
        YellowCaretManager.shared.setup()
        
        // Immediately hide any unwanted windows (like the storyboard window)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if window.title == "Window" || window.title == "Welcome to Clippy" || window.title == "Clippy" {
                    Logger.info("Hiding unwanted window with title: '\(window.title)'", module: "App")
                    window.orderOut(nil)
                }
            }
        }
        
        // Initialize authentication using Supabase SDK
        Task { @MainActor in
            // Start observing auth state and wait for initial session to be processed
            // With emitLocalSessionAsInitialSession: true, session is emitted immediately from local storage
            await AuthSessionStore.shared.startObservingAuthStateAndWait()

            if AuthSessionStore.shared.isAuthenticated {
                // User is authenticated - check if permissions are granted
                Logger.info("User authenticated - checking permissions", module: "App")

                // Refresh permissions synchronously to get current state
                PermissionStore.shared.refreshAll()

                if PermissionStore.shared.areRequiredPermissionsGranted {
                    Logger.info("Permissions granted - initializing app", module: "App")
                    self.initializeMainApp()
                } else {
                    Logger.info("Permissions missing - showing permissions window", module: "App")
                    self.showPermissionsWindow()
                }
            } else {
                // Show login window
                Logger.info("User not authenticated - showing login", module: "App")
                self.showLoginWindow()
            }
        }
    }
    
    private func initializeMainApp() {
        // Initialize the FeatureGateway UI coordinator (handles login/upgrade prompts)
        _ = FeatureGatewayUICoordinator.shared

        // Log permission status on startup (deferred to next run loop to avoid crash during early initialization)
        DispatchQueue.main.async {
            let micStatus = PermissionManager.shared.checkMicrophoneStatus()
            let accessibilityGranted = PermissionManager.shared.isAccessibilityTrusted()
            Logger.info("Microphone permission: \(micStatus == .authorized ? "granted" : "not granted")", module: "App")
            Logger.info("Accessibility permission: \(accessibilityGranted ? "granted" : "not granted")", module: "App")
        }

        // Initialize the floating window controller
        floatingWindowController = FloatingWindowController()
        
        // Initialize and show the Notion Home window
        Logger.info("Creating Notion Home window...", module: "App")
        notionHomeWindowController = NotionHomeWindowController()
        Logger.info("Notion Home window controller created: \(notionHomeWindowController != nil)", module: "App")
        notionHomeWindowController?.showWindow()
        Logger.info("Notion Home window showWindow called", module: "App")
        
        // Configure and register all shortcuts
        ShortcutManager.shared.configure(with: self)
        ShortcutManager.shared.registerAllShortcuts()
        
        // Request accessibility permissions if needed
        requestAccessibilityPermissions()
        
        // Setup menu items
        setupMenuItems()
        
        // Setup status bar item
        setupStatusBarItem()
        
        // Check for updates in background (after a short delay to not interfere with startup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.updateManager.checkForUpdatesInBackground()
            // Now safe to check notification permissions (UNUserNotificationCenter is initialized)
            PermissionStore.shared.refreshNotificationStatus()
        }
        
        // Immediately hide the main window (ViewController) but keep it alive for floating window functionality
        DispatchQueue.main.async {
            Logger.info("Attempting to hide main window immediately...", module: "App")
            Logger.info("Available windows: \(NSApp.windows.map { $0.title })", module: "App")
            
            // Hide all windows except the Notion Home window
            for window in NSApp.windows {
                if window.title != "Homie" {
                    Logger.info("Hiding window with title: '\(window.title)'", module: "App")
                    window.orderOut(nil)
                }
            }
            Logger.info("Main window hidden - only Notion Home window visible", module: "App")
        }
        
        // Start all messaging provider bridges
        if #available(macOS 15.0, *) {
            Task { @MainActor in
                for providerID in MessagingService.shared.availableProviders {
                    do {
                        try await MessagingService.shared.ensureStarted(providerID)
                        Logger.info("Messaging provider \(providerID.rawValue) started successfully", module: "App")
                    } catch {
                        Logger.error("Failed to start \(providerID.rawValue) provider: \(error.localizedDescription)", module: "App")
                    }
                }
            }
        }

        Logger.info("Homie app started!", module: "App")
        Logger.info("Press Shift+Control+I to toggle the floating window with VoiceGPT transcription.", module: "App")
        Logger.info("Press Shift+Control+O to toggle dictation recording and transcription.", module: "App")
        Logger.info("Press Shift+Control+K to toggle text entry mode.", module: "App")
    }
    
    private func showLoginWindow() {
        // Ensure any unwanted windows are hidden before showing login
        for window in NSApp.windows {
            if window.title == "Window" || window.title == "Welcome to Clippy" || window.title == "Clippy" {
                window.orderOut(nil)
            }
        }
        showAuthWindow(isSignup: true)
    }
    
    private func showPermissionsWindow() {
        // Ensure any unwanted windows are hidden before showing permissions
        for window in NSApp.windows {
            if window.title == "Window" || window.title == "Welcome to Clippy" || window.title == "Clippy" {
                window.orderOut(nil)
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Permissions Required - Homie"
        window.center()

        let permissionsView = PermissionsView(
            onPermissionsComplete: { [weak self] in
                Logger.info("Permissions granted - initializing main app", module: "App")
                self?.permissionsWindowController?.close()
                self?.permissionsWindowController = nil
                self?.initializeMainApp()
            }
        )

        let hostingController = NSHostingController(rootView: permissionsView)
        window.contentViewController = hostingController

        let windowController = NSWindowController(window: window)
        self.permissionsWindowController = windowController

        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAuthWindow(isSignup: Bool) {
        // Create auth window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = isSignup ? "Get Started - Homie" : "Sign In - Homie"
        window.center()
        
        // Create AuthCoordinatorView that handles switching between signup and login
        let authView = AuthCoordinatorView(
            showSignup: isSignup,
            onAuthSuccess: { [weak self] in
                Logger.info("✅ Authentication successful - initializing main app", module: "App")
                self?.loginWindowController?.close()
                self?.loginWindowController = nil
                self?.initializeMainApp()
            }
        )
        
        let hostingController = NSHostingController(rootView: authView)
        window.contentViewController = hostingController
        
        let windowController = NSWindowController(window: window)
        self.loginWindowController = windowController
        
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up whisper resources before termination
        floatingWindowController?.cleanup()

        // Clean up all shortcuts
        ShortcutManager.shared.unregisterAllShortcuts()

        // Stop all messaging provider bridges
        // Note: Using DispatchSemaphore to ensure async work completes before termination
        if #available(macOS 15.0, *) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await MessagingService.shared.stopAll()
                Logger.info("All messaging providers stopped", module: "App")
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5.0)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - NSControlTextEditingDelegate
    // This catches all NSTextField editing events and sets yellow caret
    func controlTextDidBeginEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            YellowCaretManager.shared.applyCaretColor(to: textField)
        }
    }
    
    // Helper function to find NSTextView in view hierarchy
    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        if let scrollView = view as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
    
    private func requestAccessibilityPermissions() {
        if !PermissionManager.shared.isAccessibilityTrusted() {
            // Log warning but don't prompt - user will be prompted during onboarding or when using features that need it
            Logger.warning("⚠️ Accessibility permissions not granted. Global shortcuts may not work.", module: "App")
            Logger.info("Enable accessibility access in System Preferences > Security & Privacy > Accessibility", module: "App")
        }
    }
    
    // Helper method to check if text is selected (prevents system beep when no text is selected)
    private func hasSelectedText() -> Bool {
        guard PermissionManager.shared.isAccessibilityTrusted() else { return false }
        
        // Get the currently focused application
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = focusedApp.processIdentifier
        
        // Get the focused UI element
        let app = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else { return false }
        
        // Check if the element has selected text
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return true
        }
        
        return false
    }
    
    private func setupMenuItems() {
        // Find the app menu (first menu item, usually named after the app)
        guard let mainMenu = NSApp.mainMenu,
              let appMenu = mainMenu.items.first?.submenu else {
            Logger.warning("⚠️ Could not find app menu", module: "App")
            return
        }
        
        // Find the separator after Preferences
        var insertIndex = -1
        for (index, item) in appMenu.items.enumerated() {
            if item.title == "Preferences…" {
                insertIndex = index + 1
                break
            }
        }
        
        // If we found Preferences, insert after it; otherwise insert after About
        if insertIndex == -1 {
            for (index, item) in appMenu.items.enumerated() {
                if item.title.contains("About") {
                    insertIndex = index + 2 // After About and separator
                    break
                }
            }
        }
        
        // Create "Check for Updates" menu item
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        
        // Insert the menu item
        if insertIndex > 0 && insertIndex <= appMenu.items.count {
            appMenu.insertItem(checkForUpdatesItem, at: insertIndex)
            appMenu.insertItem(NSMenuItem.separator(), at: insertIndex + 1)
        } else {
            // Fallback: add at the end before Quit
            let quitIndex = appMenu.items.firstIndex { $0.title.contains("Quit") } ?? appMenu.items.count - 1
            appMenu.insertItem(NSMenuItem.separator(), at: quitIndex)
            appMenu.insertItem(checkForUpdatesItem, at: quitIndex + 1)
        }
        
        Logger.info("✅ Added 'Check for Updates' menu item", module: "App")
    }
    
    @objc private func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates()
    }
    
    private func setupStatusBarItem() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else { return }
        
        // Set the button with paperclip icon from SF Symbols
        if let button = statusItem.button {
            // Use SF Symbols paperclip icon
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let baseImage = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Homie") {
                let image = baseImage.withSymbolConfiguration(config) ?? baseImage
                button.image = image
                button.imagePosition = .imageOnly
            }
        }
        
        // Create the menu
        let menu = NSMenu()
        
        // Add "Home" menu item
        let homeItem = NSMenuItem(title: "Home", action: #selector(openHomeWindow(_:)), keyEquivalent: "")
        homeItem.target = self
        menu.addItem(homeItem)
        
        // Add separator
        menu.addItem(NSMenuItem.separator())
        
        // Add "Quit" menu item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApplication(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func openHomeWindow(_ sender: Any?) {
        notionHomeWindowController?.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApplication(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Public Methods
    public func showFloatingWindow() {
        floatingWindowController?.showWindow()
    }
    
    public func hideFloatingWindow() {
        floatingWindowController?.hideWindow()
    }
    
    public func showMainWindow() {
        if let mainWindow = NSApp.windows.first(where: { $0.title == "Clippy" }) {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public func showVisualPopup() {
        // Toggle the floating window with microphone recording functionality
        guard let windowController = floatingWindowController else { return }
        
        let isWindowVisible = windowController.window?.isVisible == true
        let isWhisperActive = windowController.isWhisperTranscriptionActive()
        
        if isWindowVisible {
            // Window is visible, stop recording and transcribe
            if isWhisperActive {
                Logger.info("🛑 Stopping microphone recording and transcribing...", module: "App")
                windowController.stopWhisperTranscription()
                
                // The transcription will be processed automatically via the callback
                // and the result will be copied to clipboard
            }
            
            // Hide the window
            hideFloatingWindow()
        } else {
            // Window is hidden, show it and start recording
            Logger.info("🎤 Starting microphone recording...", module: "App")
            
            // Clear pasteboard so identical selections count as new and avoid stale content
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let initialChangeCount = pasteboard.changeCount

            // Only simulate Cmd+C if text is actually selected (prevents system beep)
            if hasSelectedText() {
                // Simulate Cmd+C to copy any selected text
                let source = CGEventSource(stateID: .combinedSessionState)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
                keyDown?.flags = .maskCommand

                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }

            // Check clipboard content after a slightly longer delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                let pb = NSPasteboard.general
                let text = pb.string(forType: .string)
                let didChange = pb.changeCount != initialChangeCount
                let hasNonEmpty = (text?.isEmpty == false)
                let contextText: String? = (didChange || hasNonEmpty) ? text : nil

                if let preview = contextText?.prefix(50), !preview.isEmpty {
                    Logger.info("📋 Captured selected text for visual popup: \(preview)...", module: "App")
                } else {
                    Logger.info("📋 No text was selected for visual popup", module: "App")
                }

                // Set context text and show window
                self?.floatingWindowController?.setContextText(contextText)
                self?.floatingWindowController?.showWindow()

                // Start microphone recording after window is shown
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.floatingWindowController?.startWhisperTranscriptionRaw()
                }
            }
        }
    }
    
    public func toggleFloatingWindow() {
        guard let windowController = floatingWindowController else { return }
        
        let isWindowVisible = windowController.window?.isVisible == true
        let isWhisperActive = windowController.isWhisperTranscriptionActive()
        
        if isWindowVisible {
            // Window is visible, stop transcription and process text
            if isWhisperActive {
                Logger.info("🛑 Stopping Whisper transcription and processing...", module: "App")
                
                // Mark to close after AI response (AI processing will start after transcription finishes)
                windowController.requestCloseAfterAIResponse()
                
                // Stop the transcription - this will trigger finalizeDictation which starts AI processing
                windowController.stopWhisperTranscription()
                
                // Don't hide the window - let it close automatically after AI response
                return
            }
            
            // Check if AI is currently processing
            if windowController.isAIProcessing() {
                // Don't hide immediately - mark to close after AI response
                Logger.info("🤖 AI is processing - will close after response is generated", module: "App")
                windowController.requestCloseAfterAIResponse()
                return
            }
            
            // Hide the window
            hideFloatingWindow()
        } else {
            // Window is hidden, start whisper transcription and show window
            Logger.info("🎤 Starting Whisper transcription...", module: "App")
            
            // Clear pasteboard so identical selections count as new and avoid stale content
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let initialChangeCount = pasteboard.changeCount

            // Only simulate Cmd+C if text is actually selected (prevents system beep)
            if hasSelectedText() {
                // Simulate Cmd+C to copy any selected text
                let source = CGEventSource(stateID: .combinedSessionState)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
                keyDown?.flags = .maskCommand

                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }

            // Check clipboard content after a slightly longer delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                let pb = NSPasteboard.general
                let text = pb.string(forType: .string)
                let didChange = pb.changeCount != initialChangeCount
                let hasNonEmpty = (text?.isEmpty == false)
                let contextText: String? = (didChange || hasNonEmpty) ? text : nil

                if let preview = contextText?.prefix(50), !preview.isEmpty {
                    Logger.info("📋 Captured selected text: \(preview)...", module: "App")
                } else {
                    Logger.info("📋 No text was selected", module: "App")
                }

                // Set context text and show window
                self?.floatingWindowController?.setContextText(contextText)
                self?.floatingWindowController?.showWindow()

                // Start whisper transcription after window is shown
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.floatingWindowController?.startWhisperTranscription()
                }
            }
        }
    }
    
    public func toggleTextEntryMode() {
        guard let windowController = floatingWindowController else { return }
        
        let isWindowVisible = windowController.window?.isVisible == true
        let isTextEntryMode = windowController.isTextEntryModeActive()
        
        if isWindowVisible {
            // Check if AI is currently processing
            if windowController.isAIProcessing() {
                // Don't hide immediately - mark to close after AI response
                Logger.info("🤖 AI is processing - will close after response is generated", module: "App")
                windowController.requestCloseAfterAIResponse()
                return
            }
            
            // Window is visible, hide it
            hideFloatingWindow()
        } else {
            // Window is hidden, show it in text entry mode
            
            // Clear pasteboard so identical selections count as new and avoid stale content
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let initialChangeCount = pasteboard.changeCount

            // Only simulate Cmd+C if text is actually selected (prevents system beep)
            if hasSelectedText() {
                // Simulate Cmd+C to copy any selected text
                let source = CGEventSource(stateID: .combinedSessionState)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
                keyDown?.flags = .maskCommand

                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }

            // Check clipboard content after a slightly longer delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                let pb = NSPasteboard.general
                let text = pb.string(forType: .string)
                let didChange = pb.changeCount != initialChangeCount
                let hasNonEmpty = (text?.isEmpty == false)
                let contextText: String? = (didChange || hasNonEmpty) ? text : nil

                if let preview = contextText?.prefix(50), !preview.isEmpty {
                    Logger.info("📋 Captured selected text for text entry: \(preview)...", module: "App")
                } else {
                    Logger.info("📋 No text was selected for text entry", module: "App")
                }

                // Set context text and show window in text entry mode
                self?.floatingWindowController?.setContextText(contextText)
                self?.floatingWindowController?.showWindowInTextEntryMode()
            }
        }
    }
}


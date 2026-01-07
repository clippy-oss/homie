import Cocoa

// Custom NSPanel subclass that provides better input handling
class InputAcceptingPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class FloatingWindowController: NSWindowController {
    
    private var previousKeyWindow: NSWindow?
    private var floatingViewController: FloatingViewController?
    private var originalPosition: NSPoint?
    private var isDragging = false
    private var dragStartPoint: NSPoint?
    
    // Workspace-aware + screen-locked properties
    private var targetScreen: NSScreen?  // Remember which screen to use
    private var isInitialized = false   // Track if we've set the target screen
    
    convenience init() {
        // Calculate panel size: 1/7th of screen height with 1:1 aspect ratio
        guard let screen = NSScreen.main else {
            fatalError("Could not get main screen")
        }
        
        let screenHeight = screen.frame.height
        let panelSize = screenHeight / 7.0
        
        // Add extra space for shadows: 50% height and 20% width
        let shadowPaddingHeight = panelSize * 0.5
        let shadowPaddingWidth = panelSize * 0.2
        
        // Create the panel with notification-style styling
        let panel = InputAcceptingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize + shadowPaddingWidth, height: panelSize + shadowPaddingHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel properties for notification-like appearance
        panel.level = .floating
        panel.backgroundColor = NSColor.clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Configure to appear on all spaces without switching spaces
        // Updated for workspace-aware behavior
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .participatesInCycle]
        
        // This is the key: allow the panel to become key when needed, but don't activate the app
        panel.becomesKeyOnlyIfNeeded = true
        
        // Position window at predetermined location (top-right corner)
        self.init(window: panel)
        
        // Set up the content view controller
        let contentViewController = FloatingViewController()
        self.floatingViewController = contentViewController
        panel.contentViewController = contentViewController
        
        // Store original position and position window
        self.positionWindow()
        self.originalPosition = window?.frame.origin
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Workspace-Aware + Screen-Locked Methods
    
    /// Detect which screen the mouse cursor is currently on
    private func getCurrentMouseScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }
    
    /// Set the target screen if not already initialized
    private func setTargetScreenIfNeeded() {
        if !isInitialized {
            targetScreen = getCurrentMouseScreen() ?? NSScreen.main
            isInitialized = true
            Logger.info("🎯 Target screen set to: \(targetScreen?.localizedName ?? "Unknown")", module: "FloatingVC")
        }
    }
    
    /// Setup workspace change monitoring
    private func setupWorkspaceMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }
    
    /// Handle workspace changes - update popup position for new workspace
    @objc private func workspaceDidChange() {
        Logger.info("🔄 Workspace changed - updating popup position", module: "FloatingVC")
        // Reposition the window for the new workspace but keep it on the same physical screen
        DispatchQueue.main.async { [weak self] in
            self?.positionWindow()
        }
    }
    
    private func positionWindow() {
        guard let window = window else { return }
        
        // Use target screen instead of NSScreen.main for workspace-aware positioning
        let screen = targetScreen ?? NSScreen.main
        
        // Position at bottom-right corner with some margin
        let screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
        let windowFrame = window.frame
        
        let x = screenFrame.maxX - windowFrame.width - 20
        let y = screenFrame.minY + 20
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
        Logger.info("📍 Positioned popup on screen: \(screen?.localizedName ?? "Unknown")", module: "FloatingVC")
    }
    
    func showWindow() {
        // Store the currently active window for focus restoration
        previousKeyWindow = NSApp.keyWindow
        
        // Set target screen on first show (workspace-aware + screen-locked)
        setTargetScreenIfNeeded()
        
        // Setup workspace monitoring if not already done
        if !isInitialized {
            setupWorkspaceMonitoring()
        }
        
        // Position at the correct top-right corner of target screen
        positionWindow()
        // Store the correct original position
        originalPosition = window?.frame.origin
        
        // Show the panel first
        window?.orderFront(nil)
        
        // Start clippy hover animation
        floatingViewController?.startHoverAnimation()
        
        // Force the panel to become key for input, even though it's nonactivating
        // This is the key to making it work like Raycast
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKey()
            self?.window?.makeMain()
        }
    }
    
    func hideWindow() {
        window?.orderOut(nil)

        // Stop clippy hover animation
        floatingViewController?.stopHoverAnimation()

        // Clean up text entry mode if active
        if floatingViewController?.isTextEntryModeActive() == true {
            floatingViewController?.disableTextEntryMode()
        }

        // Backcheck: Stop microphone if it's still active when popup closes
        if isWhisperTranscriptionActive() {
            Logger.info("🛑 Backcheck: Stopping microphone on popup close...", module: "FloatingVC")
            stopWhisperTranscription()
        }

        // Cancel any ongoing operations (LLM generation, transcription, etc.)
        floatingViewController?.cancelCurrentAction()

        // Restore focus to the previous window
        if let previousWindow = previousKeyWindow {
            DispatchQueue.main.async {
                previousWindow.makeKey()
            }
        }
        previousKeyWindow = nil
    }
    
    func toggleWindow() {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    func setContextText(_ contextText: String?) {
        floatingViewController?.setContextText(contextText)
    }
    
    // MARK: - Whisper Transcription Methods
    func startWhisperTranscription() {
        floatingViewController?.startWhisperTranscription()
    }
    
    func startWhisperTranscriptionRaw() {
        floatingViewController?.startWhisperTranscriptionRaw()
    }
    
    func stopWhisperTranscription() {
        floatingViewController?.stopWhisperTranscription()
    }
    
    func isWhisperTranscriptionActive() -> Bool {
        return floatingViewController?.speechManager?.isListening() ?? false
    }
    
    // MARK: - Text Entry Mode Methods
    func showWindowInTextEntryMode() {
        // Store the currently active window for focus restoration
        previousKeyWindow = NSApp.keyWindow
        
        // Set target screen on first show (workspace-aware + screen-locked)
        setTargetScreenIfNeeded()
        
        // Setup workspace monitoring if not already done
        if !isInitialized {
            setupWorkspaceMonitoring()
        }
        
        // Always position at the correct top-right corner of target screen first
        positionWindow()
        // Store the correct original position (don't let it get corrupted by resizing)
        originalPosition = window?.frame.origin
        
        // Immediately resize to text entry mode size (panelSize * 3)
        if let window = window {
            let currentFrame = window.frame
            let screen = targetScreen ?? NSScreen.main
            let screenHeight = screen?.frame.height ?? NSScreen.main?.frame.height ?? 1440
            let panelSize = screenHeight / 7.0
            let shadowPaddingWidth = panelSize * 0.2
            let shadowPaddingHeight = panelSize * 0.5
            let newWidth: CGFloat = panelSize * 3 + shadowPaddingWidth
            let widthDifference = newWidth - currentFrame.width
            
            // Move left by the width difference to keep right edge in place
            let newFrame = NSRect(
                x: currentFrame.origin.x - widthDifference,
                y: currentFrame.origin.y,
                width: newWidth,
                height: panelSize + shadowPaddingHeight
            )
            
            window.setFrame(newFrame, display: true, animate: false) // No animation
        }
        
        // Show the panel first
        window?.orderFront(nil)
        
        // Start clippy hover animation
        floatingViewController?.startHoverAnimation()
        
        // Enable text entry mode in the view controller
        floatingViewController?.enableTextEntryMode()
        
        // Make the panel key for text input while preserving original focus context
        DispatchQueue.main.async { [weak self] in
            // Make the panel key and main so it can receive keyboard input
            self?.window?.makeKey()
            self?.window?.makeMain()
        }
    }
    
    func isTextEntryModeActive() -> Bool {
        return floatingViewController?.isTextEntryModeActive() ?? false
    }
    
    // MARK: - AI Processing Methods
    func isAIProcessing() -> Bool {
        return floatingViewController?.isAIProcessing() ?? false
    }
    
    func requestCloseAfterAIResponse() {
        floatingViewController?.requestCloseAfterAIResponse()
    }
    
    func restorePreviousWindowFocus() {
        // Restore focus to the previous window without hiding our window
        if let previousWindow = previousKeyWindow {
            previousWindow.makeKey()
            Logger.info("🔄 Restored focus to previous window", module: "FloatingVC")
        }
    }
    
    // MARK: - Dragging Methods
    func startDragging(with event: NSEvent) {
        guard let window = window else { return }
        
        isDragging = true
        dragStartPoint = event.locationInWindow
    }
    
    func continueDragging(with event: NSEvent) {
        guard let window = window, isDragging, let startPoint = dragStartPoint else { return }
        
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - startPoint.x
        let deltaY = currentPoint.y - startPoint.y
        
        let newOrigin = NSPoint(
            x: window.frame.origin.x + deltaX,
            y: window.frame.origin.y + deltaY
        )
        
        window.setFrameOrigin(newOrigin)
    }
    
    func endDragging() {
        isDragging = false
        dragStartPoint = nil
    }
    
    // Corner snapping removed per requirements
    
    // MARK: - Cleanup
    func cleanup() {
        floatingViewController?.cleanup()
    }

    deinit {
        // Remove workspace monitoring observer
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
} 
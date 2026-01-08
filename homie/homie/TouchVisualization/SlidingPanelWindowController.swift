//
//  SlidingPanelWindowController.swift
//  homie
//
//  System-wide sliding panel that appears from the left edge of the screen
//

import Cocoa
import SwiftUI

class SlidingPanelWindowController: NSWindowController {
    
    static let shared = SlidingPanelWindowController()
    
    private var panelWidth: CGFloat = 300
    private(set) var isVisible: Bool = false
    
    private init() {
        // Use convenience init pattern but make it private to enforce singleton
        guard let screen = NSScreen.main else {
            fatalError("Could not get main screen")
        }
        
        // Calculate panel width as 1/4 of screen width
        let screenWidth = screen.frame.width
        let calculatedPanelWidth = screenWidth / 4.0
        self.panelWidth = calculatedPanelWidth
        
        // Use visibleFrame to account for menu bar and dock
        let screenFrame = screen.visibleFrame
        let screenHeight = screenFrame.height
        
        // Create the panel as a system-wide overlay
        // Start off-screen to the left
        let panel = NSPanel(
            contentRect: NSRect(
                x: screenFrame.minX - calculatedPanelWidth,
                y: screenFrame.minY,
                width: calculatedPanelWidth,
                height: screenHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel properties for system-wide overlay
        // Use .floating level to appear above normal windows but below system UI
        panel.level = .floating
        panel.backgroundColor = NSColor.clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        // Appear on all spaces without switching spaces
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .participatesInCycle]
        
        // Allow the panel to become key when needed
        panel.becomesKeyOnlyIfNeeded = true
        
        super.init(window: panel)
        
        // Create the SwiftUI view
        let contentView = SlidingPanelView(
            isVisible: Binding(
                get: { [weak self] in self?.isVisible ?? false },
                set: { [weak self] newValue in
                    self?.isVisible = newValue
                    if !newValue {
                        self?.hidePanel()
                    }
                }
            ),
            onDismiss: { [weak self] in
                self?.hidePanel()
            }
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        
        panel.contentView = hostingView
        
        Logger.info("SlidingPanelWindowController initialized", module: "SlidingPanel")
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showPanel() {
        guard let window = window else { return }
        
        // Detect which screen the mouse is currently on (for multi-monitor support)
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        isVisible = true
        
        // Calculate panel width as 1/4 of target screen width
        let screenWidth = targetScreen.frame.width
        let calculatedPanelWidth = screenWidth / 4.0
        self.panelWidth = calculatedPanelWidth
        
        // Use visibleFrame to account for menu bar and dock
        let screenFrame = targetScreen.visibleFrame
        let screenHeight = screenFrame.height
        
        // Start position: off-screen to the left
        let startFrame = NSRect(
            x: screenFrame.minX - calculatedPanelWidth,
            y: screenFrame.minY,
            width: calculatedPanelWidth,
            height: screenHeight
        )
        window.setFrame(startFrame, display: true, animate: false)
        
        // Show the window first
        window.orderFront(nil)
        
        // Animate sliding in from the left
        let endFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: calculatedPanelWidth,
            height: screenHeight
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(endFrame, display: true)
        }
        
        Logger.info("Sliding panel shown from left edge (width: \(calculatedPanelWidth), screen: \(targetScreen.localizedName))", module: "SlidingPanel")
    }
    
    func hidePanel() {
        guard let window = window else { return }
        
        isVisible = false
        
        // Get the current screen where the window is positioned
        let windowFrame = window.frame
        let targetScreen = NSScreen.screens.first { screen in
            NSIntersectsRect(windowFrame, screen.frame)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        // Use visibleFrame to account for menu bar and dock
        let screenFrame = targetScreen.visibleFrame
        
        // Animate sliding out to the left
        let endFrame = NSRect(
            x: screenFrame.minX - panelWidth,
            y: screenFrame.minY,
            width: panelWidth,
            height: screenFrame.height
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(endFrame, display: true)
        }, completionHandler: {
            window.orderOut(nil)
        })
        
        Logger.info("Sliding panel hidden", module: "SlidingPanel")
    }
    
    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
}


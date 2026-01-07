//
//  NotionHomeWindowController.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import Cocoa
import SwiftUI

class NotionHomeWindowController: NSWindowController {
    
    init() {
        Logger.info("NotionHomeWindowController init called", module: "NotionHomeWindow")
        
        // Create the custom window with modern macOS Tahoe styling
        let window = ClickableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        Logger.info("Window created: \(window)", module: "NotionHomeWindow")
        
        // Configure the window for macOS Tahoe (macOS 26) Liquid Glass design
        window.title = "Homie"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.setFrameAutosaveName("NotionHomeWindow")
        
        // Enable rounded corners and translucency
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        
        // Set content view to have rounded corners (macOS Tahoe style - more pronounced)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
        
        // Ensure window controls are still accessible and positioned correctly
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        
        // Make sure content extends under the title bar
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        
        super.init(window: window)
        
        // Create the SwiftUI view
        let contentView = NotionHomeView()
        let hostingController = NSHostingController(rootView: contentView)
        
        // Ensure the hosting controller's view fills the window
        hostingController.view.frame = window.contentView?.bounds ?? .zero
        hostingController.view.autoresizingMask = [.width, .height]
        
        // Set the content view controller
        window.contentViewController = hostingController
        Logger.info("Window content view controller set", module: "NotionHomeWindow")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        Logger.info("showWindow called, window: \(window)", module: "NotionHomeWindow")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.info("Window should now be visible", module: "NotionHomeWindow")
    }
}

// Custom window that handles mouse clicks to resign first responder when clicking outside text views
class ClickableWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }
    
    override func sendEvent(_ event: NSEvent) {
        // Handle mouse down events
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            let locationInWindow = event.locationInWindow
            let contentView = self.contentView
            
            // Find the view at the click location
            if let viewAtPoint = contentView?.hitTest(locationInWindow) {
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
                    self.makeFirstResponder(nil)
                }
            } else {
                // Clicked on empty space, resign first responder
                self.makeFirstResponder(nil)
            }
        }
        
        // Call super to handle the event normally
        super.sendEvent(event)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}






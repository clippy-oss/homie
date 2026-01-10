//
//  MessageWindowController.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import Cocoa
import SwiftUI

class MessageWindowController: NSWindowController {
    
    init() {
        Logger.info("MessageWindowController init called", module: "MessageWindow")
        
        // Create the custom window with modern macOS Tahoe styling
        let window = ClickableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        Logger.info("Window created: \(window)", module: "MessageWindow")
        
        // Configure the window for macOS Tahoe (macOS 26) Liquid Glass design
        window.title = "Messages"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.setFrameAutosaveName("MessageWindow")
        
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
        let contentView = MessageView()
        let hostingController = NSHostingController(rootView: contentView)
        
        // Ensure the hosting controller's view fills the window
        hostingController.view.frame = window.contentView?.bounds ?? .zero
        hostingController.view.autoresizingMask = [.width, .height]
        
        // Set the content view controller
        window.contentViewController = hostingController
        Logger.info("Window content view controller set", module: "MessageWindow")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        Logger.info("showWindow called, window: \(window)", module: "MessageWindow")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.info("Window should now be visible", module: "MessageWindow")
    }
}


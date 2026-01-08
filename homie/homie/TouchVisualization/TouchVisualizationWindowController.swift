//
//  TouchVisualizationWindowController.swift
//  homie
//
//  Created for touch visualization feature
//

import Cocoa
import SwiftUI

class TouchVisualizationWindowController: NSWindowController {
    
    init() {
        Logger.info("TouchVisualizationWindowController init called", module: "TouchVisualization")
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        Logger.info("Window created: \(window)", module: "TouchVisualization")
        
        // Configure the window
        window.title = "Touch Visualization"
        window.center()
        window.setFrameAutosaveName("TouchVisualizationWindow")
        
        // Enable rounded corners and translucency
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        
        // Set content view to have rounded corners
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
        
        super.init(window: window)
        
        // Create the SwiftUI view
        let contentView = TouchVisualizationView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        
        window.contentView = hostingView
        
        Logger.info("TouchVisualizationWindowController initialized", module: "TouchVisualization")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}




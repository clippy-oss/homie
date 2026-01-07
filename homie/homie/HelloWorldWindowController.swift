//
//  HelloWorldWindowController.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import Cocoa
import SwiftUI

class HelloWorldWindowController: NSWindowController {
    
    init() {
        Logger.info("HelloWorldWindowController init called", module: "HelloWorldWindow")
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        Logger.info("Window created: \(window)", module: "HelloWorldWindow")
        
        // Configure the window
        window.title = "Welcome to Clippy"
        window.center()
        
        super.init(window: window)
        
        // Create the SwiftUI view
        let contentView = HelloWorldView()
        let hostingController = NSHostingController(rootView: contentView)
        
        // Set the content view controller
        window.contentViewController = hostingController
        Logger.info("Window content view controller set", module: "HelloWorldWindow")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        Logger.info("showWindow called, window: \(window)", module: "HelloWorldWindow")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.info("Window should now be visible", module: "HelloWorldWindow")
    }
}

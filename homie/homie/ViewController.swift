//
//  ViewController.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import Cocoa

class ViewController: NSViewController {

    // UI Elements
    private var welcomeLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        // Set the window title
        view.window?.title = "Clippy"
        
        // Create welcome label
        welcomeLabel = NSTextField(labelWithString: "Welcome to Clippy")
        welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
        welcomeLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        welcomeLabel.textColor = NSColor.labelColor
        welcomeLabel.alignment = .center
        welcomeLabel.isEditable = false
        welcomeLabel.isSelectable = false
        welcomeLabel.isBezeled = false
        welcomeLabel.drawsBackground = false
        view.addSubview(welcomeLabel)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            // Welcome label
            welcomeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            welcomeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
}
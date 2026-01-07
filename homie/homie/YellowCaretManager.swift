//
//  YellowCaretManager.swift
//  homie
//
//  Comprehensive solution for yellow caret color across all text fields
//

import Cocoa

class YellowCaretManager {
    static let shared = YellowCaretManager()
    
    private var isSetup = false
    private let yellowColor = NSColor.systemYellow
    private let selectionColor = NSColor.systemYellow.withAlphaComponent(0.3)
    
    private init() {}
    
    func setup() {
        guard !isSetup else { return }
        
        // Set up comprehensive notification observers
        setupNotificationObservers()
        
        // Swizzle NSTextField to catch field editor creation
        swizzleTextField()
        
        // Swizzle NSTextView to catch when it's created
        swizzleTextView()
        
        isSetup = true
    }
    
    // MARK: - Method Swizzling
    
    private func swizzleTextField() {
        // Swizzle becomeFirstResponder to catch when text field becomes active
        let originalSelector = #selector(NSResponder.becomeFirstResponder)
        let swizzledSelector = #selector(NSTextField.yellowCaret_becomeFirstResponder)
        
        guard let originalMethod = class_getInstanceMethod(NSTextField.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSTextField.self, swizzledSelector) else {
            Logger.error("⚠️ Failed to swizzle NSTextField.becomeFirstResponder", module: "Caret")
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    private func swizzleTextView() {
        // Swizzle viewDidMoveToWindow to catch when text view is added to window
        let originalSelector = #selector(NSView.viewDidMoveToWindow)
        let swizzledSelector = #selector(NSTextView.yellowCaret_viewDidMoveToWindow)
        
        guard let originalMethod = class_getInstanceMethod(NSTextView.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSTextView.self, swizzledSelector) else {
            Logger.error("⚠️ Failed to swizzle NSTextView.viewDidMoveToWindow", module: "Caret")
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Catch when any control begins editing (most reliable for NSTextField)
        NotificationCenter.default.addObserver(
            forName: NSControl.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let textField = notification.object as? NSTextField {
                self?.applyCaretColor(to: textField)
            }
        }
        
        // Catch when text view begins editing
        NotificationCenter.default.addObserver(
            forName: NSText.didBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let textView = notification.object as? NSTextView {
                self?.applyCaretColor(to: textView)
            }
        }
        
        // Catch when window becomes key (field editor might be active)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            DispatchQueue.main.async {
                if let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
                    self?.applyCaretColor(to: fieldEditor)
                }
            }
        }
        
        // Also check periodically for active field editors (backup method)
        // This ensures we catch any field editors that might have been missed by notifications
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkActiveFieldEditors()
        }
    }
    
    private func checkActiveFieldEditors() {
        for window in NSApp.windows {
            if let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
                applyCaretColor(to: fieldEditor)
            }
        }
    }
    
    // MARK: - Apply Caret Color
    
    func applyCaretColor(to textField: NSTextField) {
        // Try immediately
        if let fieldEditor = textField.currentEditor() as? NSTextView {
            applyCaretColor(to: fieldEditor)
        } else {
            // If field editor isn't ready, try multiple times with delays
            DispatchQueue.main.async { [weak self] in
                if let fieldEditor = textField.currentEditor() as? NSTextView {
                    self?.applyCaretColor(to: fieldEditor)
                } else {
                    // Try again after a slightly longer delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        if let fieldEditor = textField.currentEditor() as? NSTextView {
                            self?.applyCaretColor(to: fieldEditor)
                        }
                    }
                }
            }
        }
    }
    
    func applyCaretColor(to textView: NSTextView) {
        textView.insertionPointColor = yellowColor
        
        // Set selection color
        var attributes = textView.selectedTextAttributes
        attributes[.backgroundColor] = selectionColor
        attributes[.foregroundColor] = NSColor.labelColor
        textView.selectedTextAttributes = attributes
    }
}

// MARK: - NSTextField Swizzling Extensions

extension NSTextField {
    @objc func yellowCaret_becomeFirstResponder() -> Bool {
        // After swizzling, the original implementation is accessible via this method name
        // So we call it recursively (which actually calls the original)
        let result = yellowCaret_becomeFirstResponder()
        
        // Apply caret color after becoming first responder
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            YellowCaretManager.shared.applyCaretColor(to: self)
        }
        
        return result
    }
}

// MARK: - NSTextView Swizzling Extensions

extension NSTextView {
    @objc func yellowCaret_viewDidMoveToWindow() {
        // After swizzling, the original implementation is accessible via this method name
        // So we call it recursively (which actually calls the original)
        yellowCaret_viewDidMoveToWindow()
        
        // Apply caret color when view moves to window
        YellowCaretManager.shared.applyCaretColor(to: self)
    }
}

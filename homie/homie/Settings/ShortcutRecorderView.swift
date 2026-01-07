import Cocoa
import Carbon

class ShortcutRecorderView: NSView {
    // MARK: - Properties
    private var keyLabel: NSTextField!
    private var recordButton: NSButton!
    private var clearButton: NSButton!
    
    var currentKey: String = ""
    var currentModifiers: UInt32 = 0
    
    var onShortcutChanged: ((String, UInt32) -> Void)?
    
    private var isRecording = false
    private var eventMonitor: Any?
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    deinit {
        stopRecording()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Key display label
        keyLabel = NSTextField()
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.isEditable = false
        keyLabel.isSelectable = false
        keyLabel.isBordered = true
        keyLabel.isBezeled = true
        keyLabel.bezelStyle = .roundedBezel
        keyLabel.backgroundColor = NSColor.textBackgroundColor
        keyLabel.alignment = .center
        keyLabel.stringValue = "Not set"
        addSubview(keyLabel)
        
        // Record button
        recordButton = NSButton()
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.title = "Record"
        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked)
        addSubview(recordButton)
        
        // Clear button
        clearButton = NSButton()
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.title = "Clear"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        addSubview(clearButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.widthAnchor.constraint(equalToConstant: 200),
            keyLabel.heightAnchor.constraint(equalToConstant: 30),
            
            recordButton.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 10),
            recordButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 30),
            
            clearButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 5),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 60),
            clearButton.heightAnchor.constraint(equalToConstant: 30),
            
            trailingAnchor.constraint(equalTo: clearButton.trailingAnchor),
            heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    // MARK: - Actions
    @objc private func recordButtonClicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    @objc private func clearButtonClicked() {
        currentKey = ""
        currentModifiers = 0
        keyLabel.stringValue = "Not set"
        onShortcutChanged?("", 0)
    }
    
    // MARK: - Recording
    private func startRecording() {
        isRecording = true
        recordButton.title = "Recording..."
        keyLabel.stringValue = "Press a key combination..."
        keyLabel.textColor = .systemBlue
        
        // Monitor keyboard events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // Consume the event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        recordButton.title = "Record"
        keyLabel.textColor = .labelColor
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard isRecording else { return }
        
        // Only process actual key presses, not just modifier changes
        if event.type == .keyDown {
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            
            // Convert keyCode to string
            if let keyString = keyStringForCode(Int(keyCode)) {
                currentKey = keyString
                currentModifiers = carbonModifiersFromNSEvent(modifiers)
                
                let modifierString = modifierStringFromCarbon(currentModifiers)
                let displayString = modifierString + keyString.uppercased()
                
                keyLabel.stringValue = displayString
                
                stopRecording()
                
                // Notify delegate
                onShortcutChanged?(currentKey, currentModifiers)
            }
        }
    }
    
    // MARK: - Helper Methods
    func setShortcut(key: String, modifiers: UInt32) {
        currentKey = key
        currentModifiers = modifiers
        
        if key.isEmpty {
            keyLabel.stringValue = "Not set"
        } else {
            let modifierString = modifierStringFromCarbon(modifiers)
            keyLabel.stringValue = modifierString + key.uppercased()
        }
    }
    
    private func modifierStringFromCarbon(_ modifiers: UInt32) -> String {
        var result = ""
        
        if modifiers & UInt32(controlKey) != 0 {
            result += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            result += "⌘"
        }
        
        return result
    }
    
    private func carbonModifiersFromNSEvent(_ modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        
        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        
        return carbonModifiers
    }
    
    private func keyStringForCode(_ keyCode: Int) -> String? {
        let keyMap: [Int: String] = [
            49: "space",
            0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i",
            38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q",
            15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
            28: "8", 25: "9",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7",
            100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"
        ]
        
        return keyMap[keyCode]
    }
}


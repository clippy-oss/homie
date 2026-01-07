import Foundation
import Cocoa
import Carbon

class ShortcutManager {
    static let shared = ShortcutManager()
    
    private var shortcuts: [ShortcutHandler] = []
    private weak var appDelegate: AppDelegate?
    
    private init() {
        // Listen for shortcut changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: NSNotification.Name("ShortcutsDidChange"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func configure(with appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func registerAllShortcuts() {
        guard let appDelegate = appDelegate else {
            Logger.error("❌ AppDelegate not configured for ShortcutManager", module: "Settings")
            return
        }
        
        // Unregister existing shortcuts first
        unregisterAllShortcuts()
        
        // Create and register all shortcuts with potentially custom key bindings
        let voiceGPTShortcut = VoiceGPTShortcut(appDelegate: appDelegate)
        let dictationShortcut = DictationShortcut(appDelegate: appDelegate)
        let textEntryShortcut = TextEntryShortcut(appDelegate: appDelegate)
        
        shortcuts = [voiceGPTShortcut, dictationShortcut, textEntryShortcut]
        
        // Register each shortcut
        for shortcut in shortcuts {
            shortcut.register()
        }
        
        Logger.info("🎹 All shortcuts registered successfully", module: "Settings")
        Logger.info("   - \(voiceGPTShortcut.description): \(formatShortcut(key: voiceGPTShortcut.key, modifiers: voiceGPTShortcut.modifiers))", module: "Settings")
        Logger.info("   - \(dictationShortcut.description): \(formatShortcut(key: dictationShortcut.key, modifiers: dictationShortcut.modifiers))", module: "Settings")
        Logger.info("   - \(textEntryShortcut.description): \(formatShortcut(key: textEntryShortcut.key, modifiers: textEntryShortcut.modifiers))", module: "Settings")
    }
    
    func unregisterAllShortcuts() {
        for shortcut in shortcuts {
            shortcut.unregister()
        }
        shortcuts.removeAll()
        if !shortcuts.isEmpty {
            Logger.info("🛑 All shortcuts unregistered", module: "Settings")
        }
    }
    
    func getShortcutInfo() -> [String] {
        return shortcuts.map { "\($0.description): \($0.key) with modifiers \($0.modifiers)" }
    }
    
    @objc private func shortcutsDidChange() {
        Logger.info("📝 Shortcuts configuration changed, reloading...", module: "Settings")
        registerAllShortcuts()
    }
    
    private func formatShortcut(key: String, modifiers: UInt32) -> String {
        var result = ""
        
        if modifiers & UInt32(controlKey) != 0 {
            result += "Control+"
        }
        if modifiers & UInt32(optionKey) != 0 {
            result += "Option+"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            result += "Shift+"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            result += "Command+"
        }
        
        result += key.uppercased()
        
        return result
    }
} 
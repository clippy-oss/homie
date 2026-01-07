import Foundation
import Cocoa

class TextEntryShortcut: ShortcutHandler {
    var key: String
    var modifiers: UInt32
    let description = "Toggle text entry mode"
    var shortcutID: UInt32?
    
    private weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        // Load custom key binding from UserDefaults or use default
        let userDefaults = UserDefaults.standard
        let defaultKey = "k"
        let defaultModifiers = GlobalKeyboardShortcutManager.controlKeyModifier | GlobalKeyboardShortcutManager.shiftKeyModifier
        
        if let savedKey = userDefaults.string(forKey: "shortcut_textentry_key"),
           userDefaults.object(forKey: "shortcut_textentry_modifiers") != nil {
            self.key = savedKey
            self.modifiers = UInt32(userDefaults.integer(forKey: "shortcut_textentry_modifiers"))
        } else {
            self.key = defaultKey
            self.modifiers = defaultModifiers
        }
    }
    
    func register() {
        // Skip registration if key is empty
        guard !key.isEmpty else {
            Logger.warning("⚠️ TextEntry shortcut not set, skipping registration", module: "Settings")
            return
        }
        
        shortcutID = GlobalKeyboardShortcutManager.shared.registerGlobalShortcut(
            key: key,
            modifiers: modifiers
        ) { [weak self] in
            self?.handleShortcut()
        }
        
        Logger.info("✅ Registered TextEntry shortcut", module: "Settings")
    }
    
    func unregister() {
        if let id = shortcutID {
            GlobalKeyboardShortcutManager.shared.unregisterGlobalShortcut(id: id)
            shortcutID = nil
            Logger.info("🛑 Unregistered TextEntry shortcut", module: "Settings")
        }
    }
    
    private func handleShortcut() {
        Logger.info("⌨️ TextEntry shortcut triggered", module: "Settings")
        appDelegate?.toggleTextEntryMode()
    }
}

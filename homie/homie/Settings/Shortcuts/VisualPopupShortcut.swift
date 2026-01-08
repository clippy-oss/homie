import Foundation
import Cocoa

class DictationShortcut: ShortcutHandler {
    var key: String
    var modifiers: UInt32
    let description = "Toggle dictation recording and transcription"
    var shortcutID: UInt32?
    
    private weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        // Load custom key binding from UserDefaults or use default
        let userDefaults = UserDefaults.standard
        let defaultKey = "x"
        let defaultModifiers = GlobalKeyboardShortcutManager.fnKeyModifier
        
        if let savedKey = userDefaults.string(forKey: "shortcut_dictation_key"),
           userDefaults.object(forKey: "shortcut_dictation_modifiers") != nil {
            self.key = savedKey
            self.modifiers = UInt32(userDefaults.integer(forKey: "shortcut_dictation_modifiers"))
        } else {
            self.key = defaultKey
            self.modifiers = defaultModifiers
        }
    }
    
    func register() {
        // Skip registration if key is empty
        guard !key.isEmpty else {
            Logger.warning("⚠️ Dictation shortcut not set, skipping registration", module: "Settings")
            return
        }
        
        shortcutID = GlobalKeyboardShortcutManager.shared.registerGlobalShortcut(
            key: key,
            modifiers: modifiers
        ) { [weak self] in
            self?.handleShortcut()
        }
        
        Logger.info("✅ Registered Dictation shortcut", module: "Settings")
    }
    
    func unregister() {
        if let id = shortcutID {
            GlobalKeyboardShortcutManager.shared.unregisterGlobalShortcut(id: id)
            shortcutID = nil
            Logger.info("🛑 Unregistered Dictation shortcut", module: "Settings")
        }
    }
    
    private func handleShortcut() {
        Logger.info("🎤 Dictation shortcut triggered", module: "Settings")
        appDelegate?.showVisualPopup()
    }
} 
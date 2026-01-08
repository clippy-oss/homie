import Foundation
import Cocoa

class VoiceGPTShortcut: ShortcutHandler {
    var key: String
    var modifiers: UInt32
    let description = "Toggle VoiceGPT transcription"
    var shortcutID: UInt32?
    
    private weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        // Load custom key binding from UserDefaults or use default
        let userDefaults = UserDefaults.standard
        let defaultKey = "space"
        let defaultModifiers = GlobalKeyboardShortcutManager.fnKeyModifier
        
        if let savedKey = userDefaults.string(forKey: "shortcut_voicegpt_key"),
           userDefaults.object(forKey: "shortcut_voicegpt_modifiers") != nil {
            self.key = savedKey
            self.modifiers = UInt32(userDefaults.integer(forKey: "shortcut_voicegpt_modifiers"))
        } else {
            self.key = defaultKey
            self.modifiers = defaultModifiers
        }
    }
    
    func register() {
        // Skip registration if key is empty
        guard !key.isEmpty else {
            Logger.warning("⚠️ VoiceGPT shortcut not set, skipping registration", module: "Speech")
            return
        }
        
        shortcutID = GlobalKeyboardShortcutManager.shared.registerGlobalShortcut(
            key: key,
            modifiers: modifiers
        ) { [weak self] in
            self?.handleShortcut()
        }
        
        Logger.info("✅ Registered VoiceGPT shortcut", module: "Speech")
    }
    
    func unregister() {
        if let id = shortcutID {
            GlobalKeyboardShortcutManager.shared.unregisterGlobalShortcut(id: id)
            shortcutID = nil
            Logger.info("🛑 Unregistered VoiceGPT shortcut", module: "Speech")
        }
    }
    
    private func handleShortcut() {
        Logger.info("🎤 VoiceGPT shortcut triggered", module: "Speech")
        appDelegate?.toggleFloatingWindow()
    }
} 
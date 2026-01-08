import Cocoa
import Carbon

class GlobalKeyboardShortcutManager {
    static let shared = GlobalKeyboardShortcutManager()
    
    private var hotKeys: [UInt32: (hotKeyRef: EventHotKeyRef, callback: () -> Void)] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 1
    
    private init() {}
    
    func registerGlobalShortcut(key: String, modifiers: UInt32, callback: @escaping () -> Void) -> UInt32? {
        // Convert key string to key code
        guard let keyCode = keyCodeForString(key) else {
            Logger.info("Invalid key: \(key)", module: "Settings")
            return nil
        }
        
        // Install event handler if not already installed
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                        eventKind: OSType(kEventHotKeyPressed))
            
            let status = InstallEventHandler(GetEventDispatcherTarget(),
                                           { (_, event, userData) -> OSStatus in
                                               if let event = event {
                                                   let result = GlobalKeyboardShortcutManager.shared.handleHotKeyEvent(event)
                                                   return result
                                               }
                                               return noErr
                                           },
                                           1,
                                           &eventType,
                                           nil,
                                           &eventHandler)
            
            guard status == noErr else {
                Logger.error("Failed to install event handler: \(status)", module: "Settings")
                return nil
            }
        }
        
        // Register the hot key
        let hotKeyID = EventHotKeyID(signature: OSType(0x68747479), id: nextHotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(UInt32(keyCode),
                                             modifiers,
                                             hotKeyID,
                                             GetEventDispatcherTarget(),
                                             0,
                                             &hotKeyRef)
        
        guard hotKeyStatus == noErr, let validHotKeyRef = hotKeyRef else {
            Logger.error("Failed to register hot key: \(hotKeyStatus)", module: "Settings")
            return nil
        }
        
        // Store the hot key reference and callback
        hotKeys[nextHotKeyID] = (validHotKeyRef, callback)
        
        Logger.info("Successfully registered global shortcut: \(key) with modifiers: \(modifiers), ID: \(nextHotKeyID)", module: "Settings")
        
        let currentID = nextHotKeyID
        nextHotKeyID += 1
        return currentID
    }
    
    func unregisterGlobalShortcut(id: UInt32? = nil) {
        if let id = id {
            // Unregister specific shortcut
            if let hotKey = hotKeys[id] {
                UnregisterEventHotKey(hotKey.hotKeyRef)
                hotKeys.removeValue(forKey: id)
            }
        } else {
            // Unregister all shortcuts
            for (_, hotKey) in hotKeys {
                UnregisterEventHotKey(hotKey.hotKeyRef)
            }
            hotKeys.removeAll()
        }
        
        // Remove event handler if no hot keys remain
        if hotKeys.isEmpty, let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        // Get the hot key ID from the event
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event,
                                     OSType(kEventParamDirectObject),
                                     OSType(typeEventHotKeyID),
                                     nil,
                                     MemoryLayout<EventHotKeyID>.size,
                                     nil,
                                     &hotKeyID)
        
        if status == noErr, let hotKey = hotKeys[hotKeyID.id] {
            hotKey.callback()
        }
        
        return noErr
    }
    
    private func keyCodeForString(_ key: String) -> Int? {
        let keyMap: [String: Int] = [
            "space": 49,
            "y": 16,
            "z": 6,
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34,
            "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12,
            "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
            "8": 28, "9": 25,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98,
            "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
        ]
        
        return keyMap[key.lowercased()]
    }
}

// Helper extension for common modifier combinations
extension GlobalKeyboardShortcutManager {
    // Proper modifier key constants from Carbon
    static let cmdKeyModifier: UInt32 = UInt32(cmdKey)
    static let shiftKeyModifier: UInt32 = UInt32(shiftKey)
    static let optionKeyModifier: UInt32 = UInt32(optionKey)
    static let controlKeyModifier: UInt32 = UInt32(controlKey)
    static let fnKeyModifier: UInt32 = UInt32(1 << 17) // 0x20000 - Function key modifier
} 
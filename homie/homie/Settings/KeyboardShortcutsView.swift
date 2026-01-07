//
//  KeyboardShortcutsView.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import SwiftUI

struct KeyboardShortcutsView: View {
    @State private var shortcuts: [ShortcutItem] = []
    
    struct ShortcutItem: Identifiable {
        let id = UUID()
        let name: String
        let identifier: String
        let description: String
        var key: String
        var modifiers: UInt32
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Keyboard Shortcuts")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(shortcuts) { shortcut in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(shortcut.name)
                                .font(.headline)
                            
                            Text(shortcut.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Shortcut:")
                                    .font(.subheadline)
                                
                                Text(formatShortcut(key: shortcut.key, modifiers: shortcut.modifiers))
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                Button("Record") {
                                    // TODO: Implement shortcut recording
                                    Logger.info("Record shortcut for \(shortcut.name)", module: "Settings")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            loadShortcuts()
        }
    }
    
    private func loadShortcuts() {
        let userDefaults = UserDefaults.standard
        
        // Define default shortcuts
        let defaultShortcuts = [
            ("VoiceGPT", "voicegpt", "Toggle VoiceGPT transcription", "i", GlobalKeyboardShortcutManager.controlKeyModifier | GlobalKeyboardShortcutManager.shiftKeyModifier),
            ("Dictation", "dictation", "Toggle dictation recording and transcription", "o", GlobalKeyboardShortcutManager.shiftKeyModifier | GlobalKeyboardShortcutManager.controlKeyModifier),
            ("Text Entry", "textentry", "Toggle text entry mode", "k", GlobalKeyboardShortcutManager.controlKeyModifier | GlobalKeyboardShortcutManager.shiftKeyModifier)
        ]
        
        var loadedShortcuts: [ShortcutItem] = []
        
        for (name, identifier, description, defaultKey, defaultModifiers) in defaultShortcuts {
            let keyKey = "shortcut_\(identifier)_key"
            let modifiersKey = "shortcut_\(identifier)_modifiers"
            
            let key = userDefaults.string(forKey: keyKey) ?? defaultKey
            let modifiers = UInt32(userDefaults.integer(forKey: modifiersKey))
            
            if modifiers == 0 {
                // No saved modifiers, use default
                loadedShortcuts.append(ShortcutItem(
                    name: name,
                    identifier: identifier,
                    description: description,
                    key: key,
                    modifiers: defaultModifiers
                ))
            } else {
                loadedShortcuts.append(ShortcutItem(
                    name: name,
                    identifier: identifier,
                    description: description,
                    key: key,
                    modifiers: modifiers
                ))
            }
        }
        
        shortcuts = loadedShortcuts
    }
    
    private func formatShortcut(key: String, modifiers: UInt32) -> String {
        var parts: [String] = []
        
        if modifiers & GlobalKeyboardShortcutManager.controlKeyModifier != 0 {
            parts.append("⌃")
        }
        if modifiers & GlobalKeyboardShortcutManager.shiftKeyModifier != 0 {
            parts.append("⇧")
        }
        if modifiers & GlobalKeyboardShortcutManager.optionKeyModifier != 0 {
            parts.append("⌥")
        }
        if modifiers & GlobalKeyboardShortcutManager.cmdKeyModifier != 0 {
            parts.append("⌘")
        }
        
        parts.append(key.uppercased())
        
        return parts.joined(separator: " ")
    }
}

#Preview {
    KeyboardShortcutsView()
}

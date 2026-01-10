//
//  PermissionsView.swift
//  homie
//
//  Permissions setup screen after successful authentication
//

import SwiftUI

struct PermissionsView: View {
    @StateObject private var store = PermissionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isCheckingMicrophone: Bool = false
    @State private var isCheckingAccessibility: Bool = false

    var isFromSettings: Bool = false
    var onPermissionsComplete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Permissions Form
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    
                    Text("Enable core features")
                        .font(.system(size: 32, weight: .semibold))
                    
                    Text("Homie needs these permissions to work")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
                
                // Microphone Permission
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        // Icon
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                            .frame(width: 40, height: 40)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        
                        // Text
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Microphone Access")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Homie only uses your microphone when you dictate")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Button or Checkmark
                        if store.isMicrophoneGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                        } else {
                            Button(action: requestMicrophonePermission) {
                                Text("Allow")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                    .background(Color.yellow)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isCheckingMicrophone)
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(store.isMicrophoneGranted ? Color.green.opacity(0.3) : Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
                
                // Accessibility Permission
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        // Icon
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                            .frame(width: 40, height: 40)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        
                        // Text
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Accessibility Access")
                                .font(.system(size: 16, weight: .semibold))
                            Text("This allows Homie to paste text into any textbox")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Button or Checkmark
                        if store.isAccessibilityGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                        } else {
                            Button(action: requestAccessibilityPermission) {
                                Text("Allow")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                    .background(Color.yellow)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isCheckingAccessibility)
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(store.isAccessibilityGranted ? Color.green.opacity(0.3) : Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
                
                // Continue/Done Button
                Button(action: {
                    if isFromSettings {
                        dismiss()
                    } else {
                        onPermissionsComplete?()
                    }
                }) {
                    HStack {
                        Text(isFromSettings ? "Done" : "Continue")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .background(isFromSettings || allPermissionsGranted ? Color.yellow : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isFromSettings && !allPermissionsGranted)
                .padding(.top, 8)
            }
            .frame(width: 520)
            .padding(40)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            checkInitialPermissions()
        }
    }
    
    // MARK: - Computed Properties
    
    private var allPermissionsGranted: Bool {
        store.areRequiredPermissionsGranted
    }
    
    // MARK: - Permission Checking
    
    private func checkInitialPermissions() {
        store.refreshAll()
    }
    
    // MARK: - Permission Requests
    
    private func requestMicrophonePermission() {
        isCheckingMicrophone = true

        Task {
            let granted = await store.requestMicrophone()
            await MainActor.run {
                isCheckingMicrophone = false

                if !granted {
                    // Show alert to direct user to System Preferences
                    let alert = NSAlert()
                    alert.messageText = "Microphone Access Required"
                    alert.informativeText = "Please enable microphone access in System Preferences > Security & Privacy > Privacy > Microphone"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Preferences")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        PermissionManager.shared.openSystemPreferences(for: .microphone)
                    }
                }
            }
        }
    }
    
    private func requestAccessibilityPermission() {
        isCheckingAccessibility = true

        // Check current status without prompting (avoids double dialog)
        store.refreshAll()

        if !store.isAccessibilityGranted {
            // Open System Preferences directly and start polling
            PermissionManager.shared.openSystemPreferences(for: .accessibility)
            store.startAccessibilityPolling()
        }

        isCheckingAccessibility = false
    }
}

#Preview {
    PermissionsView()
        .frame(width: 700, height: 650)
}


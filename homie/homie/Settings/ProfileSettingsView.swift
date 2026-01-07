//
//  ProfileSettingsView.swift
//  homie
//
//  Profile settings view
//

import SwiftUI
import AppKit
import Supabase

struct ProfileSettingsView: View {
    @ObservedObject private var authStore = AuthSessionStore.shared
    @ObservedObject private var permissionStore = PermissionStore.shared
    @State private var userName: String = ""
    @State private var userEmail: String = ""
    @State private var initialUserName: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showPermissionsSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Profile Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name field card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        
                        TextField("Enter your name", text: $userName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                            .onChange(of: userName) { newValue in
                                // Cancel previous save task
                                saveTask?.cancel()
                                
                                // Only save if the value has actually changed from initial
                                guard newValue != initialUserName && !newValue.isEmpty else { return }
                                
                                // Debounce: wait 1 second after user stops typing before saving
                                saveTask = Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                                    
                                    // Check if task was cancelled
                                    guard !Task.isCancelled else { return }
                                    
                                    // Save silently
                                    await saveProfile()
                                }
                            }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Email field card (read-only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                        
                        HStack {
                            Text(userEmail.isEmpty ? "No email" : userEmail)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding(12)
                        .background(Color.clear)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)

                    // Subscription card
                    SubscriptionView()

                    // App Version card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App Version")
                            .font(.headline)

                        HStack {
                            Text("Current Version")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(UpdateManager.shared.getCurrentVersion())
                                .font(.system(size: 14, weight: .medium))
                        }

                        Divider()

                        Button(action: {
                            UpdateManager.shared.checkForUpdates()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14))
                                Text("Check for Updates")
                                    .font(.system(size: 14))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)

                    // Permissions card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permissions")
                            .font(.headline)

                        HStack {
                            Text(permissionStore.areRequiredPermissionsGranted ? "All permissions granted" : "Some permissions required")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            if permissionStore.areRequiredPermissionsGranted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }

                        Divider()

                        Button(action: { showPermissionsSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield")
                                    .font(.system(size: 14))
                                Text("Manage Permissions")
                                    .font(.system(size: 14))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)

                    // Sign Out Button card
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            Task {
                                // Cancel any active transcription first to clean up whisper resources
                                TranscriptionStore.shared.cancelRecording()

                                try? await AuthenticationManager.shared.signOut()
                                await MainActor.run {
                                    NSApplication.shared.terminate(nil)
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14))
                                Text("Sign Out")
                                    .font(.system(size: 14))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            loadProfile()
            permissionStore.refreshAll()
        }
        .sheet(isPresented: $showPermissionsSheet) {
            PermissionsView(isFromSettings: true)
                .frame(minWidth: 600, minHeight: 500)
        }
    }
    
    private func loadProfile() {
        userName = authStore.userName ?? ""
        userEmail = authStore.userEmail ?? ""
        initialUserName = userName // Store initial value to detect changes
    }
    
    private func saveProfile() async {
        guard !userName.isEmpty && userName != initialUserName else { return }
        
        do {
            // Update user metadata in Supabase
            try await updateUserMetadata(name: userName)
            
            await MainActor.run {
                authStore.userName = userName
                initialUserName = userName // Update initial value after successful save
                // Also sync to UserDefaults for PersonalizeView
                UserDefaults.standard.set(userName, forKey: "personalize_name")
            }
        } catch {
            // Silently fail - no user feedback needed
            Logger.error("Failed to save profile: \(error.localizedDescription)", module: "Settings")
        }
    }
    
    private func updateUserMetadata(name: String) async throws {
        // Use Supabase SDK to update user metadata
        try await supabase.auth.update(user: .init(data: ["full_name": .string(name)]))
    }
}

#Preview {
    ProfileSettingsView()
        .frame(width: 600, height: 400)
}



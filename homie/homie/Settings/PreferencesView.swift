//
//  PreferencesView.swift
//  homie
//
//  User preferences view for configuring app-wide settings.
//  Includes Local LLM model toggle for opt-in model download.
//

import SwiftUI

struct PreferencesView: View {
    @State private var localLLMEnabled: Bool = false
    @ObservedObject private var localLLMStore = LocalLLMModelStore.shared
    @ObservedObject private var entitlementStore = FeatureEntitlementStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Preferences")
                .font(.largeTitle)
                .fontWeight(.bold)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Local AI Model card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Local AI Model")
                            .font(.headline)

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Local AI")
                                    .font(.system(size: 14, weight: .medium))

                                Text("Use on-device Gemma 3 Nano 2B model for AI features. Requires ~2GB download.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // Show download status when enabled
                                if localLLMEnabled {
                                    HStack(spacing: 6) {
                                        if localLLMStore.modelState.isDownloading {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text(localLLMStore.modelState.displayText)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else if localLLMStore.modelState.isReady {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                            Text("Model ready")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else if case .failed(let reason) = localLLMStore.modelState {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                            Text(reason)
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: $localLLMEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: localLLMEnabled) { newValue in
                                    savePreference(newValue)
                                    if newValue {
                                        // Trigger model loading when enabled
                                        Task {
                                            await localLLMStore.ensureModelReady()
                                        }
                                    }
                                }
                        }

                        // Warning when disabled
                        if !localLLMEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)

                                Text("AI features require a premium subscription when the local model is disabled.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }

                        // Benefits list
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Benefits of Local AI:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.top, 8)

                            benefitRow(icon: "lock.shield", text: "Privacy: All processing stays on your device")
                            benefitRow(icon: "wifi.slash", text: "Offline: Works without internet connection")
                            benefitRow(icon: "bolt", text: "Fast: No network latency for responses")
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Debug section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Debug Tools")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                Task { @MainActor in
                                    NotchManager.shared.debugShowLinearToolConfirmation()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundColor(.indigo)
                                    Text("Linear Notch")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                Task { @MainActor in
                                    NotchManager.shared.debugShowCalendarToolConfirmation()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundColor(.red)
                                    Text("Calendar Notch")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                Task { @MainActor in
                                    NotchManager.shared.debugShowReminderToolConfirmation()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Reminder Notch")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("Test tool confirmation UIs with mock data")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            loadPreference()
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func savePreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "local_llm_enabled")
        Logger.info("⚙️ PreferencesView: Local LLM preference set to \(enabled)", module: "Settings")
    }

    private func loadPreference() {
        localLLMEnabled = UserDefaults.standard.bool(forKey: "local_llm_enabled")
        Logger.info("⚙️ PreferencesView: Loaded Local LLM preference: \(localLLMEnabled)", module: "Settings")
    }
}

#Preview {
    PreferencesView()
}

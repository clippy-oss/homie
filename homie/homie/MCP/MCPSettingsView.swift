//
//  MCPSettingsView.swift
//  homie
//
//  Settings view for managing MCP server integrations
//

import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject private var mcpManager = MCPManager.shared
    @ObservedObject private var oauthManager = MCPOAuthManager.shared
    @ObservedObject private var entitlementStore = FeatureEntitlementStore.shared

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingPairingSheet = false
    @State private var pairingConfig: MCPServerConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Integrations")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Connect services to use with AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Connected count badge
                if mcpManager.connectedServerCount > 0 {
                    Text("\(mcpManager.connectedServerCount) connected")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                }
            }
            .padding(.bottom, 8)
            
            // Premium check
            if !entitlementStore.canUseMCPIntegrations {
                PremiumRequiredView()
            } else {
                // Integration list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(MCPServerConfig.allServers) { config in
                            IntegrationCard(
                                config: config,
                                status: mcpManager.connectionStatus(for: config.id),
                                isConnecting: oauthManager.isAuthenticating && oauthManager.currentServer == config.id,
                                onConnect: { connectServer(config) },
                                onDisconnect: { disconnectServer(config.id) }
                            )
                        }
                    }
                }
                
                // Info footer
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("Connected integrations let AI access your data when relevant to your requests.")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .alert("Connection Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingPairingSheet) {
            if let config = pairingConfig {
                devicePairingSheet(for: config)
            }
        }
        .onChange(of: pairingConfig) { _, newValue in
            // Show sheet when config is set, ensuring state is synchronized
            if newValue != nil {
                showingPairingSheet = true
            }
        }
    }

    // MARK: - Pairing Sheet

    @ViewBuilder
    private func devicePairingSheet(for config: MCPServerConfig) -> some View {
        if #available(macOS 15.0, *) {
            let _ = Logger.info("devicePairingSheet: Creating DevicePairingView for \(config.name)", module: "MCP")
            DevicePairingView(
                provider: mcpManager.whatsAppProvider,
                providerName: config.name,
                onSuccess: {
                    showingPairingSheet = false
                    pairingConfig = nil
                    Logger.info("MCPSettingsView: Connected to \(config.name) via device pairing", module: "MCP")
                },
                onCancel: {
                    showingPairingSheet = false
                    pairingConfig = nil
                }
            )
        } else {
            Text("Device pairing requires macOS 15.0 or later")
                .padding()
        }
    }

    // MARK: - Actions

    private func connectServer(_ config: MCPServerConfig) {
        Logger.info("connectServer called for \(config.name), authType: \(config.authType)", module: "MCP")
        switch config.authType {
        case .devicePairing:
            // Show device pairing sheet for WhatsApp, Telegram, etc.
            Logger.info("Setting up pairing sheet for \(config.name)", module: "MCP")
            // Setting pairingConfig shows the sheet (using sheet(item:) binding)
            pairingConfig = config

        case .oauth:
            // Use OAuth flow for Linear, Google Calendar, etc.
            oauthManager.authenticate(serverConfig: config) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let credentials):
                        mcpManager.connectServer(config.id, credentials: credentials)
                        Logger.info("✅ MCPSettingsView: Connected to \(config.name)", module: "MCP")

                    case .failure(let error):
                        if case .authenticationFailed(let msg) = error, msg == "User cancelled" {
                            // User cancelled, don't show error
                            return
                        }
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }
    }

    private func disconnectServer(_ serverID: String) {
        // For WhatsApp, also logout to clear device pairing
        if serverID == "whatsapp" {
            Task {
                try? await mcpManager.whatsAppProvider.logout()
            }
        }
        mcpManager.disconnectServer(serverID)
    }
}

// MARK: - Integration Card

struct IntegrationCard: View {
    let config: MCPServerConfig
    let status: MCPConnectionStatus
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBackgroundColor)
                    .frame(width: 44, height: 44)
                
                Image(systemName: config.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(iconForegroundColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.name)
                        .font(.headline)
                    
                    if status.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action button
            Button(action: {
                if status.isConnected {
                    onDisconnect()
                } else {
                    onConnect()
                }
            }) {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 80)
                } else {
                    Text(status.isConnected ? "Disconnect" : "Connect")
                        .font(.subheadline)
                        .frame(width: 80)
                }
            }
            .buttonStyle(.bordered)
            .tint(status.isConnected ? .red : .accentColor)
            .disabled(isConnecting)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(12)
    }
    
    private var iconBackgroundColor: Color {
        switch config.id {
        case "linear":
            return Color.purple.opacity(0.15)
        case "google_calendar":
            return Color.blue.opacity(0.15)
        case "whatsapp":
            return Color.green.opacity(0.15)
        default:
            return Color.gray.opacity(0.15)
        }
    }

    private var iconForegroundColor: Color {
        switch config.id {
        case "linear":
            return .purple
        case "google_calendar":
            return .blue
        case "whatsapp":
            return .green
        default:
            return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .disconnected:
            return config.description
        case .connecting:
            return "Connecting..."
        case .pairing:
            return "Waiting for pairing..."
        case .connected(let email):
            if let email = email {
                return email
            }
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Premium Required View

struct PremiumRequiredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            
            Text("Premium Required")
                .font(.headline)
            
            Text("Integrations are available for premium users. Upgrade to connect Linear, Google Calendar, and more.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    MCPSettingsView()
        .frame(width: 400, height: 500)
}




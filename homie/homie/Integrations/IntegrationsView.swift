//
//  IntegrationsView.swift
//  homie
//
//  View for managing integrations (OAuth and device pairing)
//

import SwiftUI

@available(macOS 15.0, *)
struct IntegrationsView: View {
    @ObservedObject private var mcpManager = MCPManager.shared
    @ObservedObject private var oauthManager = MCPOAuthManager.shared
    @ObservedObject private var entitlementStore = FeatureEntitlementStore.shared
    @ObservedObject private var messagingService = MessagingService.shared

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingPairingSheet = false
    @State private var pairingIntegration: IntegrationConfig?

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
                if connectedCount > 0 {
                    Text("\(connectedCount) connected")
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
                        ForEach(IntegrationConfig.allIntegrations) { config in
                            IntegrationCard(
                                config: config,
                                status: integrationStatus(for: config),
                                isConnecting: oauthManager.isAuthenticating && oauthManager.currentServer == config.id,
                                onConnect: { connectIntegration(config) },
                                onDisconnect: { disconnectIntegration(config) }
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
            if let config = pairingIntegration {
                devicePairingSheet(for: config)
            }
        }
    }

    // MARK: - Computed Properties

    private var connectedCount: Int {
        var count = mcpManager.connectedServerCount
        if messagingService.whatsApp.isLoggedIn {
            count += 1
        }
        return count
    }

    private func integrationStatus(for config: IntegrationConfig) -> IntegrationStatus {
        switch config.authType {
        case .oauth:
            return mcpManager.connectionStatus(for: config.id)
        case .devicePairing:
            return whatsAppStatus
        }
    }

    private var whatsAppStatus: IntegrationStatus {
        let provider = messagingService.whatsApp
        if provider.isLoggedIn {
            return .connected(email: nil)
        }
        switch provider.connectionStatus {
        case .connecting:
            return .connecting
        case .pairing:
            return .pairing
        case .error(let msg):
            return .error(msg)
        default:
            return .disconnected
        }
    }

    // MARK: - Pairing Sheet

    @ViewBuilder
    private func devicePairingSheet(for config: IntegrationConfig) -> some View {
        DevicePairingView(
            providerName: config.name,
            onSuccess: {
                showingPairingSheet = false
                pairingIntegration = nil
                Logger.info("IntegrationsView: Connected to \(config.name) via device pairing", module: "Integrations")
            },
            onCancel: {
                showingPairingSheet = false
                pairingIntegration = nil
            }
        )
    }

    // MARK: - Actions

    private func connectIntegration(_ config: IntegrationConfig) {
        Logger.info("connectIntegration called for \(config.name), authType: \(config.authType)", module: "Integrations")

        switch config.authType {
        case .oauth:
            oauthManager.authenticate(serverConfig: config) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let credentials):
                        mcpManager.connectServer(config.id, credentials: credentials)
                        Logger.info("IntegrationsView: Connected to \(config.name)", module: "Integrations")

                    case .failure(let error):
                        if case .authenticationFailed(let msg) = error, msg == "User cancelled" {
                            return
                        }
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }

        case .devicePairing:
            Logger.info("Showing device pairing sheet for \(config.name)", module: "Integrations")
            pairingIntegration = config
            showingPairingSheet = true
        }
    }

    private func disconnectIntegration(_ config: IntegrationConfig) {
        Logger.info("disconnectIntegration called for \(config.name)", module: "Integrations")

        switch config.authType {
        case .oauth:
            mcpManager.disconnectServer(config.id)

        case .devicePairing:
            Task {
                try? await messagingService.whatsApp.logout()
            }
        }
    }
}

// MARK: - Integration Card

struct IntegrationCard: View {
    let config: IntegrationConfig
    let status: IntegrationStatus
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(config.backgroundColorValue)
                    .frame(width: 44, height: 44)

                Image(systemName: config.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(config.foregroundColorValue)
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

@available(macOS 15.0, *)
#Preview {
    IntegrationsView()
        .frame(width: 400, height: 500)
}

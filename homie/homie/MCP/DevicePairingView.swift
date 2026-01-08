//
//  DevicePairingView.swift
//  homie
//
//  Device pairing view supporting phone code pairing.
//  Works with any MessagingProviderProtocol implementation.
//

import SwiftUI
import Combine

@available(macOS 15.0, *)
struct DevicePairingView: View {
    let provider: MessagingProviderProtocol
    let providerName: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    // Phone Code state
    @State private var phoneNumber: String = ""
    @State private var pairingCode: String?
    @State private var isRequestingCode = false

    // Common state
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPairingSuccessful = false
    @State private var isProviderReady = false
    @State private var providerStartTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if isPairingSuccessful {
                successView
            } else if !isProviderReady && isLoading {
                // Show loading while starting provider
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Starting \(providerName) bridge...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 20) {
                    phoneCodeView
                    Spacer()
                }
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 400, height: 500)
        .onAppear {
            Logger.info("DevicePairingView.onAppear called", module: "Pairing")
            ensureProviderStarted()
        }
        .task {
            // Fallback: also trigger from .task in case onAppear doesn't fire
            Logger.info("DevicePairingView.task called", module: "Pairing")
            if !isProviderReady {
                ensureProviderStarted()
            }
        }
        .onDisappear {
            Logger.info("DevicePairingView.onDisappear called", module: "Pairing")
            providerStartTask?.cancel()
            cancelCurrentPairing()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(providerName)")
                    .font(.headline)

                Text("Pair your device to enable messaging")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Phone Code View

    private var phoneCodeView: some View {
        VStack(spacing: 16) {
            if let code = pairingCode {
                // Display the pairing code
                VStack(spacing: 12) {
                    Text("Enter this code on your phone:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(formatPairingCode(code))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)

                    instructionsView

                    Button("Get New Code") {
                        pairingCode = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Phone number input
                VStack(spacing: 12) {
                    Text("Enter your phone number with country code:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("+1234567890", text: $phoneNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)

                    Button(action: requestPairingCode) {
                        if isRequestingCode {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Get Pairing Code")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(phoneNumber.isEmpty || isRequestingCode)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Successfully Connected!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your \(providerName) account is now linked.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if !isPairingSuccessful {
                Button("Cancel") {
                    cancelCurrentPairing()
                    onCancel()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if isPairingSuccessful {
                Button("Done") {
                    onSuccess()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Instructions View

    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            instructionStep(1, "Open \(providerName) on your phone")
            instructionStep(2, "Go to Settings > Linked Devices")
            instructionStep(3, "Tap 'Link a Device' > 'Link with phone number'")
            instructionStep(4, "Enter the code shown above")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(message: String, retryAction: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Connection Error")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again", action: retryAction)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func ensureProviderStarted() {
        Logger.info("ensureProviderStarted() called", module: "Pairing")

        // The provider is already started by AppDelegate at app launch.
        // We just need to mark it as ready for phone code pairing.
        isProviderReady = true
    }

    private func requestPairingCode() {
        guard !phoneNumber.isEmpty else { return }

        isRequestingCode = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let code = try await provider.startCodePairing(phoneNumber: phoneNumber)
                pairingCode = code
                isRequestingCode = false

                // Start listening for pairing success
                listenForCodePairingSuccess()
            } catch {
                errorMessage = error.localizedDescription
                isRequestingCode = false
            }
        }
    }

    private func listenForCodePairingSuccess() {
        // Subscribe to connection status events instead of polling
        Task { @MainActor in
            Logger.info("Code pairing: subscribing to connection status events", module: "Pairing")

            // Create a timeout task
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                return true
            }

            // Subscribe to connection status events
            let eventStream = provider.subscribeToEvents(types: [.connectionStatus])

            // Wait for either a connected event or timeout
            for await event in eventStream {
                if case .connectionStatus(let status) = event {
                    Logger.info("Code pairing: received connection status: \(status)", module: "Pairing")
                    if status.isConnected && provider.isLoggedIn {
                        timeoutTask.cancel()
                        isPairingSuccessful = true
                        Logger.info("Code pairing: pairing successful!", module: "Pairing")
                        return
                    }
                }
            }

            // If we get here, the stream ended without success - check final status
            if provider.isLoggedIn {
                isPairingSuccessful = true
                Logger.info("Code pairing: pairing successful (stream ended)", module: "Pairing")
            } else {
                Logger.warning("Code pairing: timed out waiting for pairing success", module: "Pairing")
            }
        }
    }

    private func cancelCurrentPairing() {
        isLoading = false
        isRequestingCode = false
    }

    // MARK: - Helpers

    private func formatPairingCode(_ code: String) -> String {
        // Format as XXXX-XXXX for readability
        let cleaned = code.replacingOccurrences(of: "-", with: "")
        if cleaned.count == 8 {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 4)
            return "\(cleaned[..<index])-\(cleaned[index...])"
        }
        return code
    }
}

// MARK: - Preview

@available(macOS 15.0, *)
#Preview {
    DevicePairingView(
        provider: MockMessagingProvider(),
        providerName: "WhatsApp",
        onSuccess: {},
        onCancel: {}
    )
}

// MARK: - Mock Provider for Preview

@available(macOS 15.0, *)
private class MockMessagingProvider: MessagingProviderProtocol {
    var providerID: String = "mock"
    var displayName: String = "Mock"
    var connectionStatus: MessagingConnectionStatus = .disconnected
    var connectionStatusPublisher: AnyPublisher<MessagingConnectionStatus, Never> {
        Just(.disconnected).eraseToAnyPublisher()
    }
    var isConnected: Bool = false
    var isLoggedIn: Bool = false

    func start() async throws {}
    func stop() async {}
    func connect() async throws {}
    func disconnect() async {}

    func startQRPairing() -> AsyncThrowingStream<PairingEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.qrCode("mock-qr-data"))
        }
    }

    func startCodePairing(phoneNumber: String) async throws -> String {
        return "12345678"
    }

    func logout() async throws {}
    func getChats(limit: Int, offset: Int) async throws -> [MessagingChat] { [] }
    func getMessages(chatID: String, limit: Int, beforeID: String?) async throws -> [MessagingMessage] { [] }
    func sendMessage(chatID: String, text: String, quotedMessageID: String?) async throws -> MessagingMessage {
        fatalError("Not implemented")
    }
    func sendReaction(chatID: String, messageID: String, emoji: String) async throws {}
    func markAsRead(chatID: String, messageIDs: [String]) async throws {}
    func subscribeToEvents(types: [MessagingEventType]) -> AsyncStream<MessagingEvent> {
        AsyncStream { _ in }
    }
}

//
//  ServiceIntegrationsStore.swift
//  homie
//
//  Observable store for service integrations state.
//  Manages connection readiness and pairing/auth workflows for all integrations
//  (messaging, calendar, ticketing, etc.).
//  Views observe this store; operations delegate to underlying services.
//

import Foundation
import Combine

// MARK: - Integration Pairing State

/// Represents the pairing/authentication workflow state for an integration
@available(macOS 15.0, *)
enum IntegrationPairingState: Equatable {
    case idle
    case starting
    case waitingForQR
    case showingQR(String)
    case waitingForCode
    case showingCode(String)
    case authenticating
    case success(userID: String)
    case failed(String)

    var isLoading: Bool {
        switch self {
        case .starting, .waitingForQR, .waitingForCode, .authenticating:
            return true
        default:
            return false
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var qrCodeData: String? {
        if case .showingQR(let data) = self { return data }
        return nil
    }

    var pairingCode: String? {
        if case .showingCode(let code) = self { return code }
        return nil
    }
}

// MARK: - ServiceIntegrationsStore

/// Observable store for service integrations state.
/// Manages connection readiness and pairing/auth workflows for all integrations.
/// Views observe this store; operations delegate to underlying services.
@available(macOS 15.0, *)
@MainActor
final class ServiceIntegrationsStore: ObservableObject {

    // MARK: - Singleton

    static let shared = ServiceIntegrationsStore()

    // MARK: - Dependencies

    private let messagingService: MessagingService

    // MARK: - WhatsApp State

    /// WhatsApp provider readiness (gRPC client ready)
    @Published private(set) var isWhatsAppReady: Bool = false

    /// WhatsApp connection status
    @Published private(set) var whatsAppConnectionStatus: MessagingConnectionStatus = .disconnected

    /// WhatsApp login status
    @Published private(set) var isWhatsAppLoggedIn: Bool = false

    /// WhatsApp pairing workflow state
    @Published private(set) var whatsAppPairingState: IntegrationPairingState = .idle

    // MARK: - WhatsApp Convenience

    var isWhatsAppConnected: Bool { whatsAppConnectionStatus.isConnected }
    var canStartWhatsAppPairing: Bool { isWhatsAppReady && !isWhatsAppLoggedIn }

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var whatsAppQRPairingTask: Task<Void, Never>?
    private var whatsAppCodePairingTask: Task<Void, Never>?

    // MARK: - Initialization

    init(messagingService: MessagingService = .shared) {
        self.messagingService = messagingService
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe WhatsApp provider connection status
        messagingService.whatsApp.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.whatsAppConnectionStatus = status
            }
            .store(in: &cancellables)

        // Observe WhatsApp provider login status
        messagingService.whatsApp.$isLoggedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoggedIn in
                self?.isWhatsAppLoggedIn = isLoggedIn
            }
            .store(in: &cancellables)
    }

    // MARK: - WhatsApp Lifecycle

    /// Ensure WhatsApp provider is started and ready
    func ensureWhatsAppReady() async throws {
        guard !isWhatsAppReady else { return }

        whatsAppPairingState = .starting

        do {
            try await messagingService.ensureWhatsAppStarted()
            isWhatsAppReady = messagingService.whatsApp.grpcClientReady

            if isWhatsAppReady {
                whatsAppPairingState = .idle
                Logger.info("ServiceIntegrationsStore: WhatsApp ready", module: "Integrations")
            } else {
                whatsAppPairingState = .failed("WhatsApp bridge not ready")
            }
        } catch {
            isWhatsAppReady = false
            whatsAppPairingState = .failed("Failed to start WhatsApp: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - WhatsApp QR Pairing

    /// Start WhatsApp QR code pairing flow
    func startWhatsAppQRPairing() {
        cancelWhatsAppPairing()
        whatsAppPairingState = .waitingForQR

        whatsAppQRPairingTask = Task { @MainActor in
            do {
                // Ensure provider is ready
                if !isWhatsAppReady {
                    whatsAppPairingState = .starting
                    try await ensureWhatsAppReady()
                }

                whatsAppPairingState = .waitingForQR

                let stream = messagingService.whatsApp.startQRPairing()

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case .qrCode(let code):
                        Logger.info("Store: Setting QR state, code length: \(code.count)", module: "Integrations")
                        whatsAppPairingState = .showingQR(code)

                    case .pairingCode:
                        // Ignore in QR mode
                        break

                    case .timeout:
                        whatsAppPairingState = .waitingForQR
                        // Stream will provide new QR code

                    case .success(let userID, _):
                        whatsAppPairingState = .success(userID: userID)
                        return

                    case .error(let message):
                        whatsAppPairingState = .failed(message)
                    }
                }

                // Stream ended - check if logged in
                if !Task.isCancelled && messagingService.whatsApp.isLoggedIn {
                    whatsAppPairingState = .success(userID: "")
                }
            } catch {
                if !Task.isCancelled {
                    whatsAppPairingState = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - WhatsApp Code Pairing

    /// Start WhatsApp phone number code pairing flow
    func startWhatsAppCodePairing(phoneNumber: String) {
        cancelWhatsAppPairing()
        whatsAppPairingState = .waitingForCode

        whatsAppCodePairingTask = Task { @MainActor in
            do {
                // Ensure provider is ready
                if !isWhatsAppReady {
                    whatsAppPairingState = .starting
                    try await ensureWhatsAppReady()
                }

                whatsAppPairingState = .waitingForCode

                let code = try await messagingService.whatsApp.startCodePairing(phoneNumber: phoneNumber)
                whatsAppPairingState = .showingCode(code)

                // Listen for pairing success
                await listenForWhatsAppCodePairingSuccess()

            } catch {
                if !Task.isCancelled {
                    whatsAppPairingState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Listen for connection status events after code is displayed
    private func listenForWhatsAppCodePairingSuccess() async {
        let eventStream = messagingService.whatsApp.subscribeToEvents(types: [.connectionStatus])

        for await event in eventStream {
            if Task.isCancelled { break }

            if case .connectionStatus(let status) = event {
                Logger.info("WhatsApp code pairing: received connection status: \(status)", module: "Integrations")
                if status.isConnected && messagingService.whatsApp.isLoggedIn {
                    whatsAppPairingState = .success(userID: "")
                    return
                }
            }
        }

        // Stream ended - check final status
        if !Task.isCancelled && messagingService.whatsApp.isLoggedIn {
            whatsAppPairingState = .success(userID: "")
        }
    }

    // MARK: - WhatsApp Cancellation

    /// Cancel any ongoing WhatsApp pairing operation
    func cancelWhatsAppPairing() {
        whatsAppQRPairingTask?.cancel()
        whatsAppQRPairingTask = nil
        whatsAppCodePairingTask?.cancel()
        whatsAppCodePairingTask = nil

        if whatsAppPairingState.isLoading {
            whatsAppPairingState = .idle
        }
    }

    /// Reset WhatsApp pairing state to idle
    func resetWhatsAppPairingState() {
        cancelWhatsAppPairing()
        whatsAppPairingState = .idle
    }
}

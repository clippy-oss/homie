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
        guard case .success = self else { return false }
        return true
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

    // MARK: - Provider State (Private Storage)

    private var providerReadiness: [MessagingProviderID: Bool] = [:]
    private var providerConnectionStatus: [MessagingProviderID: MessagingConnectionStatus] = [:]
    private var providerLoginStatus: [MessagingProviderID: Bool] = [:]
    private var providerPairingState: [MessagingProviderID: IntegrationPairingState] = [:]
    private var providerPairingTasks: [MessagingProviderID: Task<Void, Never>] = [:]

    /// Triggers view updates when any provider state changes.
    /// Views should access this property in their body to properly observe state changes.
    @Published private(set) var stateVersion: Int = 0

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(messagingService: MessagingService = .shared) {
        self.messagingService = messagingService
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Setup observers for all providers via protocol interface
        for providerID in MessagingProviderID.allCases {
            setupProviderObservers(providerID)
        }
    }

    private func setupProviderObservers(_ providerID: MessagingProviderID) {
        let provider = messagingService.provider(providerID)

        provider.connectionStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (status: MessagingConnectionStatus) in
                self?.updateConnectionStatus(providerID, status)
            }
            .store(in: &cancellables)

        provider.isLoggedInPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isLoggedIn: Bool) in
                self?.updateLoginStatus(providerID, isLoggedIn)
            }
            .store(in: &cancellables)
    }

    // MARK: - Provider State Accessors

    func isReady(_ provider: MessagingProviderID) -> Bool {
        providerReadiness[provider] ?? false
    }

    func connectionStatus(_ provider: MessagingProviderID) -> MessagingConnectionStatus {
        providerConnectionStatus[provider] ?? .disconnected
    }

    func isLoggedIn(_ provider: MessagingProviderID) -> Bool {
        providerLoginStatus[provider] ?? false
    }

    func pairingState(_ provider: MessagingProviderID) -> IntegrationPairingState {
        providerPairingState[provider] ?? .idle
    }

    func isConnected(_ provider: MessagingProviderID) -> Bool {
        connectionStatus(provider).isConnected
    }

    func canStartPairing(_ provider: MessagingProviderID) -> Bool {
        isReady(provider) && !isLoggedIn(provider)
    }

    // MARK: - Private State Update Helpers

    private func updateReadiness(_ provider: MessagingProviderID, _ value: Bool) {
        providerReadiness[provider] = value
        stateVersion += 1
    }

    private func updateConnectionStatus(_ provider: MessagingProviderID, _ value: MessagingConnectionStatus) {
        providerConnectionStatus[provider] = value
        stateVersion += 1
    }

    private func updateLoginStatus(_ provider: MessagingProviderID, _ value: Bool) {
        providerLoginStatus[provider] = value
        stateVersion += 1
    }

    private func updatePairingState(_ provider: MessagingProviderID, _ value: IntegrationPairingState) {
        providerPairingState[provider] = value
        stateVersion += 1
    }

    // MARK: - Provider Actions

    /// Logout from a messaging provider
    func logout(_ provider: MessagingProviderID) async throws {
        try await messagingService.logout(provider)
    }

    /// Reset pairing state to idle
    func resetPairingState(_ provider: MessagingProviderID) {
        cancelPairing(provider)
        updatePairingState(provider, .idle)
    }

    /// Cancel any ongoing pairing operation
    func cancelPairing(_ provider: MessagingProviderID) {
        providerPairingTasks[provider]?.cancel()
        providerPairingTasks[provider] = nil
        if pairingState(provider).isLoading {
            updatePairingState(provider, .idle)
        }
    }

    // MARK: - Service Lifecycle

    /// Ensure a messaging provider is started and ready
    func ensureServiceReady(_ provider: MessagingProviderID) async throws {
        guard !isReady(provider) else { return }

        updatePairingState(provider, .starting)

        do {
            try await messagingService.ensureStarted(provider)
            let ready = messagingService.isProviderReady(provider)
            updateReadiness(provider, ready)

            if ready {
                updatePairingState(provider, .idle)
                Logger.info("ServiceIntegrationsStore: \(provider.rawValue) ready", module: "Integrations")
            } else {
                updatePairingState(provider, .failed("\(provider.rawValue) bridge not ready"))
            }
        } catch {
            updateReadiness(provider, false)
            updatePairingState(provider, .failed("Failed to start \(provider.rawValue): \(error.localizedDescription)"))
            throw error
        }
    }

    // MARK: - QR Pairing

    /// Start QR code pairing flow for a provider
    func startQRPairing(_ provider: MessagingProviderID) {
        Logger.info("startQRPairing: \(provider.rawValue)", module: "Integrations")
        cancelPairing(provider)
        updatePairingState(provider, .waitingForQR)

        let task = Task { @MainActor in
            do {
                if !isReady(provider) {
                    updatePairingState(provider, .starting)
                    try await ensureServiceReady(provider)
                }

                updatePairingState(provider, .waitingForQR)

                let providerImpl = messagingService.provider(provider)
                let stream = providerImpl.startQRPairing()

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case .qrCode(let code):
                        Logger.info("QR code received, length: \(code.count)", module: "Integrations")
                        updatePairingState(provider, .showingQR(code))

                    case .pairingCode:
                        break

                    case .timeout:
                        updatePairingState(provider, .waitingForQR)

                    case .success(let userID, _):
                        updatePairingState(provider, .success(userID: userID))
                        return

                    case .error(let message):
                        updatePairingState(provider, .failed(message))
                    }
                }

                // Check if pairing succeeded via the provider's login status
                if !Task.isCancelled && providerImpl.isLoggedIn {
                    updatePairingState(provider, .success(userID: ""))
                }
            } catch {
                if !Task.isCancelled {
                    updatePairingState(provider, .failed(error.localizedDescription))
                }
            }
        }

        providerPairingTasks[provider] = task
    }

    // MARK: - Code Pairing

    /// Start phone number code pairing flow for a provider
    func startCodePairing(_ provider: MessagingProviderID, phoneNumber: String) {
        cancelPairing(provider)
        updatePairingState(provider, .waitingForCode)

        let task = Task { @MainActor in
            do {
                if !isReady(provider) {
                    updatePairingState(provider, .starting)
                    try await ensureServiceReady(provider)
                }

                updatePairingState(provider, .waitingForCode)

                let providerImpl = messagingService.provider(provider)
                let code = try await providerImpl.startCodePairing(phoneNumber: phoneNumber)
                if Task.isCancelled { return }
                updatePairingState(provider, .showingCode(code))

                // Wait for pairing to complete
                if Task.isCancelled { return }
                let userID = try await providerImpl.awaitCodePairingCompletion()
                updatePairingState(provider, .success(userID: userID))

            } catch {
                if !Task.isCancelled {
                    updatePairingState(provider, .failed(error.localizedDescription))
                }
            }
        }

        providerPairingTasks[provider] = task
    }
}

//
//  MessagingService.swift
//  homie
//
//  Central service that owns and manages all messaging providers.
//  Provides unified, provider-agnostic access to different messaging platforms.
//

import Foundation

/// Central service for managing messaging providers.
/// Handles lifecycle coordination (start/stop) - not observable state.
/// Observable state is managed by ServiceIntegrationsStore.
@available(macOS 15.0, *)
@MainActor
final class MessagingService {

    // MARK: - Shared Instance

    /// Shared instance for app-wide access
    static let shared = MessagingService()

    // MARK: - Providers

    private let providers: [MessagingProviderID: MessagingProviderProtocol]

    // MARK: - Private State

    private var initializationTasks: [MessagingProviderID: Task<Void, Error>] = [:]
    private var initializedProviders: Set<MessagingProviderID> = []

    // MARK: - Initialization

    /// Initialize with a dictionary of providers (dependency injection)
    init(providers: [MessagingProviderID: MessagingProviderProtocol]) {
        self.providers = providers
        Logger.info("MessagingService initialized with \(providers.count) provider(s)", module: "Messaging")
    }

    /// Convenience initializer with default providers
    convenience init() {
        self.init(providers: [
            .whatsapp: WhatsAppMessagingProvider()
        ])
    }

    // MARK: - Provider Access

    /// Get the underlying provider for a given ID (for observation/advanced use)
    func provider(_ id: MessagingProviderID) -> MessagingProviderProtocol {
        guard let provider = providers[id] else {
            fatalError("MessagingService: Provider \(id.rawValue) not registered")
        }
        return provider
    }

    /// Safely get a provider if registered, returns nil otherwise
    func providerIfRegistered(_ id: MessagingProviderID) -> MessagingProviderProtocol? {
        providers[id]
    }

    /// Check if a provider's transport is ready
    func isProviderReady(_ id: MessagingProviderID) -> Bool {
        providers[id]?.isReady ?? false
    }

    /// All available provider IDs
    var availableProviders: [MessagingProviderID] {
        Array(providers.keys)
    }

    // MARK: - Lifecycle

    /// Ensure a provider is started (lazy initialization)
    func ensureStarted(_ id: MessagingProviderID) async throws {
        // Already started?
        if isProviderReady(id) {
            return
        }

        // Already initializing?
        if let task = initializationTasks[id] {
            try await task.value
            return
        }

        // Start initialization
        let task = Task {
            Logger.info("MessagingService: Starting \(id.rawValue) provider...", module: "Messaging")
            try await provider(id).start()
            Logger.info("MessagingService: \(id.rawValue) provider started", module: "Messaging")
        }

        initializationTasks[id] = task

        do {
            try await task.value
            initializedProviders.insert(id)
        } catch {
            initializationTasks[id] = nil
            throw error
        }
    }

    /// Stop a specific provider
    func stop(_ id: MessagingProviderID) async {
        initializationTasks[id]?.cancel()
        initializationTasks[id] = nil

        await providers[id]?.stop()

        initializedProviders.remove(id)
        Logger.info("MessagingService: \(id.rawValue) provider stopped", module: "Messaging")
    }

    /// Stop all providers
    func stopAll() async {
        for id in providers.keys {
            await stop(id)
        }
        Logger.info("MessagingService: All providers stopped", module: "Messaging")
    }

    // MARK: - Provider Actions

    /// Logout from a messaging provider
    func logout(_ id: MessagingProviderID) async throws {
        try await provider(id).logout()
    }

    deinit {
        for task in initializationTasks.values {
            task.cancel()
        }
    }
}

//
//  MessagingService.swift
//  homie
//
//  Central service that owns and manages all messaging providers.
//  Provides unified access to different messaging platforms.
//

import Foundation
import Combine

/// Central service for managing messaging providers
@available(macOS 15.0, *)
@MainActor
final class MessagingService: ObservableObject {

    // MARK: - Shared Instance

    /// Shared instance for app-wide access
    static let shared = MessagingService()

    // MARK: - Providers

    /// WhatsApp messaging provider
    let whatsApp: WhatsAppMessagingProvider

    // Future: Add more providers
    // let telegram: TelegramMessagingProvider

    // MARK: - Published State

    @Published private(set) var isInitialized = false

    // MARK: - Private State

    private var initializationTask: Task<Void, Error>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize with all providers (dependency injection)
    init(whatsApp: WhatsAppMessagingProvider) {
        self.whatsApp = whatsApp
        Logger.info("MessagingService initialized", module: "Messaging")
    }

    /// Convenience initializer with default providers
    convenience init() {
        self.init(whatsApp: WhatsAppMessagingProvider())
    }

    // MARK: - Provider Access

    /// Get a provider by ID
    func provider(for id: String) -> MessagingProviderProtocol? {
        switch id {
        case "whatsapp":
            return whatsApp
        default:
            return nil
        }
    }

    /// All available provider IDs
    var availableProviderIDs: [String] {
        ["whatsapp"]
    }

    // MARK: - Lifecycle

    /// Ensure WhatsApp provider is started (lazy initialization)
    /// Call this before any WhatsApp operations
    func ensureWhatsAppStarted() async throws {
        // Already started?
        if whatsApp.grpcClientReady {
            return
        }

        // Already initializing?
        if let task = initializationTask {
            try await task.value
            return
        }

        // Start initialization
        let task = Task {
            Logger.info("MessagingService: Starting WhatsApp provider...", module: "Messaging")
            try await whatsApp.start()
            Logger.info("MessagingService: WhatsApp provider started", module: "Messaging")
        }

        initializationTask = task

        do {
            try await task.value
            isInitialized = true
        } catch {
            initializationTask = nil
            throw error
        }
    }

    /// Stop all providers
    func stopAll() async {
        initializationTask?.cancel()
        initializationTask = nil

        await whatsApp.stop()
        isInitialized = false

        Logger.info("MessagingService: All providers stopped", module: "Messaging")
    }

    deinit {
        initializationTask?.cancel()
    }
}

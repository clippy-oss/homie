//
//  LocalLLMModelStore.swift
//  homie
//
//  Observable store for local LLM model download and readiness state.
//  Publishes download progress and model availability for UI binding.
//

import Foundation
import Combine
import SwiftAI
import SwiftAIMLX

/// Model download state
enum LocalLLMModelState: Equatable {
    case notStarted
    case downloading(progress: Double)
    case ready
    case failed(reason: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .notStarted:
            return "Model not loaded"
        case .downloading(let progress):
            return "Loading model... \(Int(progress * 100))%"
        case .ready:
            return "Model ready"
        case .failed(let reason):
            return "Failed to load: \(reason)"
        }
    }
}

/// Observable store that manages local LLM model download state
/// Publishes download progress and readiness for UI binding
@MainActor
final class LocalLLMModelStore: ObservableObject {

    // MARK: - Singleton

    static let shared = LocalLLMModelStore()

    // MARK: - Published Properties

    /// Current model state (not started, downloading, ready, failed)
    @Published private(set) var modelState: LocalLLMModelState = .notStarted

    /// Download progress (0.0 to 1.0)
    @Published private(set) var downloadProgress: Double = 0.0

    /// Whether to show the download overlay
    @Published var showDownloadOverlay: Bool = false

    /// Model name being downloaded
    let modelName = "Gemma 3 Nano 2B"

    // MARK: - Private Properties

    private var pollingTimer: Timer?
    private var llmService: LocalLLMServiceImpl { LocalLLMServiceImpl.shared }

    // MARK: - Initialization

    private init() {
        Logger.info("📦 LocalLLMModelStore: Initialized", module: "LLM")
        startPollingModelStatus()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    // MARK: - Preference Check

    /// Check if Local LLM is enabled in user preferences
    private var isLocalLLMEnabled: Bool {
        UserDefaults.standard.bool(forKey: "local_llm_enabled")
    }

    // MARK: - Model Status Polling

    /// Start polling for model availability status
    private func startPollingModelStatus() {
        // Only start polling if local LLM is enabled
        guard isLocalLLMEnabled else {
            Logger.info("📦 LocalLLMModelStore: Polling skipped - Local LLM disabled", module: "LLM")
            modelState = .notStarted
            return
        }

        // Initial check
        updateModelStatus()

        // Poll every 0.5 seconds while downloading
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateModelStatus()
            }
        }
    }

    /// Restart polling when preference changes
    func restartPollingIfNeeded() {
        if isLocalLLMEnabled && pollingTimer == nil {
            Logger.info("📦 LocalLLMModelStore: Restarting polling - Local LLM enabled", module: "LLM")
            startPollingModelStatus()
        } else if !isLocalLLMEnabled {
            pollingTimer?.invalidate()
            pollingTimer = nil
            modelState = .notStarted
            showDownloadOverlay = false
            Logger.info("📦 LocalLLMModelStore: Stopped polling - Local LLM disabled", module: "LLM")
        }
    }

    /// Update model status from LocalLLMServiceImpl
    private func updateModelStatus() {
        let availability = llmService.modelAvailability

        if availability.contains("available") {
            if modelState != .ready {
                modelState = .ready
                downloadProgress = 1.0
                showDownloadOverlay = false
                Logger.info("📦 LocalLLMModelStore: Model is ready", module: "LLM")
                // Stop polling once ready
                pollingTimer?.invalidate()
                pollingTimer = nil
            }
        } else if availability.contains("downloading") {
            // Parse progress from "downloading (XX%)"
            if let percentStr = availability.components(separatedBy: "(").last?.components(separatedBy: "%").first,
               let percent = Int(percentStr) {
                let progress = Double(percent) / 100.0
                downloadProgress = progress
                modelState = .downloading(progress: progress)
                showDownloadOverlay = true
                Logger.info("📦 LocalLLMModelStore: Loading \(percent)%", module: "LLM")
            }
        } else if availability.contains("unavailable") {
            if availability.contains("modelNotDownloaded") {
                // Model needs to be downloaded - this will trigger automatically
                // when LocalLLMServiceImpl is accessed
                if case .notStarted = modelState {
                    modelState = .notStarted
                    showDownloadOverlay = true
                    Logger.info("📦 LocalLLMModelStore: Model not loaded yet", module: "LLM")
                }
            } else {
                modelState = .failed(reason: availability)
                Logger.info("📦 LocalLLMModelStore: Model unavailable - \(availability)", module: "LLM")
            }
        }
    }

    // MARK: - Public Methods

    /// Trigger model download/preload
    func ensureModelReady() async {
        // Check if local LLM is enabled
        guard isLocalLLMEnabled else {
            Logger.info("📦 LocalLLMModelStore: ensureModelReady skipped - Local LLM disabled", module: "LLM")
            return
        }

        guard !modelState.isReady else { return }

        showDownloadOverlay = true
        modelState = .downloading(progress: 0.0)

        Logger.info("📦 LocalLLMModelStore: Preparing model...", module: "LLM")

        // Restart polling if it was stopped
        restartPollingIfNeeded()

        // Access the service which will trigger model loading
        _ = llmService.isModelAvailable

        // The polling timer will update the state as download progresses
    }

    /// Dismiss the download overlay (user action)
    func dismissOverlay() {
        showDownloadOverlay = false
    }
}

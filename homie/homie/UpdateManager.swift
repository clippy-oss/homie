//
//  UpdateManager.swift
//  homie
//
//  Manages automatic updates using Sparkle framework
//

import Foundation
import Sparkle

class UpdateManager: NSObject {
    static let shared = UpdateManager()
    
    private var updaterController: SPUStandardUpdaterController?
    private var updater: SPUUpdater?
    private let appcastURL: URL
    
    private override init() {
        // Configure appcast URL from Cloudflare R2
        self.appcastURL = URL(string: Config.appcastURL)!

        super.init()
        
        // Initialize Sparkle updater
        self.setupUpdater()
    }
    
    private func setupUpdater() {
        // Create updater controller - it creates its own updater and user driver internally
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        
        // Get the updater from the controller to configure it
        guard let updater = updaterController?.updater else { return }
        
        // Clear any old feed URL from user defaults (fixes deprecation warning)
        updater.clearFeedURLFromUserDefaults()
        
        // Configure update check interval (default is 1 hour)
        updater.updateCheckInterval = 3600 // 1 hour in seconds
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = false // Let user choose when to install
        
        // Store reference to updater
        self.updater = updater
        
        Logger.info("✅ UpdateManager: Sparkle initialized with appcast URL: \(appcastURL.absoluteString)", module: "App")
        Logger.info("   Current app version: \(getCurrentVersion())", module: "App")
    }
    
    // MARK: - Public Methods
    
    /// Check for updates manually (called from menu item)
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
        Logger.debug("🔍 UpdateManager: Manual update check triggered", module: "App")
    }
    
    /// Check for updates in background (called on app launch)
    func checkForUpdatesInBackground() {
        updater?.checkForUpdatesInBackground()
        Logger.debug("🔍 UpdateManager: Background update check triggered", module: "App")
    }
    
    /// Get current app version
    func getCurrentVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateManager: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        return appcastURL.absoluteString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error {
            Logger.error("❌ UpdateManager: Update check failed: \(error.localizedDescription)", module: "App")
        } else {
            Logger.info("✅ UpdateManager: Update check completed successfully", module: "App")
        }
    }
    
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.info("🆕 UpdateManager: New update available: \(item.versionString)", module: "App")
    }
    
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error?) {
        if let error = error {
            Logger.error("⚠️ UpdateManager: Update check error: \(error.localizedDescription)", module: "App")
        } else {
            Logger.info("✅ UpdateManager: App is up to date", module: "App")
        }
    }
    
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock: @escaping () -> Void) -> Bool {
        // Allow user to finish current work before restarting
        // Return true to postpone, false to restart immediately
        return false
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdateManager: SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert(_ driver: SPUStandardUserDriver) {
        // Customize alert appearance if needed
        Logger.info("📢 UpdateManager: Showing update alert", module: "App")
    }
    
    func standardUserDriverWillShowUpdate(_ driver: SPUStandardUserDriver, for update: SUAppcastItem) {
        Logger.info("📢 UpdateManager: Showing update dialog for version \(update.versionString)", module: "App")
    }
}


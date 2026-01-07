import Foundation
import Combine

// MARK: - PermissionStore

/// Observable state store that owns permission state and delegates to PermissionManager for API calls.
@MainActor
final class PermissionStore: ObservableObject {

    // MARK: - Singleton

    static let shared = PermissionStore()

    // MARK: - Properties

    private let manager = PermissionManager.shared

    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityStatus: PermissionStatus = .notDetermined
    @Published private(set) var notificationStatus: PermissionStatus = .notDetermined

    // MARK: - Convenience Computed Properties

    var isMicrophoneGranted: Bool { microphoneStatus.isGranted }
    var isAccessibilityGranted: Bool { accessibilityStatus.isGranted }
    var isNotificationGranted: Bool { notificationStatus.isGranted }
    var areRequiredPermissionsGranted: Bool { isMicrophoneGranted && isAccessibilityGranted }

    // MARK: - Polling Timer

    private var accessibilityCheckTimer: Timer?
    private let accessibilityCheckInterval: TimeInterval = 1.0

    // MARK: - Initialization

    private init() {
        // Don't auto-refresh - let callers trigger refreshAll() when app is ready
        // This avoids crashes from accessing UNUserNotificationCenter too early on macOS 26
    }

    deinit {
        accessibilityCheckTimer?.invalidate()
    }

    // MARK: - Refresh

    /// Synchronously refreshes microphone and accessibility status.
    /// Note: Notification status is NOT checked here to avoid crashes from accessing
    /// UNUserNotificationCenter too early on macOS 26. Call refreshNotificationStatus() separately
    /// after the app is fully initialized (e.g., after main window is shown).
    func refreshAll() {
        microphoneStatus = manager.checkMicrophoneStatus()
        accessibilityStatus = manager.checkAccessibilityStatus()
    }

    /// Refreshes notification status. Call this only after the app is fully initialized.
    func refreshNotificationStatus() {
        Task {
            notificationStatus = await manager.checkNotificationStatus()
        }
    }

    // MARK: - Permission Requests

    /// Requests microphone permission and updates state.
    /// - Returns: True if permission was granted.
    func requestMicrophone() async -> Bool {
        let granted = await manager.requestMicrophonePermission()
        microphoneStatus = manager.checkMicrophoneStatus()
        return granted
    }

    /// Triggers system prompt for accessibility and starts polling if not granted.
    func requestAccessibility() {
        manager.requestAccessibilityPermission()
        accessibilityStatus = manager.checkAccessibilityStatus()
        if !accessibilityStatus.isGranted {
            startAccessibilityPolling()
        }
    }

    /// Requests notification permission and updates state.
    /// - Returns: True if permission was granted.
    func requestNotifications() async -> Bool {
        let granted = await manager.requestNotificationPermission()
        notificationStatus = await manager.checkNotificationStatus()
        return granted
    }

    // MARK: - Accessibility Polling

    /// Starts a timer that checks accessibility status every second.
    /// When granted, updates state and stops polling.
    func startAccessibilityPolling() {
        stopAccessibilityPolling()

        accessibilityCheckTimer = Timer.scheduledTimer(
            withTimeInterval: accessibilityCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let status = self.manager.checkAccessibilityStatus()
                self.accessibilityStatus = status
                if status.isGranted {
                    self.stopAccessibilityPolling()
                }
            }
        }
    }

    /// Stops the accessibility polling timer.
    func stopAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }
}

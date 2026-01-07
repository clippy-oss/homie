import Foundation
import AVFoundation
import ApplicationServices
import UserNotifications
import AppKit

// MARK: - PermissionType

enum PermissionType: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case notifications

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone:
            return "Microphone Access"
        case .accessibility:
            return "Accessibility Access"
        case .notifications:
            return "Notifications"
        }
    }

    var description: String {
        switch self {
        case .microphone:
            return "Microphone access is required to capture audio for voice commands and transcription."
        case .accessibility:
            return "Accessibility access is required to control your Mac and interact with other applications."
        case .notifications:
            return "Notifications allow Homie to alert you about important events and updates."
        }
    }

    var iconName: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .accessibility:
            return "hand.tap.fill"
        case .notifications:
            return "bell.fill"
        }
    }

    var systemPreferencesURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .notifications:
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                return URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleIdentifier)")
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        }
    }
}

// MARK: - PermissionStatus

enum PermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var isGranted: Bool { self == .authorized }
}

// MARK: - PermissionManager

final class PermissionManager {

    // MARK: - Singleton

    static let shared = PermissionManager()

    private init() {}

    // MARK: - Status Checks

    /// Checks the current microphone permission status
    func checkMicrophoneStatus() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }

    /// Checks the current accessibility permission status
    /// - Parameter prompt: If true, prompts the user to grant access if not already granted
    /// - Returns: The current permission status
    func checkAccessibilityStatus(prompt: Bool = false) -> PermissionStatus {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            return trusted ? .authorized : .denied
        } else {
            // Use AXIsProcessTrusted() without options - safer during early app initialization
            let trusted = AXIsProcessTrusted()
            return trusted ? .authorized : .denied
        }
    }

    /// Quick check if accessibility is trusted without prompting
    func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Checks the current notification permission status
    func checkNotificationStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .provisional:
            return .authorized
        case .ephemeral:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    // MARK: - Permission Requests

    /// Requests microphone permission from the user
    /// - Returns: True if permission was granted
    func requestMicrophonePermission() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Requests accessibility permission by triggering the system prompt
    /// Note: This opens the system dialog asking the user to grant accessibility access
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Requests notification permission from the user
    /// - Returns: True if permission was granted
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - System Preferences

    /// Opens System Preferences to the appropriate pane for the given permission type
    func openSystemPreferences(for type: PermissionType) {
        guard let url = type.systemPreferencesURL else { return }
        NSWorkspace.shared.open(url)
    }
}

//
//  FeatureGatewayUICoordinator.swift
//  homie
//
//  UI coordinator that handles feature gating UI presentations
//  Implements FeatureGatewayUIDelegate to show login, upgrade prompts, and alerts
//

import Cocoa
import SwiftUI

@MainActor
final class FeatureGatewayUICoordinator: FeatureGatewayUIDelegate {

    // MARK: - Singleton

    static let shared = FeatureGatewayUICoordinator()

    // MARK: - Private Properties

    private var loginWindowController: NSWindowController?
    private var upgradeWindowController: NSWindowController?

    // MARK: - Initialization

    private init() {
        // Register as the UI delegate for FeatureGateway
        FeatureGateway.shared.uiDelegate = self
    }

    // MARK: - FeatureGatewayUIDelegate

    func showLoginRequired() {
        // Close any existing login window
        loginWindowController?.close()

        // Create the login window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Sign In Required - Homie"
        window.center()

        // Create AuthCoordinatorView for login/signup flow
        let authView = AuthCoordinatorView(
            showSignup: false,
            onAuthSuccess: { [weak self] in
                Logger.info("FeatureGatewayUICoordinator: Authentication successful", module: "Feature")
                self?.loginWindowController?.close()
                self?.loginWindowController = nil
            }
        )

        let hostingController = NSHostingController(rootView: authView)
        window.contentViewController = hostingController

        let windowController = NSWindowController(window: window)
        self.loginWindowController = windowController

        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showUpgradeRequired(for feature: Feature) {
        // Close any existing upgrade window
        upgradeWindowController?.close()

        // Create the upgrade window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Upgrade Required - Homie"
        window.center()

        // Create UpgradePromptView
        let upgradeView = UpgradePromptView(
            feature: feature,
            onUpgrade: { [weak self] in
                Logger.info("FeatureGatewayUICoordinator: User requested upgrade for \(feature.displayName)", module: "Feature")
                self?.upgradeWindowController?.close()
                self?.upgradeWindowController = nil
                // TODO: Navigate to upgrade/payment flow
            },
            onDismiss: { [weak self] in
                self?.upgradeWindowController?.close()
                self?.upgradeWindowController = nil
            }
        )

        let hostingController = NSHostingController(rootView: upgradeView)
        window.contentViewController = hostingController

        let windowController = NSWindowController(window: window)
        self.upgradeWindowController = windowController

        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showFeatureUnavailable(reason: String) {
        let alert = NSAlert()
        alert.messageText = "Feature Unavailable"
        alert.informativeText = reason
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        alert.runModal()
    }
}

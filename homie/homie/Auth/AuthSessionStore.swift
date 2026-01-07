//
//  AuthSessionStore.swift
//  homie
//
//  Observable store for authentication state
//  Observes Supabase SDK authStateChanges and publishes state
//

import Foundation
import Supabase

@MainActor
class AuthSessionStore: ObservableObject {
    static let shared = AuthSessionStore()

    @Published var isAuthenticated: Bool = false
    @Published var isPremium: Bool = false
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var userId: String?
    @Published var premiumExpiresAt: Date?
    @Published var entitlements: UserEntitlements?

    private var authStateTask: Task<Void, Never>?
    private var initialSessionContinuation: CheckedContinuation<Void, Never>?
    private var hasReceivedInitialSession: Bool = false

    private init() {}

    /// Start observing auth state changes from Supabase SDK and wait for initial session
    /// This triggers an .initialSession event immediately with the current session state
    /// Returns after the initial session has been processed
    func startObservingAuthStateAndWait() async {
        authStateTask = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                handleAuthStateChange(event: event, session: session)
            }
        }

        // Wait for initial session to be processed
        await withCheckedContinuation { continuation in
            if hasReceivedInitialSession {
                continuation.resume()
            } else {
                initialSessionContinuation = continuation
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) {
        Logger.info("🔐 AuthSessionStore: Auth state changed - event: \(event)", module: "Auth")

        switch event {
        case .initialSession:
            if let session = session {
                // With emitLocalSessionAsInitialSession: true, we get the local session immediately
                // Even if the access token is expired, the refresh token may still be valid
                // and the SDK will refresh it automatically in the background
                // We only treat the user as signed out on actual .signedOut event
                updateFromSession(session)
                Task { try? await AuthenticationManager.shared.checkPremiumStatus() }
            } else {
                // initialSession with nil session = not logged in
                Logger.info("🔐 AuthSessionStore: No session found", module: "Auth")
                clearState()
            }
            // Signal that initial session has been processed
            hasReceivedInitialSession = true
            initialSessionContinuation?.resume()
            initialSessionContinuation = nil

        case .signedIn, .tokenRefreshed:
            if let session = session {
                updateFromSession(session)
                Task { try? await AuthenticationManager.shared.checkPremiumStatus() }
            }
        case .signedOut:
            Logger.info("🔐 AuthSessionStore: User signed out", module: "Auth")
            clearState()
        default:
            break
        }
    }

    private func updateFromSession(_ session: Session) {
        Logger.info("🔐 AuthSessionStore: Updating from session - user: \(session.user.id)", module: "Auth")
        isAuthenticated = true
        userId = session.user.id.uuidString
        userEmail = session.user.email
        userName = session.user.userMetadata["full_name"]?.stringValue
    }

    private func clearState() {
        isAuthenticated = false
        isPremium = false
        userId = nil
        userEmail = nil
        userName = nil
        premiumExpiresAt = nil
        entitlements = nil
    }

    /// Called by AuthenticationManager after premium status check (legacy)
    func updatePremiumStatus(isPremium: Bool, expiresAt: Date?) {
        self.isPremium = isPremium
        self.premiumExpiresAt = expiresAt
        Logger.info("💎 AuthSessionStore: Premium status updated - isPremium: \(isPremium)", module: "Auth")
    }

    /// Called by AuthenticationManager with structured entitlements
    func updateEntitlements(_ entitlements: UserEntitlements, expiresAt: Date?) {
        self.entitlements = entitlements
        // Derive isPremium from entitlements for backwards compatibility
        self.isPremium = entitlements.isPro
        self.premiumExpiresAt = expiresAt
        Logger.info("💎 AuthSessionStore: Entitlements updated - tier: \(entitlements.tier_id), features: \(entitlements.features.keys.joined(separator: ", "))", module: "Auth")
    }
}

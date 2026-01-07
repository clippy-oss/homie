//
//  AuthenticationManager.swift
//  homie
//
//  Stateless authentication manager that delegates to Supabase SDK
//  State is managed by AuthSessionStore
//

import Foundation
import Supabase

class AuthenticationManager {
    static let shared = AuthenticationManager()

    private init() {}

    // MARK: - Sign In

    /// Sign in with email and password
    /// AuthSessionStore will be notified via authStateChanges
    func signIn(email: String, password: String) async throws {
        Logger.info("🔑 AuthenticationManager: Signing in with email: \(email)", module: "Auth")
        try await supabase.auth.signIn(email: email, password: password)
        Logger.info("✅ AuthenticationManager: Sign in successful", module: "Auth")
    }

    // MARK: - Sign Out

    /// Sign out the current user
    /// AuthSessionStore will be notified via authStateChanges
    func signOut() async throws {
        Logger.info("👋 AuthenticationManager: Signing out...", module: "Auth")
        try await supabase.auth.signOut()
        Logger.info("✅ AuthenticationManager: Sign out successful", module: "Auth")
    }

    // MARK: - Check Email Exists

    /// Check if an email already exists in the system
    func checkEmailExists(email: String) async throws -> Bool {
        Logger.debug("🔍 AuthenticationManager: Checking if email exists: \(email)", module: "Auth")

        let exists: Bool = try await supabase.database
            .rpc("check_email_exists", params: ["user_email": email])
            .execute()
            .value

        Logger.info("✅ AuthenticationManager: Email exists: \(exists)", module: "Auth")
        return exists
    }

    // MARK: - Check Premium Status

    /// Check premium status and entitlements via Edge Function and update AuthSessionStore
    func checkPremiumStatus() async throws {
        Logger.info("💎 AuthenticationManager: Checking premium status...", module: "Auth")

        let response: UserStatusResponse = try await supabase.functions
            .invoke("get-user-status", options: .init(method: .post))

        await MainActor.run {
            if let entitlements = response.entitlements {
                // New path: use structured entitlements
                let expiresAt = entitlements.expires_at.flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
                AuthSessionStore.shared.updateEntitlements(entitlements, expiresAt: expiresAt)
                Logger.info("💎 AuthenticationManager: Entitlements loaded - tier: \(entitlements.tier_id)", module: "Auth")
            } else {
                // Fallback for backwards compatibility (old server response)
                let expiresAt = response.premium_expires_at.flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
                AuthSessionStore.shared.updatePremiumStatus(
                    isPremium: response.is_premium,
                    expiresAt: expiresAt
                )
                Logger.info("💎 AuthenticationManager: Premium status (legacy): \(response.is_premium ? "ACTIVE ✅" : "INACTIVE")", module: "Auth")
            }
        }
    }
}

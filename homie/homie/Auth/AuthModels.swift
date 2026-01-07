//
//  AuthModels.swift
//  homie
//
//  Data models for authentication and Supabase API responses
//  Note: SupabaseAuthResponse and SupabaseUser are now provided by Supabase SDK
//

import Foundation

// MARK: - User Entitlements

/// Structured entitlements returned from the server
/// Contains tier information and feature access flags
struct UserEntitlements: Codable {
    let tier_id: String
    let tier_name: String
    let tier_priority: Int
    let is_expired: Bool
    let expires_at: String?
    let features: [String: Bool]

    /// Check if a specific feature is available
    func hasFeature(_ feature: Feature) -> Bool {
        features[feature.rawValue] == true
    }

    /// Check if user has pro tier access
    var isPro: Bool {
        tier_id == "pro" && !is_expired
    }
}

// MARK: - User Status Response

/// Response from get-user-status Edge Function
/// Includes structured entitlements with backwards-compatible is_premium field
struct UserStatusResponse: Codable {
    let user_id: String
    let email: String
    let entitlements: UserEntitlements?  // New: structured entitlements
    let is_premium: Bool  // Backwards compatible
    let premium_expires_at: String?
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError
    case tokenExpired
    case unauthorized
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network error. Please check your connection."
        case .tokenExpired:
            return "Session expired. Please log in again."
        case .unauthorized:
            return "Unauthorized access"
        case .unknown(let message):
            return message
        }
    }
}


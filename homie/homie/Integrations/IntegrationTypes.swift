//
//  IntegrationTypes.swift
//  homie
//
//  Types for integration/connector configuration (OAuth, device pairing)
//

import Foundation
import SwiftUI

// MARK: - Integration Configuration

/// Configuration for an integration (OAuth-based or device-paired)
struct IntegrationConfig: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let iconName: String  // SF Symbol name
    let authType: IntegrationAuthType

    // OAuth-specific (empty for device pairing)
    let authURL: String
    let tokenURL: String
    let scopes: [String]
    let redirectPath: String

    // Display colors
    let iconBackgroundColor: String  // Hex color
    let iconForegroundColor: String  // Hex color

    init(
        id: String,
        name: String,
        description: String,
        iconName: String,
        authType: IntegrationAuthType,
        authURL: String = "",
        tokenURL: String = "",
        scopes: [String] = [],
        redirectPath: String = "",
        iconBackgroundColor: String = "#E5E5E5",
        iconForegroundColor: String = "#808080"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.authType = authType
        self.authURL = authURL
        self.tokenURL = tokenURL
        self.scopes = scopes
        self.redirectPath = redirectPath
        self.iconBackgroundColor = iconBackgroundColor
        self.iconForegroundColor = iconForegroundColor
    }

    /// Returns the MessagingProviderID for device pairing integrations
    var messagingProviderID: MessagingProviderID? {
        MessagingProviderID(rawValue: id)
    }
}

// MARK: - Connection Status

/// Connection status for an integration
enum IntegrationStatus: Equatable {
    case disconnected
    case connecting
    case pairing       // Waiting for device pairing (QR/code)
    case connected(email: String?)
    case error(String)

    var isConnected: Bool {
        guard case .connected = self else { return false }
        return true
    }

    var isPairing: Bool {
        guard case .pairing = self else { return false }
        return true
    }
}

// MARK: - Auth Type

/// Authentication type for integrations
enum IntegrationAuthType: String, Codable {
    case oauth           // Linear, Google Calendar - uses OAuth flow
    case devicePairing   // WhatsApp, Telegram, Signal - uses device pairing
}

// MARK: - OAuth Types

/// OAuth token response from token exchange
struct IntegrationOAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

/// Stored OAuth credentials for an integration
struct IntegrationStoredCredentials: Codable {
    let serverID: String  // Keep as serverID for backwards compatibility
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let userEmail: String?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - Error Types

enum IntegrationError: LocalizedError {
    case notConnected(integrationID: String)
    case authenticationFailed(String)
    case tokenExchangeFailed(String)
    case executionFailed(String)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected(let integrationID):
            return "Not connected to \(integrationID)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Predefined Integration Configurations

extension IntegrationConfig {
    static let linear = IntegrationConfig(
        id: "linear",
        name: "Linear",
        description: "Manage issues and projects",
        iconName: "square.stack.3d.up",
        authType: .oauth,
        authURL: "https://linear.app/oauth/authorize",
        tokenURL: "https://api.linear.app/oauth/token",
        scopes: ["read", "write"],
        redirectPath: "oauth/linear",
        iconBackgroundColor: "#F3E8FF",
        iconForegroundColor: "#9333EA"
    )

    static let googleCalendar = IntegrationConfig(
        id: "google_calendar",
        name: "Google Calendar",
        description: "View and create calendar events",
        iconName: "calendar",
        authType: .oauth,
        authURL: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenURL: "https://oauth2.googleapis.com/token",
        scopes: ["https://www.googleapis.com/auth/calendar.events"],
        redirectPath: "oauth/google",
        iconBackgroundColor: "#DBEAFE",
        iconForegroundColor: "#2563EB"
    )

    static let whatsApp = IntegrationConfig(
        id: "whatsapp",
        name: "WhatsApp",
        description: "Send and receive WhatsApp messages",
        iconName: "message.fill",
        authType: .devicePairing,
        iconBackgroundColor: "#DCFCE7",
        iconForegroundColor: "#16A34A"
    )

    /// All available integrations
    static let allIntegrations: [IntegrationConfig] = [.linear, .googleCalendar, .whatsApp]
}

// MARK: - Color Helpers

extension IntegrationConfig {
    var backgroundColorValue: Color {
        Color(hex: iconBackgroundColor) ?? Color.gray.opacity(0.15)
    }

    var foregroundColorValue: Color {
        Color(hex: iconForegroundColor) ?? Color.gray
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Type Aliases for Backwards Compatibility

typealias MCPServerConfig = IntegrationConfig
typealias MCPConnectionStatus = IntegrationStatus
typealias MCPAuthType = IntegrationAuthType
typealias MCPOAuthTokenResponse = IntegrationOAuthTokenResponse
typealias MCPStoredCredentials = IntegrationStoredCredentials

extension IntegrationConfig {
    /// Backwards compatibility alias
    static var allServers: [IntegrationConfig] {
        // Only return OAuth-based integrations for MCPManager
        allIntegrations.filter { $0.authType == .oauth }
    }
}

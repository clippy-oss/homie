//
//  MCPOAuthManager.swift
//  homie
//
//  Handles OAuth2 authentication flows for MCP servers
//

import Foundation
import AuthenticationServices
import AppKit

class MCPOAuthManager: NSObject, ObservableObject {
    static let shared = MCPOAuthManager()
    
    /// The URL scheme for OAuth callbacks
    static let callbackScheme = "homie"
    
    @Published var isAuthenticating = false
    @Published var currentServer: String?
    
    private var authSession: ASWebAuthenticationSession?
    private var completionHandler: ((Result<MCPStoredCredentials, MCPError>) -> Void)?
    
    private override init() {
        super.init()
    }
    
    // MARK: - OAuth Flow
    
    /// Start OAuth flow for a server
    func authenticate(
        serverConfig: MCPServerConfig,
        completion: @escaping (Result<MCPStoredCredentials, MCPError>) -> Void
    ) {
        isAuthenticating = true
        currentServer = serverConfig.id
        completionHandler = completion

        Logger.info("🔐 MCPOAuthManager: Starting OAuth for \(serverConfig.id)", module: "MCP")

        // Build authorization URL via edge function
        Task {
            do {
                let authURL = try await buildAuthorizationURL(for: serverConfig)
                await MainActor.run {
                    self.startAuthSession(authURL: authURL, serverConfig: serverConfig, completion: completion)
                }
            } catch let error as MCPError {
                await MainActor.run {
                    self.isAuthenticating = false
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    completion(.failure(.authenticationFailed(error.localizedDescription)))
                }
            }
        }
    }

    private func startAuthSession(
        authURL: URL,
        serverConfig: MCPServerConfig,
        completion: @escaping (Result<MCPStoredCredentials, MCPError>) -> Void
    ) {
        Logger.info("🔗 Auth URL: \(authURL)", module: "MCP")
        
        // Create and start ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: Self.callbackScheme
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isAuthenticating = false
                self.currentServer = nil
            }
            
            if let error = error {
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    Logger.warning("⚠️ MCPOAuthManager: User cancelled authentication", module: "MCP")
                    completion(.failure(.authenticationFailed("User cancelled")))
                } else {
                    Logger.error("❌ MCPOAuthManager: Authentication error: \(error)", module: "MCP")
                    completion(.failure(.authenticationFailed(error.localizedDescription)))
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                completion(.failure(.authenticationFailed("No callback URL received")))
                return
            }
            
            Logger.info("✅ MCPOAuthManager: Received callback: \(callbackURL)", module: "MCP")
            
            // Check for OAuth errors first
            if let error = self.extractError(from: callbackURL) {
                let errorDescription = self.extractErrorDescription(from: callbackURL) ?? error
                Logger.error("❌ MCPOAuthManager: OAuth error: \(error) - \(errorDescription)", module: "MCP")
                
                // Provide user-friendly error messages
                let friendlyMessage: String
                if errorDescription.lowercased().contains("workspace does not have access") ||
                   errorDescription.lowercased().contains("private application") {
                    friendlyMessage = "Your Linear workspace doesn't have access to this OAuth application. Please make the OAuth app public in Linear settings (Settings → API) or grant your workspace access."
                } else {
                    friendlyMessage = "OAuth error: \(errorDescription)"
                }
                
                completion(.failure(.authenticationFailed(friendlyMessage)))
                return
            }
            
            // Extract authorization code
            guard let code = self.extractCode(from: callbackURL) else {
                completion(.failure(.authenticationFailed("Failed to extract authorization code")))
                return
            }
            
            // Exchange code for tokens
            Task {
                do {
                    let credentials = try await self.exchangeCodeForTokens(
                        code: code,
                        serverConfig: serverConfig
                    )
                    DispatchQueue.main.async {
                        completion(.success(credentials))
                    }
                } catch let error as MCPError {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(.tokenExchangeFailed(error.localizedDescription)))
                    }
                }
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        
        if !session.start() {
            isAuthenticating = false
            completion(.failure(.authenticationFailed("Failed to start authentication session")))
        }
        
        authSession = session
    }
    
    // MARK: - URL Building

    /// Stores the redirect URI used for the current OAuth flow (needed for token exchange)
    private var currentRedirectURI: String?

    private func buildAuthorizationURL(for config: MCPServerConfig) async throws -> URL {
        let urlString = "\(Config.supabaseURL)/functions/v1/oauth-get-auth-url"
        guard let url = URL(string: urlString) else {
            throw MCPError.authenticationFailed("Invalid Supabase URL")
        }

        let redirectURI = "\(Self.callbackScheme)://\(config.redirectPath)"
        let state = generateState()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "provider": config.id,
            "redirect_uri": redirectURI,
            "state": state
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.authenticationFailed("Invalid response from auth URL endpoint")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ MCPOAuthManager: Failed to get auth URL: \(errorBody)", module: "MCP")
            throw MCPError.authenticationFailed("Failed to get auth URL: HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authURLString = json["auth_url"] as? String,
              let authURL = URL(string: authURLString) else {
            throw MCPError.authenticationFailed("Invalid auth URL response")
        }

        // Store the actual redirect URI used (may differ from what we sent for providers like Google)
        // This is needed for token exchange - must match exactly what was used in the auth request
        if let serverRedirectURI = json["redirect_uri"] as? String {
            currentRedirectURI = serverRedirectURI
            Logger.info("🔗 MCPOAuthManager: Using redirect URI: \(serverRedirectURI)", module: "MCP")
        } else {
            currentRedirectURI = redirectURI
        }

        return authURL
    }
    
    // MARK: - Code Extraction
    
    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }
    
    private func extractError(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "error" })?.value
    }
    
    private func extractErrorDescription(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "error_description" })?.value
    }
    
    // MARK: - Token Exchange

    private func exchangeCodeForTokens(
        code: String,
        serverConfig: MCPServerConfig
    ) async throws -> MCPStoredCredentials {
        let urlString = "\(Config.supabaseURL)/functions/v1/oauth-exchange-token"
        guard let url = URL(string: urlString) else {
            throw MCPError.tokenExchangeFailed("Invalid Supabase URL")
        }

        // Use the redirect URI from the auth request (required to match exactly for token exchange)
        let redirectURI = currentRedirectURI ?? "\(Self.callbackScheme)://\(serverConfig.redirectPath)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "provider": serverConfig.id,
            "code": code,
            "redirect_uri": redirectURI
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.info("🔄 MCPOAuthManager: Exchanging code for tokens...", module: "MCP")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ MCPOAuthManager: Token exchange failed: \(errorBody)", module: "MCP")
            throw MCPError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let tokenResponse = try JSONDecoder().decode(MCPOAuthTokenResponse.self, from: data)

        // Calculate expiration date
        var expiresAt: Date? = nil
        if let expiresIn = tokenResponse.expiresIn {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }

        // Try to get user email (for display purposes)
        let userEmail = await fetchUserEmail(for: serverConfig.id, accessToken: tokenResponse.accessToken)

        let credentials = MCPStoredCredentials(
            serverID: serverConfig.id,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiresAt,
            userEmail: userEmail
        )

        Logger.info("✅ MCPOAuthManager: Token exchange successful", module: "MCP")
        return credentials
    }

    // MARK: - Token Refresh

    /// Refresh an access token using a refresh token
    public func refreshToken(for serverID: String, refreshToken: String) async throws -> MCPOAuthTokenResponse {
        let urlString = "\(Config.supabaseURL)/functions/v1/oauth-refresh-token"
        guard let url = URL(string: urlString) else {
            throw MCPError.tokenExchangeFailed("Invalid Supabase URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "provider": serverID,
            "refresh_token": refreshToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.info("🔄 MCPOAuthManager: Refreshing token for \(serverID)...", module: "MCP")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ MCPOAuthManager: Token refresh failed: \(errorBody)", module: "MCP")
            throw MCPError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let tokenResponse = try JSONDecoder().decode(MCPOAuthTokenResponse.self, from: data)
        Logger.info("✅ MCPOAuthManager: Token refresh successful", module: "MCP")
        return tokenResponse
    }
    
    // MARK: - User Info
    
    private func fetchUserEmail(for serverID: String, accessToken: String) async -> String? {
        switch serverID {
        case "linear":
            return await fetchLinearUserEmail(accessToken: accessToken)
        case "google_calendar":
            return await fetchGoogleUserEmail(accessToken: accessToken)
        default:
            return nil
        }
    }
    
    private func fetchLinearUserEmail(accessToken: String) async -> String? {
        guard let url = URL(string: "https://api.linear.app/graphql") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let query = ["query": "{ viewer { email } }"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: query)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let viewer = dataDict["viewer"] as? [String: Any],
               let email = viewer["email"] as? String {
                return email
            }
        } catch {
            Logger.error("⚠️ MCPOAuthManager: Failed to fetch Linear user email", module: "MCP")
        }
        return nil
    }
    
    private func fetchGoogleUserEmail(accessToken: String) async -> String? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                return email
            }
        } catch {
            Logger.error("⚠️ MCPOAuthManager: Failed to fetch Google user email", module: "MCP")
        }
        return nil
    }
    
    // MARK: - Helpers

    private func generateState() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in letters.randomElement()! })
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension MCPOAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
    }
}



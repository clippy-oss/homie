//
//  LoginView.swift
//  homie
//
//  Login screen matching NotionHomeView styling
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private var authStore = AuthSessionStore.shared
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    var onLoginSuccess: (() -> Void)?
    var onSwitchToSignup: (() -> Void)?
    var prefilledEmail: String = ""
    var successMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Login Form
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Welcome back")
                        .font(.system(size: 32, weight: .semibold))
                    
                    Text("Sign in to your account")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
                .onAppear {
                    if !prefilledEmail.isEmpty {
                        email = prefilledEmail
                    }
                }
                
                // Email Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .disabled(isLoading)
                }
                
                // Password Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .disabled(isLoading)
                }
                
                // Error Message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                
                // Sign In Button
                Button(action: handleSignIn) {
                    HStack {
                        Text(isLoading ? "Signing in..." : "Sign In")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .background(canSignIn ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canSignIn || isLoading)
                .keyboardShortcut(.return, modifiers: [])
                
                // Don't have an account link
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Button(action: {
                        onSwitchToSignup?()
                    }) {
                        Text("Sign up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
            }
            .frame(width: 380)
            .padding(40)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private var canSignIn: Bool {
        !email.isEmpty && !password.isEmpty && !isLoading
    }
    
    private func handleSignIn() {
        guard canSignIn else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                Logger.info("🔑 LoginView: Attempting sign in with email: \(email)", module: "Auth")
                try await AuthenticationManager.shared.signIn(email: email, password: password)
                
                await MainActor.run {
                    isLoading = false
                    Logger.info("✅ LoginView: Sign in successful", module: "Auth")
                    // Notify success
                    onLoginSuccess?()
                }
            } catch let error as AuthError {
                Logger.error("❌ LoginView: AuthError - \(error.localizedDescription)", module: "Auth")
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.errorDescription
                }
            } catch {
                Logger.error("❌ LoginView: Unexpected error - \(error)", module: "Auth")
                Logger.error("❌ LoginView: Error type - \(type(of: error))", module: "Auth")
                await MainActor.run {
                    isLoading = false
                    errorMessage = "An unexpected error occurred. Please try again.\n\(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .frame(width: 700, height: 600)
}


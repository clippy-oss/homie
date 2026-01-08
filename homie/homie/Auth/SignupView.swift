//
//  SignupView.swift
//  homie
//
//  Signup/Onboarding screen
//

import SwiftUI
import Supabase

struct SignupView: View {
    @ObservedObject private var authStore = AuthSessionStore.shared
    @State private var email: String = ""
    @State private var fullName: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showNameAndPassword: Bool = false
    
    var onSignupSuccess: (() -> Void)?
    var onSwitchToLogin: ((String?, String?) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Signup Form
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Get started with Homie")
                        .font(.system(size: 32, weight: .semibold))
                    
                    Text("Your voice is your new keyboard")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
                
                if !showNameAndPassword {
                    // Step 1: Email Only
                    emailStep
                } else {
                    // Step 2: Name + Password
                    nameAndPasswordStep
                }
            }
            .frame(width: 380)
            .padding(40)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
            
            // Back button (only on name/password step)
            if showNameAndPassword {
                Button(action: {
                    showNameAndPassword = false
                    errorMessage = nil
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                        Text("Back")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 20)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Email Step
    
    private var emailStep: some View {
        VStack(spacing: 16) {
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
            
            // Continue Button
            Button(action: handleEmailContinue) {
                HStack {
                    Text("Continue with Email")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(canContinueEmail ? Color.accentColor : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!canContinueEmail)
            .keyboardShortcut(.return, modifiers: [])
            
            // Already have account link
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Button(action: {
                    onSwitchToLogin?(nil, nil)
                }) {
                    Text("Log in")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - Name and Password Step
    
    private var nameAndPasswordStep: some View {
        VStack(spacing: 16) {
            // Email (pre-filled, read-only)
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            
            // Full Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Name")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                TextField("Enter your full name", text: $fullName)
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
                
                SecureField("Create a password", text: $password)
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
                
                Text("At least 8 characters")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
            
            // Create Account Button
            Button(action: handleCreateAccount) {
                HStack {
                    Text("Create Account")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(canCreateAccount ? Color.accentColor : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!canCreateAccount || isLoading)
            .keyboardShortcut(.return, modifiers: [])
        }
    }
    
    // MARK: - Helpers
    
    private var canContinueEmail: Bool {
        !email.isEmpty && email.contains("@") && !isLoading
    }
    
    private var canCreateAccount: Bool {
        !fullName.isEmpty && password.count >= 8 && !isLoading
    }
    
    private func handleEmailContinue() {
        guard canContinueEmail else { return }
        errorMessage = nil
        isLoading = true
        
        // Check if email already exists before moving to next step
        Task {
            do {
                Logger.debug("🔍 SignupView: Checking if email exists: \(email)", module: "Auth")
                let emailExists = try await AuthenticationManager.shared.checkEmailExists(email: email)
                
                await MainActor.run {
                    isLoading = false
                    
                    if emailExists {
                        // Email exists - redirect to login
                        Logger.info("👤 SignupView: Email already exists - redirecting to login", module: "Auth")
                        onSwitchToLogin?("An account with this email already exists. Please log in.", email)
                    } else {
                        // Email doesn't exist - proceed to name and password step
                        Logger.info("✅ SignupView: Email available - proceeding to signup", module: "Auth")
                        withAnimation {
                            showNameAndPassword = true
                        }
                    }
                }
            } catch {
                Logger.error("❌ SignupView: Error checking email: \(error)", module: "Auth")
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Unable to verify email. Please try again."
                }
            }
        }
    }
    
    private func handleCreateAccount() {
        guard canCreateAccount else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                Logger.info("📝 SignupView: Creating account for email: \(email)", module: "Auth")

                // Use Supabase SDK for signup
                let response = try await supabase.auth.signUp(
                    email: email,
                    password: password,
                    data: ["full_name": .string(fullName)]
                )

                // Check if user already existed (empty identities means existing user)
                if response.user.identities?.isEmpty == true {
                    Logger.info("👤 SignupView: User already exists (empty identities) - redirecting to login", module: "Auth")
                    await MainActor.run {
                        isLoading = false
                        onSwitchToLogin?("An account with this email already exists. Please log in.", email)
                    }
                    return
                }

                // Check if we have a session (email confirmation disabled) or need to confirm email
                if response.session != nil {
                    // Has session - email confirmation is disabled, user is signed in
                    // AuthSessionStore will be notified via authStateChanges
                    Logger.info("✅ SignupView: Account created and signed in successfully", module: "Auth")
                    await MainActor.run {
                        isLoading = false
                        onSignupSuccess?()
                    }
                } else {
                    // No session - email confirmation is required
                    Logger.info("📧 SignupView: Email confirmation required - redirecting to login", module: "Auth")
                    await MainActor.run {
                        isLoading = false
                        onSwitchToLogin?("Account created! Please check your email at \(email) to verify your account, then log in.", email)
                    }
                }
            } catch let error as AuthError {
                Logger.error("❌ SignupView: AuthError - \(error.localizedDescription)", module: "Auth")
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.errorDescription
                }
            } catch {
                Logger.error("❌ SignupView: Unexpected error - \(error)", module: "Auth")

                // Check if error indicates existing user
                let errorString = String(describing: error).lowercased()
                if errorString.contains("already") ||
                   errorString.contains("exists") ||
                   errorString.contains("registered") {
                    await MainActor.run {
                        isLoading = false
                        Logger.info("👤 SignupView: Email already exists - redirecting to login", module: "Auth")
                        onSwitchToLogin?("An account with this email already exists. Please log in.", email)
                    }
                    return
                }

                await MainActor.run {
                    isLoading = false
                    errorMessage = "An unexpected error occurred. Please try again.\n\(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    SignupView()
        .frame(width: 700, height: 600)
}


//
//  AuthCoordinatorView.swift
//  homie
//
//  Coordinator to manage switching between signup and login views
//

import SwiftUI

struct AuthCoordinatorView: View {
    @State private var showSignup: Bool
    @State private var showPermissions: Bool = false
    @State private var verificationMessage: String?
    @State private var prefilledEmail: String = ""
    var onAuthSuccess: (() -> Void)?
    
    init(showSignup: Bool = true, onAuthSuccess: (() -> Void)? = nil) {
        self._showSignup = State(initialValue: showSignup)
        self.onAuthSuccess = onAuthSuccess
    }
    
    var body: some View {
        Group {
            if showPermissions {
                // Show permissions screen after successful auth
                PermissionsView(
                    onPermissionsComplete: {
                        onAuthSuccess?()
                    }
                )
            } else if showSignup {
                SignupView(
                    onSignupSuccess: {
                        // Check if permissions are already granted
                        handleAuthSuccess()
                    },
                    onSwitchToLogin: { message, email in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            verificationMessage = message
                            prefilledEmail = email ?? ""
                            showSignup = false
                        }
                    }
                )
            } else {
                LoginView(
                    onLoginSuccess: {
                        // Check if permissions are already granted
                        handleAuthSuccess()
                    },
                    onSwitchToSignup: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            verificationMessage = nil
                            prefilledEmail = ""
                            showSignup = true
                        }
                    },
                    prefilledEmail: prefilledEmail,
                    successMessage: verificationMessage
                )
            }
        }
    }
    
    // MARK: - Permission Checking
    
    private func handleAuthSuccess() {
        // Check if both permissions are already granted
        if areAllPermissionsGranted() {
            // Skip permissions screen and go directly to main app
            onAuthSuccess?()
        } else {
            // Show permissions screen
            withAnimation(.easeInOut(duration: 0.2)) {
                showPermissions = true
            }
        }
    }
    
    private func areAllPermissionsGranted() -> Bool {
        return PermissionStore.shared.areRequiredPermissionsGranted
    }
}

#Preview {
    AuthCoordinatorView()
        .frame(width: 700, height: 650)
}


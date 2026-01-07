//
//  HelloWorldView.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import SwiftUI

enum NavigationView {
    case welcome
    case personalize
    case keyboardShortcuts
}

struct HelloWorldView: View {
    @State private var currentView: NavigationView = .welcome
    
    var body: some View {
        Group {
            switch currentView {
            case .welcome:
                WelcomeContentView(currentView: $currentView)
            case .personalize:
                PersonalizeViewWithBack(currentView: $currentView)
            case .keyboardShortcuts:
                KeyboardShortcutsViewWithBack(currentView: $currentView)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct WelcomeContentView: View {
    @Binding var currentView: NavigationView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Clippy")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Use Clippy to dictate, generate, or modify text.\nYou can activate and stop each function with the same shortcut.\nYour output will be pasted in whichever text box you have your cursor in. If no text box is selected, your output will be copied to your clipboard.\n\nUse \"shift + control + o\" to dictate.\nHit \"shift + control + i\" to talk and generate text.\nHit \"shift + control + k\" to type and generate text.\n\nFor text generation you can highlight text before calling the shortcut and it will be taken as context for your prompt.\n\nAll transcription and AI text generation runs locally on your mac. You can use it without internet. You need to activate Apple Intelligence in the settings before using Clippy.")
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            HStack {
                Button("Personalize") {
                    currentView = .personalize
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Keyboard Shortcuts") {
                    currentView = .keyboardShortcuts
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}

struct PersonalizeViewWithBack: View {
    @Binding var currentView: NavigationView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Back button
            HStack {
                Button("← Back") {
                    currentView = .welcome
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            
            // Personalize content
            PersonalizeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }
}

struct KeyboardShortcutsViewWithBack: View {
    @Binding var currentView: NavigationView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Back button
            HStack {
                Button("← Back") {
                    currentView = .welcome
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            
            // Keyboard shortcuts content
            KeyboardShortcutsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }
}

#Preview {
    HelloWorldView()
}

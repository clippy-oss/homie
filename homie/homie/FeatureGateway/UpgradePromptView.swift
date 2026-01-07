//
//  UpgradePromptView.swift
//  homie
//
//  Premium upsell view shown when a user tries to access a premium feature
//

import SwiftUI

struct UpgradePromptView: View {
    let feature: Feature
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Star Icon
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.yellow)

            // Title
            Text("Premium Required")
                .font(.system(size: 24, weight: .semibold))

            // Contextual upgrade message
            Text(feature.upgradeMessage)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                // Primary - Upgrade Button
                Button(action: onUpgrade) {
                    Text("Upgrade to Premium")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Secondary - Dismiss Button
                Button(action: onDismiss) {
                    Text("Maybe Later")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

#Preview {
    UpgradePromptView(
        feature: .openAILLM,
        onUpgrade: { Logger.info("Upgrade tapped", module: "Feature") },
        onDismiss: { Logger.info("Dismiss tapped", module: "Feature") }
    )
}

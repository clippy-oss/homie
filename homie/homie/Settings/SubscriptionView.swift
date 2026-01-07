//
//  SubscriptionView.swift
//  homie
//
//  Subscription status and management view
//

import SwiftUI
import AppKit

struct SubscriptionView: View {
    @ObservedObject private var entitlementStore = FeatureEntitlementStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription")
                .font(.headline)

            // Current tier display
            HStack {
                Text("Current Plan")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entitlementStore.currentTier == .premium ? "Premium" : "Free")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(entitlementStore.currentTier == .premium ? .orange : .secondary)
            }

            Divider()

            // Features list
            VStack(alignment: .leading, spacing: 6) {
                Text("Features")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                ForEach(Feature.allCases, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: entitlementStore.isFeatureAvailable(feature) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(entitlementStore.isFeatureAvailable(feature) ? .green : .gray)
                            .font(.system(size: 12))
                        Text(feature.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(entitlementStore.isFeatureAvailable(feature) ? .primary : .secondary)
                    }
                }
            }

            // Manage subscription button
            Button(action: {
                if let urlString = Bundle.main.infoDictionary?["SUBSCRIPTION_URL"] as? String,
                   let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                    Text("Manage Subscription")
                        .font(.system(size: 14))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(8)
    }
}

#Preview {
    SubscriptionView()
        .frame(width: 400)
        .padding()
}

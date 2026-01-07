//
//  FeatureEntitlementStore.swift
//  homie
//
//  Centralized store for feature entitlement decisions
//  Observes subscription status and provides feature availability checks
//

import Foundation
import Combine

// MARK: - Feature EnumThis is the test, 123.

/// All gated features in the application
enum Feature: String, CaseIterable, Codable {
    case openAILLM = "openai_llm"
    case whisperAPI = "whisper_api"
    case personalize = "personalize"
    case mcpIntegrations = "mcp_integrations"
    case mcpToolCalling = "mcp_tool_calling"
    case localLLM = "local_llm"

    var displayName: String {
        switch self {
        case .openAILLM: return "OpenAI GPT-4o"
        case .whisperAPI: return "Cloud Transcription"
        case .personalize: return "Personalization"
        case .mcpIntegrations: return "Integrations"
        case .mcpToolCalling: return "Tool Calling"
        case .localLLM: return "Local AI"
        }
    }

    var upgradeMessage: String {
        switch self {
        case .openAILLM:
            return "Upgrade to Premium for GPT-4o powered responses"
        case .whisperAPI:
            return "Upgrade to Premium for cloud-based transcription"
        case .personalize:
            return "Upgrade to Premium to personalize your assistant"
        case .mcpIntegrations:
            return "Upgrade to Premium to connect Linear, Google Calendar, and more"
        case .mcpToolCalling:
            return "Upgrade to Premium for AI tool integrations"
        case .localLLM:
            return "Local AI is available on all tiers"
        }
    }
}

// MARK: - Subscription Tier

/// Subscription tiers - designed for future expansion
enum SubscriptionTier: Int, CaseIterable, Comparable, Codable {
    case free = 0
    case premium = 100
    // Future tiers: case pro = 200, case enterprise = 300

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Tier Configuration

/// Centralized configuration mapping tiers to features
/// Edit this struct to change which features belong to which tier
struct TierConfiguration {
    /// Features available at each tier (cumulative - higher tiers include lower tier features)
    static let featuresByTier: [SubscriptionTier: Set<Feature>] = [
        .free: [.localLLM],
        .premium: Set(Feature.allCases)
        // Future: .pro: [.openAILLM, .whisperAPI], .enterprise: Set(Feature.allCases)
    ]

    /// Get all features available at a given tier (including lower tiers)
    static func features(for tier: SubscriptionTier) -> Set<Feature> {
        var features = Set<Feature>()
        for t in SubscriptionTier.allCases where t <= tier {
            features.formUnion(featuresByTier[t] ?? [])
        }
        return features
    }

    /// Get minimum tier required for a feature
    static func minimumTier(for feature: Feature) -> SubscriptionTier {
        for tier in SubscriptionTier.allCases.sorted(by: { $0 < $1 }) {
            if featuresByTier[tier]?.contains(feature) == true {
                return tier
            }
        }
        return .premium
    }
}

// MARK: - FeatureEntitlementStore

/// Centralized store that manages feature entitlements based on subscription tier.
/// Observes AuthSessionStore for premium status changes and publishes feature availability.
@MainActor
final class FeatureEntitlementStore: ObservableObject {

    // MARK: - Singleton

    static let shared = FeatureEntitlementStore()

    // MARK: - Published Properties

    /// Current subscription tier based on authentication state
    @Published private(set) var currentTier: SubscriptionTier = .free

    /// Set of currently available features (derived from tier)
    @Published private(set) var availableFeatures: Set<Feature> = []

    // MARK: - Convenience Properties

    /// Whether OpenAI LLM can be used
    var canUseOpenAI: Bool { availableFeatures.contains(.openAILLM) }

    /// Whether Whisper API can be used for transcription
    var canUseWhisperAPI: Bool { availableFeatures.contains(.whisperAPI) }

    /// Whether personalization settings are accessible
    var canUsePersonalize: Bool { availableFeatures.contains(.personalize) }

    /// Whether MCP integrations are accessible
    var canUseMCPIntegrations: Bool { availableFeatures.contains(.mcpIntegrations) }

    /// Whether MCP tool calling is available
    var canUseMCPToolCalling: Bool { availableFeatures.contains(.mcpToolCalling) }

    /// Whether local LLM can be used
    var canUseLocalLLM: Bool { availableFeatures.contains(.localLLM) }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupSubscriptionObserver()
    }

    // MARK: - Setup

    /// Subscribe to AuthSessionStore for entitlements and premium status changes
    private func setupSubscriptionObserver() {
        // Primary: observe entitlements directly from server
        AuthSessionStore.shared.$entitlements
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entitlements in
                if let entitlements = entitlements {
                    self?.updateFromEntitlements(entitlements)
                }
            }
            .store(in: &cancellables)

        // Fallback: observe isPremium for backwards compatibility
        AuthSessionStore.shared.$isPremium
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPremium in
                // Only use if entitlements not available
                if AuthSessionStore.shared.entitlements == nil {
                    self?.updateTier(isPremium: isPremium)
                }
            }
            .store(in: &cancellables)

        // Set initial state
        if let entitlements = AuthSessionStore.shared.entitlements {
            updateFromEntitlements(entitlements)
        } else {
            updateTier(isPremium: AuthSessionStore.shared.isPremium)
        }
    }

    /// Update features from server-provided entitlements
    private func updateFromEntitlements(_ entitlements: UserEntitlements) {
        // Map tier_id to SubscriptionTier enum
        let newTier: SubscriptionTier = entitlements.tier_id == "pro" ? .premium : .free

        // Build available features from server response
        var serverFeatures = Set<Feature>()
        for feature in Feature.allCases {
            if entitlements.hasFeature(feature) {
                serverFeatures.insert(feature)
            }
        }

        // Only log if something changed
        if newTier != currentTier || serverFeatures != availableFeatures {
            currentTier = newTier
            availableFeatures = serverFeatures

            Logger.info("🎫 FeatureEntitlementStore: Updated from server entitlements", module: "Auth")
            Logger.info("   Tier: \(newTier), Features: \(availableFeatures.map(\.rawValue).joined(separator: ", "))", module: "Auth")
        }
    }

    /// Update the current tier based on premium status
    private func updateTier(isPremium: Bool) {
        let newTier: SubscriptionTier = isPremium ? .premium : .free

        guard newTier != currentTier else { return }

        currentTier = newTier
        availableFeatures = TierConfiguration.features(for: currentTier)

        Logger.info("🎫 FeatureEntitlementStore: Tier updated to \(newTier)", module: "Auth")
        Logger.info("   Available features: \(availableFeatures.map(\.rawValue).joined(separator: ", "))", module: "Auth")
    }

    // MARK: - Feature Checks

    /// Check if a specific feature is available for the current user
    /// - Parameter feature: The feature to check
    /// - Returns: True if the feature is available at the current tier
    func isFeatureAvailable(_ feature: Feature) -> Bool {
        availableFeatures.contains(feature)
    }

    /// Get all features that would be unlocked by upgrading to a specific tier
    /// - Parameter tier: The target tier to compare against
    /// - Returns: Set of features that would be gained
    func featuresUnlockedBy(tier: SubscriptionTier) -> Set<Feature> {
        guard tier > currentTier else { return [] }
        return TierConfiguration.features(for: tier).subtracting(availableFeatures)
    }

    /// Get the minimum tier required for a specific feature
    /// - Parameter feature: The feature to check
    /// - Returns: The minimum subscription tier needed
    func minimumTierRequired(for feature: Feature) -> SubscriptionTier {
        TierConfiguration.minimumTier(for: feature)
    }
}

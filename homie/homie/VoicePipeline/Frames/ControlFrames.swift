//
//  ControlFrames.swift
//  homie
//
//  Voice Processing Pipeline - Control Frames
//  Low-priority frames for signaling and state changes
//

import Foundation

// MARK: - InterruptionFrame

/// Signals that the user has interrupted the current output
/// Typically flows upstream to cancel current processing
public struct InterruptionFrame: ControlFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "InterruptionFrame"

    /// Reason for the interruption (optional)
    public let reason: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.reason = reason
    }
}

// MARK: - VAD State

/// Voice Activity Detection state
public enum VADState: String, Sendable {
    /// No speech detected
    case quiet

    /// Speech may be starting (transition state)
    case starting

    /// User is actively speaking
    case speaking

    /// Speech may be ending (transition state)
    case stopping
}

// MARK: - VADStateFrame

/// Carries VAD state changes through the pipeline
public struct VADStateFrame: ControlFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "VADStateFrame"

    /// Current VAD state
    public let state: VADState

    /// Confidence level of the detection (0.0 - 1.0)
    public let confidence: Float?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        state: VADState,
        confidence: Float? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.confidence = confidence
    }
}

// MARK: - UserTurnStartFrame

/// Signals that the user has started their turn
/// Emitted when VAD detects the user beginning to speak
public struct UserTurnStartFrame: ControlFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "UserTurnStartFrame"

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
    }
}

// MARK: - UserTurnEndFrame

/// Signals that the user has finished their turn
/// Emitted when VAD detects the user has stopped speaking
public struct UserTurnEndFrame: ControlFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "UserTurnEndFrame"

    /// Accumulated transcribed text from the user's turn (optional)
    public let aggregatedText: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        aggregatedText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.aggregatedText = aggregatedText
    }
}

// MARK: - BotTurnStartFrame

/// Signals that the bot is starting to respond
/// Emitted when the bot begins generating output
public struct BotTurnStartFrame: ControlFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "BotTurnStartFrame"

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
    }
}

// MARK: - BotTurnEndFrame

/// Signals that the bot has finished responding
/// Emitted when the bot has completed its output
public struct BotTurnEndFrame: ControlFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "BotTurnEndFrame"

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
    }
}

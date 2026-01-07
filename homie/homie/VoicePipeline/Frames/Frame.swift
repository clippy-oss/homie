//
//  Frame.swift
//  homie
//
//  Voice Processing Pipeline - Base Frame Protocols
//  Inspired by Pipecat's frame system
//

import Foundation

// MARK: - Frame Priority

/// Priority levels for frame processing
/// SystemFrames are processed first to ensure timely handling of lifecycle events
public enum FramePriority: Int, Comparable, Sendable {
    case high = 0      // SystemFrames
    case normal = 1    // DataFrames
    case low = 2       // ControlFrames

    public static func < (lhs: FramePriority, rhs: FramePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Base Frame Protocol

/// Base protocol for all frames in the voice pipeline
/// Frames are the fundamental units of data and control that flow through processors
public protocol Frame: Identifiable, Sendable {
    /// Unique identifier for this frame
    var id: UUID { get }

    /// Timestamp when the frame was created
    var timestamp: Date { get }

    /// Priority level for processing order
    var priority: FramePriority { get }

    /// Human-readable name for debugging
    var name: String { get }
}

// MARK: - Frame Category Protocols

/// System frames have the highest priority and are not affected by interruptions
/// Used for lifecycle events (start, end, cancel, error)
public protocol SystemFrame: Frame {}

extension SystemFrame {
    public var priority: FramePriority { .high }
}

/// Data frames carry actual content (audio, text, images)
/// Can be cancelled by user interruptions
public protocol DataFrame: Frame {}

extension DataFrame {
    public var priority: FramePriority { .normal }
}

/// Control frames carry signals and state changes
/// Can be cancelled by user interruptions
public protocol ControlFrame: Frame {}

extension ControlFrame {
    public var priority: FramePriority { .low }
}

// MARK: - Frame Direction

/// Direction of frame flow through the pipeline
public enum FrameDirection: Sendable {
    /// Input to output (microphone → speaker)
    case downstream

    /// Output to input (for interruptions, errors, feedback)
    case upstream
}

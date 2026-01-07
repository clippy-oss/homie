//
//  SystemFrames.swift
//  homie
//
//  Voice Processing Pipeline - System Frames
//  High-priority frames for pipeline lifecycle management
//

import Foundation

// MARK: - StartFrame

/// Signals the pipeline to start processing
/// Sent at the beginning of a pipeline run
public struct StartFrame: SystemFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "StartFrame"

    /// Whether to allow interruptions during this session
    public let allowInterruptions: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        allowInterruptions: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.allowInterruptions = allowInterruptions
    }
}

// MARK: - EndFrame

/// Signals graceful shutdown of the pipeline
/// Processors should finish current work and clean up
public struct EndFrame: SystemFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "EndFrame"

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
    }
}

// MARK: - CancelFrame

/// Signals immediate cancellation of the pipeline
/// Processors should abort current work without completing
public struct CancelFrame: SystemFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "CancelFrame"

    /// Reason for cancellation (optional)
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

// MARK: - ErrorFrame

/// Carries error information through the pipeline
/// Typically flows upstream to notify previous processors
public struct ErrorFrame: SystemFrame {
    public let id: UUID
    public let timestamp: Date
    public let name: String = "ErrorFrame"

    /// The error that occurred
    public let error: Error

    /// ID of the processor that generated the error
    public let sourceProcessorId: String

    /// Whether the error is fatal (should stop the pipeline)
    public let isFatal: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        error: Error,
        sourceProcessorId: String,
        isFatal: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.error = error
        self.sourceProcessorId = sourceProcessorId
        self.isFatal = isFatal
    }
}

// Make ErrorFrame Sendable by wrapping the error
extension ErrorFrame: @unchecked Sendable {}

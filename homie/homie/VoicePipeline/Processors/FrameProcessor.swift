//
//  FrameProcessor.swift
//  homie
//
//  Voice Processing Pipeline - Base Frame Processor Protocol and Implementations
//  Inspired by Pipecat's processor system
//

import Foundation

// MARK: - FrameProcessor Protocol

/// Protocol for processors in the voice pipeline
/// Processors receive frames, process them, and pass results to the next processor
public protocol FrameProcessor: AnyObject, Sendable {
    /// Unique identifier for this processor
    var id: String { get }

    /// Human-readable name for debugging
    var name: String { get }

    /// Reference to the next processor in the chain (downstream)
    var next: (any FrameProcessor)? { get set }

    /// Reference to the previous processor in the chain (upstream)
    var previous: (any FrameProcessor)? { get set }

    /// Processes an incoming frame
    /// - Parameters:
    ///   - frame: The frame to process
    ///   - direction: The direction of frame flow
    func process(frame: any Frame, direction: FrameDirection) async throws

    /// Pushes a frame to the next processor in the specified direction
    /// - Parameters:
    ///   - frame: The frame to push
    ///   - direction: The direction to push (downstream to next, upstream to previous)
    func push(frame: any Frame, direction: FrameDirection) async throws
}

// MARK: - Default Implementation

extension FrameProcessor {
    /// Default implementation pushes frame to appropriate neighbor
    public func push(frame: any Frame, direction: FrameDirection) async throws {
        switch direction {
        case .downstream:
            try await next?.process(frame: frame, direction: direction)
        case .upstream:
            try await previous?.process(frame: frame, direction: direction)
        }
    }
}

// MARK: - Base Frame Processor

/// Base implementation of FrameProcessor that provides common functionality.
/// Subclasses should override process() to implement custom behavior.
/// Uses a serial dispatch queue internally for thread-safety.
open class BaseFrameProcessor: FrameProcessor, @unchecked Sendable {

    // MARK: - Properties

    public let id: String
    open var name: String { "BaseFrameProcessor" }

    public var next: (any FrameProcessor)?
    public var previous: (any FrameProcessor)?

    private var _isRunning: Bool = false
    private let lock = NSLock()

    // MARK: - Initialization

    public init(id: String? = nil) {
        self.id = id ?? UUID().uuidString
    }

    // MARK: - Thread-safe property access

    public var isRunning: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isRunning
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isRunning = newValue
        }
    }

    // MARK: - FrameProcessor Protocol

    /// Default implementation that simply forwards frames.
    /// Subclasses should override to add custom processing logic.
    open func process(frame: any Frame, direction: FrameDirection) async throws {
        // Default: just forward the frame
        try await push(frame: frame, direction: direction)
    }

    /// Push a frame to the next or previous processor based on direction.
    open func push(frame: any Frame, direction: FrameDirection) async throws {
        switch direction {
        case .downstream:
            if let nextProcessor = next {
                try await nextProcessor.process(frame: frame, direction: direction)
            }
        case .upstream:
            if let previousProcessor = previous {
                try await previousProcessor.process(frame: frame, direction: direction)
            }
        }
    }

    // MARK: - Helper Methods

    /// Process a frame and then forward it downstream.
    /// Useful helper for processors that transform frames.
    public func processAndForward(
        frame: any Frame,
        direction: FrameDirection = .downstream,
        transform: ((any Frame) -> any Frame)? = nil
    ) async throws {
        let outputFrame = transform?(frame) ?? frame
        try await push(frame: outputFrame, direction: direction)
    }
}

// MARK: - FrameProcessor Extension for Linking

extension FrameProcessor {
    /// Helper method to set the previous processor reference
    public func setPrevious(_ processor: any FrameProcessor) {
        self.previous = processor
    }

    /// Helper method to set the next processor reference
    public func setNext(_ processor: any FrameProcessor) {
        self.next = processor
    }

    /// Chain multiple processors together.
    /// Returns the last processor in the chain.
    @discardableResult
    public func chain(_ processors: any FrameProcessor...) -> any FrameProcessor {
        var current: any FrameProcessor = self

        for processor in processors {
            current.setNext(processor)
            processor.setPrevious(current)
            current = processor
        }

        return current
    }
}

// MARK: - Passthrough Processor

/// A simple processor that passes all frames through unchanged.
/// Useful for debugging, logging, or as a placeholder in the pipeline.
public final class PassthroughProcessor: BaseFrameProcessor {

    // MARK: - Properties

    private let logFrames: Bool
    private let label: String

    public override var name: String { label }

    // MARK: - Initialization

    /// Create a passthrough processor
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if nil)
    ///   - label: Label for logging purposes
    ///   - logFrames: Whether to log frames passing through (for debugging)
    public init(id: String? = nil, label: String = "Passthrough", logFrames: Bool = false) {
        self.label = label
        self.logFrames = logFrames
        super.init(id: id)
    }

    // MARK: - FrameProcessor Protocol

    public override func process(frame: any Frame, direction: FrameDirection) async throws {
        if logFrames {
            let directionSymbol = direction == .downstream ? ">>>" : "<<<"
            Logger.info("[\(label)] \(directionSymbol) \(frame.name) (id: \(frame.id))", module: "Pipeline")
        }

        // Pass through unchanged
        try await push(frame: frame, direction: direction)
    }
}

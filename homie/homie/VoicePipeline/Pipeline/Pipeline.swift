//
//  Pipeline.swift
//  homie
//
//  Voice Processing Pipeline - Core Pipeline Implementation
//  Manages the flow of frames through a chain of processors
//

import Foundation

// MARK: - Pipeline Protocol

/// Protocol defining a voice processing pipeline
public protocol Pipeline: Sendable {
    /// The processors in this pipeline, in order
    var processors: [any FrameProcessor] { get }

    /// Starts the pipeline
    /// Sends a StartFrame through all processors
    func run() async throws

    /// Stops the pipeline gracefully
    /// Sends an EndFrame through all processors
    func stop() async throws

    /// Pushes a frame into the pipeline
    /// The frame is sent to the first processor
    /// - Parameter frame: The frame to push
    func push(frame: any Frame) async throws
}

// MARK: - VoicePipeline

/// Main voice processing pipeline implementation
/// Links processors together and manages frame flow
public actor VoicePipeline: Pipeline {

    // MARK: - Properties

    /// The processors in this pipeline
    public nonisolated let processors: [any FrameProcessor]

    /// Whether the pipeline is currently running
    private var isRunning: Bool = false

    // MARK: - Initialization

    /// Creates a new voice pipeline with the given processors
    /// Automatically links processors together (sets next/previous references)
    /// - Parameter processors: The processors to chain together
    public init(processors: [any FrameProcessor]) {
        self.processors = processors
        linkProcessors()
    }

    // MARK: - Private Methods

    /// Links processors together by setting next/previous references
    private func linkProcessors() {
        guard processors.count > 1 else { return }

        for i in 0..<(processors.count - 1) {
            processors[i].next = processors[i + 1]
            processors[i + 1].previous = processors[i]
        }
    }

    // MARK: - Pipeline Protocol

    /// Starts the pipeline by sending a StartFrame to the first processor
    public func run() async throws {
        guard !isRunning else { return }
        guard let firstProcessor = processors.first else { return }

        isRunning = true

        let startFrame = StartFrame()
        try await firstProcessor.process(frame: startFrame, direction: .downstream)
    }

    /// Stops the pipeline by sending an EndFrame to the first processor
    public func stop() async throws {
        guard isRunning else { return }
        guard let firstProcessor = processors.first else { return }

        let endFrame = EndFrame()
        try await firstProcessor.process(frame: endFrame, direction: .downstream)

        isRunning = false
    }

    /// Pushes a frame to the first processor in the pipeline
    /// - Parameter frame: The frame to push
    public func push(frame: any Frame) async throws {
        guard isRunning else { return }
        guard let firstProcessor = processors.first else { return }

        try await firstProcessor.process(frame: frame, direction: .downstream)
    }

    // MARK: - State Queries

    /// Whether the pipeline is currently running
    public var running: Bool {
        isRunning
    }
}

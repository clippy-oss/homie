//
//  PipelineBuilder.swift
//  homie
//
//  Voice Processing Pipeline - Fluent Builder Pattern
//  Provides a clean API for constructing voice pipelines
//

import Foundation

// MARK: - PipelineBuilder

/// Fluent builder for constructing VoicePipeline instances
///
/// Example usage:
/// ```swift
/// let pipeline = PipelineBuilder()
///     .add(inputTransport)
///     .add(vadProcessor)
///     .add(sttProcessor)
///     .build()
/// ```
public final class PipelineBuilder: @unchecked Sendable {

    // MARK: - Properties

    /// Accumulated processors in order
    private var processors: [any FrameProcessor] = []

    // MARK: - Initialization

    /// Creates a new pipeline builder
    public init() {}

    // MARK: - Builder Methods

    /// Adds a processor to the pipeline
    /// Processors are added in order and will be linked accordingly
    /// - Parameter processor: The processor to add
    /// - Returns: Self for method chaining
    @discardableResult
    public func add(_ processor: any FrameProcessor) -> Self {
        processors.append(processor)
        return self
    }

    /// Adds multiple processors to the pipeline
    /// - Parameter processors: The processors to add in order
    /// - Returns: Self for method chaining
    @discardableResult
    public func add(_ processors: [any FrameProcessor]) -> Self {
        self.processors.append(contentsOf: processors)
        return self
    }

    /// Adds multiple processors to the pipeline (variadic)
    /// - Parameter processors: The processors to add in order
    /// - Returns: Self for method chaining
    @discardableResult
    public func add(_ processors: any FrameProcessor...) -> Self {
        self.processors.append(contentsOf: processors)
        return self
    }

    /// Builds the VoicePipeline with all added processors
    /// - Returns: A configured VoicePipeline
    public func build() -> VoicePipeline {
        VoicePipeline(processors: processors)
    }

    /// Resets the builder, clearing all processors
    /// - Returns: Self for method chaining
    @discardableResult
    public func reset() -> Self {
        processors.removeAll()
        return self
    }

    // MARK: - Inspection

    /// The current number of processors added
    public var processorCount: Int {
        processors.count
    }

    /// Whether the builder has any processors
    public var hasProcessors: Bool {
        !processors.isEmpty
    }
}

// MARK: - Convenience Extensions

extension PipelineBuilder {

    /// Creates a pipeline builder with initial processors
    /// - Parameter processors: The initial processors
    /// - Returns: A configured builder
    public static func with(_ processors: any FrameProcessor...) -> PipelineBuilder {
        let builder = PipelineBuilder()
        builder.processors.append(contentsOf: processors)
        return builder
    }

    /// Creates a pipeline builder with an array of processors
    /// - Parameter processors: The initial processors
    /// - Returns: A configured builder
    public static func with(_ processors: [any FrameProcessor]) -> PipelineBuilder {
        let builder = PipelineBuilder()
        builder.processors.append(contentsOf: processors)
        return builder
    }
}

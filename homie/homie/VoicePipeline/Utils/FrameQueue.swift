//
//  FrameQueue.swift
//  homie
//
//  Voice Processing Pipeline - Priority Frame Queue
//  Actor-based thread-safe queue that processes frames by priority
//

import Foundation

// MARK: - FrameQueue

/// A thread-safe priority queue for frames
/// Processes SystemFrames before DataFrames before ControlFrames
public actor FrameQueue {

    // MARK: - Storage

    /// Separate queues for each priority level
    private var highPriorityQueue: [any Frame] = []
    private var normalPriorityQueue: [any Frame] = []
    private var lowPriorityQueue: [any Frame] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Queue Operations

    /// Enqueues a frame into the appropriate priority queue
    /// - Parameter frame: The frame to enqueue
    public func enqueue(frame: any Frame) {
        switch frame.priority {
        case .high:
            highPriorityQueue.append(frame)
        case .normal:
            normalPriorityQueue.append(frame)
        case .low:
            lowPriorityQueue.append(frame)
        }
    }

    /// Dequeues the highest priority frame available
    /// Returns frames in priority order: high (SystemFrames), normal (DataFrames), low (ControlFrames)
    /// Within each priority level, frames are returned in FIFO order
    /// - Returns: The next frame to process, or nil if the queue is empty
    public func dequeue() -> (any Frame)? {
        // Check high priority first (SystemFrames)
        if !highPriorityQueue.isEmpty {
            return highPriorityQueue.removeFirst()
        }

        // Then normal priority (DataFrames)
        if !normalPriorityQueue.isEmpty {
            return normalPriorityQueue.removeFirst()
        }

        // Finally low priority (ControlFrames)
        if !lowPriorityQueue.isEmpty {
            return lowPriorityQueue.removeFirst()
        }

        return nil
    }

    /// Whether the queue is empty
    public var isEmpty: Bool {
        highPriorityQueue.isEmpty && normalPriorityQueue.isEmpty && lowPriorityQueue.isEmpty
    }

    /// Total number of frames in all queues
    public var count: Int {
        highPriorityQueue.count + normalPriorityQueue.count + lowPriorityQueue.count
    }

    /// Clears all frames from all priority queues
    public func clear() {
        highPriorityQueue.removeAll()
        normalPriorityQueue.removeAll()
        lowPriorityQueue.removeAll()
    }

    // MARK: - Batch Operations

    /// Enqueues multiple frames
    /// - Parameter frames: The frames to enqueue
    public func enqueue(frames: [any Frame]) {
        for frame in frames {
            enqueue(frame: frame)
        }
    }

    /// Dequeues all frames in priority order
    /// - Returns: All frames ordered by priority
    public func dequeueAll() -> [any Frame] {
        var result: [any Frame] = []
        result.append(contentsOf: highPriorityQueue)
        result.append(contentsOf: normalPriorityQueue)
        result.append(contentsOf: lowPriorityQueue)
        clear()
        return result
    }
}

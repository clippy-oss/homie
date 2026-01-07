//
//  TextAggregatorProcessor.swift
//  homie
//
//  Voice Processing Pipeline - Text Aggregator Processor Protocol
//  Defines interface for aggregating text frames
//

import Foundation

// MARK: - TextAggregatorProcessor Protocol

/// Protocol for processors that aggregate text from multiple frames
public protocol TextAggregatorProcessor: FrameProcessor {
    /// The accumulated text from processed frames
    var aggregatedText: String { get }

    /// Reset the aggregated text
    func reset()
}

//
//  LLMProcessor.swift
//  homie
//
//  Voice Processing Pipeline - LLM Processor Protocol
//  Defines interface for language model processing
//

import Foundation

// MARK: - LLMMessage

/// Represents a message in the LLM conversation context
public struct LLMMessage: Sendable, Equatable {
    /// Role of the message sender (e.g., "system", "user", "assistant")
    public let role: String

    /// Content of the message
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - LLMProcessor Protocol

/// Protocol for language model processors
public protocol LLMProcessor: FrameProcessor {
    /// Conversation context (message history)
    var context: [LLMMessage] { get set }

    /// Whether the processor is currently streaming a response
    var isStreaming: Bool { get }
}

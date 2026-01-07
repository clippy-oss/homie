//
//  STTProcessor.swift
//  homie
//
//  Voice Processing Pipeline - Speech-to-Text Processor Protocol
//  Defines interface for converting audio to text
//

import Foundation

// MARK: - STTProcessor Protocol

/// Protocol for speech-to-text processors
public protocol STTProcessor: FrameProcessor {
    /// Language code for recognition (e.g., "en-US", "vi-VN")
    var language: String { get set }

    /// Whether to emit interim (partial) results during recognition
    var interimResults: Bool { get set }
}

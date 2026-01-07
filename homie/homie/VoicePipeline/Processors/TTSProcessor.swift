//
//  TTSProcessor.swift
//  homie
//
//  Voice Processing Pipeline - Text-to-Speech Processor Protocol
//  Defines interface for converting text to audio
//

import Foundation

// MARK: - TTSProcessor Protocol

/// Protocol for text-to-speech processors
public protocol TTSProcessor: FrameProcessor {
    /// Voice identifier to use for synthesis
    var voice: String { get set }
}

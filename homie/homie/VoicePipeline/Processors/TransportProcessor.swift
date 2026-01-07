//
//  TransportProcessor.swift
//  homie
//
//  Voice Processing Pipeline - Transport Processor Protocols
//  Defines interfaces for audio input/output transport
//

import Foundation
import AVFoundation

// MARK: - TransportInputProcessor Protocol

/// Protocol for processors that capture audio input (e.g., microphone)
public protocol TransportInputProcessor: FrameProcessor {
    /// The audio format used for capturing
    var audioFormat: AVAudioFormat { get }

    /// Start capturing audio
    func startCapturing() async throws

    /// Stop capturing audio
    func stopCapturing() async throws
}

// MARK: - TransportOutputProcessor Protocol

/// Protocol for processors that output audio (e.g., speaker)
public protocol TransportOutputProcessor: FrameProcessor {
    /// The audio format used for playback
    var audioFormat: AVAudioFormat { get }

    /// Write an audio frame for playback
    /// - Parameter audioFrame: The audio frame to write
    func write(audioFrame: any Frame) async throws
}

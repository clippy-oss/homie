//
//  VADProcessor.swift
//  homie
//
//  Voice Processing Pipeline - Voice Activity Detection Processor Protocol
//  Defines interface for detecting speech vs silence
//

import Foundation
import Combine

// Note: VADState enum is defined in ControlFrames.swift

// MARK: - VADProcessor Protocol

/// Protocol for voice activity detection processors
public protocol VADProcessor: FrameProcessor {
    /// Current VAD state
    var state: VADState { get }

    /// Publisher for state changes
    var statePublisher: AnyPublisher<VADState, Never> { get }

    /// Duration of silence (in milliseconds) required to transition from speaking to stopping
    var silenceThresholdMs: Int { get set }

    /// Duration of speech (in milliseconds) required to transition from quiet to starting
    var speechThresholdMs: Int { get set }
}

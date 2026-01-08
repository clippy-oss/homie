//
//  TouchVisualizationViewModel.swift
//  homie
//
//  Created for touch visualization feature
//

import OpenMultitouchSupport
import SwiftUI

@MainActor
final class TouchVisualizationViewModel: ObservableObject {
    @Published var touchData: [OMSTouchData] = []
    @Published var isListening: Bool = false

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?

    init() {}

    func onAppear() {
        task = Task { [weak self, manager] in
            for await touchData in manager.touchDataStream {
                await MainActor.run {
                    self?.touchData = touchData
                }
            }
        }
    }

    func onDisappear() {
        task?.cancel()
        stop()
    }

    func start() {
        if manager.startListening() {
            isListening = true
        }
    }

    func stop() {
        if manager.stopListening() {
            isListening = false
            touchData = []
        }
    }
}




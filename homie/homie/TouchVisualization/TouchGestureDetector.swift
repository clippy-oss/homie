//
//  TouchGestureDetector.swift
//  homie
//
//  Detects two-finger swipe from left edge gesture
//

import OpenMultitouchSupport
import Foundation
import Combine

@MainActor
class TouchGestureDetector: ObservableObject {
    static let shared = TouchGestureDetector()
    
    @Published var isGestureDetected: Bool = false
    @Published var isCloseGestureDetected: Bool = false
    
    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?
    private var isListening: Bool = false
    
    // Gesture detection parameters
    private let leftEdgeThreshold: Float = 0.2  // Consider x < 0.2 as "left edge" (increased for easier detection)
    private let rightEdgeThreshold: Float = 0.8  // Consider x > 0.8 as "right edge" (for close gesture - not required, can start anywhere)
    private let minSwipeDistance: Float = 0.10  // Minimum distance to consider it a swipe
    private let requiredTouchCount: Int = 2     // Two fingers required
    
    // Track touch positions for gesture detection
    private var touchHistory: [Int32: [OMSPosition]] = [:]
    // Store the initial start position when touch first appears at left edge (for accurate distance calculation)
    private var initialStartPositions: [Int32: OMSPosition] = [:]
    private var gestureStartTime: Date?
    
    private init() {}
    
    func startListening() {
        guard !isListening else { return }
        isListening = true
        
        Logger.info("🎯 Starting touch gesture detection", module: "TouchGesture")
        
        task = Task { [weak self, manager] in
            guard let self = self else { return }
            
            for await touchData in manager.touchDataStream {
                await self.processTouchData(touchData)
            }
        }
        
        let started = manager.startListening()
        Logger.info("🎯 Touch manager started: \(started)", module: "TouchGesture")
    }
    
    func stopListening() {
        guard isListening else { return }
        isListening = false
        task?.cancel()
        task = nil
        manager.stopListening()
        touchHistory.removeAll()
        initialStartPositions.removeAll()
        gestureStartTime = nil
    }
    
    private func processTouchData(_ touches: [OMSTouchData]) {
        // Filter to only active touches (touching state)
        let activeTouches = touches.filter { touch in
            touch.state == .touching || touch.state == .making || touch.state == .starting
        }
        
        // Need exactly 2 touches for the gesture
        guard activeTouches.count == requiredTouchCount else {
            // Don't reset if we're building up to 2 touches - only reset if we had 2 and now have different count
            if touchHistory.count >= 2 && activeTouches.count != requiredTouchCount {
                resetGestureTracking()
            }
            return
        }
        
        // Update touch history and track initial start positions
        let isPanelVisible = SlidingPanelWindowController.shared.isVisible
        
        for touch in activeTouches {
            if touchHistory[touch.id] == nil {
                touchHistory[touch.id] = []
            }
            touchHistory[touch.id]?.append(touch.position)
            
            // Store initial position based on gesture type:
            // - For open gesture: only if at left edge
            // - For close gesture: store immediately (can start anywhere)
            if isPanelVisible {
                // Close gesture: store initial position for any touch
                if initialStartPositions[touch.id] == nil {
                    initialStartPositions[touch.id] = touch.position
                }
            } else {
                // Open gesture: only store if at left edge
                if touch.position.x < leftEdgeThreshold && initialStartPositions[touch.id] == nil {
                    initialStartPositions[touch.id] = touch.position
                }
            }
            
            // Keep only recent history (last 10 positions) - but don't trim if we're tracking a gesture
            // Only trim if we have more than 10 AND we're not actively tracking this touch for a gesture
            if let history = touchHistory[touch.id], history.count > 10 {
                // Only trim if we're not tracking this touch (no initial position stored means it's not a candidate)
                if initialStartPositions[touch.id] == nil {
                    touchHistory[touch.id] = Array(history.suffix(10))
                }
            }
        }
        
        // Check if gesture is detected
        // If panel is visible, check for close gesture (right-to-left swipe)
        // Otherwise, check for open gesture (left-to-right swipe from left edge)
        if SlidingPanelWindowController.shared.isVisible {
            checkForRightToLeftSwipe(activeTouches)
        } else {
            checkForLeftEdgeSwipe(activeTouches)
        }
    }
    
    private func checkForLeftEdgeSwipe(_ touches: [OMSTouchData]) {
        // Get the two touches
        guard touches.count == 2 else { return }
        
        let touch1 = touches[0]
        let touch2 = touches[1]
        
        // Use the stored initial start positions if available, otherwise fall back to history first
        let touch1Start = initialStartPositions[touch1.id] ?? touchHistory[touch1.id]?.first
        let touch2Start = initialStartPositions[touch2.id] ?? touchHistory[touch2.id]?.first
        
        guard let touch1Start = touch1Start,
              let touch2Start = touch2Start else {
            return
        }
        
        // Both touches must start near left edge (x < threshold)
        let touch1AtLeftEdge = touch1Start.x < leftEdgeThreshold
        let touch2AtLeftEdge = touch2Start.x < leftEdgeThreshold
        
        guard touch1AtLeftEdge && touch2AtLeftEdge else {
            return
        }
        
        // Check if both are moving right (x increasing)
        let touch1Current = touch1.position
        let touch2Current = touch2.position
        
        let touch1MovedRight = touch1Current.x > touch1Start.x
        let touch2MovedRight = touch2Current.x > touch2Start.x
        
        // Both must be moving right
        guard touch1MovedRight && touch2MovedRight else {
            return
        }
        
        // Check if they've moved enough distance (using initial start positions)
        let touch1Distance = touch1Current.x - touch1Start.x
        let touch2Distance = touch2Current.x - touch2Start.x
        
        let avgDistance = (touch1Distance + touch2Distance) / 2.0
        
        // Trigger gesture if average distance exceeds threshold
        if avgDistance >= minSwipeDistance && !isGestureDetected {
            Logger.info("✅ Panel opened: Two-finger left-edge swipe detected", module: "TouchGesture")
            isGestureDetected = true
            
            // Reset after a delay to allow for gesture completion and UI update
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                isGestureDetected = false
                resetGestureTracking()
            }
        }
    }
    
    private func checkForRightToLeftSwipe(_ touches: [OMSTouchData]) {
        // Get the two touches
        guard touches.count == 2 else { return }
        
        let touch1 = touches[0]
        let touch2 = touches[1]
        
        // Use the stored initial start positions if available, otherwise fall back to history first
        let touch1Start = initialStartPositions[touch1.id] ?? touchHistory[touch1.id]?.first
        let touch2Start = initialStartPositions[touch2.id] ?? touchHistory[touch2.id]?.first
        
        guard let touch1Start = touch1Start,
              let touch2Start = touch2Start else {
            return
        }
        
        // For close gesture, touches can start anywhere (not just right edge)
        // Store initial position if not already stored
        if initialStartPositions[touch1.id] == nil {
            initialStartPositions[touch1.id] = touch1Start
        }
        if initialStartPositions[touch2.id] == nil {
            initialStartPositions[touch2.id] = touch2Start
        }
        
        // Check if both are moving left (x decreasing)
        let touch1Current = touch1.position
        let touch2Current = touch2.position
        
        let touch1MovedLeft = touch1Current.x < touch1Start.x
        let touch2MovedLeft = touch2Current.x < touch2Start.x
        
        // Both must be moving left
        guard touch1MovedLeft && touch2MovedLeft else {
            return
        }
        
        // Check if they've moved enough distance (using initial start positions)
        let touch1Distance = touch1Start.x - touch1Current.x  // Positive when moving left
        let touch2Distance = touch2Start.x - touch2Current.x  // Positive when moving left
        
        let avgDistance = (touch1Distance + touch2Distance) / 2.0
        
        // Trigger close gesture if average distance exceeds threshold
        if avgDistance >= minSwipeDistance && !isCloseGestureDetected {
            Logger.info("✅ Panel closed: Two-finger right-to-left swipe detected", module: "TouchGesture")
            isCloseGestureDetected = true
            
            // Close the panel
            SlidingPanelWindowController.shared.hidePanel()
            
            // Reset after a delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                isCloseGestureDetected = false
                resetGestureTracking()
            }
        }
    }
    
    private func resetGestureTracking() {
        touchHistory.removeAll()
        initialStartPositions.removeAll()
        gestureStartTime = nil
        
        // Reset gesture detection after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            isGestureDetected = false
            isCloseGestureDetected = false
        }
    }
}


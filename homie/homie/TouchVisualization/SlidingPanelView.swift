//
//  SlidingPanelView.swift
//  homie
//
//  White sliding panel that appears from the left
//

import SwiftUI

struct SlidingPanelView: View {
    @Binding var isVisible: Bool
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Panel")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    onDismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Two-finger swipe detected!")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top)
                    
                    Text("This panel slides in from the left edge of your screen when you perform a two-finger swipe gesture starting from the left edge of your trackpad.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    // Example content
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Features:")
                            .font(.headline)
                        
                        Label("Real-time touch tracking", systemImage: "hand.point.up.left")
                        Label("Gesture detection", systemImage: "hand.draw")
                        Label("Smooth animations", systemImage: "sparkles")
                        Label("System-wide overlay", systemImage: "rectangle.inset.filled")
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#Preview {
    SlidingPanelView(isVisible: .constant(true), onDismiss: {})
        .frame(width: 800, height: 600)
}


//
//  ClippyResponseBubbleView.swift
//  homie
//
//  Displays streamed LLM response text in a liquid glass bubble.
//  Uses GlassEffectContainer for morphing transitions between elements.
//

import SwiftUI

/// A view that displays the current streamed LLM response with liquid glass effects.
/// The bubble morphs in/out from an indicator dot using Apple's GlassEffectContainer.
struct ClippyResponseBubbleView: View {
    @ObservedObject var sessionStore: LLMSessionStore
    @State private var isVisible = false
    @State private var displayedText = ""
    @Namespace private var glassNamespace

    /// Container spacing controls when shapes start blending together.
    /// Larger spacing = shapes blend sooner during transitions.
    private let containerSpacing: CGFloat = 30.0

    /// Maximum width for the response bubble
    private let maxBubbleWidth: CGFloat = 250.0

    var body: some View {
        GlassEffectContainer(spacing: containerSpacing) {
            HStack(spacing: 20.0) {
                // Response bubble - morphs in/out from indicator
                if isVisible && !displayedText.isEmpty {
                    responseContent
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .glassEffectID("responseBubble", in: glassNamespace)
                }

                // Indicator dot - always present, bubble morphs into/from this
                Circle()
                    .frame(width: 12, height: 12)
                    .glassEffect()
                    .glassEffectID("indicator", in: glassNamespace)
            }
        }
        .onChange(of: sessionStore.currentStreamedText) { _, newText in
            // Fade in text chunks as they arrive
            withAnimation(.easeIn(duration: 0.2)) {
                displayedText = newText
            }
            // Also update visibility when text changes
            withAnimation(.bouncy) {
                isVisible = !newText.isEmpty
            }
        }
        .onChange(of: sessionStore.isGenerating) { _, generating in
            // Morph bubble in/out with bouncy animation
            withAnimation(.bouncy) {
                isVisible = generating || !sessionStore.currentStreamedText.isEmpty
            }
        }
        .onAppear {
            // Initialize state from current store values
            displayedText = sessionStore.currentStreamedText
            isVisible = !sessionStore.currentStreamedText.isEmpty
        }
    }

    /// The content inside the response bubble
    private var responseContent: some View {
        Text(displayedText)
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
    }
}

#Preview {
    ClippyResponseBubbleView(sessionStore: LLMSessionStore.shared)
        .frame(width: 400, height: 100)
        .background(Color.gray.opacity(0.3))
}

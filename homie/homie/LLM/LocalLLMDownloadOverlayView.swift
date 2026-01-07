//
//  LocalLLMDownloadOverlayView.swift
//  homie
//
//  SwiftUI overlay view showing local LLM model download progress.
//  Displayed as a small card in the bottom-right corner of the window.
//

import SwiftUI

/// Overlay card showing local LLM model download progress
struct LocalLLMDownloadOverlayView: View {
    @ObservedObject var store: LocalLLMModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14, weight: .medium))

                Text("Local AI Model")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                // Dismiss button (only when ready or failed)
                if store.modelState.isReady || isFailedState {
                    Button(action: {
                        store.dismissOverlay()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Model name
            Text(store.modelName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Progress bar (when downloading)
            if case .downloading(let progress) = store.modelState {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    Text("\(Int(progress * 100))% complete")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Status text
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(statusColor)
        }
        .padding(12)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch store.modelState {
        case .notStarted:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch store.modelState {
        case .notStarted:
            return .secondary
        case .downloading:
            return .blue
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusText: String {
        switch store.modelState {
        case .notStarted:
            return "Preparing model..."
        case .downloading:
            return "Loading model..."
        case .ready:
            return "Ready for offline use"
        case .failed(let reason):
            return reason
        }
    }

    private var statusColor: Color {
        switch store.modelState {
        case .ready:
            return .green
        case .failed:
            return .red
        default:
            return .secondary
        }
    }

    private var isFailedState: Bool {
        if case .failed = store.modelState { return true }
        return false
    }
}

/// Container view that positions the overlay in the bottom-right corner
struct LocalLLMDownloadOverlayContainer: View {
    @ObservedObject var store = LocalLLMModelStore.shared

    var body: some View {
        if store.showDownloadOverlay {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    LocalLLMDownloadOverlayView(store: store)
                        .padding(16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.showDownloadOverlay)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2)

        LocalLLMDownloadOverlayContainer()
    }
    .frame(width: 400, height: 300)
}

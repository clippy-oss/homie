//
//  TouchVisualizationView.swift
//  homie
//
//  Created for touch visualization feature
//

import OpenMultitouchSupport
import SwiftUI

struct TouchVisualizationView: View {
    @StateObject private var viewModel = TouchVisualizationViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            // Control buttons
            HStack(spacing: 12) {
                if viewModel.isListening {
                    Button {
                        viewModel.stop()
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("Stop")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        viewModel.start()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Start")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Touch count indicator
                if viewModel.isListening {
                    Text("\(viewModel.touchData.count) touch\(viewModel.touchData.count == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Canvas for touch visualization
            Canvas { context, size in
                viewModel.touchData.forEach { touch in
                    let path = makeEllipse(touch: touch, size: size)
                    // Use opacity based on total capacitance for visual feedback
                    let opacity = min(Double(touch.total) * 2.0, 1.0)
                    context.fill(path, with: .color(.blue.opacity(opacity)))
                    
                    // Draw touch ID
                    let x = Double(touch.position.x) * size.width
                    let y = Double(1.0 - touch.position.y) * size.height
                    context.draw(
                        Text("\(touch.id)")
                            .font(.caption2)
                            .foregroundColor(.white),
                        at: CGPoint(x: x, y: y)
                    )
                }
            }
            .frame(minHeight: 400)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal)
            
            // Info section
            if viewModel.isListening && !viewModel.touchData.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.touchData, id: \.id) { touch in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Touch ID: \(touch.id)")
                                    .font(.headline)
                                Text("Position: (\(String(format: "%.3f", touch.position.x)), \(String(format: "%.3f", touch.position.y)))")
                                    .font(.caption)
                                Text("State: \(touch.state.rawValue)")
                                    .font(.caption)
                                Text("Pressure: \(String(format: "%.3f", touch.pressure))")
                                    .font(.caption)
                                Text("Total: \(String(format: "%.3f", touch.total))")
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 200)
            } else if viewModel.isListening {
                Text("Touch your trackpad to see visualization")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    private func makeEllipse(touch: OMSTouchData, size: CGSize) -> Path {
        let x = Double(touch.position.x) * size.width
        let y = Double(1.0 - touch.position.y) * size.height
        let u = size.width / 100.0
        let w = Double(touch.axis.major) * u
        let h = Double(touch.axis.minor) * u
        
        return Path(ellipseIn: CGRect(x: -0.5 * w, y: -0.5 * h, width: w, height: h))
            .rotation(.radians(Double(-touch.angle)), anchor: .topLeading)
            .offset(x: x, y: y)
            .path(in: CGRect(origin: .zero, size: size))
    }
}

#Preview {
    TouchVisualizationView()
        .frame(width: 800, height: 600)
}


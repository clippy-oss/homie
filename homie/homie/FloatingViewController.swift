import Cocoa
import Foundation
import AVFoundation
import Combine
import FoundationModels
import SwiftUI

// MARK: - Liquid Glass Background Wrapper
/// All 20 available liquid‑glass variants.
/// Apple does not publicly describe how each value looks so experiment and pick the one you like!
public enum GlassVariant: Int, CaseIterable, Identifiable, Sendable {
    case v0  = 0,  v1  = 1,  v2  = 2,  v3  = 3,  v4  = 4
    case v5  = 5,  v6  = 6,  v7  = 7,  v8  = 8,  v9  = 9
    case v10 = 10, v11 = 11, v12 = 12, v13 = 13, v14 = 14
    case v15 = 15, v16 = 16, v17 = 17, v18 = 18, v19 = 19

    public var id: Int { rawValue }
}

/// A SwiftUI view that embeds its content inside Apple's private liquid‑glass material.
public struct LiquidGlassBackground<Content: View>: NSViewRepresentable {
    private let content: Content
    private let cornerRadius: CGFloat
    private let variant: GlassVariant

    public init(
        variant: GlassVariant = .v11,
        cornerRadius: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.variant      = variant
        self.cornerRadius = cornerRadius
        self.content      = content()
    }

    @inline(__always)
    private func setterSelector(for key: String, privateVariant: Bool = true) -> Selector? {
        guard !key.isEmpty else { return nil }
        let name: String
        if privateVariant {
            let cleaned = key.hasPrefix("_") ? key : "_" + key
            name = "set" + cleaned
        } else {
            let first = String(key.prefix(1)).uppercased()
            let rest  = String(key.dropFirst())
            name = "set" + first + rest
        }
        return NSSelectorFromString(name + ":")
    }

    private typealias VariantSetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void

    private func callPrivateVariantSetter(on object: AnyObject, value: Int) {
        guard
            let sel   = setterSelector(for: "variant", privateVariant: true),
            let m     = class_getInstanceMethod(object_getClass(object), sel)
        else {
            #if DEBUG
            Logger.warning("LiquidGlassBackground: selector set_variant: not found, falling back to default", module: "UI")
            #endif
            return
        }
        let imp = method_getImplementation(m)
        let f   = unsafeBitCast(imp, to: VariantSetterIMP.self)
        f(object, sel, value)
    }

    public func makeNSView(context: Context) -> NSView {
        // `NSGlassEffectView` is private. Look it up dynamically to avoid compile‑time coupling.
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: .zero)
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            callPrivateVariantSetter(on: glass, value: variant.rawValue)

            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(hosting, forKey: "contentView")
            return glass
        }

        // Fallback for earlier macOS – use an ordinary blur.
        let fallback = NSVisualEffectView()
        fallback.material = .underWindowBackground

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: fallback.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: fallback.bottomAnchor)
        ])
        return fallback
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let hosting = nsView.value(forKey: "contentView") as? NSHostingView<Content> {
            hosting.rootView = content
        }
        nsView.setValue(cornerRadius, forKey: "cornerRadius")
        callPrivateVariantSetter(on: nsView, value: variant.rawValue)
    }
}

// SwiftUI view for liquid glass text field using dynamic variant
struct LiquidGlassTextField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let onCommit: () -> Void
    let glassVariant: GlassVariant
    let shadowIntensity: Double
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        LiquidGlassBackground(variant: glassVariant, cornerRadius: 20) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .focusEffectDisabled() 
                .focused($isTextFieldFocused)
                .onSubmit {
                    onCommit()
                }
                .onChange(of: isFocused) { newValue in
                    isTextFieldFocused = newValue
                }
                .onAppear {
                    // Auto-focus when the view appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isTextFieldFocused = true
                    }
                }
        }
        .shadow(
            color: Color.black.opacity(shadowIntensity / 20.0 * 0.8),
            radius: shadowIntensity * 2,
            x: 0,
            y: shadowIntensity
        )
    }
}

// SwiftUI view for circular liquid glass button using dynamic variant
struct CircularLiquidGlassButton: View {
    let action: () -> Void
    let icon: String
    let panelSize: CGFloat
    let glassVariant: GlassVariant
    let shadowIntensity: Double
    
    var body: some View {
        ZStack {
            // White circular background with 20% opacity, behind everything
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: panelSize, height: panelSize)
                .zIndex(-1)  // Behind the glass effect
            
            // Liquid glass effect on top
            LiquidGlassBackground(variant: glassVariant, cornerRadius: panelSize / 2) {
                // Use a simple view instead of Button to make it unclickable
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: panelSize / 3, height: panelSize / 3)
                    .padding(panelSize / 3)
                    .opacity(0)  // Make plus sign 100% transparent
            }
            .frame(width: panelSize, height: panelSize)
            .clipShape(Circle())  // This will clip the square frame to a perfect circle
        }
        .shadow(
            color: Color.black.opacity(shadowIntensity / 20.0 * 0.8),
            radius: shadowIntensity * 2,
            x: 0,
            y: shadowIntensity
        )
    }
}

// SwiftUI view for animated waveform
struct WaveformAnimationView: View {
    @State private var animationPhase: CGFloat = 0
    let panelSize: CGFloat
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2.25)
                    .fill(Color(red: 0.96, green: 0.76, blue: 0.28))
                    .frame(width: 4.5, height: barHeight(for: index))
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = panelSize * 0.3
        
        // Define amplitude multipliers for each bar (0-5)
        let amplitudeMultipliers: [CGFloat] = [0.3, 0.6, 1.0, 0.3, 0.6, 0.3]
        let amplitude = amplitudeMultipliers[index]
        
        // Create chaotic movement with multiple sine waves at different frequencies
        let phase1 = animationPhase + Double(index) * 0.15
        let phase2 = animationPhase * 1.7 + Double(index) * 0.23
        let phase3 = animationPhase * 0.8 + Double(index) * 0.31
        
        // Combine multiple sine waves for chaotic movement
        let wave1 = sin(phase1 * 2 * .pi) * 0.4
        let wave2 = sin(phase2 * 2 * .pi) * 0.3
        let wave3 = sin(phase3 * 2 * .pi) * 0.3
        
        let combinedWave = (wave1 + wave2 + wave3)
        let normalizedWave = (combinedWave + 1.0) * 0.5 // Normalize to 0-1 range
        
        // All bars have the same minimum height, but different maximum heights
        let minHeight = baseHeight
        let maxHeightForBar = baseHeight + (maxHeight - baseHeight) * amplitude
        
        return minHeight + (maxHeightForBar - minHeight) * normalizedWave
    }
    
    private func startAnimation() {
        // Use a timer to continuously update the animation
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                animationPhase += 0.1
                if animationPhase >= 1.0 {
                    animationPhase = 0.0
                }
            }
        }
    }
}

class FloatingViewController: NSViewController {
    
    private var visualEffectView: NSVisualEffectView!
    private var containerView: NSView!
    private var clippyImageView: NSImageView!
    private var clippyWidthConstraint: NSLayoutConstraint?
    private var clippyHeightConstraint: NSLayoutConstraint?
    private var clippy4ImageView: NSImageView!
    private var clippy4WidthConstraint: NSLayoutConstraint?
    private var clippy4HeightConstraint: NSLayoutConstraint?
    private var clippyThinkingImageView: NSImageView!
    private var clippyThinkingWidthConstraint: NSLayoutConstraint?
    private var clippyThinkingHeightConstraint: NSLayoutConstraint?
    
    // Thinking state animation
    private enum ThinkingVariant {
        case static1
        case static2
        case static3
        case animated4  // 4-1 and 4-2, switches every 1 second
        case animated5  // 5-1, 5-2, 5-3, cycles every 500ms
    }
    private var currentThinkingVariant: ThinkingVariant?
    private var thinkingAnimationTimer: Timer?
    
    // Clippy hover animation
    private var clippyHoverTimer: Timer?
    var speechManager: SpeechManager!
    private var cancellables = Set<AnyCancellable>()
    
    // Panel size for circular appearance
    private var panelSize: CGFloat = 0
    
    // Context text from selected text
    private var contextText: String?
    
    // Flag to track whether to use raw dictation (no Foundation Models processing)
    private var useRawDictation = false
    
    // Foundation Models Configuration (no API keys needed)

    // Single-paste guard per interaction
    private var currentInteractionId: UUID?
    private var hasPastedForCurrentInteraction: Bool = false
    
    // AI Processing State - track when AI is processing and if we should close after
    private var isProcessingWithAI = false
    private var shouldCloseAfterAIResponse = false
    
    // Text entry mode
    private var isTextEntryMode = false
    private var textEntryHostingView: NSHostingView<LiquidGlassTextField>?
    private var textEntryText: String = ""
    private var textEntryIsFocused: Bool = false
    private var textEntryWidthConstraint: NSLayoutConstraint?
    private var circularButtonHostingView: NSHostingView<CircularLiquidGlassButton>?
    
    // Waveform animation for dictation/speech modes
    private var waveformHostingView: NSHostingView<WaveformAnimationView>?

    // Response bubble for displaying LLM streamed text
    private var responseBubbleHostingView: NSHostingView<ClippyResponseBubbleView>?

    // MARK: - Glass Variants (Final Settings)
    private var textFieldGlassVariant: GlassVariant = .v2
    private var circularButtonGlassVariant: GlassVariant = .v2
    private var shadowIntensity: Double = 4.0  // Locked at level 4
    
    override func loadView() {
        // Calculate view size: 1/7th of screen height with 1:1 aspect ratio
        guard let screen = NSScreen.main else {
            fatalError("Could not get main screen")
        }
        
        let screenHeight = screen.frame.height
        panelSize = screenHeight / 7.0
        
        // Add extra space for shadows: 50% height and 20% width
        // Add 5% padding to right and top for shadow cutoff prevention
        // Add additional 5% on the right for shadow visibility
        let shadowPaddingHeight = panelSize * 0.5
        let shadowPaddingWidth = panelSize * 0.2
        let shadowCutoffPadding = panelSize * 0.05  // 5% padding for shadow cutoff
        let additionalRightPadding = panelSize * 0.05  // Additional 5% on the right
        
        view = NSView(frame: NSRect(x: 0, y: 0, width: panelSize + shadowPaddingWidth + shadowCutoffPadding + additionalRightPadding, height: panelSize + shadowPaddingHeight + shadowCutoffPadding))
        view.wantsLayer = true
        view.layer?.masksToBounds = false  // Allow shadows to extend beyond bounds
        
        setupNotificationStyleUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize speech manager
        speechManager = SpeechManager()
        speechManager.onTranscriptionUpdate = { [weak self] text in
            self?.updateDictationText(text)
        }
        speechManager.onTranscriptionFinal = { [weak self] text in
            self?.finalizeDictation(text)
        }
        speechManager.onError = { [weak self] error in
            self?.handleDictationError(error)
        }
        
        // Enable mouse events for dragging
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Initialize Foundation Models
        Task {
            await FoundationModelsManager.shared.prewarm()
        }
        
        // MARK: - Testing Glass Variants (DELETED)
        // Testing popup removed - keeping current settings
    }
    
    
    func setContextText(_ text: String?) {
        self.contextText = text
        if let text = text, !text.isEmpty {
            // Optionally show some visual indication that context is available
            Logger.debug("Context set: \(text.prefix(100))", module: "FloatingVC")
        }
    }
    
    // MARK: - Text Entry Mode
    func enableTextEntryMode() {
        isTextEntryMode = true
        // Hide waveform animation when entering text entry mode
        hideWaveformAnimation()
        // Show clippy-4 image for text entry mode
        showClippy4Image()
        setupTextEntryField()
    }
    
    func isTextEntryModeActive() -> Bool {
        return isTextEntryMode
    }
    
    func isAIProcessing() -> Bool {
        return isProcessingWithAI
    }
    
    func requestCloseAfterAIResponse() {
        shouldCloseAfterAIResponse = true
        Logger.info("Marked to close popup after AI response is generated", module: "FloatingVC")
    }
    
    func disableTextEntryMode() {
        isTextEntryMode = false
        textEntryIsFocused = false
        textEntryHostingView?.removeFromSuperview()
        textEntryHostingView = nil
        textEntryWidthConstraint = nil
        textEntryText = ""
        // Don't remove circular button - it should persist across all modes
        
        // Hide clippy-4 image when exiting text entry mode
        hideClippy4Image()
        
        // Restore original window size
        restoreOriginalWindowSize()
        
        // Waveform animation will be shown again when dictation/speech modes are activated
    }
    
    private func restoreOriginalWindowSize() {
        guard let window = view.window else { return }
        
        // Calculate new position to keep right edge anchored when restoring
        let currentFrame = window.frame
        let shadowPaddingWidth = panelSize * 0.2
        let shadowPaddingHeight = panelSize * 0.5
        let shadowCutoffPadding = panelSize * 0.05  // 5% padding for shadow cutoff
        let additionalRightPadding = panelSize * 0.05  // Additional 5% on the right
        let newWidth = panelSize + shadowPaddingWidth + shadowCutoffPadding + additionalRightPadding
        let widthDifference = currentFrame.width - newWidth
        
        // Move right by the width difference to keep right edge in place
        let newFrame = NSRect(
            x: currentFrame.origin.x + widthDifference,
            y: currentFrame.origin.y,
            width: newWidth,
            height: panelSize + shadowPaddingHeight + shadowCutoffPadding
        )
        
        window.setFrame(newFrame, display: true, animate: true)
        
        // Restore the original corner radius
        let cornerRadius = panelSize / 2
        visualEffectView.layer?.cornerRadius = cornerRadius
    }
    
    private func setupTextEntryField() {
        // Remove existing text fields if any
        textEntryHostingView?.removeFromSuperview()
        
        // Set focus to true to activate the text field
        textEntryIsFocused = true
        
        // Create main SwiftUI text field with liquid glass material
        let swiftUITextField = LiquidGlassTextField(
            text: Binding(
                get: { [weak self] in self?.textEntryText ?? "" },
                set: { [weak self] in self?.textEntryText = $0 }
            ),
            isFocused: Binding(
                get: { [weak self] in self?.textEntryIsFocused ?? false },
                set: { [weak self] in self?.textEntryIsFocused = $0 }
            ),
            placeholder: "Type your message and press Enter...",
            onCommit: { [weak self] in
                self?.handleTextEntrySubmit()
            },
            glassVariant: textFieldGlassVariant,
            shadowIntensity: shadowIntensity
        )
        
        // Create hosting view for main SwiftUI text field
        textEntryHostingView = NSHostingView(rootView: swiftUITextField)
        guard let hostingView = textEntryHostingView else { return }
        
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor  // Ensure transparent background
        hostingView.layer?.masksToBounds = false  // Allow shadows to extend beyond bounds
        hostingView.focusRingType = .none
        containerView.addSubview(hostingView)
        
        // Position the text field anchored at panelSize * 2 + 10px from left
        // Start with tiny width, will grow leftward with animation
        let shadowPaddingWidth = panelSize * 0.2
        let shadowCutoffPadding = panelSize * 0.05  // 5% padding for shadow cutoff
        let additionalRightPadding = panelSize * 0.05  // Additional 5% on the right
        let widthConstraint = hostingView.widthAnchor.constraint(equalToConstant: 10) // Start tiny
        let rightEdgeConstraint = hostingView.trailingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: panelSize * 2 + 10 + shadowPaddingWidth + shadowCutoffPadding + additionalRightPadding)
        NSLayoutConstraint.activate([
            rightEdgeConstraint, // Anchor right edge at panelSize * 2 + 10px from left + shadow padding
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20), // Back to original positioning
            widthConstraint, // Store reference for animation
            hostingView.heightAnchor.constraint(equalToConstant: 44)  // Increased height for pill shape
        ])
        
        // Store width constraint for animation
        textEntryWidthConstraint = widthConstraint
        
        // Make the main hosting view focusable for typing in the popup
        DispatchQueue.main.async { [weak self] in
            // Make sure the hosting view can receive keyboard input
            self?.view.window?.makeFirstResponder(hostingView)
        }
        
        // Animate text field growth after a small delay to ensure proper layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateTextEntryFieldGrowth()
        }
    }
    
    private func animateTextEntryFieldGrowth() {
        guard let widthConstraint = textEntryWidthConstraint else { return }
        
        // Ensure the view is properly laid out before starting animation
        containerView.layoutSubtreeIfNeeded()
        
        // Animate the text field width from tiny to full size
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            widthConstraint.animator().constant = panelSize * 2 // Use animator() for smooth animation
        }, completionHandler: {
            // Animation completed
        })
    }
    
    private func resizeWindowForTextEntry() {
        guard let window = view.window else { return }
        
        // Calculate new position to keep right edge anchored
        let currentFrame = window.frame
        let shadowPaddingWidth = panelSize * 0.2
        let shadowPaddingHeight = panelSize * 0.5
        let shadowCutoffPadding = panelSize * 0.05  // 5% padding for shadow cutoff
        let additionalRightPadding = panelSize * 0.05  // Additional 5% on the right
        let newWidth: CGFloat = panelSize * 3 + shadowPaddingWidth + shadowCutoffPadding + additionalRightPadding
        let widthDifference = newWidth - currentFrame.width
        
        // Move left by the width difference to keep right edge in place
        let newFrame = NSRect(
            x: currentFrame.origin.x - widthDifference,
            y: currentFrame.origin.y,
            width: newWidth,
            height: panelSize + shadowPaddingHeight + shadowCutoffPadding
        )
        
        window.setFrame(newFrame, display: true, animate: true)
        
        // Update the visual effect view corner radius for the new width
        let cornerRadius = window.frame.height / 2
        visualEffectView.layer?.cornerRadius = cornerRadius
    }
    
    private func handleTextEntrySubmit() {
        let text = textEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty {
            Logger.info("Text entry submitted: \(text)", module: "FloatingVC")
            
            // Store the submitted text for processing
            let submittedText = text
            
            // Clear the text field but keep the input box visible during thinking
            textEntryText = ""
            
            // Mark to close after AI response instead of closing immediately
            shouldCloseAfterAIResponse = true
            
            // Keep text entry UI visible during AI processing (don't remove it)
            // Just disable focus so user can't type while processing
            textEntryIsFocused = false
            
            // Keep the window in expanded text entry size during thinking
            // Don't resize back to circular - keep the input box visible
            
            // Set up interaction tracking for text entry mode
            currentInteractionId = UUID()
            hasPastedForCurrentInteraction = false
                
            // Process the text - the popup will close after the result is pasted
            processTranscribedTextWithFoundationModels(submittedText)
        }
    }
    
    private func handleCircularButtonTap() {
        // For now, just log - you can customize this action
        Logger.debug("Circular button tapped", module: "FloatingVC")
        
        // Example: You could add functionality like:
        // - Clear the blind text field
        // - Toggle some state
        // - Perform a specific action
    }
    
    private func completeTextEntryMode() {
        isTextEntryMode = false
        textEntryIsFocused = false
        textEntryHostingView?.removeFromSuperview()
        textEntryHostingView = nil
        textEntryWidthConstraint = nil
        // Don't remove circular button - it should persist across all modes
        textEntryText = ""
        
        // Use the proper hideWindow method to restore focus to original text field
        DispatchQueue.main.async { [weak self] in
            if let windowController = self?.view.window?.windowController as? FloatingWindowController {
                windowController.hideWindow()
            } else {
                // Fallback if we can't get the window controller
                self?.view.window?.orderOut(nil)
            }
        }
    }
    
    private func setupNotificationStyleUI() {
        // Calculate corner radius for circular appearance
        let cornerRadius = panelSize / 2
        
        // Create visual effect view for the blurred background
        visualEffectView = NSVisualEffectView()
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true
        
        // Commented out to hide the white frosted glass circle background
        // view.addSubview(visualEffectView)
        
        // Create container view for content
        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = false  // Allow shadows to extend beyond bounds
        
        // Commented out to hide the white frosted glass circle background
        // visualEffectView.addSubview(containerView)
        view.addSubview(containerView)
        
        // Set up constraints to keep containerView at original size, positioned with 5% padding from top and 10% from right
        let shadowCutoffPadding = panelSize * 0.05  // 5% padding for shadow cutoff
        let additionalRightPadding = panelSize * 0.05  // Additional 5% on the right
        let totalRightPadding = shadowCutoffPadding + additionalRightPadding  // Total 10% right padding
        NSLayoutConstraint.activate([
            // Commented out to hide the white frosted glass circle background
            // visualEffectView.topAnchor.constraint(equalTo: view.topAnchor),
            // visualEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            // visualEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // visualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Position containerView with 5% padding from top and 10% from right to prevent shadow cutoff
            containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: shadowCutoffPadding),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -totalRightPadding),
            containerView.heightAnchor.constraint(equalToConstant: panelSize) // Original height, no extra padding
        ])
        
        // Commented out to hide the white frosted glass circle background
        // Add a subtle white overlay for the notification appearance
        // let overlayView = NSView()
        // overlayView.translatesAutoresizingMaskIntoConstraints = false
        // overlayView.wantsLayer = true
        // overlayView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        // overlayView.layer?.cornerRadius = cornerRadius
        // overlayView.layer?.masksToBounds = true
        // 
        // containerView.addSubview(overlayView)
        // 
        // NSLayoutConstraint.activate([
        //     overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
        //     overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        //     overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        //     overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        // ])

        // Add the Clippy-4 image (background layer) - initially hidden
        clippy4ImageView = NSImageView()
        clippy4ImageView.translatesAutoresizingMaskIntoConstraints = false
        clippy4ImageView.imageScaling = .scaleProportionallyUpOrDown
        clippy4ImageView.wantsLayer = true
        clippy4ImageView.canDrawSubviewsIntoLayer = true
        clippy4ImageView.isHidden = true  // Initially hidden

        let clippy4Image = loadClippy4Image()
        clippy4ImageView.image = clippy4Image

        containerView.addSubview(clippy4ImageView)
        
        // Position the clippy-4 image view on the right side, same position as clippy-2
        NSLayoutConstraint.activate([
            clippy4ImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            clippy4ImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        clippy4WidthConstraint = clippy4ImageView.widthAnchor.constraint(equalToConstant: 10)
        clippy4HeightConstraint = clippy4ImageView.heightAnchor.constraint(equalToConstant: 10)
        clippy4WidthConstraint?.isActive = true
        clippy4HeightConstraint?.isActive = true
        
        // Set clippy-4 to be behind clippy-2 but above the liquid glass button
        // Button is at -1, clippy-4 should be at -0.5, clippy-2 at 0 (default)
        clippy4ImageView.layer?.zPosition = -0.5

        // Add the Clippy-2 image (foreground layer)
        clippyImageView = NSImageView()
        clippyImageView.translatesAutoresizingMaskIntoConstraints = false
        clippyImageView.imageScaling = .scaleProportionallyUpOrDown
        clippyImageView.wantsLayer = true
        clippyImageView.canDrawSubviewsIntoLayer = true

        let clippyImage = loadClippyImage()
        clippyImageView.image = clippyImage

        containerView.addSubview(clippyImageView)
        
        // Position the image view on the right side; its size will be controlled via width/height constants we compute to 90% of the circle
        NSLayoutConstraint.activate([
            clippyImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            clippyImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        clippyWidthConstraint = clippyImageView.widthAnchor.constraint(equalToConstant: 10)
        clippyHeightConstraint = clippyImageView.heightAnchor.constraint(equalToConstant: 10)
        clippyWidthConstraint?.isActive = true
        clippyHeightConstraint?.isActive = true
        
        // Add the Clippy Thinking image (for Thinking State) - initially hidden
        clippyThinkingImageView = NSImageView()
        clippyThinkingImageView.translatesAutoresizingMaskIntoConstraints = false
        clippyThinkingImageView.imageScaling = .scaleProportionallyUpOrDown
        clippyThinkingImageView.wantsLayer = true
        clippyThinkingImageView.canDrawSubviewsIntoLayer = true
        clippyThinkingImageView.isHidden = true  // Initially hidden

        // Initial image will be set when thinking state is shown
        clippyThinkingImageView.image = nil

        containerView.addSubview(clippyThinkingImageView)
        
        // Position the thinking image view on the right side, same position as clippy-2
        NSLayoutConstraint.activate([
            clippyThinkingImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            clippyThinkingImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        clippyThinkingWidthConstraint = clippyThinkingImageView.widthAnchor.constraint(equalToConstant: 10)
        clippyThinkingHeightConstraint = clippyThinkingImageView.heightAnchor.constraint(equalToConstant: 10)
        clippyThinkingWidthConstraint?.isActive = true
        clippyThinkingHeightConstraint?.isActive = true
        
        // Set thinking image to same z-position as clippy-2 (will replace it when shown)
        clippyThinkingImageView.layer?.zPosition = 0
        
        // Initial sizing
        DispatchQueue.main.async { [weak self] in
            self?.updateClippySize()
        }
        
        // Add circular liquid glass button (appears in all modes)
        setupCircularButton()

        // Add response bubble for displaying LLM streamed text
        setupResponseBubble()
    }
    
    private func setupCircularButton() {
        // Create circular liquid glass button (blind/unclickable)
        let circularButton = CircularLiquidGlassButton(
            action: {}, // Empty action since button is blind
            icon: "plus",
            panelSize: panelSize,
            glassVariant: circularButtonGlassVariant,
            shadowIntensity: shadowIntensity
        )
        
        // Create circular button hosting view
        circularButtonHostingView = NSHostingView(rootView: circularButton)
        guard let buttonHostingView = circularButtonHostingView else { return }
        
        buttonHostingView.translatesAutoresizingMaskIntoConstraints = false
        buttonHostingView.wantsLayer = true
        buttonHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(buttonHostingView)
        
        // Position the circular button stuck to the right edge of the popup
        NSLayoutConstraint.activate([
            buttonHostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            buttonHostingView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            buttonHostingView.widthAnchor.constraint(equalToConstant: panelSize), // panelSize width
            buttonHostingView.heightAnchor.constraint(equalToConstant: panelSize) // panelSize height
        ])
        
        // Move button to background layer so it appears behind other elements
        // In AppKit, we need to adjust the layer z-position instead
        buttonHostingView.layer?.zPosition = -1
    }

    // MARK: - Response Bubble Setup

    private func setupResponseBubble() {
        // Create response bubble view connected to LLMSessionStore
        let responseBubbleView = ClippyResponseBubbleView(sessionStore: LLMSessionStore.shared)

        // Create hosting view
        responseBubbleHostingView = NSHostingView(rootView: responseBubbleView)
        guard let bubbleHostingView = responseBubbleHostingView else { return }

        bubbleHostingView.translatesAutoresizingMaskIntoConstraints = false
        bubbleHostingView.wantsLayer = true
        bubbleHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        bubbleHostingView.layer?.masksToBounds = false  // Allow glass effects to render properly

        // Add to the main view so it can be positioned relative to clippy
        view.addSubview(bubbleHostingView)

        // Position the response bubble to the left of clippy
        // The trailing edge is anchored relative to clippy's leading edge
        NSLayoutConstraint.activate([
            // Trailing edge anchored to the left of clippy with spacing
            bubbleHostingView.trailingAnchor.constraint(equalTo: clippyImageView.leadingAnchor, constant: -15),
            // Vertically centered with clippy
            bubbleHostingView.centerYAnchor.constraint(equalTo: clippyImageView.centerYAnchor),
            // Constrain height
            bubbleHostingView.heightAnchor.constraint(lessThanOrEqualToConstant: panelSize),
            // Leading edge should stay within view bounds with some padding
            bubbleHostingView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 10)
        ])

        // Set z-position above the circular button but below clippy
        bubbleHostingView.layer?.zPosition = -0.3

        Logger.info("Response bubble view set up", module: "FloatingVC")
    }

    /// Expand window to accommodate response bubble
    private func expandWindowForResponseBubble() {
        guard let window = view.window else { return }

        let currentFrame = window.frame
        let shadowPaddingWidth = panelSize * 0.2
        let shadowPaddingHeight = panelSize * 0.5
        let shadowCutoffPadding = panelSize * 0.05
        let additionalRightPadding = panelSize * 0.05
        // Expand by bubble max width (250) + spacing
        let bubbleWidth: CGFloat = 280.0
        let newWidth = panelSize + shadowPaddingWidth + shadowCutoffPadding + additionalRightPadding + bubbleWidth
        let widthDifference = newWidth - currentFrame.width

        // Move left by the width difference to keep right edge in place
        let newFrame = NSRect(
            x: currentFrame.origin.x - widthDifference,
            y: currentFrame.origin.y,
            width: newWidth,
            height: panelSize + shadowPaddingHeight + shadowCutoffPadding
        )

        window.setFrame(newFrame, display: true, animate: true)
        Logger.debug("Window expanded for response bubble", module: "FloatingVC")
    }

    /// Restore window to original size after response bubble is dismissed
    private func restoreWindowFromResponseBubble() {
        guard let window = view.window else { return }

        let currentFrame = window.frame
        let shadowPaddingWidth = panelSize * 0.2
        let shadowPaddingHeight = panelSize * 0.5
        let shadowCutoffPadding = panelSize * 0.05
        let additionalRightPadding = panelSize * 0.05
        let originalWidth = panelSize + shadowPaddingWidth + shadowCutoffPadding + additionalRightPadding
        let widthDifference = currentFrame.width - originalWidth

        // Move right by the width difference to keep right edge in place
        let newFrame = NSRect(
            x: currentFrame.origin.x + widthDifference,
            y: currentFrame.origin.y,
            width: originalWidth,
            height: panelSize + shadowPaddingHeight + shadowCutoffPadding
        )

        window.setFrame(newFrame, display: true, animate: true)
        Logger.debug("Window restored from response bubble", module: "FloatingVC")
    }

    // Chat functionality removed for notification-style panel
    
    // Dictation functionality removed for notification-style panel
    private func updateDictationText(_ text: String) {
        // No UI to update in notification panel, but we can log it
        Logger.debug("Whisper update: \(text)", module: "Speech")
    }
    
    private func finalizeDictation(_ text: String) {
        Logger.info("Whisper final: \(text)", module: "Speech")

        // Filter out noise/music annotations
        let filteredText = filterNoiseAnnotations(text)
        Logger.debug("Filtered text: \(filteredText)", module: "Speech")
        
        // Ignore empty or punctuation-only results
        if isEmptyOrPunctuationOnly(filteredText) {
            Logger.warning("Ignoring empty/punctuation-only transcription; nothing will be pasted or sent to GPT", module: "Speech")
            DispatchQueue.main.async { [weak self] in
                // Ensure any visual states are reset
                self?.updatePanelForRecordingState(active: false)
                self?.updatePanelForProcessingState(active: false)
                // Reset raw dictation flag if it was set
                if self?.useRawDictation == true {
                    self?.useRawDictation = false
                }
            }
            // Hide the voice notch since no processing will happen
            Task { @MainActor in
                NotchManager.shared.hideVoiceNotch()
            }
            return
        }

        // Start a new interaction id for guard logic
        currentInteractionId = UUID()
        hasPastedForCurrentInteraction = false

        if useRawDictation {
            // Raw dictation path: copy directly to clipboard
            finalizeRawDictation(filteredText)
        } else {
            // Original path: process with Foundation Models
            processTranscribedTextWithFoundationModels(filteredText)
        }
    }
    
    private func handleDictationError(_ error: Error) {
        Logger.error("Whisper error: \(error.localizedDescription)", module: "Speech")
        updatePanelForRecordingState(active: false)
        // Hide the voice notch on error
        Task { @MainActor in
            NotchManager.shared.hideVoiceNotch()
        }
    }
    
    // MARK: - Noise Annotation Filtering
    private func filterNoiseAnnotations(_ text: String) -> String {
        var filteredText = text
        
        // Remove content within parentheses (e.g., "(Music)", "(background noise)")
        filteredText = filteredText.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        
        // Remove content within square brackets (e.g., "[background noise]", "[Music]")
        filteredText = filteredText.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        
        // Clean up any extra whitespace that might be left behind
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove multiple consecutive spaces
        filteredText = filteredText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return filteredText
    }
    
    // MARK: - Testing Helper (can be removed in production)
    private func testNoiseFiltering() {
        let testCases = [
            "(Music) Hello world",
            "[background noise] Hello world",
            "(Music) [background noise] Hello world",
            "Hello (Music) world",
            "Hello [background noise] world",
            "(Music)",
            "[background noise]",
            "(Music) [background noise]",
            "Hello world",
            "  (Music)  ",
            "  [background noise]  "
        ]
        
        for testCase in testCases {
            let result = filterNoiseAnnotations(testCase)
            Logger.debug("Test: '\(testCase)' -> '\(result)'", module: "Speech")
        }
    }
    
    // MARK: - Whisper Transcription and GPT Processing
    func startWhisperTranscription() {
        Logger.info("Starting Whisper transcription", module: "Speech")
        
        // Visual feedback for recording state
        updatePanelForRecordingState(active: true)
        
        do {
            try speechManager.startListening()
        } catch {
            Logger.error("Failed to start Whisper transcription: \(error.localizedDescription)", module: "Speech")
            updatePanelForRecordingState(active: false)
        }
    }

    func stopWhisperTranscription() {
        Logger.info("Stopping Whisper transcription", module: "Speech")
        
        speechManager.stopListening()
        updatePanelForRecordingState(active: false)
    }
    
    func startWhisperTranscriptionRaw() {
        Logger.info("Starting raw Whisper transcription", module: "Speech")
        
        // Set flag for raw dictation
        useRawDictation = true
        
        // Visual feedback for recording state
        updatePanelForRecordingState(active: true)
        
        do {
            try speechManager.startListening()
        } catch {
            Logger.error("Failed to start raw Whisper transcription: \(error.localizedDescription)", module: "Speech")
            updatePanelForRecordingState(active: false)
            useRawDictation = false
        }
    }
    
    private func updatePanelForRecordingState(active: Bool) {
        DispatchQueue.main.async { [weak self] in
            if active {
                // Add visual feedback for recording (e.g., slight blue tint)
                self?.visualEffectView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
                self?.visualEffectView.layer?.borderWidth = 2.0
                // Show waveform animation for dictation/speech modes (not text entry)
                if !(self?.isTextEntryMode ?? false) {
                    self?.showWaveformAnimation()
                }
            } else {
                // Remove visual feedback
                self?.visualEffectView.layer?.borderColor = NSColor.clear.cgColor
                self?.visualEffectView.layer?.borderWidth = 0.0
                // Hide waveform animation
                self?.hideWaveformAnimation()
            }
        }
    }
    
    private func finalizeRawDictation(_ transcribedText: String) {
        Logger.info("Raw dictation completed: \(transcribedText)", module: "Speech")
        
        DispatchQueue.main.async { [weak self] in
            // Copy raw transcription directly to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcribedText, forType: .string)

            Logger.debug("Raw transcription copied to clipboard", module: "Speech")
            
            // Automatically paste the transcription at current cursor position
            self?.pasteResponseAtCursor()
            
            // Reset panel state
            self?.updatePanelForRecordingState(active: false)
            
            // Reset the flag for next use
            self?.useRawDictation = false
            
            // Note: pasteResponseAtCursor will hide the voice notch (Processing state)
        }
    }
    
    private func logCompletePrompt(transcribedText: String, context: String?) async {
        let canUseOpenAI = await MainActor.run { FeatureEntitlementStore.shared.canUseOpenAI }
        let modelType = canUseOpenAI ? "OPENAI" : "FOUNDATION MODELS"

        // Get the actual system instructions being used (with user info embedded)
        let systemInstructions = canUseOpenAI
            ? LLMRouter.shared.getSystemInstructions()
            : FoundationModelsManager.shared.getSystemInstructions()

        Logger.debug("COMPLETE \(modelType) PROMPT - System Instructions: \(systemInstructions.prefix(200))...", module: "LLM")

        // Memory context is stored but not added to prompts
        // (Memory system continues to work for storage but doesn't influence responses)

        // Get conversation history
        let memoryTurns = ConversationMemory.shared.getRecentTurns(maxPairs: 6, withinMinutes: 3)
        if !memoryTurns.isEmpty {
            Logger.debug("Conversation history: \(memoryTurns.count) turns", module: "LLM")
        }

        // Show the actual prompt structure
        if let context = context, !context.isEmpty {
            Logger.info("Processing with context (\(context.count) chars), request: \(transcribedText)", module: "LLM")
        } else {
            Logger.info("Processing prompt: \(transcribedText)", module: "LLM")
        }
    }
    
    private func processTranscribedTextWithFoundationModels(_ transcribedText: String) {
        // NOTE: Auth/tier checks are now handled by FeatureGateway via LLMRouter.
        // FeatureGateway will trigger appropriate UI (login/upgrade prompt) if access is denied.

        // Clear previous response to prepare for new generation
        Task { @MainActor in
            LLMSessionStore.shared.clearResponse()
        }

        // Visual feedback for processing state
        updatePanelForProcessingState(active: true)

        // Mark that AI processing has started and enter Thinking State
        isProcessingWithAI = true
        showThinkingState()

        // Expand window early to show streaming response
        expandWindowForResponseBubble()

        Task {
            do {
                // Log the complete prompt that will be sent to LLM
                await logCompletePrompt(transcribedText: transcribedText, context: contextText)

                // Check if MCP tools are connected - use non-streaming for tool support
                let hasTools = MCPManager.shared.hasConnectedServers

                if hasTools {
                    // Non-streaming path: MCP tool calling requires complete response
                    Logger.info("🔧 Using non-streaming path (MCP tools connected)", module: "LLM")
                    
                    // Create tool confirmation handler
                    let toolConfirmationHandler: OpenAIServiceImpl.ToolCallConfirmationHandler = { [weak self] toolCall in
                        // Auto-approve read-only tools (get, list, search operations)
                        let readOnlyToolPrefixes = ["linear_get", "linear_list", "calendar_list", "calendar_get"]
                        let isReadOnly = readOnlyToolPrefixes.contains { toolCall.function.name.hasPrefix($0) }
                        
                        if isReadOnly {
                            Logger.info("🔓 Auto-approving read-only tool: \(toolCall.function.name)", module: "LLM")
                            return toolCall
                        }
                        
                        // Show tool confirmation in notch and wait for user decision for write operations
                        return await withCheckedContinuation { continuation in
                            Task { @MainActor in
                                NotchManager.shared.showToolConfirmation(
                                    toolCall: toolCall,
                                    onApproved: { confirmedToolCall in
                                        continuation.resume(returning: confirmedToolCall)
                                    },
                                    onCancelled: {
                                        continuation.resume(returning: nil)
                                    }
                                )
                            }
                        }
                    }
                    
                    let response = try await LLMRouter.shared.processQuery(
                        transcribedText,
                        context: contextText,
                        toolConfirmationHandler: toolConfirmationHandler
                    )
                    await handleCompleteResponse(response, transcribedText: transcribedText)
                } else {
                    // Streaming path: real-time text display
                    Logger.info("📡 Using streaming path", module: "LLM")
                    let stream = try await LLMRouter.shared.processQueryStreaming(transcribedText, context: contextText)

                    await MainActor.run {
                        Task {
                            await LLMSessionStore.shared.generateFromStream(stream) { [weak self] finalText in
                                Task { @MainActor in
                                    self?.handleCompleteResponse(finalText, transcribedText: transcribedText)
                                }
                            }
                        }
                    }
                }

            } catch {
                DispatchQueue.main.async { [weak self] in
                    Logger.error("Error processing with Foundation Models: \(error.localizedDescription)", module: "LLM")
                    self?.updatePanelForProcessingState(active: false)
                    self?.isProcessingWithAI = false
                    self?.shouldCloseAfterAIResponse = false
                    self?.hideThinkingState()
                    // Hide the voice notch on error
                    Task { @MainActor in
                        NotchManager.shared.hideVoiceNotch()
                    }
                }
            }
        }
    }

    /// Handle complete LLM response (called from both streaming and non-streaming paths)
    @MainActor
    private func handleCompleteResponse(_ response: String, transcribedText: String) {
        // Log the response
        Logger.info("LLM response received (\(response.count) chars)", module: "LLM")
        Logger.debug("LLM RESPONSE: \(response)", module: "LLM")

        // Store in rolling memory
        ConversationMemory.shared.addTurn(userText: transcribedText, assistantText: response)

        // Update LLMSessionStore with the response to display in bubble (for non-streaming path)
        LLMSessionStore.shared.setStreamedText(response)

        // Single-paste guard per interaction
        if let _ = currentInteractionId, !hasPastedForCurrentInteraction {
            hasPastedForCurrentInteraction = true
            // Copy response to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(response, forType: .string)
            Logger.debug("LLM response copied to clipboard", module: "LLM")

            // Store reference to window controller before closing
            let windowController = view.window?.windowController as? FloatingWindowController

            // Delay closing the window to show the response bubble
            let responseDisplayDelay: TimeInterval = 3.0
            Logger.debug("Showing response bubble for \(responseDisplayDelay)s before closing", module: "FloatingVC")

            DispatchQueue.main.asyncAfter(deadline: .now() + responseDisplayDelay) { [weak self] in
                // Restore window size before closing
                self?.restoreWindowFromResponseBubble()

                // Small delay to let window animate back, then close
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    // Close the window - this will restore focus via hideWindow()
                    windowController?.hideWindow()

                    Logger.debug("Closed popup after response display, waiting for focus to restore, then pasting", module: "FloatingVC")

                    // Wait a bit for focus to restore
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.pasteResponseAtCursor()
                    }
                }
            }
        } else {
            Logger.debug("Skipping duplicate paste for this interaction", module: "FloatingVC")
        }

        // Reset panel state and AI processing flag, exit Thinking State
        updatePanelForProcessingState(active: false)
        isProcessingWithAI = false
        shouldCloseAfterAIResponse = false
        hideThinkingState()

        // Fire-and-forget long-term memory extraction and update
        Task {
            let convoChunk = MemoryRetriever.buildConversationChunk(
                previousTurns: ConversationMemory.shared.getRecentTurns(maxPairs: 6, withinMinutes: 3),
                currentUser: transcribedText,
                currentAssistant: response
            )
            do {
                let extracted = try await FoundationModelsManager.shared.extractMemoryFacts(from: convoChunk)
                let (incomingBig, incomingSmall) = FoundationModelsManager.shared.convertToMemoryFacts(extracted)
                MemoryStore.shared.update(with: incomingBig, newSmallFacts: incomingSmall)
                Logger.debug("Long-term memory updated: \(incomingBig.count) big facts, \(incomingSmall.count) small facts", module: "Memory")
            } catch {
                Logger.error("Long-term memory extraction failed: \(error.localizedDescription)", module: "Memory")
            }
        }
    }

    private func pasteResponseAtCursor() {
        // Simulate Cmd+V to paste the response at the current cursor position
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Create Cmd+V key event
        let cmdVEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        cmdVEvent?.flags = .maskCommand
        
        // Post the event
        cmdVEvent?.post(tap: .cghidEventTap)
        
        // Create key up event
        let cmdVEventUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        cmdVEventUp?.flags = .maskCommand
        
        // Post the key up event
        cmdVEventUp?.post(tap: .cghidEventTap)

        Logger.debug("Automatically pasted response at cursor position", module: "FloatingVC")
        
        // Hide the voice notch now that processing is complete and pasted
        Task { @MainActor in
            NotchManager.shared.hideVoiceNotch()
        }
    }

    // MARK: - Transcription Filtering
    private func isEmptyOrPunctuationOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // If there are any alphanumeric characters, treat as meaningful
        if trimmed.rangeOfCharacter(from: .alphanumerics) != nil { return false }
        // Otherwise, likely punctuation/symbols only
        return true
    }
    
    private func updatePanelForProcessingState(active: Bool) {
        DispatchQueue.main.async { [weak self] in
            if active {
                // Add visual feedback for processing (e.g., slight yellow tint)
                self?.visualEffectView.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.3).cgColor
                self?.visualEffectView.layer?.borderWidth = 2.0
                // Show waveform animation for processing state (not text entry)
                if !(self?.isTextEntryMode ?? false) {
                    self?.showWaveformAnimation()
                }
            } else {
                // Remove visual feedback
                self?.visualEffectView.layer?.borderColor = NSColor.clear.cgColor
                self?.visualEffectView.layer?.borderWidth = 0.0
                // Hide waveform animation
                self?.hideWaveformAnimation()
            }
        }
    }
    
    // MARK: - Waveform Animation
    private func showWaveformAnimation() {
        // Remove existing waveform if any
        hideWaveformAnimation()
        
        // Hide clippy-4 image when showing waveform (speech modes)
        hideClippy4Image()
        
        // Create waveform animation view
        let waveformView = WaveformAnimationView(panelSize: panelSize)
        waveformHostingView = NSHostingView(rootView: waveformView)
        
        guard let hostingView = waveformHostingView else { return }
        
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Add to container view
        containerView.addSubview(hostingView)
        
        // Position waveform animation 10% right and 10% down from clippy center
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: clippyImageView.centerXAnchor, constant: panelSize * 0.1),
            hostingView.centerYAnchor.constraint(equalTo: clippyImageView.centerYAnchor, constant: panelSize * 0.1),
            hostingView.widthAnchor.constraint(equalToConstant: 40), // Fixed width for waveform
            hostingView.heightAnchor.constraint(equalToConstant: panelSize * 0.4) // Height based on panel size
        ])
        
        // Place waveform behind clippy image
        hostingView.layer?.zPosition = -1
    }
    
    private func hideWaveformAnimation() {
        waveformHostingView?.removeFromSuperview()
        waveformHostingView = nil
    }
    
    // MARK: - Clippy-4 Image Management
    private func showClippy4Image() {
        DispatchQueue.main.async { [weak self] in
            self?.clippy4ImageView?.isHidden = false
        }
    }
    
    private func hideClippy4Image() {
        DispatchQueue.main.async { [weak self] in
            self?.clippy4ImageView?.isHidden = true
        }
    }
    
    // MARK: - Clippy Hover Animation
    private func startClippyHoverAnimation() {
        // Stop any existing animation
        stopClippyHoverAnimation()
        
        // Make clippy 5% smaller
        let originalSize = panelSize
        let smallerSize = originalSize * 0.95
        
        // Update constraints to make it 5% smaller
        clippyWidthConstraint?.constant = smallerSize
        clippyHeightConstraint?.constant = smallerSize
        
        // Start the bouncy hover animation
        var animationPhase: CGFloat = 0
        let animationDuration: TimeInterval = 8.0 // Much slower 8-second cycle
        let maxVerticalOffset: CGFloat = panelSize * 0.02 // Much smaller movement - 2% of panel size
        
        clippyHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Create a very subtle, smooth swaying motion using a single sine wave
            // Use a continuous phase that never resets to avoid flicker
            let phase = animationPhase * 2 * .pi
            
            // Use a single, smooth sine wave for gentle movement
            let verticalOffset = sin(phase) * maxVerticalOffset
            
            // Apply the transform to create the hover effect
            let transform = CGAffineTransform(translationX: 0, y: verticalOffset)
            self.clippyImageView.layer?.setAffineTransform(transform)
            
            // Update animation phase continuously without resetting
            animationPhase += 0.016 / animationDuration
            // Keep phase in 0-1 range but don't reset to 0 to avoid flicker
            if animationPhase >= 1.0 {
                animationPhase -= 1.0
            }
        }
    }
    
    private func stopClippyHoverAnimation() {
        clippyHoverTimer?.invalidate()
        clippyHoverTimer = nil
        
        // Reset transform
        clippyImageView.layer?.setAffineTransform(.identity)
        
        // Reset to original size
        clippyWidthConstraint?.constant = panelSize
        clippyHeightConstraint?.constant = panelSize
    }
    
    // Public methods to control hover animation from FloatingWindowController
    func startHoverAnimation() {
        startClippyHoverAnimation()
    }
    
    func stopHoverAnimation() {
        stopClippyHoverAnimation()
    }

    // MARK: - Cleanup
    func cleanup() {
        speechManager?.cleanup()
    }

    // MARK: - Action Cancellation

    /// Cancel all currently active operations (transcription, LLM generation, etc.)
    /// Called when the window is dismissed prematurely
    func cancelCurrentAction() {
        Logger.info("🛑 FloatingVC: Cancelling current action", module: "FloatingVC")

        // Cancel any ongoing LLM generation (streaming or regular)
        LLMSessionStore.shared.cancelGeneration()
        LLMSessionStore.shared.clearResponse()

        // Cancel transcription if active
        if speechManager?.isInStreamingMode() == true {
            speechManager?.stopStreamingListening()
        }
        TranscriptionStore.shared.cancelRecording()

        // Reset processing state
        isProcessingWithAI = false
        updatePanelForProcessingState(active: false)
        hideThinkingState()

        Logger.info("✅ FloatingVC: Current action cancelled", module: "FloatingVC")
    }

    // MARK: - Thinking State Management
    private func showThinkingState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure thinking image size matches clippy size before showing
            if let clippyWidth = self.clippyWidthConstraint?.constant,
               let clippyHeight = self.clippyHeightConstraint?.constant {
                self.clippyThinkingWidthConstraint?.constant = clippyWidth
                self.clippyThinkingHeightConstraint?.constant = clippyHeight
            }
            
            // Randomly select a thinking variant
            let variants: [ThinkingVariant] = [.static1, .static2, .static3, .animated4, .animated5]
            let selectedVariant = variants.randomElement() ?? .static1
            self.currentThinkingVariant = selectedVariant
            
            // Load and show the initial thinking image based on variant
            switch selectedVariant {
            case .static1:
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(1)
                Logger.debug("Entered Thinking State - showing Clippy Thinking 1 (static)", module: "UI")
            case .static2:
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(2)
                Logger.debug("Entered Thinking State - showing Clippy Thinking 2 (static)", module: "UI")
            case .static3:
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(3)
                Logger.debug("Entered Thinking State - showing Clippy Thinking 3 (static)", module: "UI")
            case .animated4:
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(4, frame: 1)
                Logger.debug("Entered Thinking State - showing Clippy Thinking 4 (animated)", module: "UI")
                self.startThinking4Animation()
            case .animated5:
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(5, frame: 1)
                Logger.debug("Entered Thinking State - showing Clippy Thinking 5 (animated)", module: "UI")
                self.startThinking5Animation()
            }
            
            // Hide the main clippy image
            self.clippyImageView?.isHidden = true
            // Show the thinking image
            self.clippyThinkingImageView?.isHidden = false
        }
    }
    
    private func hideThinkingState() {
        DispatchQueue.main.async { [weak self] in
            // Stop any animation timers
            self?.thinkingAnimationTimer?.invalidate()
            self?.thinkingAnimationTimer = nil
            self?.currentThinkingVariant = nil
            
            // Hide the thinking image
            self?.clippyThinkingImageView?.isHidden = true
            // Show the main clippy image
            self?.clippyImageView?.isHidden = false
            Logger.debug("Exited Thinking State - showing normal Clippy", module: "UI")
        }
    }
    
    private func startThinking4Animation() {
        // Switch between 4-1 and 4-2 every 1 second
        var isFrame1 = true
        thinkingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            DispatchQueue.main.async {
                isFrame1.toggle()
                let frame = isFrame1 ? 1 : 2
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(4, frame: frame)
            }
        }
        // Add to common run loop modes so it works even when scrolling/interacting
        RunLoop.current.add(thinkingAnimationTimer!, forMode: .common)
    }
    
    private func startThinking5Animation() {
        // Cycle through 5-1, 5-2, 5-3 every 500ms
        var currentFrame = 1
        thinkingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            DispatchQueue.main.async {
                currentFrame += 1
                if currentFrame > 3 {
                    currentFrame = 1
                }
                self.clippyThinkingImageView.image = self.loadClippyThinkingImage(5, frame: currentFrame)
            }
        }
        // Add to common run loop modes so it works even when scrolling/interacting
        RunLoop.current.add(thinkingAnimationTimer!, forMode: .common)
    }
    
    
    // MARK: - Speech Manager Callbacks
    // Foundation Models integration for intelligent text processing
}

// MARK: - Image Loading
private extension FloatingViewController {
    func loadClippyImage() -> NSImage? {
        let imageName = "Clippy"
        guard let image = NSImage(named: imageName) else {
            Logger.error("Failed to load image: \(imageName)", module: "Assets")
            return nil
        }
        Logger.debug("Loaded image: \(imageName) (\(Int(image.size.width))x\(Int(image.size.height)))", module: "Assets")
        return image
    }

    func loadClippy4Image() -> NSImage? {
        let imageName = "Yellowdot"
        guard let image = NSImage(named: imageName) else {
            Logger.error("Failed to load image: \(imageName)", module: "Assets")
            return nil
        }
        Logger.debug("Loaded image: \(imageName) (\(Int(image.size.width))x\(Int(image.size.height)))", module: "Assets")
        return image
    }

    func loadClippyThinkingImage(_ number: Int, frame: Int = 1) -> NSImage? {
        // Build the image name based on number and frame
        let imageName: String
        if number == 4 || number == 5 {
            // For animated sequences, use format: clippy-thinking-4-1, clippy-thinking-4-2, etc.
            imageName = "clippy-thinking-\(number)-\(frame)"
        } else {
            // For static images, just use the number
            imageName = "clippy-thinking-\(number)"
        }
        guard let image = NSImage(named: imageName) else {
            Logger.error("Failed to load image: \(imageName)", module: "Assets")
            return nil
        }
        Logger.debug("Loaded image: \(imageName) (\(Int(image.size.width))x\(Int(image.size.height)))", module: "Assets")
        return image
    }
    
    func updateClippySize() {
        guard let image = clippyImageView.image else { return }
        containerView.layoutSubtreeIfNeeded()
        let containerSize = containerView.bounds.size
        guard containerSize.width > 0 && containerSize.height > 0 && image.size.height > 0 else { return }
        
        // Set clippy to panelSize x panelSize
        let targetHeight = panelSize  // panelSize height
        let targetWidth = panelSize  // panelSize width
        
        // Update clippy-2 image size
        clippyWidthConstraint?.constant = targetWidth
        clippyHeightConstraint?.constant = targetHeight
        
        // Update thinking image size (same as clippy-2)
        clippyThinkingWidthConstraint?.constant = targetWidth
        clippyThinkingHeightConstraint?.constant = targetHeight
        
        // Update clippy-4 image size (same as clippy-2)
        clippy4WidthConstraint?.constant = targetWidth
        clippy4HeightConstraint?.constant = targetHeight
        
        // Commented out circular corner radius since we removed the circular design
        // Keep the circle perfectly round on any potential resize
        // let radius = circleDiameter / 2
        // visualEffectView.layer?.cornerRadius = radius
        // if let overlayLayer = containerView.subviews.first?.layer { // overlayView is the first subview added
        //     overlayLayer.cornerRadius = radius
        //     overlayLayer.masksToBounds = true
        // }
    }
}

// MARK: - Layout
extension FloatingViewController {
    override func viewDidLayout() {
        super.viewDidLayout()
        updateClippySize()
    }
}

// MARK: - Mouse Event Handling for Dragging
extension FloatingViewController {
    override func mouseDown(with event: NSEvent) {
        // Start dragging
        guard let window = view.window else { return }
        
        let windowController = window.windowController as? FloatingWindowController
        windowController?.startDragging(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Continue dragging
        guard let window = view.window else { return }
        
        let windowController = window.windowController as? FloatingWindowController
        windowController?.continueDragging(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        // End dragging
        guard let window = view.window else { return }
        
        let windowController = window.windowController as? FloatingWindowController
        windowController?.endDragging()
    }
    
}

// MARK: - Notification-style panel with minimal UI
// No text field delegates needed for this simple panel

// MARK: - Foundation Models Integration
// Data structures moved to FoundationModelsManager.swift

// MARK: - Rolling Conversation Memory (6 pairs, 15-minute TTL)
struct ConversationTurn {
    let userText: String
    let assistantText: String
    let timestamp: Date
}

// MARK: - Long-Term Memory Models and Config
struct BigFact: Codable, Hashable {
    var factText: String
    var importanceScore: Double
    var lastUpdated: Date
}

struct SmallFact: Codable, Hashable {
    var factText: String
    var importanceScore: Double
    var timestamp: Date
}

struct MemorySnapshot: Codable {
    var bigFacts: [BigFact]
    var smallFacts: [SmallFact]
    var lastMaintenance: Date?
}

enum MemoryConfig {
    static let bigFactsMinImportance: Double = 0.8
    static let bigFactsUpdateConfidence: Double = 0.9
    static let bigFactsMaxWords: Int = 200

    static let smallFactsMinImportance: Double = 0.6
    static let smallFactsTTL: TimeInterval = 90 * 24 * 60 * 60
    static let smallFactsTotalMaxWords: Int = 500

    static let maxSmallFactsForPrompt: Int = 8
}

struct IncomingBigFact {
    let factText: String
    let importanceScore: Double
    let updateConfidence: Double
}

struct IncomingSmallFact {
    let factText: String
    let importanceScore: Double
}

final class MemoryStore {
    static let shared = MemoryStore()

    private let queue = DispatchQueue(label: "MemoryStore.queue")
    private let fileURL: URL
    private var snapshot: MemorySnapshot

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("homie", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("memory.json")
        self.snapshot = MemorySnapshot(bigFacts: [], smallFacts: [], lastMaintenance: nil)
        loadOrInitialize()
        pruneAndEnforceLimits()
        save()
    }

    func getSnapshot() -> MemorySnapshot { queue.sync { snapshot } }

    func retrieveForPrompt(query: String?, recentTopicHint: String?) -> (big: [BigFact], small: [SmallFact]) {
        queue.sync {
            let big = snapshot.bigFacts
            let small = MemoryRetriever.selectSmallFacts(for: query, hint: recentTopicHint, from: snapshot.smallFacts, bigFacts: big)
            return (big, small)
        }
    }

    func update(with newBigFacts: [IncomingBigFact], newSmallFacts: [IncomingSmallFact]) {
        queue.sync {
            applyBigFacts(newBigFacts)
            applySmallFacts(newSmallFacts)
            pruneAndEnforceLimits()
            save()
        }
    }

    private func loadOrInitialize() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let loaded = try? JSONDecoder().decode(MemorySnapshot.self, from: data) {
            snapshot = loaded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL)
        }
    }

    private func applyBigFacts(_ incoming: [IncomingBigFact]) {
        let now = Date()
        for fact in incoming where fact.importanceScore >= MemoryConfig.bigFactsMinImportance {
            let normalizedIncoming = MemoryRetriever.normalizeFact(fact.factText)
            let key = MemoryRetriever.factKey(from: normalizedIncoming)
            if let idx = snapshot.bigFacts.firstIndex(where: { MemoryRetriever.factKey(from: MemoryRetriever.normalizeFact($0.factText)) == key }) {
                if fact.updateConfidence >= MemoryConfig.bigFactsUpdateConfidence {
                    snapshot.bigFacts[idx] = BigFact(factText: normalizedIncoming, importanceScore: fact.importanceScore, lastUpdated: now)
                }
            } else {
                // Avoid exact-text duplicates after normalization
                if !snapshot.bigFacts.contains(where: { MemoryRetriever.normalizeFact($0.factText) == normalizedIncoming }) {
                    snapshot.bigFacts.append(BigFact(factText: normalizedIncoming, importanceScore: fact.importanceScore, lastUpdated: now))
                }
            }
        }
    }

    private func applySmallFacts(_ incoming: [IncomingSmallFact]) {
        let now = Date()
        for fact in incoming where fact.importanceScore >= MemoryConfig.smallFactsMinImportance {
            // Skip small facts that directly conflict with existing big facts
            if MemoryRetriever.conflictsWithBigFacts(smallText: fact.factText, bigFacts: snapshot.bigFacts) {
                continue
            }
            snapshot.smallFacts.append(SmallFact(factText: fact.factText, importanceScore: fact.importanceScore, timestamp: now))
        }
    }

    private func pruneAndEnforceLimits() {
        let cutoff = Date().addingTimeInterval(-MemoryConfig.smallFactsTTL)
        snapshot.smallFacts.removeAll { $0.timestamp < cutoff }
        enforceWordBudgetForBigFacts()
        collapseNearDuplicateSmallFactsLocked()
        enforceWordBudgetForSmallFacts()
    }

    private func collapseNearDuplicateSmallFactsLocked() {
        guard !snapshot.smallFacts.isEmpty else { return }
        // Sort by (importance desc, timestamp desc)
        let sorted = snapshot.smallFacts.sorted { lhs, rhs in
            if lhs.importanceScore == rhs.importanceScore {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.importanceScore > rhs.importanceScore
        }
        var kept: [SmallFact] = []
        for sf in sorted {
            if kept.contains(where: { MemoryRetriever.isNearDuplicate($0.factText, sf.factText) }) {
                continue
            }
            kept.append(sf)
        }
        snapshot.smallFacts = kept
    }

    private func enforceWordBudgetForBigFacts() {
        while MemoryRetriever.totalWords(of: snapshot.bigFacts.map { $0.factText }) > MemoryConfig.bigFactsMaxWords {
            if snapshot.bigFacts.isEmpty { break }
            if let idx = snapshot.bigFacts.enumerated().min(by: { (a, b) in
                if a.element.importanceScore == b.element.importanceScore {
                    return a.element.lastUpdated < b.element.lastUpdated
                }
                return a.element.importanceScore < b.element.importanceScore
            })?.offset {
                snapshot.bigFacts.remove(at: idx)
            } else {
                snapshot.bigFacts.removeFirst()
            }
        }
    }

    private func enforceWordBudgetForSmallFacts() {
        while MemoryRetriever.totalWords(of: snapshot.smallFacts.map { $0.factText }) > MemoryConfig.smallFactsTotalMaxWords {
            if snapshot.smallFacts.isEmpty { break }
            snapshot.smallFacts.sort { $0.timestamp < $1.timestamp }
            snapshot.smallFacts.removeFirst()
        }
    }
}

// ExtractedFacts moved to FoundationModelsManager.swift

// MemoryExtractor moved to FoundationModelsManager.swift

// Retriever and utilities
enum MemoryRetriever {
    static func selectSmallFacts(for query: String?, hint: String?, from facts: [SmallFact], bigFacts: [BigFact]) -> [SmallFact] {
        var candidates = facts
        // Drop any small facts that contradict big facts
        candidates.removeAll { conflictsWithBigFacts(smallText: $0.factText, bigFacts: bigFacts) }
        if let q = query, !q.isEmpty {
            let qTokens = tokenize(q + " " + (hint ?? ""))
            candidates.sort { score($0.factText, qTokens) > score($1.factText, qTokens) }
        } else {
            candidates.sort { $0.timestamp > $1.timestamp }
        }
        // Collapse near duplicates before capping
        var deduped: [SmallFact] = []
        for sf in candidates {
            if deduped.contains(where: { isNearDuplicate($0.factText, sf.factText) }) { continue }
            deduped.append(sf)
        }
        return Array(deduped.prefix(MemoryConfig.maxSmallFactsForPrompt))
    }

    static func buildMemoryContextBlock(bigFacts: [BigFact], smallFacts: [SmallFact]) -> String {
        var lines: [String] = []
        if !bigFacts.isEmpty {
            lines.append("[Permanent Facts]")
            for f in bigFacts { lines.append("- \(f.factText)") }
            lines.append("")
        }
        if !smallFacts.isEmpty {
            lines.append("[Relevant Episodic Facts]")
            for f in smallFacts { lines.append("- \(f.factText)") }
        }
        return lines.joined(separator: "\n")
    }

    static func buildConversationChunk(previousTurns: [ConversationTurn], currentUser: String, currentAssistant: String) -> String {
        var lines: [String] = []
        for t in previousTurns {
            lines.append("User: \(t.userText)")
            lines.append("Assistant: \(t.assistantText)")
        }
        lines.append("User: \(currentUser)")
        lines.append("Assistant: \(currentAssistant)")
        return lines.joined(separator: "\n")
    }

    static func buildExtractionPrompt(withConversation chunk: String) -> String {
        return """
You are an assistant that analyzes a conversation between a user and an AI, and extracts facts about the USER for long-term memory.

You must output ONLY valid JSON in the following structure:
{
  "new_big_facts": [ { "fact_text": "string", "importance_score": 0.0, "update_confidence": 0.0 } ],
  "new_small_facts": [ { "fact_text": "string", "importance_score": 0.0 } ]
}

Rules:
1. Big facts = stable, identity-defining, rarely changing information about the USER.
2. Small facts = short-term, contextual, or time-sensitive information about the USER.
3. Ignore facts about other people unless directly relevant to the USER.
4. Only extract facts explicitly stated or with very high certainty.
5. Assign reasonable importance_score (0.0–1.0). For big facts include update_confidence (0.0–1.0).
6. Be concise — fact_text is one sentence or shorter.
7. If no facts are found, return empty lists.

Conversation:
---
\(chunk)
---
"""
    }

    static func totalWords(of texts: [String]) -> Int { texts.reduce(0) { $0 + wordCount($1) } }
    static func wordCount(_ text: String) -> Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    static func factKey(from text: String) -> String {
        let lower = text.lowercased()
        if let r = lower.range(of: ":") { return String(lower[..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
        if let r = lower.range(of: " is ") { return String(lower[..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
        let parts = lower.split(separator: " ")
        return parts.prefix(2).joined(separator: " ")
    }

    static func conflictsWithBigFacts(smallText: String, bigFacts: [BigFact]) -> Bool {
        // Heuristic: if smallText indicates a value for a canonical key and differs from big fact's value, treat as conflict
        let sNorm = normalizeFact(smallText)
        if let (sKey, sVal) = canonicalKeyValue(from: sNorm) {
            for bf in bigFacts {
                let bNorm = normalizeFact(bf.factText)
                if let (bKey, bVal) = canonicalKeyValue(from: bNorm), bKey == sKey, !valuesMatch(sVal, bVal) {
                    return true
                }
            }
        }
        return false
    }

    static func canonicalKeyValue(from text: String) -> (String, String)? {
        // Simple patterns: "name is X", "user name: X", "email is X", "respond in language X"
        let lower = text.lowercased()
        // name
        if lower.contains("name") {
            if let val = valueAfterColonOrIs(lower) { return ("name", val) }
        }
        // email
        if lower.contains("email") {
            if let val = valueAfterColonOrIs(lower) { return ("email", val) }
        }
        // language preference
        if lower.contains("language") || lower.contains("respond in") {
            if let val = valueAfterColonOrIs(lower) { return ("language", val) }
        }
        return nil
    }

    private static func valueAfterColonOrIs(_ text: String) -> String? {
        if let r = text.range(of: ":") {
            let val = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
            return val
        }
        if let r = text.range(of: " is ") {
            let val = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
            return val
        }
        return nil
    }

    static func valuesMatch(_ a: String, _ b: String) -> Bool {
        return normalizeFact(a) == normalizeFact(b)
    }

    static func isNearDuplicate(_ a: String, _ b: String) -> Bool {
        let ta = tokenize(normalizeFact(a))
        let tb = tokenize(normalizeFact(b))
        if ta == tb { return true }
        // Jaccard similarity heuristic
        let inter = ta.intersection(tb).count
        let union = ta.union(tb).count
        if union == 0 { return true }
        let jaccard = Double(inter) / Double(union)
        return jaccard >= 0.8
    }

    static func normalizeFact(_ text: String) -> String {
        // Normalize common patterns to reduce duplicates like "User's name is Max" vs "Name is Max"
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "User's ", with: "", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "The user's ", with: "", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "My ", with: "", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "Preferred ", with: "", options: .caseInsensitive)
        // Collapse multiple spaces
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = text.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
        let stop: Set<String> = ["the","a","an","and","or","to","of","in","on","for","with","is","are","it","this","that","i","you","he","she","they","we","at","as","by","be","from"]
        return Set(tokens.filter { !stop.contains($0) })
    }

    private static func score(_ text: String, _ qTokens: Set<String>) -> Int {
        let tTokens = tokenize(text)
        return tTokens.intersection(qTokens).count
    }
}

final class ConversationMemory {
    static let shared = ConversationMemory()
    private init() {}
    
    private let queue = DispatchQueue(label: "ConversationMemory.queue")
    private var turns: [ConversationTurn] = []
    private let ttlSeconds: TimeInterval = 15 * 60
    private let maxPairs: Int = 6
    
    func addTurn(userText: String, assistantText: String, now: Date = Date()) {
        queue.sync {
            pruneExpiredLocked(now: now)
            turns.append(ConversationTurn(userText: userText, assistantText: assistantText, timestamp: now))
            if turns.count > maxPairs {
                let overflow = turns.count - maxPairs
                turns.removeFirst(overflow)
            }
        }
    }
    
    func getRecentTurns(maxPairs: Int = 6, withinMinutes: Int = 3, now: Date = Date()) -> [ConversationTurn] {
        queue.sync {
            pruneExpiredLocked(now: now)
            let limit = min(maxPairs, self.maxPairs)
            let start = max(0, turns.count - limit)
            return Array(turns[start..<turns.count])
        }
    }
    
    private func pruneExpiredLocked(now: Date) {
        let cutoff = now.addingTimeInterval(-ttlSeconds)
        if let firstValid = turns.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValid > 0 {
                turns.removeFirst(firstValid)
            }
        } else {
            turns.removeAll()
        }
    }
}



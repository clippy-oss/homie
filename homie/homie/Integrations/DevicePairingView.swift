//
//  DevicePairingView.swift
//  homie
//
//  Device pairing view supporting both QR code and phone code pairing.
//  Observes ServiceIntegrationsStore for state; delegates actions to store.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Pairing Method

enum PairingMethod: String, CaseIterable {
    case qrCode = "QR Code"
    case phoneCode = "Phone Number"
}

@available(macOS 15.0, *)
struct DevicePairingView: View {
    // MARK: - Dependencies

    let providerName: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    // MARK: - Store Observation

    @ObservedObject private var store: ServiceIntegrationsStore

    // MARK: - Local UI State

    @State private var selectedMethod: PairingMethod = .qrCode
    @State private var phoneNumber: String = ""

    // MARK: - Initialization

    init(
        providerName: String,
        store: ServiceIntegrationsStore = .shared,
        onSuccess: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.providerName = providerName
        self._store = ObservedObject(wrappedValue: store)
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 420, height: 550)
        .onChange(of: selectedMethod) { _, newMethod in
            handleMethodChange(newMethod)
        }
        .onDisappear {
            store.cancelWhatsAppPairing()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(providerName)")
                    .font(.headline)

                Text("Pair your device to enable messaging")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch store.whatsAppPairingState {
        case .success:
            successView
        case .starting:
            loadingView("Starting \(providerName) bridge...")
        default:
            pairingContentView
        }
    }

    @ViewBuilder
    private var pairingContentView: some View {
        VStack(spacing: 16) {
            Picker("Pairing Method", selection: $selectedMethod) {
                ForEach(PairingMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)

            if selectedMethod == .qrCode {
                qrCodeView
            } else {
                phoneCodeView
            }

            Spacer()
        }
    }

    // MARK: - QR Code View

    private var qrCodeView: some View {
        VStack(spacing: 16) {
            if let qrData = store.whatsAppPairingState.qrCodeData {
                qrCodeDisplay(qrData)
            } else if store.whatsAppPairingState.isLoading {
                loadingView("Loading QR code...")
                    .frame(height: 200)
            } else if let error = store.whatsAppPairingState.errorMessage {
                errorView(error) { store.startWhatsAppQRPairing() }
                    .frame(height: 200)
            } else {
                VStack(spacing: 12) {
                    Button("Start QR Pairing") {
                        store.startWhatsAppQRPairing()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .onAppear {
            if selectedMethod == .qrCode && store.whatsAppPairingState == .idle {
                store.startWhatsAppQRPairing()
            }
        }
    }

    private func qrCodeDisplay(_ qrData: String) -> some View {
        VStack(spacing: 12) {
            if let qrImage = generateQRCode(from: qrData) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(Color.white)
                    .cornerRadius(8)
            } else {
                // Fallback: Show error message when QR generation fails
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("QR code generation failed")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("Data length: \(qrData.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 200, height: 200)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Text("Scan this QR code with your phone")
                .font(.subheadline)
                .foregroundColor(.secondary)

            qrInstructionsView
        }
    }

    // MARK: - Phone Code View

    private var phoneCodeView: some View {
        VStack(spacing: 16) {
            if let code = store.whatsAppPairingState.pairingCode {
                pairingCodeDisplay(code)
            } else if store.whatsAppPairingState.isLoading {
                loadingView("Requesting pairing code...")
            } else {
                phoneNumberInput
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func pairingCodeDisplay(_ code: String) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on your phone:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(formatPairingCode(code))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .tracking(4)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

            phoneInstructionsView

            Button("Get New Code") {
                store.resetWhatsAppPairingState()
            }
            .buttonStyle(.bordered)
        }
    }

    private var phoneNumberInput: some View {
        VStack(spacing: 12) {
            Text("Enter your phone number with country code:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("+1234567890", text: $phoneNumber)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)

            Button(action: { store.startWhatsAppCodePairing(phoneNumber: phoneNumber) }) {
                Text("Get Pairing Code")
            }
            .buttonStyle(.borderedProminent)
            .disabled(phoneNumber.isEmpty)

            if let error = store.whatsAppPairingState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Successfully Connected!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your \(providerName) account is now linked.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if !store.whatsAppPairingState.isSuccess {
                Button("Cancel") {
                    store.cancelWhatsAppPairing()
                    onCancel()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if store.whatsAppPairingState.isSuccess {
                Button("Done") {
                    onSuccess()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Shared Components

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func errorView(_ message: String, retryAction: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Instructions Views

    private var qrInstructionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            instructionStep(1, "Open \(providerName) on your phone")
            instructionStep(2, "Go to Settings > Linked Devices")
            instructionStep(3, "Tap 'Link a Device'")
            instructionStep(4, "Scan this QR code")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var phoneInstructionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            instructionStep(1, "Open \(providerName) on your phone")
            instructionStep(2, "Go to Settings > Linked Devices")
            instructionStep(3, "Tap 'Link a Device' > 'Link with phone number'")
            instructionStep(4, "Enter the code shown above")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func handleMethodChange(_ method: PairingMethod) {
        store.resetWhatsAppPairingState()
        if method == .qrCode {
            store.startWhatsAppQRPairing()
        }
    }

    // MARK: - Helpers

    private func formatPairingCode(_ code: String) -> String {
        let cleaned = code.replacingOccurrences(of: "-", with: "")
        if cleaned.count == 8 {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 4)
            return "\(cleaned[..<index])-\(cleaned[index...])"
        }
        return code
    }

    private func generateQRCode(from string: String) -> NSImage? {
        // Debug: Log input
        Logger.info("QR Generation: Input string length: \(string.count)", module: "WhatsApp")
        if string.isEmpty {
            Logger.error("QR Generation: Empty string received!", module: "WhatsApp")
            return nil
        }
        Logger.debug("QR Generation: First 50 chars: \(string.prefix(50))", module: "WhatsApp")

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        // Convert string to data
        let data = Data(string.utf8)
        Logger.debug("QR Generation: Data size: \(data.count) bytes", module: "WhatsApp")

        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            Logger.error("QR Generation: CIFilter.outputImage is nil!", module: "WhatsApp")
            return nil
        }

        Logger.debug("QR Generation: CIImage size: \(outputImage.extent)", module: "WhatsApp")

        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            Logger.error("QR Generation: Failed to create CGImage", module: "WhatsApp")
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
        Logger.info("QR Generation: Success! Image size: \(nsImage.size)", module: "WhatsApp")
        return nsImage
    }
}

// MARK: - Preview

@available(macOS 15.0, *)
#Preview {
    DevicePairingView(
        providerName: "WhatsApp",
        onSuccess: {},
        onCancel: {}
    )
}

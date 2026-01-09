//
//  WhatsAppProcessManager.swift
//  homie
//
//  Manages the whatsapp-bridge subprocess lifecycle.
//  Handles starting, stopping, and monitoring the Go bridge process.
//

import Foundation

// MARK: - Configuration

/// Configuration for the WhatsApp bridge process
struct WhatsAppProcessConfiguration {
    let binaryPath: String
    let grpcAddress: String
    let databasePath: String

    static var `default`: WhatsAppProcessConfiguration {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let homieDir = appSupport.appendingPathComponent("homie", isDirectory: true)

        return WhatsAppProcessConfiguration(
            binaryPath: Bundle.main.bundlePath + "/Contents/Resources/whatsapp-bridge",
            grpcAddress: "127.0.0.1:50051",
            databasePath: homieDir.appendingPathComponent("whatsapp.db").path
        )
    }
}

// MARK: - Errors

/// Errors that can occur during process management
enum WhatsAppProcessError: LocalizedError {
    case binaryNotFound
    case startFailed(String)
    case readyTimeout
    case unexpectedExit(Int32)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "WhatsApp bridge binary not found"
        case .startFailed(let message):
            return "Failed to start WhatsApp bridge: \(message)"
        case .readyTimeout:
            return "WhatsApp bridge did not become ready within timeout"
        case .unexpectedExit(let code):
            return "WhatsApp bridge exited unexpectedly with code \(code)"
        }
    }
}

// MARK: - Process Manager

/// Manages the lifecycle of the whatsapp-bridge subprocess
final class WhatsAppProcessManager {

    // MARK: - Properties

    private let configuration: WhatsAppProcessConfiguration
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private let readyTimeout: TimeInterval = 30.0
    private let stopTimeout: TimeInterval = 5.0

    /// Whether the process is currently running
    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Initialization

    init(configuration: WhatsAppProcessConfiguration) {
        self.configuration = configuration
    }

    convenience init() {
        self.init(configuration: .default)
    }

    // MARK: - Lifecycle

    /// Start the subprocess and wait for it to become ready
    func start() async throws {
        Logger.info("Starting WhatsApp bridge process", module: "WhatsApp")

        // Check if binary exists
        guard FileManager.default.fileExists(atPath: configuration.binaryPath) else {
            Logger.error("Binary not found at path: \(configuration.binaryPath)", module: "WhatsApp")
            throw WhatsAppProcessError.binaryNotFound
        }

        // Stop any existing process
        if isRunning {
            Logger.info("Stopping existing process before starting new one", module: "WhatsApp")
            stop()
        }

        // Ensure database directory exists
        let databaseDir = (configuration.databasePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: databaseDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Setup pipes
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.binaryPath)
        process.arguments = ["-mode", "server"]
        process.environment = [
            "WA_GRPC_ADDRESS": configuration.grpcAddress,
            "WA_DATABASE_PATH": configuration.databasePath
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process

        // Setup stderr logging
        setupStderrLogging()

        // Start process
        do {
            try process.run()
            Logger.info("Process started with PID: \(process.processIdentifier)", module: "WhatsApp")
        } catch {
            Logger.error("Failed to start process: \(error.localizedDescription)", module: "WhatsApp")
            cleanup()
            throw WhatsAppProcessError.startFailed(error.localizedDescription)
        }

        // Wait for ready signal
        do {
            try await waitForReady()
            Logger.info("WhatsApp bridge is ready", module: "WhatsApp")
        } catch {
            Logger.error("Failed waiting for ready signal: \(error.localizedDescription)", module: "WhatsApp")
            stop()
            throw error
        }
    }

    /// Stop the subprocess gracefully
    func stop() {
        guard let process = process, process.isRunning else {
            Logger.debug("Process not running, nothing to stop", module: "WhatsApp")
            cleanup()
            return
        }

        Logger.info("Stopping WhatsApp bridge process (PID: \(process.processIdentifier))", module: "WhatsApp")

        // Send SIGTERM for graceful shutdown
        process.terminate()

        // Wait for graceful shutdown with timeout
        let deadline = Date().addingTimeInterval(stopTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Force kill if still running
        if process.isRunning {
            Logger.warning("Process did not terminate gracefully, force killing", module: "WhatsApp")
            process.interrupt()

            // Give it a moment to die
            Thread.sleep(forTimeInterval: 0.5)

            // If still running, use SIGKILL
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        Logger.info("WhatsApp bridge process stopped", module: "WhatsApp")
        cleanup()
    }

    // MARK: - Ready Signal

    /// Wait for the process to emit the "ready" signal on stdout
    func waitForReady() async throws {
        guard let stdoutPipe = stdoutPipe else {
            throw WhatsAppProcessError.startFailed("stdout pipe not configured")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            let resumeLock = NSLock()

            func safeResume(with result: Result<Void, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            // Setup timeout
            let timeoutWorkItem = DispatchWorkItem {
                safeResume(with: .failure(WhatsAppProcessError.readyTimeout))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + readyTimeout, execute: timeoutWorkItem)

            // Monitor stdout for "ready" line
            let fileHandle = stdoutPipe.fileHandleForReading
            fileHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData

                guard !data.isEmpty else {
                    // EOF - check if process has actually exited before accessing terminationStatus
                    if let process = self?.process, !process.isRunning {
                        let exitCode = process.terminationStatus
                        if exitCode != 0 {
                            timeoutWorkItem.cancel()
                            safeResume(with: .failure(WhatsAppProcessError.unexpectedExit(exitCode)))
                        }
                    }
                    return
                }

                if let output = String(data: data, encoding: .utf8) {
                    // Log stdout for debugging
                    for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                        Logger.debug("stdout: \(line)", module: "WhatsApp")

                        // Check for ready signal
                        if line.lowercased().contains("ready") {
                            timeoutWorkItem.cancel()
                            fileHandle.readabilityHandler = nil
                            safeResume(with: .success(()))
                            return
                        }
                    }
                }
            }

            // Monitor for unexpected process termination
            self.process?.terminationHandler = { process in
                timeoutWorkItem.cancel()
                fileHandle.readabilityHandler = nil
                safeResume(with: .failure(WhatsAppProcessError.unexpectedExit(process.terminationStatus)))
            }
        }
    }

    // MARK: - Private Helpers

    /// Setup stderr logging for debugging
    private func setupStderrLogging() {
        guard let stderrPipe = stderrPipe else { return }

        let fileHandle = stderrPipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else { return }

            for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                Logger.warning("stderr: \(line)", module: "WhatsApp")
            }
        }
    }

    /// Cleanup pipes and process reference
    private func cleanup() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
    }

    deinit {
        stop()
    }
}

//
//  WhatsAppProcessManager.swift
//  homie
//
//  Manages the whatsapp-bridge subprocess lifecycle.
//  Handles starting, stopping, and monitoring the Go bridge process.
//

import Foundation

// MARK: - Bridge Log Entry

/// Represents a structured JSON log entry from the whatsapp-bridge
private struct BridgeLogEntry: Codable {
    let time: String
    let level: String
    let module: String?
    let message: String

    // Optional fields for different log types
    let method: String?
    let durationMs: Int?
    let code: String?
    let error: String?
    let pid: Int?
    let database: String?
    let address: String?
    let sub: String?
    let stack: String?

    enum CodingKeys: String, CodingKey {
        case time, level, module, message, method, code, error, pid, database, address, sub, stack
        case durationMs = "duration_ms"
    }
}

// MARK: - Configuration

/// Configuration for the WhatsApp bridge process
struct WhatsAppProcessConfiguration {
    let binaryPath: String
    let grpcAddress: String
    let databasePath: String

    static var `default`: WhatsAppProcessConfiguration {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory not found - this should never happen on macOS")
        }

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

        // Clean up any orphaned processes from previous crashes
        cleanupOrphanedProcesses()

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
            "WA_DATABASE_PATH": configuration.databasePath,
            "WA_PARENT_PID": String(ProcessInfo.processInfo.processIdentifier)
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
    /// Note: This method blocks until the process terminates or timeout is reached.
    /// The blocking wait is performed on a background queue to avoid UI freezes.
    func stop() {
        guard let process = process, process.isRunning else {
            Logger.debug("Process not running, nothing to stop", module: "WhatsApp")
            cleanup()
            return
        }

        Logger.info("Stopping WhatsApp bridge process (PID: \(process.processIdentifier))", module: "WhatsApp")

        // Send SIGTERM for graceful shutdown
        process.terminate()

        // Wait for graceful shutdown on background queue to avoid blocking main thread
        let semaphore = DispatchSemaphore(value: 0)
        let capturedProcess = process
        let timeout = stopTimeout

        DispatchQueue.global(qos: .utility).async {
            let deadline = Date().addingTimeInterval(timeout)
            while capturedProcess.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            semaphore.signal()
        }

        // Wait for graceful shutdown with timeout
        _ = semaphore.wait(timeout: .now() + stopTimeout + 0.5)

        // Force kill if still running
        if process.isRunning {
            Logger.warning("Process did not terminate gracefully, force killing", module: "WhatsApp")
            process.interrupt()

            // Brief wait for interrupt to take effect
            let forceKillSemaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                forceKillSemaphore.signal()
            }
            _ = forceKillSemaphore.wait(timeout: .now() + 1.0)

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
                    // Process each line from stdout
                    for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                        // Check for ready signal first (plain text "ready" line)
                        if line.lowercased() == "ready" {
                            timeoutWorkItem.cancel()
                            fileHandle.readabilityHandler = nil
                            safeResume(with: .success(()))
                            return
                        }

                        // Parse and log the line (handles both JSON and plain text)
                        self?.parseBridgeLine(line, defaultLevel: .debug)
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

    /// Convert bridge log level string to Swift LogLevel
    private func logLevelFromBridge(_ level: String) -> LogLevel {
        let levelMappings: [String: LogLevel] = [
            "debug": .debug, "trace": .debug,
            "info": .info,
            "warn": .warning, "warning": .warning,
            "error": .error,
            "fatal": .critical, "panic": .critical
        ]
        return levelMappings[level.lowercased()] ?? .debug
    }

    /// Parse and log a line from the bridge, handling both JSON and plain text
    private func parseBridgeLine(_ line: String, defaultLevel: LogLevel) {
        // Try to parse as JSON log entry
        if let jsonData = line.data(using: .utf8),
           let entry = try? JSONDecoder().decode(BridgeLogEntry.self, from: jsonData) {
            let level = logLevelFromBridge(entry.level)
            let moduleName = [entry.module, entry.sub].compactMap { $0 }.joined(separator: "/")
            let prefix = moduleName.isEmpty ? "" : "[\(moduleName)] "
            logWithLevel(level, message: "\(prefix)\(entry.message)")
        } else {
            // Fallback for non-JSON output (plain text, panics, etc.)
            logWithLevel(defaultLevel, message: line)
        }
    }

    /// Log a message at the specified level using Logger's static methods
    private func logWithLevel(_ level: LogLevel, message: String) {
        switch level {
        case .debug:
            Logger.debug(message, module: "WhatsApp-Bridge")
        case .info:
            Logger.info(message, module: "WhatsApp-Bridge")
        case .warning:
            Logger.warning(message, module: "WhatsApp-Bridge")
        case .error:
            Logger.error(message, module: "WhatsApp-Bridge")
        case .critical:
            Logger.critical(message, module: "WhatsApp-Bridge")
        }
    }

    /// Setup stderr logging for debugging
    private func setupStderrLogging() {
        guard let stderrPipe = stderrPipe else { return }

        let fileHandle = stderrPipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else { return }

            for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                self?.parseBridgeLine(line, defaultLevel: .warning)
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

    /// Kill any orphaned whatsapp-bridge processes from previous app crashes
    private func cleanupOrphanedProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "whatsapp-bridge"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            Logger.debug("Cleaned up any orphaned whatsapp-bridge processes", module: "WhatsApp")
        } catch {
            // pkill may fail if no matching processes found, which is fine
            Logger.debug("No orphaned whatsapp-bridge processes to clean up", module: "WhatsApp")
        }
    }

    deinit {
        stop()
    }
}

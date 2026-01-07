import Foundation
import os.log

// MARK: - Log Level
enum LogLevel: Int, Comparable, CustomStringConvertible {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Rotating File Logger
final class RotatingFileLogger {
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let maxFileSize: UInt64
    private let maxFileCount: Int
    private let dateFormatter: DateFormatter
    private var currentFileHandle: FileHandle?
    private var currentFilePath: URL?
    private let queue = DispatchQueue(label: "com.homie.logger.file", qos: .utility)

    init(maxFileSize: UInt64 = 5 * 1024 * 1024, maxFileCount: Int = 5) {
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount

        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDirectory = appSupport.appendingPathComponent("homie/Logs", isDirectory: true)

        createLogDirectoryIfNeeded()
        openCurrentLogFile()
    }

    deinit {
        try? currentFileHandle?.close()
    }

    private func createLogDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
    }

    private func openCurrentLogFile() {
        let fileName = "homie_\(dateFormatter.string(from: Date())).log"
        currentFilePath = logDirectory.appendingPathComponent(fileName)

        if let path = currentFilePath {
            if !fileManager.fileExists(atPath: path.path) {
                fileManager.createFile(atPath: path.path, contents: nil)
            }
            currentFileHandle = try? FileHandle(forWritingTo: path)
            currentFileHandle?.seekToEndOfFile()
        }
    }

    func write(_ message: String) {
        queue.async { [weak self] in
            self?.writeSync(message)
        }
    }

    private func writeSync(_ message: String) {
        guard let handle = currentFileHandle, let path = currentFilePath else { return }

        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)

            // Check if rotation is needed
            if let attrs = try? fileManager.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? UInt64,
               size >= maxFileSize {
                rotateFiles()
            }
        }
    }

    private func rotateFiles() {
        try? currentFileHandle?.close()
        currentFileHandle = nil

        // Get all log files sorted by creation date
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            openCurrentLogFile()
            return
        }

        let logFiles = files
            .filter { $0.pathExtension == "log" }
            .sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 < date2
            }

        // Remove oldest files if we exceed max count
        if logFiles.count >= maxFileCount {
            let filesToRemove = logFiles.prefix(logFiles.count - maxFileCount + 1)
            for file in filesToRemove {
                try? fileManager.removeItem(at: file)
            }
        }

        openCurrentLogFile()
    }

    func getLogDirectory() -> URL {
        return logDirectory
    }
}

// MARK: - Logger
final class Logger {
    static let shared = Logger()

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.homie"
    private let osLog: OSLog
    private let fileLogger: RotatingFileLogger
    private let timestampFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.homie.logger", qos: .utility)

    var minimumLevel: LogLevel = .debug
    var fileLoggingEnabled: Bool = true
    var consoleLoggingEnabled: Bool = true

    private init() {
        osLog = OSLog(subsystem: subsystem, category: "general")
        fileLogger = RotatingFileLogger()

        timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        timestampFormatter.timeZone = TimeZone.current
    }

    // MARK: - Logging Methods

    static func debug(
        _ message: @autoclosure () -> String,
        module: String = "App",
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .debug, message: message(), module: module, file: file, line: line, function: function)
    }

    static func info(
        _ message: @autoclosure () -> String,
        module: String = "App",
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .info, message: message(), module: module, file: file, line: line, function: function)
    }

    static func warning(
        _ message: @autoclosure () -> String,
        module: String = "App",
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .warning, message: message(), module: module, file: file, line: line, function: function)
    }

    static func error(
        _ message: @autoclosure () -> String,
        module: String = "App",
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .error, message: message(), module: module, file: file, line: line, function: function)
    }

    static func critical(
        _ message: @autoclosure () -> String,
        module: String = "App",
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        shared.log(level: .critical, message: message(), module: module, file: file, line: line, function: function)
    }

    // MARK: - Core Logging

    private func log(
        level: LogLevel,
        message: String,
        module: String,
        file: String,
        line: Int,
        function: String
    ) {
        guard level >= minimumLevel else { return }

        let timestamp = timestampFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent

        // Format: [TIMESTAMP] [LEVEL] [MODULE] [FILE:LINE] MESSAGE
        let formattedMessage = "[\(timestamp)] [\(level.description)] [\(module)] [\(fileName):\(line)] \(message)"

        queue.async { [weak self] in
            guard let self = self else { return }

            // Log to os.log
            if self.consoleLoggingEnabled {
                os_log("%{public}@", log: self.osLog, type: level.osLogType, formattedMessage)
            }

            // Log to file
            if self.fileLoggingEnabled {
                self.fileLogger.write(formattedMessage)
            }
        }
    }

    // MARK: - Scoped Loggers

    static func scoped(_ module: String) -> ScopedLogger {
        return ScopedLogger(module: module)
    }

    // MARK: - Configuration

    static func setMinimumLevel(_ level: LogLevel) {
        shared.minimumLevel = level
    }

    static func enableFileLogging(_ enabled: Bool) {
        shared.fileLoggingEnabled = enabled
    }

    static func enableConsoleLogging(_ enabled: Bool) {
        shared.consoleLoggingEnabled = enabled
    }

    static func getLogDirectory() -> URL {
        return shared.fileLogger.getLogDirectory()
    }
}

// MARK: - Scoped Logger
struct ScopedLogger {
    let module: String

    func debug(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        Logger.debug(message(), module: module, file: file, line: line, function: function)
    }

    func info(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        Logger.info(message(), module: module, file: file, line: line, function: function)
    }

    func warning(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        Logger.warning(message(), module: module, file: file, line: line, function: function)
    }

    func error(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        Logger.error(message(), module: module, file: file, line: line, function: function)
    }

    func critical(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        Logger.critical(message(), module: module, file: file, line: line, function: function)
    }
}

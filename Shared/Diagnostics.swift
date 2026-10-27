import Foundation
import AppKit

/// Lightweight diagnostics shared by the main app and the Finder Sync
/// extension: a rotating text log plus crash capture.
///
/// Everything is written into the App Group container so both processes
/// (one sandboxed, one not) can read and write the same files:
///
///     <container>/Logs/quicklet.log        rotating text log
///     <container>/Logs/session.active      present only while a session runs
///     <container>/Crashes/crash-*.txt      exception / signal reports
enum Diagnostics {
    private static let maxLogBytes = 512 * 1024
    private static let logQueue = DispatchQueue(label: "com.ice.quicklet.diagnostics")

    // MARK: - Locations

    static var rootDirectory: URL {
        let directory: URL
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CommandStore.appGroupID
        ) {
            directory = container
        } else {
            directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Quicklet", isDirectory: true)
        }
        return directory
    }

    static var logsDirectory: URL { rootDirectory.appendingPathComponent("Logs", isDirectory: true) }
    static var logFileURL: URL { logsDirectory.appendingPathComponent("quicklet.log") }
    static var crashDirectory: URL { rootDirectory.appendingPathComponent("Crashes", isDirectory: true) }
    private static var sessionMarkerURL: URL { logsDirectory.appendingPathComponent("session.active") }

    /// Directory where macOS itself stores crash reports (.ips files).
    static var systemCrashReportsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
    }

    // MARK: - Install

    private nonisolated(unsafe) static var processName = "Quicklet"
    private nonisolated(unsafe) static var tracksSession = false
    /// Installs crash handlers and writes the "started" log line.
    /// - Parameter tracksSession: true for the long-lived main app. A marker
    ///   file is then left behind while it runs, so an unclean exit can be
    ///   reported on the next launch.
    static func install(processName name: String, tracksSession: Bool) {
        processName = name
        self.tracksSession = tracksSession
        createDirectories()

        if tracksSession {
            previousSessionUnclean = FileManager.default.fileExists(atPath: sessionMarkerURL.path)
            if previousSessionUnclean {
                log("previous session ended without a clean exit - see crash reports")
            }
            FileManager.default.createFile(atPath: sessionMarkerURL.path, contents: Data())
        }

        installExceptionHandler()
        installSignalHandlers()
        installTerminationHandlers()
        log("=== \(name) started (pid \(ProcessInfo.processInfo.processIdentifier)) ===")
    }

    /// Removes the session marker; call from applicationWillTerminate.
    static func markCleanExit() {
        guard tracksSession else { return }
        log("=== \(processName) exiting cleanly ===")
        logQueue.sync {
            try? FileManager.default.removeItem(at: sessionMarkerURL)
        }
    }

    /// True when the *previous* app session did not exit cleanly. Captured
    /// at install time, because the marker exists during the current run too.
    private nonisolated(unsafe) static var previousSessionUnclean = false

    static var previousSessionWasUnclean: Bool { previousSessionUnclean }

    // MARK: - Logging

    static func log(_ message: String) {
        NSLog("Quicklet: %@", message)
        let line = "[\(timestamp())] [\(processName)] \(message)\n"
        logQueue.async { append(line) }
    }

    /// Returns the tail of the log, newest lines last.
    static func recentLog(maxBytes: Int = 32 * 1024) -> String {
        logQueue.sync {
            guard let data = try? Data(contentsOf: logFileURL) else { return "(no log yet)" }
            let slice = data.count > maxBytes ? data.suffix(maxBytes) : data
            return String(decoding: slice, as: UTF8.self)
        }
    }

    static func clearLog() {
        logQueue.sync {
            try? FileManager.default.removeItem(at: logFileURL)
            try? FileManager.default.removeItem(at: logFileURL.appendingPathExtension("1"))
        }
        log("log cleared")
    }

    /// Crash reports produced by Quicklet itself, newest first.
    static func crashReports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: crashDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.lastPathComponent.hasSuffix(".txt") }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    /// macOS crash reports (.ips) for either Quicklet process, newest first.
    static func systemCrashReports(limit: Int = 10) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: systemCrashReportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.lastPathComponent.lowercased().hasPrefix("quicklet") }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func createDirectories() {
        for directory in [logsDirectory, crashDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func append(_ line: String) {
        createDirectories()
        rotateIfNeeded()

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL)
        }
    }

    private static func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size > maxLogBytes else { return }
        let previous = logFileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: logFileURL, to: previous)
    }

    // MARK: - Exception capture

    private static func installExceptionHandler() {
        // A named file-scope function keeps this a plain C function pointer.
        NSSetUncaughtExceptionHandler(quickletHandleUncaughtException)
    }

    fileprivate static func record(exception: NSException) {
        writeCrashReport(
            title: "Uncaught exception: \(exception.name.rawValue)",
            details: """
            process: \(processName) (pid \(ProcessInfo.processInfo.processIdentifier))
            reason: \(exception.reason ?? "unknown")
            user info: \(exception.userInfo ?? [:])
            """,
            symbols: exception.callStackSymbols
        )
    }

    fileprivate static func writeCrashReport(title: String, details: String, symbols: [String]) {
        createDirectories()
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let file = crashDirectory.appendingPathComponent("crash-\(stamp)-\(ProcessInfo.processInfo.processIdentifier).txt")
        let body = """
        \(title)
        time: \(Date())
        \(details)

        --- stack ---
        \(symbols.joined(separator: "\n"))
        """
        try? Data(body.utf8).write(to: file)
    }

    // MARK: - Signal capture

    // Pre-built, allocation-free state used from the signal handler.
    fileprivate nonisolated(unsafe) static var crashPrefix = [CChar]()
    fileprivate nonisolated(unsafe) static var crashPath = [CChar]()
    fileprivate nonisolated(unsafe) static var signalLabel = [CChar]()

    private static func installSignalHandlers() {
        crashPrefix = Array("quicklet \(processName) crashed: ".utf8CString)
        signalLabel = Array("signal ".utf8).map { CChar(bitPattern: $0) }
        let path = crashDirectory
            .appendingPathComponent("crash-signal-\(Int(Date().timeIntervalSince1970))-\(ProcessInfo.processInfo.processIdentifier).txt")
            .path
        crashPath = Array(path.utf8CString)

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, quickletHandleCrashSignal)
        }
    }

    /// SIGTERM / SIGINT mean "someone asked us to stop" (pkill, Force Quit
    /// scripts, ...), not a crash. Clear the session marker so the next launch
    /// does not report a false crash. unlink(2) is async-signal-safe.
    fileprivate nonisolated(unsafe) static var sessionMarkerPath = [CChar]()

    private static func installTerminationHandlers() {
        guard tracksSession else { return }
        sessionMarkerPath = Array(sessionMarkerURL.path.utf8CString)
        for sig in [SIGTERM, SIGINT] {
            signal(sig, quickletHandleTerminationSignal)
        }
    }
}

// MARK: - C entry points

/// Must stay async-signal-safe: no allocation, only write(2) and stack buffers.
private func quickletHandleCrashSignal(_ received: Int32) {
    let fd = open(Diagnostics.crashPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    if fd >= 0 {
        Diagnostics.crashPrefix.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                _ = write(fd, base, strlen(base))
            }
        }

        withUnsafeTemporaryAllocation(of: CChar.self, capacity: 32) { buffer in
            guard let base = buffer.baseAddress else { return }
            var position = 0

            Diagnostics.signalLabel.withUnsafeBufferPointer { label in
                guard let source = label.baseAddress else { return }
                for offset in 0..<label.count {
                    base[position + offset] = source[offset]
                }
                position += label.count
            }

            // Write the signal number by hand: snprintf is a variadic C
            // function and therefore unavailable in Swift.
            var number = Int(received)
            var digitCount = 1
            var probe = number
            while probe >= 10 {
                probe /= 10
                digitCount += 1
            }
            let digitsStart = position
            var index = digitCount - 1
            while index >= 0 {
                base[digitsStart + index] = CChar(48 + number % 10)
                number /= 10
                index -= 1
            }
            position += digitCount
            base[position] = 10  // newline
            position += 1

            _ = write(fd, base, position)
        }

        // Append a best-effort stack trace. backtrace_symbols_fd is not
        // strictly async-signal-safe, but it is the standard approach and
        // keeps the report readable; the system crash report still exists
        // as a fallback.
        withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer?.self, capacity: 64) { stack in
            guard let base = stack.baseAddress else { return }
            let frames = backtrace(base, 64)
            if frames > 0 {
                backtrace_symbols_fd(base, frames, fd)
            }
        }

        close(fd)
    }

    // Restore default handling so the system crash reporter runs too.
    signal(received, SIG_DFL)
    raise(received)
}

private func quickletHandleUncaughtException(_ exception: NSException) {
    Diagnostics.record(exception: exception)
}

/// Treat an explicit termination request as a clean exit.
private func quickletHandleTerminationSignal(_ received: Int32) {
    unlink(Diagnostics.sessionMarkerPath)
    signal(received, SIG_DFL)
    raise(received)
}

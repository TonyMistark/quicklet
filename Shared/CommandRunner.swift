import Foundation

/// Executes a command's shell template with the given selected paths.
///
/// The Finder Sync extension is sandboxed and cannot spawn subprocesses,
/// so execution always happens in the (unsandboxed) main app after the
/// extension hands the selection over through a `quicklet://` URL.
enum CommandRunner {
    /// Placeholders supported in command templates.
    enum Placeholder {
        static let allPaths = "{paths}"
        static let firstPath = "{path}"
        static let directory = "{dir}"
        static let parentDirectory = "{parent}"
        static let input = "{input}"
    }

    /// Runs `command` against `paths`. Returns false when the process
    /// could not be started.
    @discardableResult
    static func run(_ command: QuickletCommand, paths: [String], input: String? = nil) -> Bool {
        let script = expand(template: command.script, paths: paths, input: input)
        guard !script.isEmpty else {
            Diagnostics.log("skip '\(command.name)': empty script after expansion")
            return false
        }

        Diagnostics.log("run '\(command.name)' paths=\(paths.count) script=\(script)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { finished in
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            var message = "finished '\(command.name)' exit=\(finished.terminationStatus)"
            if finished.terminationReason == .uncaughtSignal {
                message += " signal=\(finished.terminationStatus)"
            }
            if !stderr.isEmpty {
                message += " stderr=\(stderr.prefix(2000))"
                // A denied folder access surfaces as a plain shell error, so
                // point at the permission that fixes it.
                if stderr.contains("Operation not permitted") || stderr.contains("Permission denied") {
                    message += " | hint: folder access may be blocked - grant Full Disk Access"
                }
            }
            Diagnostics.log(message)
        }

        do {
            try process.run()
            return true
        } catch {
            Diagnostics.log("failed to start '\(command.name)': \(error.localizedDescription)")
            return false
        }
    }

    /// Substitutes placeholders with shell-quoted paths.
    ///
    /// A placeholder that is already wrapped in quotes (`"{dir}"`) keeps
    /// working: the wrapping quotes are dropped so the path is quoted once.
    static func expand(template: String, paths: [String], input: String? = nil) -> String {
        let quoted = paths.map(\.shellQuoted)
        let firstURL = paths.first.map { URL(fileURLWithPath: $0) }
        let parentDirectory = firstURL?.deletingLastPathComponent().path.shellQuoted ?? ""

        // {dir} is the folder a command should work in: the selection itself
        // when a folder is selected, otherwise the folder containing the
        // selection. Using the parent unconditionally sent "open in Terminal"
        // one level up, which looked like it ignored the selection entirely.
        let isFolder = firstURL.map { url in
            var flag: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
        } ?? false
        let workingDirectory = firstURL.map { url -> String in
            (isFolder ? url.path : url.deletingLastPathComponent().path).shellQuoted
        } ?? ""

        // Order matters: {paths} must be handled before {path}.
        let substitutions: [(token: String, value: String)] = [
            (Placeholder.allPaths, quoted.joined(separator: " ")),
            (Placeholder.parentDirectory, parentDirectory),
            (Placeholder.firstPath, quoted.first ?? ""),
            (Placeholder.directory, workingDirectory),
            (Placeholder.input, (input ?? "").shellQuoted),
        ]

        var script = template
        for (token, value) in substitutions {
            for wrapper in ["\"", "'"] {
                script = script.replacingOccurrences(of: wrapper + token + wrapper, with: value)
            }
            script = script.replacingOccurrences(of: token, with: value)
        }
        return script
    }
}

extension String {
    /// Single-quote a path so it is safe to embed in a shell command.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

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
    }

    /// Runs `command` against `paths`. Returns false when the process
    /// could not be started.
    @discardableResult
    static func run(_ command: QuickletCommand, paths: [String]) -> Bool {
        let script = expand(template: command.script, paths: paths)
        guard !script.isEmpty else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            NSLog("Quicklet: failed to run '%@': %@", command.name, error.localizedDescription)
            return false
        }
    }

    /// Substitutes placeholders with shell-quoted paths.
    static func expand(template: String, paths: [String]) -> String {
        let quoted = paths.map(\.shellQuoted)
        let firstURL = paths.first.map { URL(fileURLWithPath: $0) }
        let directory = firstURL?.deletingLastPathComponent().path.shellQuoted ?? ""

        var script = template
        script = script.replacingOccurrences(of: Placeholder.allPaths, with: quoted.joined(separator: " "))
        script = script.replacingOccurrences(of: Placeholder.firstPath, with: quoted.first ?? "")
        script = script.replacingOccurrences(of: Placeholder.directory, with: directory)
        return script
    }
}

extension String {
    /// Single-quote a path so it is safe to embed in a shell command.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

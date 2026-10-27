import Foundation
import AppKit

/// macOS privacy permissions Quicklet depends on.
///
/// The extension only forwards a selection; the unsandboxed app runs the
/// shell command, so any command that touches Desktop, Documents or
/// Downloads is gated by macOS' per-app, per-folder consent. Granting Full
/// Disk Access supersedes those per-folder prompts and is the supported
/// setup, which is why the app can check for it and point the user to the
/// right settings pane.
enum Permissions {
    /// Full Disk Access is not exposed through a public API, so probe a
    /// location that only FDA holders can read. TCC.db is the most reliable
    /// probe: it is unreadable for every app without the grant.
    static var hasFullDiskAccess: Bool {
        let probes = [
            "~/Library/Application Support/com.apple.TCC/TCC.db",
            "~/Library/Safari",
        ]
        return probes.contains { probe in
            let path = (probe as NSString).expandingTildeInPath
            return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
                || FileManager.default.isReadableFile(atPath: path)
        }
    }

    /// True when the running copy lives in /Applications. A second copy
    /// (for example the build output) also registers as a `quicklet://`
    /// handler and makes the code identity seen by macOS flip between
    /// builds, which is what breaks saved permission grants.
    static var isInstalledInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static var bundlePath: String { Bundle.main.bundlePath }

    // MARK: - Settings panes

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openFilesAndFoldersSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    static func openExtensionsSettings() {
        open("x-apple.systempreferences:com.apple.ExtensionsPreferences")
    }

    /// Relaunches the app so a freshly granted permission takes effect;
    /// macOS caches the TCC decision per process.
    static func restart() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(bundlePath)\""]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

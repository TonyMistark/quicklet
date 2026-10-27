import AppKit
import Combine
import Foundation

/// One click from "new version available" to a running new build:
/// download the zip, unpack it, swap it into /Applications, relaunch.
///
/// Three rules, in order of importance:
/// 1. **The installed copy stays intact until the new one is verified.** The
///    new bundle is staged and checked (its bundle version must equal the
///    release tag) before the old one is touched; any failure leaves the
///    previous install exactly as it was.
/// 2. **Fall back, do not fight.** When an install cannot happen, the UI
///    offers the release page instead of retrying silently.
/// 3. **Say what happened.** Every step lands in the diagnostic log, because
///    an update that half-worked is the hardest thing to debug from outside.
@MainActor
final class UpdateInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading
        case installing
        case failed(reason: String)

        var isWorking: Bool {
            switch self {
            case .downloading, .installing: return true
            case .idle, .failed: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// Last archive that made it to disk; the failure path reveals it so the
    /// user can finish the job by hand.
    private(set) var downloadedArchive: URL?

    private static let appName = "Quicklet.app"

    // MARK: - Entry point

    func run(asset: UpdateAsset, version: String, releaseURL: URL, fallbacks: [UpdateAsset] = []) async {
        guard !phase.isWorking else { return }

        do {
            phase = .downloading
            let archive = try await downloadFirst([asset] + fallbacks)
            downloadedArchive = archive

            phase = .installing
            let unpacked = try unpack(archive)
            let installed = try install(app: unpacked, expectedVersion: version)
            Diagnostics.log("update: \(version) installed at \(installed.path)")

            relaunch(installed)
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Diagnostics.log("update failed: \(reason)")
            phase = .failed(reason: reason)
        }
    }

    /// Brings the downloaded archive up in Finder after a failed install.
    func revealFallback() {
        guard let downloadedArchive else { return }
        NSWorkspace.shared.activateFileViewerSelecting([downloadedArchive])
    }

    // MARK: - Steps

    /// Tries the primary source first, then the mirrors for the same version:
    /// a blocked CDN is the most common download failure, and switching hosts
    /// is cheaper than asking the user to click again.
    private func downloadFirst(_ assets: [UpdateAsset]) async throws -> URL {
        var lastError: Error = InstallError.noAsset
        for asset in assets {
            do {
                let file = try await download(asset)
                if assets.count > 1 {
                    Diagnostics.log("update: downloaded from \(asset.name) (\(asset.url.host() ?? "?"))")
                }
                return file
            } catch {
                lastError = error
                Diagnostics.log("update: download from \(asset.name) failed: \(error.localizedDescription)")
            }
        }
        throw lastError
    }

    private func download(_ asset: UpdateAsset) async throws -> URL {
        var request = URLRequest(url: asset.url)
        request.timeoutInterval = 60
        request.setValue("Quicklet/\(AppInfo.shortVersion)", forHTTPHeaderField: "User-Agent")

        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.download(status: http.statusCode)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickletUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Unpacks the zip and returns the `.app` inside it.
    private func unpack(_ archive: URL) throws -> URL {
        let directory = archive.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])

        guard let app = firstApplication(in: directory) else {
            throw InstallError.noBundleInArchive
        }
        return app
    }

    private func firstApplication(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }

    /// Copies the verified bundle into /Applications, keeping a rollback copy
    /// of whatever was installed until the swap has succeeded.
    private func install(app: URL, expectedVersion: String) throws -> URL {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let destination = applications.appendingPathComponent(Self.appName)

        let stagedVersion = bundleVersion(of: app)
        guard stagedVersion == expectedVersion else {
            throw InstallError.versionMismatch(expected: expectedVersion, actual: stagedVersion ?? "?")
        }

        let token = UUID().uuidString
        let staged = applications.appendingPathComponent(".Quicklet-stage-\(token).app")
        let backup = applications.appendingPathComponent(".Quicklet-backup-\(token).app")

        // ditto (not copyItem) keeps extended attributes, permissions and the
        // embedded signature intact, which matters for a Finder extension.
        try? FileManager.default.removeItem(at: staged)
        try run("/usr/bin/ditto", [app.path, staged.path])

        guard bundleVersion(of: staged) == expectedVersion else {
            try? FileManager.default.removeItem(at: staged)
            throw InstallError.versionMismatch(expected: expectedVersion, actual: "?")
        }

        var movedAside = false
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: backup)
            movedAside = true
        }

        do {
            try FileManager.default.moveItem(at: staged, to: destination)
        } catch {
            // Put the working copy back before reporting the failure.
            if movedAside {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            try? FileManager.default.removeItem(at: staged)
            throw error
        }

        if movedAside {
            try? FileManager.default.removeItem(at: backup)
        }

        // Two copies claiming quicklet:// make macOS treat them as different
        // programs and drop saved privacy grants, so register only the new one.
        try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                 ["-f", "-R", destination.path])

        return destination
    }

    private func bundleVersion(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let parsed = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any]
        else { return nil }
        return parsed["CFBundleShortVersionString"] as? String
    }

    /// Reopens the freshly installed copy and quits. A short delay lets this
    /// process exit before the new instance claims the URL scheme.
    private func relaunch(_ app: URL) {
        let script = "sleep 1; open \"\(app.path)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            Diagnostics.log("update: relaunch failed: \(error.localizedDescription)")
        }
        NSApplication.shared.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw InstallError.toolFailed(tool: (tool as NSString).lastPathComponent, status: task.terminationStatus)
        }
    }
}

enum InstallError: LocalizedError {
    case noAsset
    case download(status: Int)
    case noBundleInArchive
    case versionMismatch(expected: String, actual: String)
    case toolFailed(tool: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .noAsset:
            return "这个版本没有提供可下载的 zip"
        case .download(let status):
            return "下载失败（HTTP \(status)）"
        case .noBundleInArchive:
            return "压缩包里没有找到 Quicklet.app"
        case .versionMismatch(let expected, let actual):
            return "压缩包版本不符（期望 \(expected)，实际 \(actual)）"
        case .toolFailed(let tool, let status):
            return "\(tool) 执行失败（退出码 \(status)）"
        }
    }
}

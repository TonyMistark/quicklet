import AppKit
import Combine

/// Name and picture shown in the settings sidebar.
///
/// Both live inside the App Group container next to `commands.json`: the
/// promise on the profile page is that they stay on this Mac, so nothing is
/// uploaded and no system-wide account is touched.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var avatar: NSImage?
    @Published var nickname: String = "" {
        didSet {
            guard nickname != oldValue else { return }
            save()
        }
    }

    private let directory: URL
    private let metadataURL: URL
    private let avatarURL: URL

    init(directory: URL = ProfileStore.defaultDirectory) {
        self.directory = directory
        metadataURL = directory.appendingPathComponent("profile.json")
        avatarURL = directory.appendingPathComponent("avatar.png")
        load()
    }

    /// Same container as the command config, so the extension could read the
    /// profile later without a second storage decision.
    nonisolated static var defaultDirectory: URL {
        let base: URL
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CommandStore.appGroupID
        ) {
            base = container
        } else {
            base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Quicklet", isDirectory: true)
        }
        let directory = base.appendingPathComponent("Profile", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Derived values

    /// Falls back to the macOS account name so the sidebar never shows a
    /// blank line before the user picks a nickname.
    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let full = NSFullUserName()
        return full.isEmpty ? "Quicklet" : full
    }

    var initial: String {
        String(displayName.prefix(1)).uppercased()
    }

    var hasNickname: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Avatar

    /// Stores the picture re-encoded as PNG so any format the open panel
    /// accepts ends up in one predictable file.
    @discardableResult
    func setAvatar(from url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:])
        else {
            Diagnostics.log("avatar: could not read \(url.lastPathComponent)")
            return false
        }
        do {
            try png.write(to: avatarURL, options: .atomic)
            avatar = NSImage(data: png)
            Diagnostics.log("avatar updated (\(png.count) bytes)")
            return true
        } catch {
            Diagnostics.log("avatar: write failed: \(error.localizedDescription)")
            return false
        }
    }

    func clearAvatar() {
        try? FileManager.default.removeItem(at: avatarURL)
        avatar = nil
    }

    // MARK: - Persistence

    private struct Metadata: Codable {
        var nickname: String
    }

    private func load() {
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(Metadata.self, from: data) {
            nickname = metadata.nickname
        }
        if let data = try? Data(contentsOf: avatarURL) {
            avatar = NSImage(data: data)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Metadata(nickname: nickname))
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            Diagnostics.log("profile: save failed: \(error.localizedDescription)")
        }
    }
}

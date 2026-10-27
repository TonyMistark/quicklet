import Foundation
import Combine

/// Loads and persists the command list as a JSON file.
///
/// The file lives in the shared App Group container so that both the main
/// app (writer) and the Finder Sync extension (reader) see the same data.
final class CommandStore: ObservableObject {
    static let appGroupID = "group.com.ice.quicklet"

    @Published var commands: [QuickletCommand] = []

    /// Location of the JSON config. Prefers the App Group container and
    /// falls back to a plain Application Support directory (useful when the
    /// entitlement is not available, e.g. previews or unsandboxed debug runs).
    static var defaultFileURL: URL {
        let directory: URL
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            directory = container
        } else {
            directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Quicklet", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("commands.json")
    }

    private let fileURL: URL
    private var saveCancellable: AnyCancellable?

    init(fileURL: URL = CommandStore.defaultFileURL) {
        self.fileURL = fileURL
        load()

        // Debounced autosave whenever the command list changes.
        saveCancellable = $commands
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                commands = Self.sampleCommands()
            }
            return
        }
        do {
            commands = try JSONDecoder().decode([QuickletCommand].self, from: data)
        } catch {
            NSLog("Quicklet: failed to decode commands.json: \(error)")
            commands = []
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(commands)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Quicklet: failed to save commands.json: \(error)")
        }
    }

    /// Seed commands shown on first launch.
    static func sampleCommands() -> [QuickletCommand] {
        [
            QuickletCommand(
                name: "在终端中打开",
                icon: "terminal",
                script: #"open -a Terminal "{dir}""#
            ),
            QuickletCommand(
                name: "用 VS Code 打开",
                icon: "chevron.left.forwardslash.chevron.right",
                script: #"open -a "Visual Studio Code" {paths}"#
            ),
        ]
    }
}

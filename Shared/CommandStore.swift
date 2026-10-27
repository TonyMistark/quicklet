import Foundation
import Combine

/// Loads and persists the command list as a JSON file.
///
/// The file lives in the shared App Group container so that both the main
/// app (writer) and the Finder Sync extension (reader) see the same data.
final class CommandStore: ObservableObject {
    static let appGroupID = "group.com.ice.quicklet"

    /// Shared instance used by the main app (settings window + URL handler).
    static let shared = CommandStore()

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
                // Seed and persist immediately: the extension hands commands
                // over by UUID, so both processes must see the same ids.
                commands = Self.sampleCommands()
                save()
            }
            return
        }
        do {
            commands = try JSONDecoder().decode([QuickletCommand].self, from: data)
        } catch {
            Diagnostics.log("failed to decode commands.json: \(error.localizedDescription)")
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
            Diagnostics.log("failed to save commands.json: \(error.localizedDescription)")
        }
    }

    /// Re-reads the config from disk, replacing the in-memory list.
    /// Used before resolving a command handed over from the extension,
    /// so edits made in another process are always picked up.
    func reloadFromDisk() {
        load()
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
            QuickletCommand(
                name: "新建文件…",
                icon: "doc.badge.plus",
                script: #"test -e {dir}/{input} && { echo "同名文件已存在，未覆盖"; exit 1; }; touch {dir}/{input}; open -R {dir}/{input}"#,
                promptTitle: "新建文件",
                promptPlaceholder: "文件名，例如 notes.md"
            ),
            // Grouped example: lives under Quicklet › 文件, demonstrating
            // the submenu placement (the root menu itself is fixed).
            QuickletCommand(
                name: "复制路径",
                icon: "doc.on.doc",
                script: #"printf '%s\n' {paths} | pbcopy"#,
                group: ["文件"]
            ),
        ]
    }
}

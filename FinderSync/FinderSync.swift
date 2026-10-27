import FinderSync

/// Finder Sync extension that appends user-defined commands to the
/// Finder context menu. The command list is read from the shared
/// App Group container, so edits made in the main app show up
/// immediately (the list is re-read every time the menu is opened).
final class FinderSync: FIFinderSync {
    private let store = CommandStore()

    override init() {
        super.init()
        // Watch the whole filesystem so the menu is available everywhere.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    // MARK: - Menu building

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // Re-read the config on every menu invocation so that changes
        // from the main app are picked up without relaunching Finder.
        store.load()

        let menu = NSMenu(title: "Quicklet")
        let commands = store.commands.filter { $0.enabled && !$0.isBlank }
        guard !commands.isEmpty else { return menu }

        for (index, command) in commands.enumerated() {
            let item = NSMenuItem(
                title: command.name,
                action: #selector(runCommand(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(systemSymbolName: command.icon, accessibilityDescription: command.name)
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Execution

    @objc private func runCommand(_ sender: NSMenuItem) {
        let commands = store.commands.filter { $0.enabled && !$0.isBlank }
        guard sender.tag >= 0, sender.tag < commands.count else { return }
        let command = commands[sender.tag]

        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        let paths = urls.map(\.path)

        var script = command.script
        script = script.replacingOccurrences(of: "{paths}", with: paths.map(\.shellQuoted).joined(separator: " "))
        script = script.replacingOccurrences(of: "{path}", with: paths.first?.shellQuoted ?? "")
        script = script.replacingOccurrences(of: "{dir}", with: urls.first?.deletingLastPathComponent().path.shellQuoted ?? "")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("Quicklet: failed to run command '%@': %@", command.name, error.localizedDescription)
        }
    }
}

// MARK: - Helpers

private extension String {
    /// Single-quote a path so it is safe to embed in a shell command.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

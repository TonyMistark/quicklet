import AppKit
import FinderSync

/// Finder Sync extension that appends user-defined commands to the
/// Finder context menu.
///
/// Extensions run inside the App Sandbox, which forbids spawning child
/// processes, so clicking an item does not execute the script here.
/// Instead the selection is handed over to the main app via a
/// `quicklet://run` URL; the unsandboxed app performs the execution.
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
        store.reloadFromDisk()

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

    // MARK: - Hand-off

    @objc private func runCommand(_ sender: NSMenuItem) {
        let commands = store.commands.filter { $0.enabled && !$0.isBlank }
        guard sender.tag >= 0, sender.tag < commands.count else { return }
        let command = commands[sender.tag]

        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        let paths = urls.map(\.path)

        guard let handoffURL = CommandURL.make(commandID: command.id, paths: paths) else {
            NSLog("Quicklet: could not build hand-off URL for '%@'", command.name)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(handoffURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Quicklet: failed to hand command '%@' to app: %@",
                      command.name, error.localizedDescription)
            }
        }
    }
}

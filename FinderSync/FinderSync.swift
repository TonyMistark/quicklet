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
        Diagnostics.install(processName: "QuickletFinder", tracksSession: false)
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
        guard !commands.isEmpty else {
            Diagnostics.log("menu requested but no enabled commands (total=\(store.commands.count))")
            return menu
        }
        Diagnostics.log("menu built with \(commands.count) command(s), kind=\(menuKind.rawValue)")

        let tree = MenuTree.build(from: commands)
        Diagnostics.log("menu structure: \(MenuTree.describe(tree.root))")

        // Ungrouped commands keep the original behaviour: first level of the
        // Finder context menu.
        for command in tree.topLevel {
            menu.addItem(item(for: command))
        }

        // The Quicklet submenu always exists - it is the app's fixed entry
        // point and cannot be renamed or removed by the user.
        menu.addItem(rootMenuItem(level: tree.root))
        return menu
    }

    private func rootMenuItem(level: MenuTree.Level) -> NSMenuItem {
        let title = QuickletCommand.rootMenuTitle
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: title)

        let submenu = NSMenu(title: title)
        populate(menu: submenu, level: level)

        if submenu.items.isEmpty {
            // Keep the entry visible (it is mandatory) but explain why it
            // is empty.
            let empty = NSMenuItem(title: "在 Quicklet 设置中添加分组命令", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        root.submenu = submenu
        return root
    }

    /// Renders one tree level: its commands first, then one submenu per
    /// child group.
    private func populate(menu: NSMenu, level: MenuTree.Level) {
        for command in level.commands {
            menu.addItem(item(for: command))
        }
        for child in level.children {
            let groupItem = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
            groupItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: child.name)
            let submenu = NSMenu(title: child.name)
            populate(menu: submenu, level: child.level)
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }
    }

    private func item(for command: QuickletCommand) -> NSMenuItem {
        let item = NSMenuItem(title: command.name, action: #selector(runCommand(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: command.icon, accessibilityDescription: command.name)
        // The menu travels between the extension and Finder and back, so
        // representedObject must survive a round-trip. Only property-list
        // types do: a UUID object arrives as nil on the way back, which
        // silently swallowed every click. Ship the UUID as a string.
        item.representedObject = command.id.uuidString
        return item
    }

    // MARK: - Hand-off

    @objc private func runCommand(_ sender: NSMenuItem) {
        Diagnostics.log("menu item clicked: '\(sender.title)'")

        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else {
            Diagnostics.log("representedObject is not a UUID string: \(String(describing: sender.representedObject))")
            return
        }
        guard let command = store.commands.first(where: { $0.id == id }) else {
            Diagnostics.log("command \(id) not found in store (\(store.commands.count) loaded)")
            return
        }

        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []

        // Right-clicking empty space inside a folder selects nothing; fall
        // back to the folder being viewed so commands like "new file" still
        // know where to work.
        if urls.isEmpty, let targeted = controller.targetedURL() {
            urls = [targeted]
        }
        let paths = urls.map(\.path)

        guard let handoffURL = CommandURL.make(commandID: command.id, paths: paths) else {
            Diagnostics.log("could not build hand-off URL for '\(command.name)'")
            return
        }
        Diagnostics.log("handing off '\(command.name)' with \(paths.count) path(s)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(handoffURL, configuration: configuration) { _, error in
            if let error {
                Diagnostics.log("hand-off failed for '\(command.name)': \(error.localizedDescription)")
            }
        }
    }
}

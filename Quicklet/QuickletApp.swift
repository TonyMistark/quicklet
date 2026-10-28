import SwiftUI
import AppKit

@main
struct QuickletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Quicklet", systemImage: "cursorarrow.click.2") {
            Button("Quicklet 设置…") {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("检查更新…") {
                appDelegate.show(.about)
                Task { await UpdateCenter.checker.check(force: true) }
            }

            Divider()

            Button("权限与安装…") {
                appDelegate.show(.permissions)
            }

            Button("诊断与日志…") {
                appDelegate.show(.diagnostics)
            }

            Divider()

            Button("关于 Quicklet") {
                AboutPanel.show()
            }

            Button("退出 Quicklet") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

/// Runs as a menu bar agent (LSUIElement). The Finder Sync extension hands
/// commands over through a `quicklet://` URL; this app is unsandboxed so it
/// can actually spawn the shell.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One window, several entry points: menu items switch the selected page.
    private var settingsWindow: NSWindow?
    private let router = SettingsRouter()
    private let profile = ProfileStore.shared
    private var didHandleCommand = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Diagnostics.install(processName: "Quicklet", tracksSession: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app: shows a Dock icon and a cmd+tab entry. The menu bar
        // extra remains as a second entry point.
        NSApp.setActivationPolicy(.regular)

        Diagnostics.log("""
        bundle=\(Permissions.bundlePath) version=\(AppInfo.shortVersion) \
        build=\(AppInfo.build) commit=\(AppInfo.commit ?? "-") \
        fullDiskAccess=\(Permissions.hasFullDiskAccess ? "granted" : "missing")
        """)

        // Commands that touch Desktop/Documents/Downloads are gated by macOS
        // per-app consent; without Full Disk Access every invocation prompts.
        if !Permissions.hasFullDiskAccess {
            Diagnostics.log("warning: Full Disk Access not granted - folder access prompts will repeat")
        }

        // A plain launch (double-click) should show the settings window, but a
        // launch triggered by the extension must stay invisible. The update
        // check runs in the background either way and stays quiet on failure.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !self.didHandleCommand {
                self.showSettings()
            }
            Task { await UpdateCenter.checker.checkIfDue() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.markCleanExit()
    }

    /// Clicking the Dock icon with no visible window reopens settings,
    /// otherwise the icon would look dead after the user closes the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettings()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let (commandID, paths) = CommandURL.parse(url) else {
                Diagnostics.log("ignored unparsable URL: \(url.absoluteString.prefix(200))")
                continue
            }
            didHandleCommand = true
            runCommand(id: commandID, paths: paths)
        }
    }

    private func runCommand(id: UUID, paths: [String]) {
        let store = CommandStore.shared
        store.reloadFromDisk()
        guard let command = store.commands.first(where: { $0.id == id }) else {
            Diagnostics.log("command \(id.uuidString) not found (config has \(store.commands.count) entries)")
            return
        }

        // Commands such as "new file" need one line of input from the user
        // before the shell runs; the value is exposed as {input}.
        if command.needsInput {
            guard let input = requestInput(for: command, paths: paths) else {
                Diagnostics.log("no input for '\(command.name)', nothing ran")
                return
            }
            CommandRunner.run(command, paths: paths, input: input)
        } else {
            CommandRunner.run(command, paths: paths)
        }
    }

    /// Shows a one-field modal prompt. Returns nil when cancelled or empty.
    private func requestInput(for command: QuickletCommand, paths: [String]) -> String? {
        let alert = NSAlert()
        alert.messageText = command.promptTitle ?? command.name
        if let first = paths.first {
            alert.informativeText = "位置：\(first)"
        }
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = command.promptPlaceholder ?? "请输入"
        field.font = .systemFont(ofSize: 13)
        alert.accessoryView = field

        // The app is a menu bar agent, so it has to come forward explicitly
        // or the modal prompt can appear behind the Finder window.
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        Diagnostics.log("input for '\(command.name)': \(text)")
        return text
    }

    // MARK: - Windows

    @objc func showSettings() {
        show(router.tab)
    }

    @objc func showDiagnostics() {
        show(.diagnostics)
    }

    @objc func showPermissions() {
        show(.permissions)
    }

    /// Opens the settings window, switching it to `tab` when it is already up.
    func show(_ tab: SettingsTab) {
        if settingsWindow == nil {
            let shell = SettingsShell(router: router, store: .shared, profile: profile)
            let hosting = NSHostingView(rootView: shell)
            hosting.frame = NSRect(
                x: 0, y: 0,
                width: SettingsLayout.width,
                height: SettingsLayout.height
            )

            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Quicklet"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        router.open(tab)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

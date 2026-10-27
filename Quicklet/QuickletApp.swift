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

            Button("诊断与日志…") {
                appDelegate.showDiagnostics()
            }

            Button("权限与安装…") {
                appDelegate.showPermissions()
            }

            Divider()

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var didHandleCommand = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Diagnostics.install(processName: "Quicklet", tracksSession: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Diagnostics.log("bundle=\(Permissions.bundlePath) fullDiskAccess=\(Permissions.hasFullDiskAccess ? "granted" : "missing")")

        // Commands that touch Desktop/Documents/Downloads are gated by macOS
        // per-app consent; without Full Disk Access every invocation prompts.
        if !Permissions.hasFullDiskAccess {
            Diagnostics.log("warning: Full Disk Access not granted - folder access prompts will repeat")
        }

        // A plain launch (double-click) should show the settings window,
        // but a launch triggered by the extension must stay invisible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.didHandleCommand else { return }
            self.showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.markCleanExit()
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
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: ContentView(store: .shared))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Quicklet 设置"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showDiagnostics() {
        if diagnosticsWindow == nil {
            let hosting = NSHostingView(rootView: DiagnosticsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Quicklet 诊断"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            diagnosticsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showPermissions() {
        if permissionsWindow == nil {
            let hosting = NSHostingView(rootView: PermissionsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Quicklet 权限"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            permissionsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        permissionsWindow?.makeKeyAndOrderFront(nil)
    }
}

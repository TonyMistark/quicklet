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
    private var didHandleCommand = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // A plain launch (double-click) should show the settings window,
        // but a launch triggered by the extension must stay invisible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.didHandleCommand else { return }
            self.showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let (commandID, paths) = CommandURL.parse(url) else { continue }
            didHandleCommand = true
            runCommand(id: commandID, paths: paths)
        }
    }

    private func runCommand(id: UUID, paths: [String]) {
        let store = CommandStore.shared
        store.reloadFromDisk()
        guard let command = store.commands.first(where: { $0.id == id }) else {
            NSLog("Quicklet: command %@ not found", id.uuidString)
            return
        }
        CommandRunner.run(command, paths: paths)
    }

    // MARK: - Settings window

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
}

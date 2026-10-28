import AppKit
import SwiftUI

_ = NSApplication.shared
NSApp.appearance = NSAppearance(named: .aqua)

func render(_ view: NSView, width: CGFloat, height: CGFloat, to path: String) {
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    view.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    view.cacheDisplay(in: NSRect(x: 0, y: 0, width: width, height: height), to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let store = CommandStore(fileURL: URL(fileURLWithPath: "/tmp/uirender/commands.json"))
var draft = QuickletCommand()
draft.enabled = false
store.commands = [
    QuickletCommand(name: "在终端中打开", icon: "terminal", script: #"open -a Terminal {dir}"#),
    QuickletCommand(name: "新建文件…", icon: "doc.badge.plus", script: "touch {dir}/{input}", promptTitle: "新建文件", promptPlaceholder: "文件名，例如 notes.md"),
    QuickletCommand(name: "复制路径", icon: "doc.on.doc", script: "printf '%s\\n' {paths} | pbcopy", group: ["文件"]),
    draft,
]

// Standalone inspector (List does not paint rows without a real window).
let inspector = CommandInspector(
    command: Binding(get: { store.commands[1] }, set: { store.commands[1] = $0 }),
    allCommands: store.commands
)
render(NSHostingView(rootView: inspector.frame(width: 624, height: 580).background(Color(nsColor: .windowBackgroundColor))),
       width: 624, height: 580, to: "/tmp/uirender/inspector.png")
print("rendered")

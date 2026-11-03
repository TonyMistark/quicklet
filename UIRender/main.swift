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

let json = #"{"tag_name":"v1.0.9","assets":[{"name":"Quicklet-v1.0.9.zip","size":1336600,"browser_download_url":"https://example.invalid/primary/Quicklet-v1.0.9.zip"}]}"#

var finished = false
Task { @MainActor in
    // Two feeds: the primary reports a newer release, the mirror's API is
    // unreachable - the case that must still yield a fallback download.
    let configuration = UpdateChecker.Configuration(
        currentVersion: "1.0.4",
        sources: [
            .init(name: "GitHub", endpoint: URL(string: "https://example.invalid/primary")!),
            .init(name: "Gitee", endpoint: URL(string: "https://example.invalid/mirror")!,
                  assetTemplate: "https://gitee.com/Micestark/quicklet/releases/download/{tag}/{file}"),
        ],
        interval: 0,
        retryInterval: 0
    )

    let checker = UpdateChecker(
        configuration: configuration,
        defaults: UserDefaults(suiteName: "uirender")!,
        fetch: { source in
            if source.name == "GitHub" {
                return (Data(json.utf8), HTTPURLResponse(url: source.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            throw URLError(.badServerResponse)
        }
    )
    let installer = UpdateInstaller()
    let profile = ProfileStore(directory: URL(fileURLWithPath: "/tmp/uirender/profile"))

    await checker.check(force: true)
    if case .available(let version, let downloads) = checker.status {
        print("version: \(version)")
        print("downloads: \(downloads.count)")
        for asset in downloads { print("  - \(asset.url.host() ?? "?") \(asset.name)") }
    } else {
        print("unexpected status: \(checker.status)")
    }

    render(
        NSHostingView(rootView: AboutSettingsView(profile: profile, checker: checker, installer: installer)
            .frame(width: 624, height: 560)
            .background(Color(nsColor: .windowBackgroundColor))),
        width: 624, height: 560, to: "/tmp/uirender/about.png"
    )
    finished = true
}
while !finished { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
print("rendered")

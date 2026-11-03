import AppKit
import SwiftUI

/// Version, update checking and the links that matter. Everything a reader
/// might need after "which build is this, and is there a newer one?".
struct AboutSettingsView: View {
    @ObservedObject var profile: ProfileStore
    @ObservedObject var checker: UpdateChecker
    @ObservedObject var installer: UpdateInstaller

    var body: some View {
        Form {
            versionSection
            updateSection
            dataSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Version

    private var versionSection: some View {
        Section("版本") {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quicklet")
                        .font(.title3.bold())
                    Text("版本 \(AppInfo.shortVersion) · build \(AppInfo.build)")
                        .foregroundStyle(.secondary)
                    Text(AppInfo.systemDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let commit = AppInfo.commit {
                        Text("commit \(commit)\(AppInfo.buildDate.map { " · \($0)" } ?? "")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            LabeledContent("安装位置") {
                Text(AppInfo.bundlePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Updates

    private var updateSection: some View {
        Section("更新") {
            HStack(spacing: 10) {
                Text(checker.status.summary ?? "尚未检查")
                    .font(.callout)
                    .foregroundStyle(checker.status.hasUpdateBadge ? .primary : .secondary)
                Spacer()
                updateAction
                Button(checker.isChecking ? "正在检查…" : "检查更新") {
                    Task { await checker.check(force: true) }
                }
                .disabled(checker.isChecking || installer.phase.isWorking)
            }

            // Only the outcome belongs here. Where the package comes from,
            // which host answered and what a mirror is are all internal: the
            // reader asked for a newer version, not for a download route.
            if case .failed = checker.status {
                Text("暂时无法检查更新，请稍后重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed = installer.phase {
                Text("更新没有完成，当前版本仍然可用。稍后可以再试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Update…" appears only while a newer version is known; installing and
    /// downloading states replace it in place so the row does not jump.
    @ViewBuilder
    private var updateAction: some View {
        switch (checker.status, installer.phase) {
        case (.available(let version, let downloads), .idle):
            Button("更新到 \(version)") {
                startInstall(version: version, downloads: downloads)
            }
            .disabled(downloads.isEmpty)
        case (_, .downloading):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("下载中…").font(.callout).foregroundStyle(.secondary)
            }
        case (_, .installing):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("安装中…").font(.callout).foregroundStyle(.secondary)
            }
        case (_, .failed(let reason)):
            if installer.downloadedArchive != nil {
                Button("显示已下载的安装包") { installer.revealFallback() }
                    .help(reason)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(reason)
            }
        default:
            EmptyView()
        }
    }

    /// The installer walks the list on its own: primary host first, mirror
    /// second. One click, no route to choose.
    private func startInstall(version: String, downloads: [UpdateAsset]) {
        guard let primary = downloads.first else { return }
        Task {
            await installer.run(
                asset: primary,
                version: version,
                fallbacks: Array(downloads.dropFirst())
            )
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section("配置") {
            LabeledContent("命令配置") {
                Text(CommandStore.defaultFileURL.abbreviatedPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([CommandStore.defaultFileURL])
                }
                Button("打开日志文件夹") {
                    NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.logFileURL])
                }
                Spacer()
            }
        }
    }
}

// MARK: - About panel

/// The system about panel, shared by the app menu and the profile block.
/// No repository link in the credits: this build is handed to people as an
/// app, and a project URL is not something they asked to see.
@MainActor
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSMutableAttributedString(
            string: "Finder 右键菜单定制器",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "Quicklet",
            .applicationVersion: AppInfo.shortVersion,
            .version: "build \(AppInfo.build)",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

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
            linksSection
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

            if case .failed = checker.status, !checker.lastFailures.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("检查失败：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(checker.lastFailures) { failure in
                        Text("\(failure.source) · \(failure.reason)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Text("启动时最多每 24 小时查一次（失败后 1 小时重试）。更新包从 GitHub 下载，Gitee 作为备源。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "Update…" appears only while a newer version is known; installing and
    /// downloading states replace it in place so the row does not jump.
    @ViewBuilder
    private var updateAction: some View {
        switch (checker.status, installer.phase) {
        case (.available(let version, let sources), .idle):
            if let primary = sources.first {
                Button("更新…") {
                    startInstall(from: primary, version: version, all: sources)
                }
                if sources.count > 1 {
                    Menu("或从其他源下载") {
                        ForEach(sources, id: \.name) { source in
                            Button("从 \(source.name) 下载") {
                                startInstall(from: source, version: version, all: sources)
                            }
                            Button("打开 \(source.name) 发布页") {
                                NSWorkspace.shared.open(source.releaseURL)
                            }
                        }
                    }
                    .fixedSize()
                }
            }
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
                Button("显示下载的压缩包") { installer.revealFallback() }
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

    private func startInstall(from source: UpdateSource, version: String, all: [UpdateSource]) {
        guard let asset = source.asset else {
            NSWorkspace.shared.open(source.releaseURL)
            return
        }
        Task {
            await installer.run(
                asset: asset,
                version: version,
                releaseURL: source.releaseURL,
                fallbacks: all.filter { $0.name != source.name }.compactMap(\.asset)
            )
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Section("链接") {
            Button("GitHub 仓库（开发主线）") {
                open("https://github.com/TonyMistark/quicklet")
            }
            Button("Gitee 镜像（发布版）") {
                open("https://gitee.com/Micestark/quicklet")
            }
            Button("反馈问题") {
                open("https://github.com/TonyMistark/quicklet/issues")
            }
            Button("关于 Quicklet") {
                AboutPanel.show()
            }
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

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - About panel

/// The system about panel, shared by the app menu and the about page.
@MainActor
enum AboutPanel {
    static func show() {
        let repository = "https://github.com/TonyMistark/quicklet"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let text = "Finder 右键菜单定制器\ngithub.com/TonyMistark/quicklet"
        let credits = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        credits.addAttribute(
            .link,
            value: repository,
            range: (text as NSString).range(of: "github.com/TonyMistark/quicklet")
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

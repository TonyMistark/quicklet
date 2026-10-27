import SwiftUI
import AppKit

/// Shows the diagnostic log and any captured crash reports, so a failed
/// command or crash can be understood without digging through /var/log.
struct DiagnosticsView: View {
    @State private var logText: String = ""
    @State private var crashFiles: [URL] = []
    @State private var systemCrashes: [URL] = []
    @State private var sessionWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            logSection
            Divider()
            crashSection
        }
        .onAppear(perform: refresh)
    }

    // MARK: - Header

    // The page title lives in the settings shell; this row is actions only.
    private var header: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("刷新", action: refresh)
            Button("打开日志文件夹") {
                NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.logFileURL])
            }
            Button("清空日志") {
                Diagnostics.clearLog()
                refresh()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("运行日志").font(.subheadline.bold())
                Text(Diagnostics.logFileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                .controlSize(.small)
            }

            if let sessionWarning {
                Label(sessionWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                Text(logText.isEmpty ? "（暂无日志）" : logText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            .frame(minHeight: 200)
        }
        .padding(16)
    }

    // MARK: - Crashes

    private var crashSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("崩溃报告").font(.subheadline.bold())

            if crashFiles.isEmpty && systemCrashes.isEmpty {
                Text("没有发现崩溃报告")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(crashFiles, id: \.path) { file in
                fileRow(file, badge: "Quicklet")
            }
            ForEach(systemCrashes, id: \.path) { file in
                fileRow(file, badge: "系统")
            }
        }
        .padding(16)
    }

    private func fileRow(_ file: URL, badge: String) -> some View {
        HStack(spacing: 8) {
            Text(badge)
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Text(file.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("打开") { NSWorkspace.shared.open(file) }
                .controlSize(.small)
            Button("定位") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                .controlSize(.small)
        }
    }

    // MARK: - Data

    private func refresh() {
        logText = Diagnostics.recentLog()
        crashFiles = Diagnostics.crashReports()
        systemCrashes = Diagnostics.systemCrashReports()
        sessionWarning = Diagnostics.previousSessionWasUnclean
            ? "注意：上次退出属于非正常结束，可能发生过崩溃"
            : nil
    }
}

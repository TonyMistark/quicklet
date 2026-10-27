import SwiftUI
import AppKit

/// Explains and checks the macOS permissions Quicklet needs.
struct PermissionsView: View {
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess
    @State private var installedInApplications = Permissions.isInstalledInApplications
    @State private var bundlePath = Permissions.bundlePath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                section(
                    title: "完全磁盘访问权限",
                    granted: hasFullDiskAccess,
                    grantedText: "已授权，不会再逐次询问文件夹访问",
                    missingText: "未授权：命令访问桌面、文稿、下载时会反复弹窗"
                ) {
                    HStack(spacing: 8) {
                        Button("打开设置") { Permissions.openFullDiskAccessSettings() }
                        Button("检查一次") { refresh() }
                        Spacer()
                        Button("重新启动 Quicklet") { Permissions.restart() }
                    }
                    hint("""
                    在「隐私与安全性 → 完全磁盘访问权限」里点 + ，选择 /Applications/Quicklet.app，\
                    打开开关后重新启动 Quicklet。只需做一次，之后执行命令不再询问。
                    """)
                }

                section(
                    title: "安装位置",
                    granted: installedInApplications,
                    grantedText: "运行中的副本位于 /Applications",
                    missingText: "当前运行的副本不在 /Applications，权限会按副本分别记录"
                ) {
                    Text(bundlePath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    hint("""
                    同一份 App 存在多个副本时，quicklet:// 的处理程序会在副本之间跳，\
                    系统看到的是不同的程序身份，授权就会每次重新弹窗。\
                    请确保只保留 /Applications 里的一份，构建产物不要注册为处理器。
                    """)
                }

                section(
                    title: "Finder 扩展",
                    granted: true,
                    grantedText: "右键菜单已可用（能出现菜单项即说明已启用）",
                    missingText: ""
                ) {
                    Button("打开扩展设置") { Permissions.openExtensionsSettings() }
                    hint("系统设置 → 通用 → 登录项与扩展 → 扩展 → 添加到 Finder，勾选 Quicklet。")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: refresh)
    }

    // The page title lives in the settings shell, so this is only the action
    // row.
    private var header: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("刷新", action: refresh)
        }
    }

    private func section<Content: View>(
        title: String,
        granted: Bool,
        grantedText: String,
        missingText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.bold())
                Label(granted ? grantedText : missingText,
                      systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .labelStyle(.titleAndIcon)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func refresh() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        installedInApplications = Permissions.isInstalledInApplications
        bundlePath = Permissions.bundlePath
    }
}

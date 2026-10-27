import AppKit
import SwiftUI

// MARK: - Tabs

/// One page of the settings window. `rawValue` is persisted, so renaming a
/// case loses the reader's last position - new cases go at the end.
enum SettingsTab: String, CaseIterable, Identifiable {
    case commands
    case profile
    case permissions
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commands: return "命令"
        case .profile: return "个人信息"
        case .permissions: return "权限与安装"
        case .diagnostics: return "诊断与日志"
        case .about: return "应用与更新"
        }
    }

    var symbol: String {
        switch self {
        case .commands: return "list.bullet.rectangle"
        case .profile: return "person.crop.circle"
        case .permissions: return "lock.shield"
        case .diagnostics: return "stethoscope"
        case .about: return "shippingbox"
        }
    }

    /// Profile is the account block at the top of the sidebar, not a row in
    /// the list, exactly like a mail client's account header.
    var group: SettingsGroup {
        switch self {
        case .profile: return .profile
        case .commands: return .commands
        case .permissions, .diagnostics: return .maintenance
        case .about: return .about
        }
    }

    static let storageKey = "quicklet.settings.tab"
    static let fallback: SettingsTab = .commands
}

enum SettingsGroup: String, CaseIterable, Identifiable {
    case profile
    case commands
    case maintenance
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "个人信息"
        case .commands: return "菜单"
        case .maintenance: return "维护"
        case .about: return "应用"
        }
    }

    var tabs: [SettingsTab] {
        guard self != .profile else { return [] }
        return SettingsTab.allCases.filter { $0.group == self }
    }
}

// MARK: - Router

/// Which page the settings window shows. The window is a long-lived AppKit
/// window, so menu items switch pages through this object instead of opening
/// new windows (one window, several entry points).
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        tab = stored.flatMap(SettingsTab.init(rawValue:)) ?? SettingsTab.fallback
    }

    func open(_ tab: SettingsTab) {
        self.tab = tab
    }
}

/// Owns the update objects so both the about page and the menu bar share one
/// check state and one in-flight download.
@MainActor
enum UpdateCenter {
    static let checker = UpdateChecker()
    static let installer = UpdateInstaller()
}

// MARK: - Shell

/// Settings window: account block and page list on the left, the selected
/// page on the right. Fixed size, because a window that resizes per page
/// makes the eye hunt for the controls again.
struct SettingsShell: View {
    @ObservedObject var router: SettingsRouter
    @ObservedObject var store: CommandStore
    @ObservedObject var profile: ProfileStore

    private var tab: SettingsTab { router.tab }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: SettingsLayout.sidebarWidth)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Left

    /// Hand-drawn sidebar rather than `List`: the account block and the rows
    /// need the same hover/selection treatment, and List cannot do that.
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                account
                ForEach(SettingsGroup.allCases.filter { $0 != .profile }) { group in
                    Text(group.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 3)
                    ForEach(group.tabs) { item in
                        sidebarRow(item)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var account: some View {
        Button {
            router.open(.profile)
        } label: {
            HStack(spacing: 9) {
                ProfileAvatar(image: profile.avatar, initial: profile.initial, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(profile.hasNickname ? "只存在这台 Mac 上" : "点这里设置昵称与头像")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(tab == .profile ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("昵称与头像，保存在本机")
        .padding(.top, 10)
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        let selected = item == tab
        return Button {
            router.open(item)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12.5))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item == .about, UpdateCenter.checker.status.hasUpdateBadge {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(selected ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    // MARK: Right

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 2)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .commands: CommandsPage(store: store)
        case .profile: ProfileSettingsView(profile: profile)
        case .permissions: PermissionsView()
        case .diagnostics: DiagnosticsView()
        case .about: AboutSettingsView(
            profile: profile,
            checker: UpdateCenter.checker,
            installer: UpdateCenter.installer
        )
        }
    }
}

enum SettingsLayout {
    static let width: CGFloat = 820
    static let height: CGFloat = 580
    static let sidebarWidth: CGFloat = 196
}

extension UpdateStatus {
    /// One line for the sidebar badge / about page.
    var summary: String? {
        switch self {
        case .idle: return nil
        case .checking: return "正在检查…"
        case .upToDate(let version): return "v\(version) 已是最新"
        case .available(let version, _): return "v\(version) 可更新"
        case .failed: return "上次检查失败"
        }
    }

    var hasUpdateBadge: Bool {
        if case .available = self { return true }
        return false
    }
}

// MARK: - Avatar

/// Round avatar with an initial as fallback.
struct ProfileAvatar: View {
    let image: NSImage?
    let initial: String
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
    }
}

import SwiftUI

/// Command list plus detail pane. This is a page inside the settings window,
/// so it uses a plain split instead of a NavigationSplitView: nesting a
/// navigation stack inside an AppKit-hosted window adds a title bar we do not
/// want.
///
/// The detail pane IS the editor: selecting a command shows its editable form
/// right away, and every change autosaves through the store's debounced write.
/// There is no modal editor - "+" creates a disabled draft instead.
struct CommandsPage: View {
    @ObservedObject var store: CommandStore
    @State private var selectedID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                listHeader
                Divider()
                list
            }
            .frame(width: 236)
            Divider()
            detail
        }
        .onAppear {
            // Show something editable right away instead of an empty pane.
            if selectedID == nil {
                selectedID = store.commands.first?.id
            }
        }
    }

    // MARK: - List

    private var listHeader: some View {
        HStack(spacing: 4) {
            Text("\(store.commands.count) 条命令")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                addDraft()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("新建命令")

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .help("删除选中命令")
            .disabled(selectedID == nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var list: some View {
        List(selection: $selectedID) {
            ForEach($store.commands) { $command in
                CommandRow(command: $command)
                    .tag(command.id)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            store.commands.removeAll { $0.id == command.id }
                        }
                    }
            }
            .onDelete { indexSet in
                store.commands.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.inset)
        .overlay {
            if store.commands.isEmpty {
                Text("还没有自定义命令，点 + 新建一个")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID,
           let index = store.commands.firstIndex(where: { $0.id == id }) {
            CommandInspector(command: $store.commands[index], allCommands: store.commands)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 38))
                    .foregroundStyle(.tertiary)
                Text("选择左侧命令，或点 + 新建")
                    .foregroundStyle(.secondary)
                Text("选中后直接在这里编辑，修改会自动保存")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                EnableExtensionHint()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // MARK: - Actions

    /// Creates a disabled draft and selects it, so the inspector opens on a
    /// blank form instead of a modal. Disabled drafts never reach the menu.
    private func addDraft() {
        var draft = QuickletCommand()
        draft.enabled = false
        store.commands.append(draft)
        selectedID = draft.id
    }

    private func deleteSelected() {
        guard let id = selectedID,
              let index = store.commands.firstIndex(where: { $0.id == id }) else { return }
        store.commands.remove(at: index)
        selectedID = nil
    }
}

// MARK: - Row

private struct CommandRow: View {
    @Binding var command: QuickletCommand

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon.isEmpty ? "questionmark" : command.icon)
                .frame(width: 20)
                .foregroundStyle(command.enabled ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.name.isEmpty ? "（未命名）" : command.name)
                    .strikethrough(!command.enabled)
                if command.isGrouped {
                    Text(command.menuPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if command.script.isEmpty {
                Text("未设置命令")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Inspector

/// Inline editor shown in the detail pane. Fields bind straight to the store,
/// so edits autosave (the store debounces writes); no Save/Cancel step.
struct CommandInspector: View {
    @Binding var command: QuickletCommand
    let allCommands: [QuickletCommand]

    // Group fields need local state because the model stores one path array
    // while the UI edits two levels; they re-sync when the selection changes.
    @State private var isGrouped: Bool
    @State private var group1: String
    @State private var group2: String

    private let presetIcons = [
        "terminal", "chevron.left.forwardslash.chevron.right", "folder",
        "doc.text", "link", "photo", "archivebox", "trash",
        "square.and.arrow.up", "scissors", "tag", "wand.and.stars",
    ]

    init(command: Binding<QuickletCommand>, allCommands: [QuickletCommand]) {
        _command = command
        self.allCommands = allCommands
        _isGrouped = State(initialValue: !command.wrappedValue.group.isEmpty)
        _group1 = State(initialValue: command.wrappedValue.group.first ?? "")
        _group2 = State(initialValue: command.wrappedValue.group.count > 1 ? command.wrappedValue.group[1] : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                iconSection
                placementSection
                scriptSection
                promptSection
            }
            .padding(20)
        }
        .onChange(of: command.id) { _ in syncGroupStates() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon.isEmpty ? "questionmark" : command.icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            TextField("名称", text: $command.name)
                .textFieldStyle(.plain)
                .font(.title2.bold())
            Toggle("已启用", isOn: $command.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: Icon

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("图标（SF Symbol）")
            HStack(spacing: 12) {
                Image(systemName: command.icon.isEmpty ? "questionmark" : command.icon)
                    .frame(width: 24)
                    .foregroundStyle(Color.accentColor)
                TextField("SF Symbol 名称", text: $command.icon)
                    .textFieldStyle(.roundedBorder)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetIcons, id: \.self) { name in
                        Button {
                            command.icon = name
                        } label: {
                            Image(systemName: name)
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.bordered)
                        .tint(command.icon == name ? .accentColor : .primary)
                    }
                }
            }
        }
    }

    // MARK: Placement

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("菜单位置")
            Picker("显示位置", selection: $isGrouped) {
                Text("右键第一层").tag(false)
                Text("Quicklet 菜单内").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: isGrouped) { _ in applyGroup() }

            if isGrouped {
                HStack(spacing: 8) {
                    groupField("一级分组", text: $group1, suggestions: firstLevelGroups)
                    groupField("二级分组（可选）", text: $group2, suggestions: secondLevelGroups)
                }
                Text("路径：Quicklet › \(pathPreview)")
                    .font(.caption)
                    .foregroundStyle(isGroupValid ? Color.secondary : Color.orange)
            } else {
                Text("直接出现在 Finder 右键菜单的第一层。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Script

    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Shell 命令模板")
            TextEditor(text: $command.script)
                .font(.system(.body, design: .monospaced))
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
                .overlay(alignment: .topLeading) {
                    if command.script.isEmpty {
                        Text(#"例如：open -a Terminal "{dir}""#)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 12)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                }
            HStack(spacing: 6) {
                ForEach(["{paths}", "{path}", "{dir}", "{parent}", "{input}"], id: \.self) { token in
                    Text(token)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                        .help(tokenHelp(token))
                }
                Spacer()
                Text("路径自动转义，\"{dir}\" 不会双重引号")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func tokenHelp(_ token: String) -> String {
        switch token {
        case "{paths}": return "全部选中路径"
        case "{path}": return "第一个选中路径"
        case "{dir}": return "工作目录：选中文件夹即它本身"
        case "{parent}": return "所在目录"
        case "{input}": return "执行前输入框的内容"
        default: return token
        }
    }

    // MARK: Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("执行前输入（可选）")
            TextField("输入框标题（留空则不弹输入框）", text: promptTitleBinding)
                .textFieldStyle(.roundedBorder)
            TextField("输入框占位提示，例如：文件名，如 notes.md", text: promptPlaceholderBinding)
                .textFieldStyle(.roundedBorder)
            Text("填写标题后，命令执行前会弹出输入框；输入内容在模板中用 {input} 引用（自动 shell 转义）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // Optional prompt fields map to nil when the text field is empty, so a
    // command keeps "no prompt" semantics until a title is typed.
    private var promptTitleBinding: Binding<String> {
        Binding(
            get: { command.promptTitle ?? "" },
            set: { command.promptTitle = $0.isEmpty ? nil : $0 }
        )
    }

    private var promptPlaceholderBinding: Binding<String> {
        Binding(
            get: { command.promptPlaceholder ?? "" },
            set: { command.promptPlaceholder = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: Grouping

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func syncGroupStates() {
        isGrouped = !command.group.isEmpty
        group1 = command.group.first ?? ""
        group2 = command.group.count > 1 ? command.group[1] : ""
    }

    /// Writes the two local group fields back to the model's path array.
    private func applyGroup() {
        let first = group1.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = group2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isGrouped, !first.isEmpty else {
            command.group = []
            return
        }
        command.group = second.isEmpty ? [first] : [first, second]
    }

    private var trimmedGroup1: String {
        group1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedGroup2: String {
        group2.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isGroupValid: Bool {
        !isGrouped || !trimmedGroup1.isEmpty
    }

    private var pathPreview: String {
        guard !trimmedGroup1.isEmpty else { return "（先填写一级分组）" }
        return trimmedGroup2.isEmpty ? trimmedGroup1 : "\(trimmedGroup1) › \(trimmedGroup2)"
    }

    /// Existing first-level group names, so the user can reuse instead of
    /// retyping (a typo would silently create a second menu).
    private var firstLevelGroups: [String] {
        Set(allCommands.map(\.group).compactMap(\.first)).sorted()
    }

    private var secondLevelGroups: [String] {
        let parent = trimmedGroup1
        guard !parent.isEmpty else { return [] }
        let names = allCommands
            .map(\.group)
            .filter { $0.count > 1 && $0[0] == parent }
            .map { $0[1] }
        return Array(Set(names)).sorted()
    }

    private func groupField(
        _ title: String,
        text: Binding<String>,
        suggestions: [String]
    ) -> some View {
        HStack(spacing: 6) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _ in applyGroup() }
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) {
                            text.wrappedValue = name
                            applyGroup()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("选择已有分组")
            }
        }
    }
}

// MARK: - Enable-extension hint

struct EnableExtensionHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("启用 Finder 扩展")
                .font(.headline)
            Text("系统设置 → 通用 → 登录项与扩展 → 扩展 → 添加到 Finder → 勾选 Quicklet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("打开系统设置") {
                Permissions.openExtensionsSettings()
            }
            .controlSize(.small)
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

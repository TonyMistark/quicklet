import SwiftUI

/// Sheet for creating or editing a single command.
struct CommandEditorView: View {
    enum Result {
        case saved(QuickletCommand)
        case cancelled
    }

    @State private var command: QuickletCommand
    private let isNew: Bool
    private let allCommands: [QuickletCommand]
    private let completion: (Result) -> Void

    @State private var selectedIcon: String
    @State private var isGrouped: Bool
    @State private var group1: String
    @State private var group2: String
    @Environment(\.dismiss) private var dismiss

    private let presetIcons = [
        "terminal", "chevron.left.forwardslash.chevron.right", "folder",
        "doc.text", "link", "photo", "archivebox", "trash",
        "square.and.arrow.up", "scissors", "tag", "wand.and.stars",
    ]

    init(
        command: QuickletCommand,
        isNew: Bool,
        allCommands: [QuickletCommand] = [],
        completion: @escaping (Result) -> Void
    ) {
        _command = State(initialValue: command)
        _selectedIcon = State(initialValue: command.icon)
        _isGrouped = State(initialValue: !command.group.isEmpty)
        _group1 = State(initialValue: command.group.first ?? "")
        _group2 = State(initialValue: command.group.count > 1 ? command.group[1] : "")
        self.isNew = isNew
        self.allCommands = allCommands
        self.completion = completion
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("名称", text: $command.name)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("菜单项名称")
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIcon.isEmpty ? "questionmark" : selectedIcon)
                            .frame(width: 28)
                            .foregroundStyle(Color.accentColor)
                        TextField("SF Symbol 名称", text: $selectedIcon)
                            .textFieldStyle(.roundedBorder)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presetIcons, id: \.self) { name in
                                Button {
                                    selectedIcon = name
                                } label: {
                                    Image(systemName: name)
                                        .frame(width: 30, height: 26)
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedIcon == name ? .accentColor : .primary)
                            }
                        }
                    }
                } header: {
                    Text("图标（SF Symbol）")
                }

                Section {
                    Picker("显示位置", selection: $isGrouped) {
                        Text("右键第一层").tag(false)
                        Text("Quicklet 菜单内").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if isGrouped {
                        groupField("一级分组", text: $group1, suggestions: firstLevelGroups)
                        groupField("二级分组（可选）", text: $group2, suggestions: secondLevelGroups)
                        Text("路径：Quicklet › \(pathPreview)")
                            .font(.caption)
                            .foregroundStyle(isGroupValid ? Color.secondary : Color.orange)
                    } else {
                        Text("直接出现在 Finder 右键菜单的第一层。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("菜单位置")
                }

                Section {
                    TextEditor(text: $command.script)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 90)
                        .overlay(alignment: .topLeading) {
                            if command.script.isEmpty {
                                Text(#"例如：open -a Terminal "{dir}""#)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    Text("占位符：{paths} 全部选中路径 · {path} 第一个路径 · {dir} 工作目录（选中文件夹即它本身）· {parent} 所在目录 · {input} 输入框内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Shell 命令模板")
                }

                Section {
                    TextField("输入框标题（留空则不弹输入框）", text: promptTitleBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField("输入框占位提示，例如：文件名，如 notes.md", text: promptPlaceholderBinding)
                        .textFieldStyle(.roundedBorder)
                    Text("填写标题后，命令执行前会弹出输入框；输入内容在模板中用 {input} 引用（自动 shell 转义）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("执行前输入（可选）")
                }

                Section {
                    Toggle("在 Finder 右键菜单中启用", isOn: $command.enabled)
                }
            }
            .formStyle(.grouped)
            .padding(.top, 8)

            HStack {
                Spacer()
                Button("取消") {
                    completion(.cancelled)
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "添加" : "存储") {
                    command.icon = selectedIcon
                    command.group = resolvedGroup
                    completion(.saved(command))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.isBlank || !isGroupValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480)
    }

    // Optional prompt fields map to nil when the text field is empty, so a
    // command keeps "no prompt" semantics until a title is typed.
    private var promptTitleBinding: Binding<String> {
        Binding(
            get: { command.promptTitle ?? "" },
            set: { command.promptTitle = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Grouping

    private var trimmedGroup1: String {
        group1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedGroup2: String {
        group2.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Group path written back to the model; a group needs a first level, and
    /// leaving the section untouched keeps the command at the first level.
    private var resolvedGroup: [String] {
        guard isGrouped, !trimmedGroup1.isEmpty else { return [] }
        return trimmedGroup2.isEmpty ? [trimmedGroup1] : [trimmedGroup1, trimmedGroup2]
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
        uniqueFirstLevel.sorted()
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

    private var uniqueFirstLevel: Set<String> {
        Set(allCommands.map(\.group).compactMap(\.first))
    }

    private func groupField(
        _ title: String,
        text: Binding<String>,
        suggestions: [String]
    ) -> some View {
        HStack(spacing: 8) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) { text.wrappedValue = name }
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

    private var promptPlaceholderBinding: Binding<String> {
        Binding(
            get: { command.promptPlaceholder ?? "" },
            set: { command.promptPlaceholder = $0.isEmpty ? nil : $0 }
        )
    }
}

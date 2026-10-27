import SwiftUI

/// Sheet for creating or editing a single command.
struct CommandEditorView: View {
    enum Result {
        case saved(QuickletCommand)
        case cancelled
    }

    @State private var command: QuickletCommand
    private let isNew: Bool
    private let completion: (Result) -> Void

    @State private var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let presetIcons = [
        "terminal", "chevron.left.forwardslash.chevron.right", "folder",
        "doc.text", "link", "photo", "archivebox", "trash",
        "square.and.arrow.up", "scissors", "tag", "wand.and.stars",
    ]

    init(command: QuickletCommand, isNew: Bool, completion: @escaping (Result) -> Void) {
        _command = State(initialValue: command)
        _selectedIcon = State(initialValue: command.icon)
        self.isNew = isNew
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
                    completion(.saved(command))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.isBlank)
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

    private var promptPlaceholderBinding: Binding<String> {
        Binding(
            get: { command.promptPlaceholder ?? "" },
            set: { command.promptPlaceholder = $0.isEmpty ? nil : $0 }
        )
    }
}

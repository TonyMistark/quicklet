import SwiftUI

/// Command list plus detail pane. This is a page inside the settings window,
/// so it uses a plain split instead of a NavigationSplitView: nesting a
/// navigation stack inside an AppKit-hosted window adds a title bar we do not
/// want.
struct CommandsPage: View {
    @ObservedObject var store: CommandStore
    @State private var selectedID: UUID?
    @State private var editingCommand: QuickletCommand?
    @State private var isShowingEditor = false
    @State private var isEditingNew = false

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
        .sheet(isPresented: $isShowingEditor) {
            CommandEditorView(
                command: editingCommand ?? QuickletCommand(),
                isNew: isEditingNew,
                allCommands: store.commands
            ) { result in
                switch result {
                case .saved(let command):
                    saveCommand(command)
                case .cancelled:
                    break
                }
                isShowingEditor = false
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
                startEditingNew()
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
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startEditing(command) }
                    .contextMenu {
                        Button("编辑…") { startEditing(command) }
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
           let command = store.commands.first(where: { $0.id == id }) {
            CommandDetail(command: command) {
                startEditing(command)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 38))
                    .foregroundStyle(.tertiary)
                Text("选择左侧命令，或点 + 新建")
                    .foregroundStyle(.secondary)
                EnableExtensionHint()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // MARK: - Actions

    private func startEditing(_ command: QuickletCommand) {
        selectedID = command.id
        editingCommand = command
        isEditingNew = false
        isShowingEditor = true
    }

    private func startEditingNew() {
        selectedID = nil
        editingCommand = QuickletCommand()
        isEditingNew = true
        isShowingEditor = true
    }

    private func deleteSelected() {
        guard let id = selectedID,
              let index = store.commands.firstIndex(where: { $0.id == id }) else { return }
        store.commands.remove(at: index)
        selectedID = nil
    }

    private func saveCommand(_ command: QuickletCommand) {
        if let index = store.commands.firstIndex(where: { $0.id == command.id }) {
            store.commands[index] = command
        } else {
            store.commands.append(command)
        }
        selectedID = command.id
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

// MARK: - Detail pane

private struct CommandDetail: View {
    let command: QuickletCommand
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: command.icon.isEmpty ? "questionmark" : command.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    Text(command.name.isEmpty ? "（未命名）" : command.name)
                        .font(.title2.bold())
                    Spacer()
                    Button("编辑…", action: onEdit)
                }

                LabeledContent("菜单位置") {
                    Text(command.menuPath)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LabeledContent("脚本") {
                    Text(command.script.isEmpty ? "未设置" : command.script)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if command.needsInput {
                    LabeledContent("执行前输入") {
                        Text(command.promptTitle ?? "")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("占位符：{paths} 全部选中路径 · {path} 第一个路径 · {dir} 工作目录（选中文件夹即它本身）· {parent} 所在目录 · {input} 输入框内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
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

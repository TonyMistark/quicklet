import SwiftUI

/// Main configuration window: lists all custom commands and allows
/// adding, editing, deleting and toggling them.
struct ContentView: View {
    @ObservedObject var store: CommandStore
    @State private var editingCommand: QuickletCommand?
    @State private var isShowingEditor = false
    @State private var isEditingNew = false

    var body: some View {
        NavigationSplitView {
            List {
                ForEach($store.commands) { $command in
                    CommandRow(command: $command)
                        .contentShape(Rectangle())
                        .onTapGesture { startEditing(command) }
                }
                .onDelete { indexSet in
                    store.commands.remove(atOffsets: indexSet)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if store.commands.isEmpty {
                    Text("还没有自定义命令，点击 + 新建一个")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailView
        }
        .navigationTitle("Quicklet")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    startEditingNew()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新建命令")

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .help("删除选中命令")
                .disabled(selectedID == nil)
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            CommandEditorView(
                command: editingCommand ?? QuickletCommand(),
                isNew: isEditingNew
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

    // MARK: - Selection

    @State private var selectedID: UUID?

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
            selectedID = command.id
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let id = selectedID,
           let command = store.commands.first(where: { $0.id == id }) {
            CommandDetail(command: command)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("选择左侧命令，或点击 + 新建")
                    .foregroundStyle(.secondary)
                EnableExtensionHint()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
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
            Text(command.name.isEmpty ? "（未命名）" : command.name)
                .strikethrough(!command.enabled)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: command.icon.isEmpty ? "questionmark" : command.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                Text(command.name.isEmpty ? "（未命名）" : command.name)
                    .font(.title2.bold())
                Spacer()
            }

            LabeledContent("脚本") {
                Text(command.script.isEmpty ? "未设置" : command.script)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("在 Finder 脚本中可用占位符：{paths}（全部选中路径）、{path}（第一个路径）、{dir}（工作目录：选中文件夹时是它本身，选中文件时是所在目录）、{parent}（始终为所在目录）")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

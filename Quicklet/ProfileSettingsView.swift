import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Nickname and picture. Both are local only - the sentence on this page is a
/// promise, not decoration.
struct ProfileSettingsView: View {
    @ObservedObject var profile: ProfileStore
    /// Shown when a picked file cannot be decoded, instead of doing nothing.
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    ProfileAvatar(image: profile.avatar, initial: profile.initial, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("选择图片…") { choosePicture() }
                            if profile.avatar != nil {
                                Button("移除") { profile.clearAvatar() }
                            }
                        }
                        Text("PNG、JPEG、HEIC 都可以，会统一存成 PNG。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let failure {
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.vertical, 4)

                TextField(
                    "昵称",
                    text: $profile.nickname,
                    prompt: Text("希望 Quicklet 怎么称呼你？")
                )
                .textFieldStyle(.roundedBorder)
            }

            Section {
                Text("昵称和头像只保存在这台 Mac 上（App Group 容器内），不会上传，也不会写进命令配置。留空时显示当前 macOS 账户名。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if profile.setAvatar(from: url) {
            failure = nil
        } else {
            failure = "这个文件读不出图像，换一张试试。"
        }
    }
}

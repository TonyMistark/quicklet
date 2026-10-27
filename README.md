# Quicklet

macOS Finder 右键菜单定制器：把你的自定义 Shell 命令加进 Finder 右键第一级菜单。

- 主 App（SwiftUI）：管理命令列表（名称 / SF Symbol 图标 / Shell 模板 / 启用开关）
- FinderSync 扩展：读取配置，在 Finder 右键菜单里渲染自定义项并执行
- 配置共享：App Group 容器（`group.com.ice.quicklet`）里的 `commands.json`，主 App 改完扩展立即生效

## 系统要求

- macOS 13.0+
- Xcode（含命令行工具）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- 钥匙串中有 "Apple Development" 签名证书

## 构建与安装

```sh
xcodegen generate        # 首次或修改 project.yml 后
scripts/build.sh         # 构建 + 用本机开发证书重签
cp -R build/Build/Products/Debug/Quicklet.app /Applications/
open /Applications/Quicklet.app
```

启用扩展：**系统设置 → 通用 → 登录项与扩展 → 扩展 → 添加到 Finder** → 勾选 Quicklet。

> 直接在 Xcode 里 ⌘B/⌘R 也可以，但需要在 Signing & Capabilities 里登录 Apple ID
> （App Groups 在新系统上要求 provisioning profile）。`scripts/build.sh` 是绕过方案：
> ad-hoc 构建，再用本机钥匙串里的开发证书重签。

## 脚本占位符

| 占位符 | 含义 |
| --- | --- |
| `{paths}` | 全部选中路径（shell 转义、空格分隔） |
| `{path}` | 第一个选中路径 |
| `{dir}` | 第一个选中项所在目录 |

示例：`open -a Terminal "{dir}"`、`open -a "Visual Studio Code" {paths}`

## 配置文件位置

`~/Library/Group Containers/group.com.ice.quicklet/commands.json`

## 已知限制 / Roadmap

- [ ] 按选中类型（文件/文件夹）过滤菜单项
- [ ] 沙箱内执行 shell 受限（无网络、文件访问受限）；计划加非沙箱 Helper 通过 XPC 执行
- [ ] 快捷键、子菜单分组、菜单排序
- [ ] Developer ID 签名分发

## 项目结构

```
project.yml            # xcodegen 配置
Quicklet/              # 主 App（SwiftUI）
FinderSync/            # Finder Sync 扩展
Shared/                # 两端共享：命令模型 + JSON 存储
scripts/build.sh       # 构建 + 重签脚本
```

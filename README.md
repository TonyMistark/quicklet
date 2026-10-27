# Quicklet

macOS Finder 右键菜单定制器：把你的自定义 Shell 命令加进 Finder 右键第一级菜单。

## 架构

Finder Sync 扩展必须运行在 App Sandbox 里（系统强制），而沙箱内**不能启动子进程**，
所以执行链路拆成两段：

```
Finder 右键点击
   └─ QuickletFinder.appex（沙箱）   只负责读取配置、渲染菜单
        └─ quicklet://run?id=<UUID>&path=...   URL scheme 传话
             └─ Quicklet.app（非沙箱、菜单栏常驻）  真正执行 shell / 打开其他 App
```

- 配置共享：App Group 容器（`group.com.ice.quicklet`）里的 `commands.json`
- 扩展每次弹出菜单都会重读配置，主 App 改完立即生效
- 命令用 UUID 传递，两端读取同一份 JSON，id 一致

## 使用

- 主 App 是菜单栏工具（`LSUIElement`，无 Dock 图标）：点菜单栏图标 → **Quicklet 设置…**
- 设置窗口里增删命令：名称、SF Symbol 图标、Shell 模板、启用开关
- 首次运行时若扩展没出现，去 **系统设置 → 通用 → 登录项与扩展 → 扩展 → 添加到 Finder** 勾选 Quicklet

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

> 直接在 Xcode 里 ⌘B/⌘R 也可以，但需要在 Signing & Capabilities 里登录 Apple ID
> （App Groups 在新系统上要求 provisioning profile）。`scripts/build.sh` 是绕过方案：
> ad-hoc 构建（跳过 entitlements 嵌入），再用本机钥匙串里的开发证书重签，
> 分别嵌入 app / appex 的 entitlements。

## 脚本占位符

| 占位符 | 含义 |
| --- | --- |
| `{paths}` | 全部选中路径（shell 转义、空格分隔） |
| `{path}` | 第一个选中路径 |
| `{dir}` | 第一个选中项所在目录 |

示例：`open -a Terminal "{dir}"`、`open -a "Visual Studio Code" {paths}`

## 配置文件位置

`~/Library/Group Containers/group.com.ice.quicklet/commands.json`

## 诊断与崩溃收集

菜单栏图标 → **诊断与日志…**，可以查看：

- **运行日志**：每条命令展开后的脚本、退出码、stderr（两类进程分别标注 `[Quicklet]` / `[QuickletFinder]`）
- **崩溃报告**：Quicklet 自己捕获的崩溃（含调用栈）+ 系统 `.ips` 报告入口
- **异常退出提示**：上次如果没正常退出，会在窗口里标出

文件位置（App Group 容器内，两端共享）：

| 文件 | 说明 |
| --- | --- |
| `Logs/quicklet.log` | 滚动日志，超过 512 KB 自动轮转一份 `.1` |
| `Logs/session.active` | 会话标记，正常退出/SIGTERM 会清除 |
| `Crashes/crash-*.txt` | 未捕获异常（含完整调用栈）与崩溃信号（`SIGSEGV` 等）记录 |

捕获范围：`NSSetUncaughtExceptionHandler` + `SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGFPE/SIGTRAP`。
信号处理里只做 `write(2)`、`unlink(2)` 和栈回溯，避免崩溃时再崩；之后恢复默认处理，
系统自身的 `.ips` 报告仍会正常生成。

## 已知限制 / Roadmap

- [ ] 按选中类型（文件/文件夹）过滤菜单项
- [ ] 每次执行都会拉起/复用主 App；后续可改为 XPC Mach service，省掉 URL 跳转
- [ ] 快捷键、子菜单分组、菜单排序
- [ ] Developer ID 签名分发（需要为两个 bundle 各配一个描述文件）

## 项目结构

```
project.yml                 # xcodegen 配置
Quicklet/                   # 主 App（SwiftUI，菜单栏 + 设置窗口 + URL 处理）
FinderSync/                 # Finder Sync 扩展（仅渲染菜单 + 传话）
Shared/                     # 两端共享：命令模型、JSON 存储、URL 协议、执行器
scripts/build.sh            # 构建 + 重签脚本
scripts/app.entitlements    # 主 App：仅 App Groups（不沙箱）
scripts/appex.entitlements  # 扩展：沙箱 + App Groups
```

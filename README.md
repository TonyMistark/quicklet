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

## 权限（为什么之前每次执行都弹授权）

命令是在主 App 里跑的，凡是访问桌面、文稿、下载、外置磁盘，macOS 都会按「App × 文件夹」逐次询问。
弹窗反复出现通常是下面两个原因叠加：

1. **同一份 App 有多个副本**。`quicklet://` 被几个 bundle 同时认领时，由哪个副本响应是随机的，
   而每个副本的代码身份不同，macOS 会把它们当成不同的程序，之前记下的授权就不再生效。
   检查当前有哪些副本在抢占：

   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
     | awk '/^path:/{p=$0} /claimed schemes:.*quicklet:/{print p}'
   ```

   应当只有 `/Applications/Quicklet.app` 一条。多余的副本（build 产物、废纸篓里的旧版本）
   用 `lsregister -u <路径>` 注销，或直接从废纸篓清掉。

2. **没有完全磁盘访问权限**。授予一次之后，逐文件夹询问会被整体覆盖，不再弹窗。

菜单栏图标 → **权限与安装…** 可以查看当前状态、一键跳到对应系统设置面板，并重启 App 让新授权生效
（macOS 对单个进程缓存 TCC 决定，授权后必须重启）。

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
scripts/build.sh         # 构建 + 用本机开发证书重签 + 安装到 /Applications 并启动
```

`scripts/build.sh` 会顺带做三件容易忘的事：杀掉旧实例、把 bundle 装到 `/Applications`、
注销 build 产物与废纸篓旧副本的 `quicklet://` 注册（避免授权被多个副本打散）。
不想自动安装可以设 `QUICKLET_INSTALL_DIR` 到别处或指向不可写路径。

> 直接在 Xcode 里 ⌘B/⌘R 也可以，但需要在 Signing & Capabilities 里登录 Apple ID
> （App Groups 在新系统上要求 provisioning profile）。`scripts/build.sh` 是绕过方案：
> ad-hoc 构建（跳过 entitlements 嵌入），再用本机钥匙串里的开发证书重签，
> 分别嵌入 app / appex 的 entitlements。

## 脚本占位符

| 占位符 | 含义 |
| --- | --- |
| `{paths}` | 全部选中路径（shell 转义、空格分隔） |
| `{path}` | 第一个选中路径 |
| `{dir}` | 工作目录：**选中文件夹时是它本身**，选中文件时是它所在目录 |
| `{parent}` | 第一个选中项所在目录（无论选中的是不是文件夹） |
| `{input}` | 执行前输入框里填的内容（仅当命令设了「输入框标题」时可用） |

示例：`open -a Terminal "{dir}"`、`open -a "Visual Studio Code" {paths}`

> `{dir}` 早先是「无条件取父目录」，右键文件夹时会退到上一层（在 home 下的文件夹就直接退到 home），
> 看起来像完全没拿到选择。现在按所选类型判断，`{parent}` 保留旧语义。

> 在文件夹空白处右键（没有选中任何项）时，扩展会回退到 Finder 当前正在查看的文件夹，
> 所以「新建文件」这类命令在空白处右键也能用。

## 执行前输入（新建文件等）

命令可以配置一个「输入框标题」，执行前会弹出输入框，输入内容通过 `{input}` 引用。
内置示例：

| 字段 | 值 |
| --- | --- |
| 名称 | `新建文件…` |
| 输入框标题 | `新建文件` |
| 占位提示 | `文件名，例如 notes.md` |
| 模板 | `test -e {dir}/{input} && { echo "同名文件已存在，未覆盖"; exit 1; }; touch {dir}/{input}; open -R {dir}/{input}` |

行为：在目标文件夹里创建空文件，创建后在 Finder 中选中它；若同名文件已存在则拒绝覆盖。

同一个机制也能做别的事，比如新建文件夹（`mkdir -p {dir}/{input}`）、
`git clone {input}`、按输入名重命名（`mv {path} {parent}/{input}`）。

## 配置文件位置

`~/Library/Group Containers/group.com.ice.quicklet/commands.json`

## 分组（Quicklet 子菜单）

每个命令有两种位置：

1. **右键第一层**（默认）——直接出现在 Finder 右键菜单里
2. **Quicklet 菜单内**——收进固定的 `Quicklet` 子菜单，按分组排

规则：

- `Quicklet` 是**固定入口**，名称不可改、不可删；即使没有任何分组命令，这一项也仍然存在（显示一条提示项）
- 分组最多**两层**：`Quicklet › 分组 › 子分组`；配置里手写更深的路径会被自动截断到两层
- 分组本身不需要预先创建，由命令的 `group` 路径定义；同名路径自动合并成同一个菜单
- 编辑器「菜单位置」里填分组名，右侧下拉箭头可以从已有分组里挑（避免手打拼错，拼错会生成两个同名菜单）

配置里对应关系：

| 配置 | 效果 |
| --- | --- |
| `"group": []` | 右键第一层 |
| `"group": ["文件"]` | `Quicklet › 文件 › 命令` |
| `"group": ["开发", "Git"]` | `Quicklet › 开发 › Git › 命令` |

菜单结构会写进诊断日志，方便确认层级符合预期：

```
menu structure: 文件{复制路径}
```

> 菜单树由 `Shared/MenuTree.swift` 解析（纯逻辑，可脱离 Finder 单独测试），
> 扩展只负责把结果渲染成 NSMenu。

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

## 仓库与发布

| 远程 | 地址 | 用途 |
| --- | --- | --- |
| `origin` | `git@github.com:TonyMistark/quicklet.git` | **开发主线**，所有提交都推这里 |
| `gitee` | `git@gitee.com:Micestark/quicklet.git` | **仅发布镜像**，只在打版本时同步 |

日常开发只跟 GitHub 打交道：

```sh
git push            # 等价于 git push origin main（remote.pushDefault 已设为 origin）
```

发版本时用脚本一次搞定（打 tag → 推 GitHub → 镜像到 Gitee）：

```sh
scripts/release.sh v1.0.0          # 打 tag 并同步
scripts/release.sh v1.0.0 --build  # 先构建，额外产出 dist/Quicklet-v1.0.0.zip
```

脚本会在动手前检查：必须在 `main` 分支、工作区必须干净、tag 不能已存在。
构建产物 `dist/*.zip` 用于上传到 Gitee 的 Release 附件。

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
Shared/                     # 两端共享：命令模型、JSON 存储、URL 协议、执行器、权限检查
scripts/build.sh            # 构建 + 重签 + 安装到 /Applications
scripts/release.sh          # 打 tag 并同步 GitHub / Gitee
dist/                       # release.sh --build 产出的安装包（未纳入版本管理）
scripts/app.entitlements    # 主 App：仅 App Groups（不沙箱）
scripts/appex.entitlements  # 扩展：沙箱 + App Groups
```

# 语境输入法（LO Input Method）

> 边写边翻译的智能输入法 —— 打字的同时，悬浮窗实时显示翻译结果，无需切换应用。

<div align="center">
  <p><strong>课程与交流</strong></p>
  <p><a href="https://space.bilibili.com/481791559">B 站课程与动态：语境输入法作者空间</a></p>
  <p>微信交流：</p>
  <img src="assets/images/vx.png" width="180" alt="微信二维码" />
</div>

> 本项目是 macOS 原生输入法，不是前后端分离的网站项目；无需启动后端服务。克隆后可按下方步骤构建并体验。

[![macOS Build](https://github.com/chengpeng-cp/lo/actions/workflows/build-macos.yml/badge.svg)](https://github.com/chengpeng-cp/lo/actions/workflows/build-macos.yml)
<!-- Windows 端尚在调试，暂不对外发布
[![Windows Build](https://github.com/chengpeng-cp/lo/actions/workflows/build-windows.yml/badge.svg)](https://github.com/chengpeng-cp/lo/actions/workflows/build-windows.yml)
-->


<p align="center">
  <img src="assets/images/lo-logo.png" width="128" alt="语境输入法 Logo" />
</p>

## ✨ 功能特点

- **边写边翻译** —— 打字时悬浮窗实时显示翻译结果，无需切换应用或复制粘贴
- **免费翻译开箱即用** —— 接入微软 Edge 翻译接口（Bing），无需 API Key、零配置即用
- **可选本地离线翻译** —— 中→英等 8 个目标语言的语言包按需下载，断网可用、文本不出本机
- **23 种目标语言** —— 英、日、韩、法、德、西、俄、阿、泰、越等主流语言全覆盖
- **拼音输入引擎** —— 基于 [Rime（中州韻）](https://github.com/rime/librime) 引擎，支持朙月拼音、全拼、繁体等方案
- **高度可定制悬浮窗** —— 位置（固定/拖动/跟随光标）、大小、透明度、深/浅色主题、字号、颜色全部可调
- **可选语音播报** —— 使用系统语音离线朗读译文，也可在关闭翻译时朗读原文
- **原生实现** —— macOS 使用 Swift + SwiftPM（IMKit），体验对齐系统原生输入法；Windows 版本调试中，暂不发布

## 📥 下载安装

前往 [Releases](https://github.com/chengpeng-cp/lo/releases) 页面下载最新版本安装包。

### macOS

**系统要求**：下载与你的 CPU 架构和系统版本匹配的安装包。源码的 Swift 部署目标为 macOS 13，但最终安装包的最低系统版本取决于 librime 等依赖；打包脚本会将真实最低版本写入应用。当前构建为本机架构，不会自动生成 Universal 安装包。

1. 下载 `LOInputMethod-<version>.dmg`
2. 双击挂载 DMG，将「语境输入法安装器」拖到「应用程序」文件夹（同一镜像内还带有「语境输入法卸载工具」，重装或测试前用它清理旧版本）
3. 打开「应用程序」中的「语境输入法安装器」，按提示完成安装
4. 安装器会登记并启用「语境输入法」；打开「系统设置 → 键盘 → 输入法」确认后，用 `Ctrl + Space` 切换。如果安装后列表仍未刷新，请注销并重新登录再检查

> ⚠️ 当前版本未使用 Apple 开发者证书签名，首次打开需在「系统设置 → 隐私与安全性」底部点击"仍要打开"以允许运行。

<!-- Windows 端尚在调试，暂不对外发布
### Windows

**系统要求**：Windows 10 1809+ 或 Windows 11。当前构建为 x64 TSF 输入法，支持 x64 宿主应用；32 位应用和 ARM64 原生宿主尚需对应架构版本。

1. 下载 `LOInputMethod-Setup-<version>.exe`
2. 双击运行，按提示完成安装（需要管理员权限以注册 TSF 输入法）
3. 安装完成后，使用 `Win + Space` 切换到「语境输入法」即可开始使用
-->

## 🧹 卸载与彻底清理

只删除 `.app` / 安装目录是不够的：输入法还会留下输入源注册、LaunchServices 记录、Rime 部署缓存，旧版本可能还有 Keychain 中的翻译密钥。这些残留会让重装后的输入法列表出现重复项，或让新版本继续使用旧词库缓存。macOS 端提供了专门的卸载工具。

### macOS

**图形界面（推荐）**：安装镜像里已经带好「语境输入法卸载工具」——挂载 `LOInputMethod-<version>.dmg` 后直接运行它，无需再下载第二个包。工具会先扫描并列出来自以下位置的残留（含体积），确认后一键清理：

| 类别 | 位置 |
|------|------|
| 应用与副本 | `/Library/Input Methods/LOInputMethod.app`、`~/Library/Input Methods/`、安装器临时目录、废纸篓中的旧副本 |
| 系统注册 | LaunchServices 记录、`AppleEnabledInputSources` / `AppleEnabledThirdPartyInputSources` 中的输入源条目、辅助功能与输入监听授权（TCC） |
| 偏好设置 | `~/Library/Preferences/com.lo.inputmethod*.plist`（含 ByHost） |
| 钥匙串 | 服务名为 `com.lo.inputmethod` 的旧版本翻译密钥 |
| 用户数据 | `~/Library/Application Support/LOInputMethod`、`~/Library/Rime`（词库、用户词典、部署缓存、日志） |
| 日志与缓存 | `~/Library/Logs/LOInputMethod`、崩溃报告、Caches、Saved Application State |

默认勾选「同时清空 Rime 词库与用户词典」——这是避免旧词频和旧部署缓存干扰新版本的关键；需要保留时可取消勾选，或先勾选「备份到桌面」。若检测到鼠须管（Squirrel）等同样使用 `~/Library/Rime` 的输入法，工具只会删除语境输入法自己的文件。

**命令行（适合反复回归测试）**：

```bash
cd macos
bash scripts/uninstall.sh --dry-run     # 只扫描，不改动任何文件
bash scripts/uninstall.sh --purge       # 彻底清理（含词库、设置、旧版本密钥）
make uninstall-clean                    # 等价的 Makefile 入口
make package                            # 打安装镜像（自动内置卸载工具）
bash scripts/package-uninstaller.sh     # 仅开发用：单独打一个卸载工具 DMG
```

`--purge --backup ~/Desktop` 可在清空前把 Rime 与偏好设置备份到桌面；`--force-rime` 会强制整体删除 `~/Library/Rime`（默认遇到其他输入法数据时会保留）。

<!-- Windows 端尚在调试，暂不对外发布
### Windows

**图形界面（推荐）**：从 Releases 下载 `LOInputMethod-Uninstaller-<version>.exe` 并运行。工具会注销 TSF/COM 组件、删除程序文件与快捷方式、清理 CTF `TIP`/`Assemblies`/`SortOrder` 中的残留排序项；「清空本地词库、设置与 API Key」默认勾选，对应 `%LOCALAPPDATA%\LOInputMethod`（Rime 词库、用户词典、`apikeys.dat`、翻译缓存与日志）和 `HKCU\Software\LOInputMethod`。

也可以使用「设置 → 应用 → 已安装的应用」中的卸载项；安装包内置的 `uninstall.exe` 与本工具使用同一套清理逻辑，但本工具在安装目录损坏、`uninstall.exe` 丢失时仍然可用。

```bat
windows\scripts\build-uninstaller.bat 1.0.0   :: 本地生成卸载工具
windows\scripts\package.bat                   :: 同时生成安装包与卸载工具
```

> 卸载后建议注销并重新登录（Windows 可重启）再安装新版本，确保系统输入法列表完全刷新。
-->

## ⌨️ 快捷键

| 功能 | macOS |
|------|-------|
| 切换输入法 | `Ctrl + Space` |
| 中英文切换 | 中/英键（CapsLock，切系统 ABC，再按切回语境） |
| 复制翻译内容 | `⌃ ⌘ ,`（Ctrl+Cmd+逗号） |
| 选择候选词 | 数字键 `1–9` |
| 确认候选词 | `Space` |
| 导航候选词 | `← → ↑ ↓` |

> 中英文切换默认走「系统输入源」，与微信输入法、macOS 自带中文输入法一致：按中/英键（CapsLock）切到 ABC，再按切回语境，菜单栏会同步显示当前输入源。该方案需要在「系统设置 → 隐私与安全性 → 辅助功能」中授权语境输入法（用于拦截 CapsLock，避免触发大写锁定），未授权时会自动退回 Shift 短按切换。

悬浮窗也提供一键复制按钮，点一下即可复制当前翻译结果。

## 🔧 使用说明

安装后即可直接使用，翻译由免费的语境翻译（微软 Edge 翻译接口）提供，无需 API Key：

1. 点击输入法菜单栏图标 → **设置**
2. 在「翻译」页选择目标语言（默认 English）
3. 关闭设置页，开始打字即可看到悬浮窗实时翻译

翻译开关、悬浮窗、语音播报三者相互独立，可任意组合：关闭翻译时悬浮窗与播报只使用原文。

### 本地离线翻译（可选）

「翻译 → 翻译引擎」是一个下拉选项：

| 引擎 | 行为 |
|------|------|
| 语境翻译（在线）（默认） | 使用微软 Edge 翻译，无需下载，联网即用 |
| 本地翻译 · 轻量 | OPUS-MT 语言包离线翻译，文本不出本机；支持英语、简体中文、日语、法语、德语、西班牙语、俄语、阿拉伯语 |

选择本地档后，「本地模型」区块会列出当前目标语言所需的语言包，缺什么点「下载」即可，下载完成立即生效、无需重启。语言包按方向单独分发：中 → 英、英 → 中，以及英 → 日/法/德/西/俄/阿。

> 由于开放的中文直译模型有限，中文 → 日语等目标会经英语中转：**中文 → English → 目标语言**，因此需要同时安装「中→英」和「英→目标」两个包。设置页会明确列出这两个包，缺一个都不能离线翻译。

勾选「本地模型不可用时自动使用在线翻译」后，缺少语言包或语言不支持时会自动回退在线。翻译时只会加载当前方向用到的语言包，安装更多方向不会拖慢速度；直达方向（中→英）只占一个包的磁盘与内存，经英语中转的方向会同时驻留两个包。

目标语言列表会随引擎自动变化：在线 23 种常用语言、本地轻量 8 种；切换引擎时不支持的当前语言会自动切回 English。

模型保存在 `~/Library/Application Support/LOInputMethod/models/`，可随时删除。

> 在线模式下待翻译文本会直接发送给微软翻译接口，不经过任何中间服务器；本地模式不产生任何网络请求。翻译缓存保存在本机。

## 🏗️ 从源码构建

### 技术栈

| 平台 | 技术 | 主要依赖 |
|------|------|----------|
| macOS | Swift 5.9+、Swift Package Manager、AppKit / IMKit | librime（Homebrew） |

项目没有 Web 前端、后端 API 服务或数据库。翻译功能由桌面客户端直接连接微软翻译接口。

### 快速体验

如果只想使用输入法，前往 [GitHub Releases](https://github.com/chengpeng-cp/lo/releases) 下载安装包，按「下载安装」部分完成安装即可。

如果要从源码构建，请按以下步骤操作。首次构建会下载 librime 依赖和 Rime 社区词库，因此需要网络连接。

#### macOS：克隆并安装运行

要求受所安装 librime 版本支持的 macOS、Xcode Command Line Tools（含 Swift 5.9+）和 Homebrew。

```bash
git clone https://github.com/chengpeng-cp/lo.git
cd lo/macos
brew install librime
bash scripts/fetch-onnxruntime.sh   # 本地翻译所需的 ONNX Runtime（不随仓库分发）
make install-full
```

> `scripts/fetch-onnxruntime.sh` 会把 ONNX Runtime 1.20.1 解压到 `macos/vendor/onnxruntime/`；`make package` 与 `assemble-app.sh` 会自动调用它，只有单独执行 `make build` 时才需要手动运行一次。

`make install-full` 会构建程序、下载词库并将完整应用安装到当前用户的输入法目录；首次启动时会注册并启用输入法父来源和拼音模式。安装后可在「系统设置 → 键盘 → 输入法」确认「语境输入法」已列出，再用 `Ctrl + Space` 切换。

需要制作 DMG 安装包时，在 `macos/` 目录运行：

```bash
make package
```

<!-- Windows 端尚在调试，暂不对外发布
#### Windows：克隆并构建

要求 64 位 Windows 10 或更高版本、Visual Studio 2019+（含 MSVC 与 Windows SDK）、CMake 和 7-Zip。构建脚本会下载 librime 预编译依赖和 Rime 社区词库。

```bat
git clone https://github.com/chengpeng-cp/lo.git
cd lo\windows
scripts\build.bat Release
```

构建 DLL 位于 `windows\build\bin\Release\`。要生成可安装的 EXE，还需安装 [NSIS](https://nsis.sourceforge.io/) 并确保 `makensis` 在 PATH 中，然后运行：

```bat
scripts\package.bat Release
```

安装包生成在 `windows\dist\`。运行安装程序后，在系统输入法设置中启用「语境输入法」，再按 `Win + Space` 切换。
-->

### 目录结构

```
lo/
├── macos/                     # macOS 端（Swift + SwiftPM）
│   ├── LOInputMethod/         # 输入法主程序（IMKit）
│   ├── Installer/             # 安装器（SwiftUI App）
│   ├── CRime/                 # Rime C 接口桥接
│   ├── scripts/               # 构建、打包、词库下载脚本
│   ├── Makefile               # 快捷命令
│   └── Package.swift          # SwiftPM 配置
├── assets/images/vx.png       # README 中的微信二维码
└── .github/workflows/         # CI 构建（GitHub Actions）
```

### 日常开发命令

在 `macos/` 中执行 `make build` 只编译；`make install-full` 在构建、词库下载及签名验证成功后替换用户级安装，并在替换失败时回滚。已有系统级安装时，请使用 DMG 安装器升级。

### CI 自动构建

项目使用 GitHub Actions 自动构建，每次 push 到 `main` 或推送 `v*` 标签都会触发：

- `.github/workflows/build-macos.yml` —— 在 `macos-14` runner 上构建并打包 DMG

推送 `v*` tag（如 `v1.0.4`）时，CI 会自动创建 GitHub Release 并上传安装包。手动触发也支持：在 Actions 页面点击 "Run workflow" 即可。

## 🔒 隐私

- 翻译请求**直连**微软 Edge 翻译接口，不经过任何中间服务器
- 无需注册、无需 API Key、无账户关联
- 不收集任何使用数据、不联网上报、不嵌入第三方统计 SDK
- 输入法作为本地进程运行，所有输入内容仅在本地处理并直接发送到翻译接口

## 🤝 参与贡献

欢迎 Issue 和 PR！提交前请确认：

1. macOS 代码使用 Swift，遵循 Swift API Design Guidelines
2. 提交前请确保本地构建通过（`make package`）
3. 敏感信息（API Key、个人配置等）请勿提交；本仓库通过 `.gitignore` 排除 `.env`、本地凭据文件和 `personal-docs/` 等个人内容

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源，可自由使用、修改和分发。

项目输入引擎基于 [Rime（中州韻輸入法引擎）](https://github.com/rime/librime)（BSD 许可），默认词库使用 [rime-ice](https://github.com/iDvel/rime-ice)，使用和二次分发时请遵守相应许可条款。

## 💬 反馈

如有问题或建议，欢迎在 [GitHub Issues](https://github.com/chengpeng-cp/lo/issues) 中反馈。

---

**打字就是翻译，语境即沟通。**

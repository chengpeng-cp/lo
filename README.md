# 语境输入法（LO Input Method）

> 边写边翻译的智能输入法 —— 打字的同时，悬浮窗实时显示翻译结果，无需切换应用。

[![macOS Build](https://github.com/chengpeng-cp/lo/actions/workflows/build-macos.yml/badge.svg)](https://github.com/chengpeng-cp/lo/actions/workflows/build-macos.yml)
[![Windows Build](https://github.com/chengpeng-cp/lo/actions/workflows/build-windows.yml/badge.svg)](https://github.com/chengpeng-cp/lo/actions/workflows/build-windows.yml)

<p align="center">
  <img src="macos/LOInputMethod/Resources/AppIcon.icns" width="128" alt="Logo" />
</p>

## ✨ 功能特点

- **边写边翻译** —— 打字时悬浮窗实时显示翻译结果，无需切换应用或复制粘贴
- **免费翻译开箱即用** —— 默认接入微软 Edge 翻译接口（Bing），无需 API Key、零配置即用
- **多模型大模型支持** —— 兼容 DeepSeek、GLM（智谱）、Qwen（通义千问）、Kimi（月之暗面）、MiniMax、OpenAI、火山引擎（豆包），以及任何 OpenAI 兼容的自定义端点
- **流式输出** —— 大模型翻译采用 SSE 流式返回，首字延迟低、逐字显示
- **三种翻译模式** —— 自然翻译 / 母语级表达 / 直译，按需选择
- **23 种目标语言** —— 英、日、韩、法、德、西、俄、阿、泰、越等主流语言全覆盖
- **拼音输入引擎** —— 基于 [Rime（中州韻）](https://github.com/rime/librime) 引擎，支持朙月拼音、全拼、繁体等方案
- **高度可定制悬浮窗** —— 位置（固定/拖动/跟随光标）、大小、透明度、深/浅色主题、字号、颜色全部可调
- **API Key 安全存储** —— macOS 使用 Keychain，密钥不落盘明文
- **双平台原生实现** —— macOS 使用 Swift + SwiftPM（IMKit），Windows 使用 C++ + CMake（TSF），体验对齐系统原生输入法

## 📥 下载安装

前往 [Releases](https://github.com/chengpeng-cp/lo/releases) 页面下载最新版本安装包。

### macOS

**系统要求**：macOS 13 Ventura 或更高版本（Apple Silicon / Intel 均可）

1. 下载 `LOInputMethod-<version>.dmg`
2. 双击挂载 DMG，将「语境输入法安装器」拖到「应用程序」文件夹
3. 打开「应用程序」中的「语境输入法安装器」，按提示完成安装
4. 打开「系统设置 → 键盘 → 输入法」，点击 **+** 添加「语境输入法」
5. 授予输入法辅助功能权限（系统会自动提示）

> ⚠️ 当前版本未使用 Apple 开发者证书签名，首次打开需在「系统设置 → 隐私与安全性」底部点击"仍要打开"以允许运行。

### Windows

**系统要求**：Windows 10 1809+ 或 Windows 11，64 位系统

1. 下载 `LOInputMethod-Setup-<version>.exe`
2. 双击运行，按提示完成安装（需要管理员权限以注册 TSF 输入法）
3. 安装完成后，使用 `Win + Space` 切换到「语境输入法」即可开始使用

## ⌨️ 快捷键

| 功能 | macOS | Windows |
|------|-------|---------|
| 切换输入法 | `Ctrl + Space` | `Win + Space` |
| 中英文切换 | `Shift` | `Shift` |
| CapsLock 切换 ABC | 原生支持 | — |
| 复制翻译内容 | `⌃ ⌘ ,`（Ctrl+Cmd+逗号） | `Ctrl + Alt + ,` |
| 选择候选词 | 数字键 `1–9` | 数字键 `1–9` |
| 确认候选词 | `Space` | `Space` |
| 导航候选词 | `← → ↑ ↓` | `← → ↑ ↓` |

悬浮窗也提供一键复制按钮，点一下即可复制当前翻译结果。

## 🔧 使用说明

安装后输入法默认启用"语境翻译（免费）"模式，可直接使用。如需使用大模型翻译：

1. 点击输入法菜单栏图标 → **设置**（macOS）或右键悬浮窗 → **设置**（Windows）
2. 在「翻译提供商」下拉中选择你想使用的大模型（如 DeepSeek）
3. 填入对应的 API Key，选择目标模型（如 `deepseek-chat`）
4. 选择目标语言（默认 English）和翻译模式
5. 关闭设置页，开始打字即可看到悬浮窗实时翻译

API Key 存储在系统密钥链中，不会上传到任何第三方服务器，仅用于直接调用对应 API。

## 🏗️ 从源码构建

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
├── windows/                   # Windows 端（C++17 + CMake）
│   ├── src/
│   │   ├── core/              # TSF 框架核心（TextService、注册）
│   │   ├── rime/              # Rime 引擎封装
│   │   ├── translation/       # 翻译后端（Bing + LLM）
│   │   ├── ui/                # 候选窗、悬浮窗
│   │   └── settings/          # 设置对话框
│   ├── installer/             # NSIS 安装脚本
│   ├── resources/rime/        # Rime 方案配置
│   └── CMakeLists.txt
└── .github/workflows/         # CI 构建（GitHub Actions）
```

### macOS 构建

**依赖**：
- Xcode 15+（含 Swift 5.9+）
- [Homebrew](https://brew.sh/)

```bash
# 安装 librime
brew install librime

# 构建输入法主程序
cd macos
make build        # 等价于 swift build -c release

# 下载 rime-ice 社区词库（首次构建时）
bash scripts/fetch-dict.sh

# 一键打包（构建 → 组装 .app → 签名 → 生成 DMG）
make package      # 或 bash scripts/package.sh
# 产物：macos/dist/语境输入法-<version>.dmg
```

### Windows 构建

**依赖**：
- Visual Studio 2019+（带 MSVC、CMake、Windows SDK 10.0+）
- [NSIS](https://nsis.sourceforge.io/)（用于制作安装包）
- 7-Zip（解压 librime 预编译包用）
- librime 预编译包（本地构建可用 `vcpkg install librime`）

```bat
cd windows

:: 配置 CMake
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release

:: 编译
cmake --build build --config Release --parallel

:: 产物在 build\bin\Release\LOInputMethod.dll

:: 下载 rime-ice 词库（可选）
scripts\fetch-dict.bat

:: 打包为安装包（需 NSIS）
cd installer
makensis installer.nsi
:: 产物：windows\dist\LOInputMethod-Setup-<version>.exe
```

### CI 自动构建

项目使用 GitHub Actions 实现双平台自动构建，每次 push 到 `main` 或推送 `v*` 标签都会触发：

- `.github/workflows/build-macos.yml` —— 在 `macos-14` runner 上构建并打包 DMG
- `.github/workflows/build-windows.yml` —— 在 `windows-latest` runner 上构建并打包 EXE

推送 `v*` tag（如 `v1.0.4`）时，CI 会自动创建 GitHub Release 并上传安装包。手动触发也支持：在 Actions 页面点击 "Run workflow" 即可。

## 🔒 隐私说明

- 翻译请求**直连**所选的翻译服务（Bing / DeepSeek / OpenAI 等），不经过任何中间服务器
- API Key 存储在系统密钥管理中（macOS Keychain / Windows Credential Manager）
- 默认 Bing 翻译使用微软 Edge 浏览器同款公开接口，无需注册、无账户关联
- 不收集任何使用数据、不联网上报、不嵌入第三方统计 SDK
- 输入法作为本地进程运行，所有输入内容仅在本地处理和直接发送到用户所选翻译 API

## 🤝 参与贡献

欢迎 Issue 和 PR！提交前请确认：

1. macOS 代码使用 Swift，遵循 Swift API Design Guidelines；Windows 代码使用 C++17
2. 双平台功能尽量保持对齐（新增翻译后端需同时实现 Swift 和 C++ 版本）
3. 提交前请确保本地构建通过（`make package` / `cmake --build`）
4. 敏感信息（API Key、个人配置等）请勿提交

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源，可自由使用、修改和分发。

项目输入引擎基于 [Rime（中州韻輸入法引擎）](https://github.com/rime/librime)（BSD 许可），默认词库使用 [rime-ice](https://github.com/iDvel/rime-ice)，使用和二次分发时请遵守相应许可条款。

## 💬 反馈

如有问题或建议，欢迎在 [GitHub Issues](https://github.com/chengpeng-cp/lo/issues) 中反馈。

---

**打字就是翻译，语境即沟通。**

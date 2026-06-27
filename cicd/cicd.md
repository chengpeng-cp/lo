# 语境输入法 - CI/CD 自动打包发布操作手册

## 概览

本项目使用 **GitHub Actions** 实现自动打包。你只需要把代码 push 到 GitHub,云端会自动在 macOS 和 Windows 虚拟机上完成构建,生成 `.dmg`（macOS）和 `.exe`（Windows）安装包,用户直接从 Release 页面下载即可。

```
你的 Mac（开发）  ──push代码──▶  GitHub 仓库
                                   │
                          ┌────────┴────────┐
                          ▼                 ▼
                   macOS 虚拟机       Windows 虚拟机
                   构建 + 打包         构建 + 打包
                          │                 │
                          ▼                 ▼
                       .dmg              .exe
                          │                 │
                          └────────┬────────┘
                                   ▼
                            GitHub Release 页面
                                   │
                            用户直接下载使用
```

---

## 一、文件结构

```
lo/
├── cicd/
│   ├── cicd.md                  # 本文档（操作手册）
│   └── build-via-ci.sh          # 跨平台一键构建脚本
└── .github/workflows/
    ├── build-macos.yml          # macOS 自动打包 workflow
    └── build-windows.yml        # Windows 自动打包 workflow
```

---

## 二、首次配置（一次性）

### 1. 确保代码已推送到 GitHub

如果还没有 GitHub 仓库,先创建一个：

```bash
cd /Users/joyy/myProjects/lo

# 初始化 git（如果还没有）
git init
git add .
git commit -m "initial commit"

# 添加 GitHub 远程仓库（替换成你的仓库地址）
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 2. 安装 GitHub CLI（可选,但强烈推荐）

GitHub CLI 让你在终端就能触发构建、查看进度、下载产物,不用打开浏览器：

```bash
brew install gh
gh auth login
# 按提示选择 GitHub.com → HTTPS → 浏览器登录
```

### 3. 确认 workflow 文件已存在

项目中应该有以下文件（已创建好）：

```
.github/workflows/
├── build-macos.yml      # macOS 自动打包
└── build-windows.yml    # Windows 自动打包

cicd/
├── cicd.md              # 本文档
└── build-via-ci.sh      # 一键构建脚本
```

把这些文件 push 到 GitHub：

```bash
git add .github/ cicd/
git commit -m "ci: 添加双平台自动打包 workflow"
git push
```

push 后,GitHub 仓库的 **Actions** 标签页会自动出现两个 workflow。

---

## 三、日常开发迭代流程

### 场景 A：日常开发,只想验证代码能否编译通过

直接 push 到 main 分支：

```bash
git add .
git commit -m "fix: 修复某个 bug"
git push
```

push 后会自动触发两个 workflow,但**只构建验证,不发布 Release**。你可以在 GitHub Actions 页面查看构建是否成功,构建产物会作为 artifact 保存 30 天供你下载测试。

### 场景 B：手动触发构建,下载测试安装包

不想打 tag,只想快速构建一个测试包：

**方式 1：用一键脚本（推荐）**

```bash
# 同时构建 macOS 和 Windows
./cicd/build-via-ci.sh --watch
# 完成后自动下载到 .artifacts/ 目录

# 或单独构建某个平台
./cicd/build-via-ci.sh --platform mac --watch
./cicd/build-via-ci.sh --platform windows --watch
```

**方式 2：用 gh CLI 手动操作**

```bash
# 触发 Windows 构建
gh workflow run build-windows.yml

# 触发 macOS 构建
gh workflow run build-macos.yml

# 查看构建进度
gh run watch

# 构建完成后,下载安装包到本地
gh run download
```

**方式 3：用浏览器**

1. 打开 GitHub 仓库 → **Actions** 标签页
2. 左侧选择 `Build Windows Installer` 或 `Build macOS Installer`
3. 点击右侧 **Run workflow** 按钮
4. 等待构建完成（绿色对勾）
5. 点击构建记录 → 下滑到 **Artifacts** 区域 → 下载

### 场景 C：发布正式版本（用户可下载）

这是最常见的发布方式。打个 tag,push 后自动构建并发布到 Release 页面：

```bash
# 1. 确保所有改动已提交并 push
git add .
git commit -m "release: 准备发布 v1.0.0"
git push

# 2. 打 tag（版本号前加 v）
git tag v1.0.0
git push origin v1.0.0
```

push tag 后会**同时**触发 macOS 和 Windows 构建,大约 10-15 分钟后：

- GitHub Release 页面会自动出现 `语境输入法 1.0.0`
- 包含两个文件：
  - `语境输入法-1.0.0.dmg`（macOS 用户下载）
  - `语境输入法-Setup-1.0.0.exe`（Windows 用户下载）
- Release 说明里写好了安装指南

用户访问 `https://github.com/<用户名>/<仓库名>/releases` 即可下载。

**用脚本一键发布并观看进度：**

```bash
./cicd/build-via-ci.sh v1.0.0 --watch
```

### 场景 D：发布预发布版本（beta/rc）

```bash
git tag v1.1.0-beta1
git push origin v1.1.0-beta1
```

需要修改为预发布的话,在 GitHub Release 页面手动勾选 "Set as a pre-release",或编辑 workflow 调整 `prerelease: true`。

### 场景 E：只发布其中一个平台

有时只想更新一个平台。两个 workflow 是独立的,你可以：

**临时方案**：去 GitHub Actions 页面,在构建前手动取消不需要的那个 workflow。

**长期方案**：把 tag 命名区分开,例如：
- `mac-v1.0.0` → 只触发 macOS（需修改 build-macos.yml 的 tag 过滤）
- `win-v1.0.0` → 只触发 Windows
- `v1.0.0` → 同时触发（默认行为）

或者直接用脚本指定平台：

```bash
# 只构建 macOS 测试包
./cicd/build-via-ci.sh --platform mac --watch

# 只构建 Windows 测试包
./cicd/build-via-ci.sh --platform windows --watch
```

---

## 四、用户如何下载安装

### macOS 用户

1. 打开项目的 Release 页面：`https://github.com/<用户名>/<仓库名>/releases`
2. 下载 `语境输入法-1.0.0.dmg`
3. 双击挂载 dmg
4. 将「语境输入法安装器」拖到「应用程序」文件夹
5. 打开「应用程序」中的「语境输入法安装器」,按提示完成安装
6. 打开「系统设置 > 键盘 > 输入法」,添加「语境输入法」
7. 授予辅助功能权限（系统会自动提示）

**首次打开可能被 Gatekeeper 拦截**（因为未用 Apple 开发者证书签名）：
- 打开「系统设置 > 隐私与安全性」
- 找到「已阻止打开语境输入法」提示,点击「仍要打开」

### Windows 用户

1. 打开项目的 Release 页面
2. 下载 `语境输入法-Setup-1.0.0.exe`
3. 双击运行安装程序,按提示完成安装
4. 打开「系统设置 > 时间和语言 > 语言和区域」
5. 在「中文（简体）> 语言选项 > 键盘」中添加「语境输入法」
6. 使用 `Win+Space` 切换到语境输入法

---

## 五、查看构建状态

### 方式 1：GitHub CLI（终端查看）

```bash
# 查看最近的构建
gh run list

# 实时观看最新一次构建
gh run watch

# 查看特定 workflow 的历史
gh run list --workflow=build-macos.yml
gh run list --workflow=build-windows.yml
```

### 方式 2：浏览器

打开 `https://github.com/<用户名>/<仓库名>/actions`

- 绿色对勾 = 构建成功
- 红色叉号 = 构建失败,点击查看日志
- 黄色圆圈 = 正在构建

### 构建失败怎么办？

```bash
# 查看失败原因
gh run view <run-id> --log-failed

# 或在浏览器打开构建记录,点击失败的步骤查看日志
```

常见失败原因：
- **编译错误**：代码有语法错误,本地先 `swift build`（macOS）或检查 C++ 代码
- **依赖安装失败**：网络问题,重新触发即可
- **librime 找不到**：vcpkg 缓存问题,重新触发或检查 CMakeLists.txt

---

## 六、版本号管理

### 版本号规则

建议遵循语义化版本：

| 版本号 | 含义 | 示例 |
|--------|------|------|
| `v1.0.0` | 正式版 | 首次发布 |
| `v1.1.0` | 新功能 | 加了新翻译引擎 |
| `v1.0.1` | Bug 修复 | 修复悬浮窗闪烁 |
| `v1.2.0-beta1` | 测试版 | 新功能预览 |

### 版本号在哪改？

- **macOS**：`macos/LOInputMethod/Info.plist` 的 `CFBundleShortVersionString`
- **Windows**：`windows/resources/app.rc` 的 `VER_PRODUCTVERSION_STR`,以及 `windows/installer/installer.nsi` 的 `APP_VERSION`
- **CI 生成的安装包文件名**：由 tag 名决定（`v1.0.0` → `语境输入法-1.0.0.dmg`）

发布前确保三处版本号一致。

---

## 七、一键脚本详解

`cicd/build-via-ci.sh` 是跨平台发布脚本,支持以下用法：

| 命令 | 作用 |
|------|------|
| `./cicd/build-via-ci.sh` | 手动触发双平台构建,完成后下载 artifact |
| `./cicd/build-via-ci.sh --watch` | 同上,但实时观看构建日志 |
| `./cicd/build-via-ci.sh v1.0.0` | 打 tag `v1.0.0` 并 push,触发 Release 发布 |
| `./cicd/build-via-ci.sh v1.0.0 --watch` | 打 tag 并实时观看构建日志 |
| `./cicd/build-via-ci.sh --platform mac` | 只触发 macOS 构建 |
| `./cicd/build-via-ci.sh --platform windows` | 只触发 Windows 构建 |

**脚本功能：**
1. 检查 GitHub CLI 是否安装并登录
2. 触发对应的 workflow
3. 等待构建完成（可选实时观看日志）
4. 构建成功后自动下载安装包到 `.artifacts/` 目录
5. 打 tag 模式下,自动创建并 push tag,触发 Release 发布

---

## 八、CI/CD 文件结构说明

### build-macos.yml 触发条件

- `push` 到 main/master 分支 → 构建验证（不上传 Release）
- `push` tag `v*` → 构建并发布 Release
- `workflow_dispatch`（手动触发）→ 构建并上传 artifact

### build-windows.yml 触发条件

同上,在 Windows 虚拟机上运行。

### 构建流程

**macOS workflow：**
1. 在 `macos-14` runner 上运行
2. 用 Homebrew 安装 librime
3. 调用 `macos/scripts/package.sh` 完成构建
4. 生成 `.dmg` 安装镜像
5. 上传 artifact / 发布 Release

**Windows workflow：**
1. 在 `windows-latest` runner 上运行
2. 用 vcpkg 安装 librime
3. 用 CMake + MSVC 编译 DLL
4. 用 NSIS 生成 `.exe` 安装包
5. 上传 artifact / 发布 Release

---

## 九、常用命令速查

```bash
# === 发布 ===
git tag v1.0.0
git push origin v1.0.0              # 触发双平台自动发布

# 一键发布（脚本方式）
./cicd/build-via-ci.sh v1.0.0 --watch

# === 手动触发 ===
gh workflow run build-macos.yml     # 触发 macOS 构建
gh workflow run build-windows.yml   # 触发 Windows 构建
./cicd/build-via-ci.sh --watch      # 脚本方式（双平台）

# === 查看状态 ===
gh run list                          # 列出最近构建
gh run watch                         # 实时观看最新构建
gh run view <run-id> --log-failed    # 查看失败日志

# === 下载产物 ===
gh run download <run-id>             # 下载到当前目录
gh run download <run-id> -D ./output # 下载到指定目录
./cicd/build-via-ci.sh --watch       # 脚本会自动下载

# === 删除本地 tag（打错了版本号）===
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0    # 删除远端 tag

# === 查看所有 tag ===
git tag -l
```

---

## 十、常见问题

### Q1：为什么 macOS 上不能直接编译 Windows 版？

Windows 版依赖 TSF（Text Services Framework）API,这些头文件只随 Windows SDK 提供,macOS 上没有。同理,Windows 上也无法编译 macOS 版（没有 IMK.framework）。所以必须用 CI 跨平台构建。

### Q2：构建大概要多久？

- macOS：约 5-8 分钟（Homebrew 装 librime 较慢,后续构建快）
- Windows：约 8-12 分钟（vcpkg 编译 librime 较慢）
- 两平台并行,总时长约 12 分钟

### Q3：构建产物会保存多久？

- **Artifact**（手动触发或 push 到 main）：保存 30 天
- **Release**（打 tag 触发）：永久保存,除非手动删除

### Q4：如何让构建更快？

librime 是最大的耗时项。可以考虑：
1. 用 GitHub Actions 缓存 vcpkg/Homebrew 产物
2. 预编译 librime 并提交到仓库（不推荐,体积大）
3. 升级到 GitHub Pro/Team 加快 runner 速度

### Q5：没 Apple 开发者证书,macOS 用户安装会被拦截吗？

会,但用户可以手动放行：
- 系统设置 > 隐私与安全性 > 找到拦截提示 > 点击「仍要打开」

如果有 Apple 开发者证书,可以在 workflow 中加入签名和公证步骤,实现完全静默安装。需要时告诉我帮你加。

### Q6：如何同时发布两个平台？

打一个 tag 即可,两个 workflow 会同时触发,构建完成后会合并到同一个 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
# 约 12 分钟后,Release 页面同时出现 .dmg 和 .exe
```

### Q7：打错版本号了怎么办？

```bash
# 删除本地 tag
git tag -d v1.0.0

# 删除远端 tag
git push origin :refs/tags/v1.0.0

# 如果 Release 已创建,去 GitHub Release 页面手动删除
# 然后重新打正确的 tag
git tag v1.0.1
git push origin v1.0.1
```

### Q8：可以只发布一个平台吗？

默认情况下打 tag 会同时触发两个平台。如果需要单独发布：

**临时方案**：去 GitHub Actions 页面,在构建前手动取消不需要的那个 workflow。

**长期方案**：修改 workflow 的触发条件,用不同的 tag 前缀区分,例如：
- `mac-v1.0.0` 只触发 macOS
- `win-v1.0.0` 只触发 Windows
- `v1.0.0` 触发两个平台

需要这种方案告诉我帮你调整。

或者直接用脚本手动触发单平台构建（仅生成 artifact,不发布 Release）：

```bash
./cicd/build-via-ci.sh --platform mac --watch
./cicd/build-via-ci.sh --platform windows --watch
```

---

## 十一、后续迭代发布流程

每次发布新版本的完整步骤：

```bash
# 1. 本地开发测试
cd /Users/joyy/myProjects/lo

# 2. （macOS 端）本地验证编译通过
cd macos && make build && cd ..

# 3. 提交代码
git add .
git commit -m "feat: 新增 xxx 功能 / fix: 修复 xxx bug"
git push

# 4. （可选）先手动触发一次构建,验证 CI 能通过
./cicd/build-via-ci.sh --watch

# 5. 确认无误后,更新版本号
# 编辑 macos/LOInputMethod/Info.plist
# 编辑 windows/resources/app.rc
# 编辑 windows/installer/installer.nsi
git add -A
git commit -m "release: bump version to 1.1.0"
git push

# 6. 打 tag 并 push,触发自动发布
git tag v1.1.0
git push origin v1.1.0

# 或用脚本一键完成并观看进度
./cicd/build-via-ci.sh v1.1.0 --watch

# 7. 等待约 12 分钟,Release 页面自动出现安装包
# 用户即可下载
```

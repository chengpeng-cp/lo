#!/bin/bash
# 语境输入法一键打包脚本
#
# 流程：构建输入法 → 组装 staging payload .app（含 librime）→ 构建安装器
#       → 嵌入 payload → 签名 → 生成 .dmg 安装镜像
#
# 用法：在 macos/ 目录下执行 bash scripts/package.sh
#       或通过 Makefile：make package

set -euo pipefail

# === 配置 ===
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # macos/
APP_NAME="LOInputMethod"
INSTALLER_NAME="LOInstaller"
BUNDLE_ID="com.lo.inputmethod.ime"
INSTALLER_BUNDLE_ID="com.lo.inputmethod.installer"

# 版本号：CI 通过 LO_VERSION 传入 tag 版本，本地在 tag 上打包则自动取 tag；
# 否则回退到 Info.plist 的开发默认值。解析一次并导出，组装脚本与安装器共用同一份。
# shellcheck source=scripts/lib-version.sh
source "$ROOT_DIR/scripts/lib-version.sh"
VERSION="$(resolve_lo_version "$ROOT_DIR" "$ROOT_DIR/LOInputMethod/Info.plist")"
export LO_VERSION="$VERSION"

# 目录
BUILD_DIR="$ROOT_DIR/.build/release"
STAGING_DIR="$ROOT_DIR/.build/staging"
PAYLOAD_APP="$STAGING_DIR/payload/$APP_NAME.app"
INSTALLER_BUILD_DIR="$ROOT_DIR/Installer/.build/release"
INSTALLER_APP="$STAGING_DIR/$INSTALLER_NAME.app"
DMG_ROOT="$STAGING_DIR/dmg"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/语境输入法-$VERSION.dmg"

echo "=========================================="
echo "  语境输入法打包  (v$VERSION)"
echo "=========================================="

# 1. 构建输入法二进制 + 下载词库
echo ""
echo "[1/7] 构建输入法二进制..."
cd "$ROOT_DIR"
# 本地翻译依赖 ONNX Runtime；不随仓库分发，构建前按需下载
bash scripts/fetch-onnxruntime.sh
# -Xswiftc -strict-concurrency=minimal : 禁用 Swift 严格并发检查
# 避免 @MainActor 类在 Timer/Task 闭包中捕获 self 的并发警告升级为错误
# （CI 的 Xcode 15.4 默认启用严格并发检查,即使 -swift-version 5 也不够）
swift build -c release -Xswiftc -strict-concurrency=minimal ${SWIFT_BUILD_FLAGS:-}

echo ""
echo "[2/7] 下载 rime-ice 词库..."
bash scripts/fetch-dict.sh

# 2. Build the same complete bundle used by local installation.
echo "[3/7] 组装并验证输入法 payload..."
bash "$ROOT_DIR/scripts/assemble-app.sh" "$PAYLOAD_APP"

# 3. 构建安装器
echo ""
echo "[4/7] 构建安装器..."
cd "$ROOT_DIR/Installer"
swift build -c release ${SWIFT_BUILD_FLAGS:-}

# 4. 组装安装器 .app 并嵌入 payload
echo ""
echo "[5/7] 组装安装器并嵌入 payload..."
rm -rf "$INSTALLER_APP"
mkdir -p "$INSTALLER_APP/Contents/MacOS"
mkdir -p "$INSTALLER_APP/Contents/Resources"
cp "$INSTALLER_BUILD_DIR/$INSTALLER_NAME" "$INSTALLER_APP/Contents/MacOS/$INSTALLER_NAME"
cp "$ROOT_DIR/Installer/Resources/Info.plist" "$INSTALLER_APP/Contents/Info.plist"
# 安装器也要报真实版本，否则「关于」里永远显示 1.0.0
stamp_lo_version "$INSTALLER_APP/Contents/Info.plist" "$VERSION"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PAYLOAD_APP/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_OS" "$INSTALLER_APP/Contents/Info.plist"
cp "$ROOT_DIR/LOInputMethod/Resources/AppIcon.icns" "$INSTALLER_APP/Contents/Resources/AppIcon.icns"
# 嵌入输入法 payload，安装器运行时从这里读取并拷贝到系统目录
cp -R "$PAYLOAD_APP" "$INSTALLER_APP/Contents/Resources/$APP_NAME.app"

# 签名安装器（内层 payload 已签名，此处签名外层 installer）
# 本地开发建议 CODESIGN_IDENTITY="LO Input Method Development"：
# 稳定证书能让辅助功能授权在重装后继续有效；CI 无证书时回退 ad-hoc。
echo "  签名安装器..."
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime \
    --identifier "$INSTALLER_BUNDLE_ID" \
    -s "$IDENTITY" "$INSTALLER_APP"

codesign --verify --deep --strict "$INSTALLER_APP"

# 5. 组装卸载工具：与安装器放进同一个镜像，重装/清理不必再找第二个 DMG
echo ""
echo "[6/7] 构建卸载工具..."
UNINSTALLER_APP="$ROOT_DIR/.build/staging-uninstaller/语境输入法卸载工具.app"
bash "$ROOT_DIR/scripts/package-uninstaller.sh" --app-only

# 6. 生成 DMG
echo ""
echo "[7/7] 生成 DMG 安装镜像..."
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
# Finder 里显示中文名，和说明文字一致
cp -R "$INSTALLER_APP" "$DMG_ROOT/语境输入法安装器.app"
cp -R "$UNINSTALLER_APP" "$DMG_ROOT/"

cat > "$DMG_ROOT/使用说明.txt" <<'EOF'
语境输入法

安装（首次使用或升级）
  1. 打开「语境输入法安装器」，按提示完成安装（需要管理员密码）。
  2. 打开「系统设置 → 键盘 → 输入法」，确认已添加「语境输入法」。
  3. 按 Ctrl + Space 切换输入法。

重装 / 测试前彻底清理
  1. 先打开「语境输入法卸载工具」。
  2. 工具会扫描旧版本残留（程序副本、输入源注册、Rime 词库缓存、
     设置与 API Key），确认后点「彻底卸载」。
  3. 建议注销并重新登录，再运行安装器安装新版本。
     否则重复的输入源记录和旧词库缓存可能干扰测试。

提示
- 卸载工具默认清空 ~/Library/Rime 词库；需要保留可取消勾选或先备份到桌面。
- 若检测到鼠须管等共用 ~/Library/Rime 的输入法，只会删除语境自己的文件。
- 未使用开发者证书签名，首次打开被拦截时请右键选择「打开」。
EOF

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "语境输入法" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

echo ""
echo "=========================================="
echo "  打包完成"
echo "=========================================="
echo "安装镜像: $DMG_PATH"
echo "版本:     v$VERSION"
echo "架构:     $(lipo -archs "$PAYLOAD_APP/Contents/MacOS/LOInputMethod")"
echo "最低系统: macOS $MIN_OS"
echo ""
echo "分发说明："
echo "  - 未用开发者证书签名公证时，用户首次打开需在「系统设置 › 隐私与安全性」"
echo "    中允许打开（Gatekeeper 拦截）。"
echo "  - 拥有 Apple 开发者账号后，可在本脚本中对 payload/installer 改用正式签名"
echo "    并执行 xcrun notarytool 公证，实现完全静默安装体验。"

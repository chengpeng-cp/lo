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

# 版本号从输入法 Info.plist 读取，避免多处硬编码
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/LOInputMethod/Info.plist")"

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
echo "[1/6] 构建输入法二进制..."
cd "$ROOT_DIR"
swift build -c release

echo ""
echo "[2/6] 下载 rime-ice 词库..."
bash scripts/fetch-dict.sh

# 2. 组装 staging payload .app
echo ""
echo "[3/6] 组装输入法 payload..."
rm -rf "$PAYLOAD_APP"
mkdir -p "$PAYLOAD_APP/Contents/MacOS"
mkdir -p "$PAYLOAD_APP/Contents/Resources/rime"
cp "$BUILD_DIR/$APP_NAME" "$PAYLOAD_APP/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/LOInputMethod/Info.plist" "$PAYLOAD_APP/Contents/Info.plist"
cp "$ROOT_DIR/LOInputMethod/Resources/AppIcon.icns" "$PAYLOAD_APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/LOInputMethod/Resources/InfoPlist.strings" "$PAYLOAD_APP/Contents/Resources/InfoPlist.strings"
cp -r "$ROOT_DIR/LOInputMethod/Resources/rime/." "$PAYLOAD_APP/Contents/Resources/rime/"
cp -r "$ROOT_DIR/LOInputMethod/Resources/zh-Hans.lproj" "$PAYLOAD_APP/Contents/Resources/"
cp -r "$ROOT_DIR/LOInputMethod/Resources/en.lproj" "$PAYLOAD_APP/Contents/Resources/"

# 把 librime 及依赖库打包进 payload（通过 INSTALL_DIR 覆盖指向 staging）
echo "  打包 librime 动态库..."
INSTALL_DIR="$PAYLOAD_APP" bash "$ROOT_DIR/scripts/build-librime.sh"

# 签名 payload（ad-hoc）
echo "  签名 payload..."
codesign --force --deep --options runtime \
    --identifier "$BUNDLE_ID" \
    -s - "$PAYLOAD_APP"

# 3. 构建安装器
echo ""
echo "[4/6] 构建安装器..."
cd "$ROOT_DIR/Installer"
swift build -c release

# 4. 组装安装器 .app 并嵌入 payload
echo ""
echo "[5/6] 组装安装器并嵌入 payload..."
rm -rf "$INSTALLER_APP"
mkdir -p "$INSTALLER_APP/Contents/MacOS"
mkdir -p "$INSTALLER_APP/Contents/Resources"
cp "$INSTALLER_BUILD_DIR/$INSTALLER_NAME" "$INSTALLER_APP/Contents/MacOS/$INSTALLER_NAME"
cp "$ROOT_DIR/Installer/Resources/Info.plist" "$INSTALLER_APP/Contents/Info.plist"
cp "$ROOT_DIR/LOInputMethod/Resources/AppIcon.icns" "$INSTALLER_APP/Contents/Resources/AppIcon.icns"
# 嵌入输入法 payload，安装器运行时从这里读取并拷贝到系统目录
cp -R "$PAYLOAD_APP" "$INSTALLER_APP/Contents/Resources/$APP_NAME.app"

# 签名安装器（内层 payload 已签名，此处签名外层 installer）
echo "  签名安装器..."
codesign --force --deep --options runtime \
    --identifier "$INSTALLER_BUNDLE_ID" \
    -s - "$INSTALLER_APP"

# 5. 生成 DMG
echo ""
echo "[6/6] 生成 DMG 安装镜像..."
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$INSTALLER_APP" "$DMG_ROOT/"
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
echo ""
echo "分发说明："
echo "  - 未用开发者证书签名公证时，用户首次打开需在「系统设置 › 隐私与安全性」"
echo "    中允许打开（Gatekeeper 拦截）。"
echo "  - 拥有 Apple 开发者账号后，可在本脚本中对 payload/installer 改用正式签名"
echo "    并执行 xcrun notarytool 公证，实现完全静默安装体验。"

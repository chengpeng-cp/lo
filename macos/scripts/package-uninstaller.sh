#!/bin/bash
# ============================================================================
# 语境输入法卸载工具打包脚本
#
# 流程：构建 LOUninstaller → 组装 .app → 嵌入 scripts/uninstall.sh
#       → 签名 → 生成 .dmg
#
# 用法：在 macos/ 目录下执行 bash scripts/package-uninstaller.sh
#       或通过 Makefile：make package-uninstaller
#       bash scripts/package-uninstaller.sh --app-only   # 只组装 .app，不生成 DMG
#       （package.sh 用它把卸载工具放进安装镜像）
#
# 产物：dist/语境输入法卸载工具-<版本>.dmg
# ============================================================================

set -euo pipefail

APP_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --app-only) APP_ONLY=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *)
            echo "未知参数：$arg" >&2
            exit 2
            ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # macos/
APP_NAME="LOUninstaller"
APP_DISPLAY="语境输入法卸载工具"
BUNDLE_ID="com.lo.inputmethod.uninstaller"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/LOInputMethod/Info.plist")"

BUILD_DIR="$ROOT_DIR/Uninstaller/.build/release"
STAGING_DIR="$ROOT_DIR/.build/staging-uninstaller"
APP_PATH="$STAGING_DIR/$APP_DISPLAY.app"
DMG_ROOT="$STAGING_DIR/dmg"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_DISPLAY-$VERSION.dmg"

echo "=========================================="
echo "  语境输入法卸载工具打包  (v$VERSION)"
echo "=========================================="

echo ""
echo "[1/4] 构建卸载工具..."
cd "$ROOT_DIR/Uninstaller"
# 受限环境（如 CI 容器）可用 SWIFT_BUILD_FLAGS=--disable-sandbox 关闭 SwiftPM 沙箱
# shellcheck disable=SC2086
swift build -c release -Xswiftc -strict-concurrency=minimal ${SWIFT_BUILD_FLAGS:-}

echo ""
echo "[2/4] 组装 .app 并嵌入清理脚本..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Uninstaller/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/LOInputMethod/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

# 清理逻辑只有一份：直接复用 scripts/uninstall.sh
cp "$ROOT_DIR/scripts/uninstall.sh" "$APP_PATH/Contents/Resources/uninstall.sh"
chmod 755 "$APP_PATH/Contents/Resources/uninstall.sh"

echo ""
echo "[3/4] 签名..."
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime \
    --identifier "$BUNDLE_ID" \
    -s "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

if [ "$APP_ONLY" -eq 1 ]; then
    echo ""
    echo "已组装: $APP_PATH"
    exit 0
fi

echo ""
echo "[4/4] 生成 DMG..."
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"

cat > "$DMG_ROOT/使用说明.txt" <<'EOF'
语境输入法卸载工具

1. 双击「语境输入法卸载工具」。
2. 工具会自动扫描本机的语境输入法残留，并列出将被删除的路径与体积。
3. 点击「彻底卸载」，输入管理员密码即可清理系统级安装。
4. 清理完成后建议注销并重新登录，再安装新版本。

提示
- 默认勾选「同时清空 Rime 词库与用户词典」，这是避免旧词频、旧部署缓存
  干扰新版本的关键；如需保留词库，可取消勾选或先备份到桌面。
- 若检测到鼠须管（Squirrel）等共用 ~/Library/Rime 的输入法，工具只会
  删除语境输入法自己的文件，不会破坏其他输入法的用户词典。
- 未使用开发者证书签名，首次打开若被系统拦截，请右键点击图标选择「打开」。

命令行方式（适合反复测试）
  cd macos
  bash scripts/uninstall.sh --dry-run          # 只扫描
  bash scripts/uninstall.sh --purge            # 彻底清理
EOF

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_DISPLAY" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

echo ""
echo "=========================================="
echo "  打包完成"
echo "=========================================="
echo "卸载镜像: $DMG_PATH"

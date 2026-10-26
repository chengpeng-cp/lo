#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-version.sh
source "$ROOT_DIR/scripts/lib-version.sh"

DEST="${1:?Usage: assemble-app.sh output.app}"
case "$DEST" in *.app) ;; *) echo 'Output must be an .app bundle' >&2; exit 1 ;; esac
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$ROOT_DIR/.build/release/LOInputMethod" "$DEST/Contents/MacOS/"
# 输入源切换助手：输入法进程内选择自身会握手弹跳，必须以独立进程执行 TISSelectInputSource
cp "$ROOT_DIR/.build/release/LOSourceSwitcher" "$DEST/Contents/MacOS/"
cp "$ROOT_DIR/LOInputMethod/Info.plist" "$DEST/Contents/"

# 版本号：CI 传入 LO_VERSION（tag 版本）；本地在 tag 上打包时自动取 tag；否则保持 Info.plist 默认值。
# 必须写在拷贝 Info.plist 之后，否则会被源文件覆盖回开发默认值。
VERSION="$(resolve_lo_version "$ROOT_DIR" "$ROOT_DIR/LOInputMethod/Info.plist")"
export LO_VERSION="$VERSION"
stamp_lo_version "$DEST/Contents/Info.plist" "$VERSION"

cp -R "$ROOT_DIR/LOInputMethod/Resources/." "$DEST/Contents/Resources/"
INSTALL_DIR="$DEST" bash "$ROOT_DIR/scripts/build-librime.sh"

# 本地翻译：helper 进程 + ONNX Runtime 动态库
if [ ! -f "$ROOT_DIR/vendor/onnxruntime/lib/libonnxruntime.dylib" ]; then
    bash "$ROOT_DIR/scripts/fetch-onnxruntime.sh"
fi
cp "$ROOT_DIR/.build/release/LOMTEngine" "$DEST/Contents/MacOS/"
mkdir -p "$DEST/Contents/Frameworks"

# 架构自检：产物必须包含当前机器的架构。
# 双架构流水线（macos-14 / macos-15-intel）下，如果 .build 里残留了另一台机器的产物，
# 这里就会立刻失败，而不是悄悄打出一个跑不起来的包。
APP_ARCHS="$(lipo -archs "$DEST/Contents/MacOS/LOInputMethod")"
HOST_ARCH="$(uname -m)"
case " $APP_ARCHS " in
    *" $HOST_ARCH "*) ;;
    *)
        echo "构建产物架构为 [$APP_ARCHS]，不含本机架构 $HOST_ARCH" >&2
        echo "请清理 .build 后重新构建（swift package clean）" >&2
        exit 1
        ;;
esac

# ONNX Runtime 上游发布的是 universal2（x86_64 + arm64）。
# 单架构可执行文件就削成同架构以省体积；多架构产物则原样保留——
# 早先这里无条件 lipo -thin，等于把 universal 库强行降级，架构信息一丢就再也做不回通用包。
ORT_LIB="$ROOT_DIR/vendor/onnxruntime/lib/libonnxruntime.1.20.1.dylib"
ORT_DEST="$DEST/Contents/Frameworks/libonnxruntime.1.20.1.dylib"
if [ "$(printf '%s\n' $APP_ARCHS | wc -l | tr -d ' ')" -eq 1 ]; then
    lipo -thin "$APP_ARCHS" "$ORT_LIB" -output "$ORT_DEST"
else
    cp "$ORT_LIB" "$ORT_DEST"
fi
ln -sf libonnxruntime.1.20.1.dylib "$DEST/Contents/Frameworks/libonnxruntime.dylib"
strip -x "$ORT_DEST" 2>/dev/null || true

# Homebrew bottles may require a newer OS than the Swift deployment target.
MIN_OS="$(otool -l "$DEST/Contents/MacOS/LOInputMethod" "$DEST/Contents/Frameworks/"*.dylib | awk '$1 == "minos" {split($2, p, "."); n=p[1]*10000+p[2]*100+p[3]; if(n>max){max=n; version=$2}} END {print version}')"
if [ -n "$MIN_OS" ]; then
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_OS" "$DEST/Contents/Info.plist"
fi
# CODESIGN_IDENTITY 可指定稳定的开发证书；默认 ad-hoc（CI 无证书）
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime --identifier com.lo.inputmethod.ime -s "$IDENTITY" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Assembled $DEST (v$VERSION, minimum macOS $MIN_OS, $(lipo -archs "$DEST/Contents/MacOS/LOInputMethod"))"

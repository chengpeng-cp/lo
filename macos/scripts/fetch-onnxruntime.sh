#!/bin/bash
# 下载 ONNX Runtime 的 macOS universal2 预编译包到 macos/vendor/onnxruntime。
# 该目录不随仓库分发（见 .gitignore），由构建脚本按需获取。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${ONNXRUNTIME_VERSION:-1.20.1}"
DEST="$ROOT_DIR/vendor/onnxruntime"
ARCHIVE="onnxruntime-osx-universal2-$VERSION.tgz"
URL="https://github.com/microsoft/onnxruntime/releases/download/v$VERSION/$ARCHIVE"

if [ -f "$DEST/lib/libonnxruntime.dylib" ] && [ -f "$DEST/include/onnxruntime_cxx_api.h" ]; then
    echo "ONNX Runtime $VERSION 已存在：$DEST"
    exit 0
fi

mkdir -p "$ROOT_DIR/vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "下载 $URL …"
curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$TMP/$ARCHIVE"

tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
SRC="$TMP/onnxruntime-osx-universal2-$VERSION"
[ -d "$SRC" ] || SRC="$(find "$TMP" -maxdepth 1 -type d -name 'onnxruntime-osx-*' | head -1)"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/include" "$DEST/include"
cp -R "$SRC/lib" "$DEST/lib"

echo "已安装 ONNX Runtime $VERSION 到 $DEST"

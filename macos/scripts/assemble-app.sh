#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?Usage: assemble-app.sh output.app}"
case "$DEST" in *.app) ;; *) echo 'Output must be an .app bundle' >&2; exit 1 ;; esac
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$ROOT_DIR/.build/release/LOInputMethod" "$DEST/Contents/MacOS/"
cp "$ROOT_DIR/LOInputMethod/Info.plist" "$DEST/Contents/"
cp -R "$ROOT_DIR/LOInputMethod/Resources/." "$DEST/Contents/Resources/"
INSTALL_DIR="$DEST" bash "$ROOT_DIR/scripts/build-librime.sh"
# Homebrew bottles may require a newer OS than the Swift deployment target.
MIN_OS="$(otool -l "$DEST/Contents/MacOS/LOInputMethod" "$DEST/Contents/Frameworks/"*.dylib | awk '$1 == "minos" {split($2, p, "."); n=p[1]*10000+p[2]*100+p[3]; if(n>max){max=n; version=$2}} END {print version}')"
if [ -n "$MIN_OS" ]; then
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_OS" "$DEST/Contents/Info.plist"
fi
# CODESIGN_IDENTITY 可指定稳定的开发证书；默认 ad-hoc（CI 无证书）
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime --identifier com.lo.inputmethod.ime -s "$IDENTITY" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Assembled $DEST (minimum macOS $MIN_OS, $(lipo -archs "$DEST/Contents/MacOS/LOInputMethod"))"

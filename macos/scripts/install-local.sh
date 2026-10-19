#!/bin/bash
# Install only after a complete, signed bundle exists; restore on replacement failure.
set -euo pipefail
SOURCE="${1:?Usage: install-local.sh source.app}"
TARGET="${HOME}/Library/Input Methods/LOInputMethod.app"
SYSTEM_TARGET="/Library/Input Methods/LOInputMethod.app"
if [ -d "$SYSTEM_TARGET" ]; then
    echo "A system installation exists. Upgrade with the DMG installer to avoid duplicates." >&2
    exit 1
fi
PARENT="$(dirname "$TARGET")"
mkdir -p "$PARENT"
WORK="$(mktemp -d "$PARENT/.lo-install.XXXXXX")"
INSTALLED=0
cleanup() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        if [ "$INSTALLED" -eq 1 ]; then rm -rf "$TARGET"; fi
        if [ -e "$WORK/previous.app" ]; then mv "$WORK/previous.app" "$TARGET"; fi
    fi
    rm -rf "$WORK"
    exit "$status"
}
trap cleanup EXIT
ditto "$SOURCE" "$WORK/new.app"
codesign --verify --deep --strict "$WORK/new.app"
killall LOInputMethod 2>/dev/null || true
if [ -d "$TARGET" ]; then mv "$TARGET" "$WORK/previous.app"; fi
mv "$WORK/new.app" "$TARGET"
INSTALLED=1
codesign --verify --deep --strict "$TARGET"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$TARGET"
echo "Installed $TARGET. Enable it in System Settings > Keyboard > Input Sources."

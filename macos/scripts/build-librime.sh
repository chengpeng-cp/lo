#!/bin/bash
# Collect the complete dylib dependency graph and remove build-machine paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LOInputMethod"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/Library/Input Methods/${APP_NAME}.app}"
FRAMEWORKS_DIR="${INSTALL_DIR}/Contents/Frameworks"
EXECUTABLE="${INSTALL_DIR}/Contents/MacOS/${APP_NAME}"
[ -f "$EXECUTABLE" ] || { echo "Missing executable: $EXECUTABLE" >&2; exit 1; }
mkdir -p "$FRAMEWORKS_DIR"

# bash 3.2 is the macOS default: use arrays rather than associative arrays.
BUNDLED_NAMES=()
BUNDLED_SOURCES=()
resolve_dependency() {
    local ref="$1" owner="$2"
    case "$ref" in
        /*) printf '%s\n' "$ref" ;;
        @loader_path/*) printf '%s/%s\n' "$(dirname "$owner")" "${ref#@loader_path/}" ;;
        @rpath/*)
            local name="${ref#@rpath/}" candidate
            for candidate in "$(dirname "$owner")/$name" /opt/homebrew/lib/"$name" /usr/local/lib/"$name"; do
                if [ -f "$candidate" ]; then printf '%s\n' "$candidate"; return; fi
            done
            echo "Cannot resolve dependency $ref from $owner" >&2; return 1 ;;
        *) echo "Unsupported dependency $ref from $owner" >&2; return 1 ;;
    esac
}

bundle_library() {
    local source="$1" name index destination ref dependency depname
    name="$(basename "$source")"
    index=0
    while [ "$index" -lt "${#BUNDLED_NAMES[@]}" ]; do
        if [ "${BUNDLED_NAMES[$index]}" = "$name" ]; then
            # A basename collision must never silently link the wrong library.
            cmp -s "$source" "${BUNDLED_SOURCES[$index]}" || {
                echo "Conflicting libraries named $name" >&2; return 1;
            }
            return
        fi
        index=$((index + 1))
    done
    [ -f "$source" ] || { echo "Missing dependency: $source" >&2; return 1; }
    BUNDLED_NAMES+=("$name")
    BUNDLED_SOURCES+=("$source")
    destination="$FRAMEWORKS_DIR/$name"
    cp -L "$source" "$destination"
    chmod u+w "$destination"
    install_name_tool -id "@rpath/$name" "$destination"
    # A dylib's first otool entry is its own ID, not a dependency.
    while IFS= read -r ref; do
        case "$ref" in /System/Library/*|/usr/lib/*) continue ;; esac
        dependency="$(resolve_dependency "$ref" "$source")"
        depname="$(basename "$dependency")"
        bundle_library "$dependency"
        install_name_tool -change "$ref" "@loader_path/$depname" "$destination"
    done < <(otool -L "$source" | awk 'NR > 2 {print $1}')
    codesign --force --sign - "$destination"
}

while IFS= read -r ref; do
    case "$ref" in /System/Library/*|/usr/lib/*) continue ;; esac
    dependency="$(resolve_dependency "$ref" "$EXECUTABLE")"
    bundle_library "$dependency"
    install_name_tool -change "$ref" "@executable_path/../Frameworks/$(basename "$dependency")" "$EXECUTABLE"
done < <(otool -L "$EXECUTABLE" | awk 'NR > 1 {print $1}')

# Fail packaging if any executable or copied dylib still references this machine.
for binary in "$EXECUTABLE" "$FRAMEWORKS_DIR/"*.dylib; do
    if otool -L "$binary" | awk 'NR > 1 {print $1}' | /usr/bin/grep -Eq '^/(opt|usr/local|Users|Volumes)/'; then
        echo "Nonportable dependency remains in $binary" >&2
        exit 1
    fi
done
codesign --force --sign - "$EXECUTABLE"
echo "Bundled ${#BUNDLED_NAMES[@]} dylibs; no external Homebrew dependencies remain."

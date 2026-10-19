#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$repo_root/macos/.build/translation-regressions"
mkdir -p "$build_dir/module-cache"
# Merge into one Swift file so same-file test extensions can exercise private state
# without exposing test hooks in production or changing Package.swift.
cat "$repo_root"/macos/LOInputMethod/Translation/*.swift "$repo_root/macos/Tests/TranslationRegression.swift" > "$build_dir/TranslationRegression.swift"
CLANG_MODULE_CACHE_PATH="$build_dir/module-cache" swiftc -parse-as-library "$build_dir/TranslationRegression.swift" -o "$build_dir/translation-regressions"
"$build_dir/translation-regressions"

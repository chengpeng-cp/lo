#!/bin/bash
# ============================================================================
# 版本号解析（供 package.sh / assemble-app.sh / package-uninstaller.sh source）
#
# 为什么要单独抽出来：
#   输入法 Info.plist、安装器 Info.plist、卸载工具 Info.plist 三处各写过一个 1.0.0，
#   历史上从 v1.0.0 到 v1.2.1 全都没人改，导致 DMG 永远叫「语境输入法-1.0.0.dmg」，
#   崩溃报告里的 app_version 也全是 1.0.0，无法把用户反馈映射到版本。
#
# 解析优先级：
#   1. 环境变量 LO_VERSION（CI 从 tag 传入，是唯一权威来源）
#   2. git describe --tags --exact-match（本地正好在 tag 上打包）
#   3. Info.plist 里的开发默认值
#
# 只接受纯数字点分版本（Apple 对 CFBundleShortVersionString 的要求），
# 形如 0.0.0-dev12 的 CI 预发布号不会写进 plist，只用于 artifact 命名。
# ============================================================================

# 解析版本号
# 用法：resolve_lo_version <repo_root> <fallback_plist>
resolve_lo_version() {
    local root="$1" fallback_plist="$2" candidate="${LO_VERSION:-}"

    if [ -z "$candidate" ]; then
        # 带上 --dirty：工作区有未提交改动时输出 v1.2.1-dirty，过不了数字校验，
        # 从而回退到开发默认值——不能让「本地改了几个文件」的包冒充正式版本号。
        candidate="$(git -C "$root" describe --tags --exact-match --dirty 2>/dev/null || true)"
        candidate="${candidate#v}"
    fi

    if printf '%s' "$candidate" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [ -n "$candidate" ]; then
        echo "提示：$candidate 不是纯数字版本，Info.plist 保持原值" >&2
    fi
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$fallback_plist"
}

# 把版本号写进 .app 的 Info.plist
# 用法：stamp_lo_version <plist_path> <version>
stamp_lo_version() {
    local plist="$1" version="$2"
    [ -f "$plist" ] || return 0
    printf '%s' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*$' || return 0
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$plist" 2>/dev/null || true
}

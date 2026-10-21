#!/bin/bash
# ============================================================================
# 语境输入法（LO Input Method）macOS 彻底卸载脚本
#
# 为什么需要它：
#   旧版本会在系统里留下 bundle 副本、LaunchServices 注册、输入源启用记录、
#   Rime 部署缓存、Keychain 中的 API Key 等。只把 .app 拖进废纸篓，重新安装
#   新包后这些残留仍会参与输入法列表与引擎初始化，导致“旧版本干扰测试”。
#
# 用法：
#   bash scripts/uninstall.sh --dry-run                     # 只扫描，不改动任何文件
#   bash scripts/uninstall.sh                               # 卸载应用与系统注册，保留词库
#   bash scripts/uninstall.sh --purge                       # 连同 Rime 词库/用户词典一起清空
#   bash scripts/uninstall.sh --purge --backup ~/Desktop    # 清空前先备份用户数据
#   bash scripts/uninstall.sh --system-only                 # 仅系统级（GUI 特权阶段使用）
#   bash scripts/uninstall.sh --user-only                   # 仅当前用户级（GUI 用户阶段使用）
#
# 选项：
#   --purge              清空 ~/Library/Rime（词库、用户词典、部署缓存）
#   --backup <dir>       删除前把 Rime 与偏好设置备份到 <dir>
#   --force-rime         即使检测到其他 Rime 输入法的数据也整体删除 ~/Library/Rime
#   --system-only        只清理 /Library/Input Methods 与进程
#   --user-only          只清理当前用户目录与用户级注册（不需要 root）
#   --keep-agent         不重启 TextInputMenuAgent
#   --skip-tis           跳过输入源列表清理（GUI 已用原生 API 完成）
#   --yes                不再询问确认
#   --quiet              只输出结果行
#
# 输出协议（制表符分隔，供 GUI/CI 解析）：
#   LO_ITEM     <分组> <字节数> <类型:file|service> <路径/描述>
#   LO_STEP     <文案>
#   LO_REMOVED  <路径>
#   LO_WARN     <文案>
#   LO_RESULT   <已清理> <失败> <剩余>
#   LO_DONE / LO_FAIL
# ============================================================================

set -uo pipefail

APP_NAME="LOInputMethod"
APP_DISPLAY_NAME="语境输入法"
BUNDLE_ID="com.lo.inputmethod.ime"
INSTALLER_BUNDLE_ID="com.lo.inputmethod.installer"
KEYCHAIN_SERVICE="com.lo.inputmethod"
SYSTEM_DIR="/Library/Input Methods"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

MODE="uninstall"
PURGE=0
SYSTEM_ONLY=0
USER_ONLY=0
ASSUME_YES=0
BACKUP_DIR=""
FORCE_RIME=0
KEEP_AGENT=0
SKIP_TIS=0
QUIET=0
RIME_SHARED_KEPT=0
REMAINING_PATHS=()

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    MODE="dry-run" ;;
        --purge)      PURGE=1 ;;
        --system-only) SYSTEM_ONLY=1 ;;
        --user-only)  USER_ONLY=1 ;;
        --backup)     BACKUP_DIR="${2:-}"; [ -n "$BACKUP_DIR" ] || { echo "缺少 --backup 的目录参数" >&2; exit 2; }; shift ;;
        --backup=*)   BACKUP_DIR="${1#*=}" ;;
        --force-rime) FORCE_RIME=1 ;;
        --keep-agent) KEEP_AGENT=1 ;;
        --skip-tis)   SKIP_TIS=1 ;;
        --yes|-y)     ASSUME_YES=1 ;;
        --quiet)      QUIET=1 ;;
        -h|--help)    sed -n '2,37p' "$0"; exit 0 ;;
        *) echo "未知参数：$1（使用 --help 查看用法）" >&2; exit 2 ;;
    esac
    shift
done

if [ $((SYSTEM_ONLY + USER_ONLY)) -gt 1 ]; then
    echo "--system-only 与 --user-only 不能同时使用" >&2
    exit 2
fi

IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

if [ "$USER_ONLY" -eq 1 ] && [ "$IS_ROOT" -eq 1 ]; then
    echo "--user-only 必须以当前登录用户身份运行（不要加 sudo），否则会清理到 root 的家目录。" >&2
    exit 2
fi
if [ "$SYSTEM_ONLY" -eq 0 ] && [ "$USER_ONLY" -eq 0 ] && [ "$IS_ROOT" -eq 1 ]; then
    echo "请以普通用户身份运行本脚本；需要 root 的部分会自动提示 sudo。" >&2
    exit 2
fi
if [ "$SYSTEM_ONLY" -eq 1 ] && [ "$IS_ROOT" -ne 1 ]; then
    echo "--system-only 需要 root 权限，请通过 sudo 运行。" >&2
    exit 2
fi

HOME_DIR="${HOME:-$(eval echo "~$(id -un)")}"
SCRIPT_PATH="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)/$(basename "$0")"

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
step() { [ "$QUIET" -eq 1 ] || printf 'LO_STEP\t%s\n' "$*"; }
warn() { printf 'LO_WARN\t%s\n' "$*"; }
removed_line() { printf 'LO_REMOVED\t%s\n' "$*"; }
fail_line() { printf 'LO_ERROR\t%s\n' "$*"; }

# ---------------------------------------------------------------------------
# 待清理项收集
# ---------------------------------------------------------------------------
GROUP_APP="应用与副本"
GROUP_REG="系统注册"
GROUP_SETTINGS="偏好设置"
GROUP_KEYCHAIN="钥匙串"
GROUP_DATA="用户数据"
GROUP_LOG="日志与缓存"

ITEM_GROUP=()
ITEM_PATH=()
ITEM_KIND=()

add_item() { # group path [kind]
    local g="$1" p="$2" k="${3:-file}"
    if [ -e "$p" ] || [ -L "$p" ]; then
        ITEM_GROUP+=("$g"); ITEM_PATH+=("$p"); ITEM_KIND+=("$k")
    fi
}

add_glob() { # group pattern [kind]
    local g="$1" pattern="$2" k="${3:-file}" f
    # compgen 以整条路径匹配，避免 “Input Methods” 这类含空格目录被词分割
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -e "$f" ] || [ -L "$f" ] || continue
        ITEM_GROUP+=("$g"); ITEM_PATH+=("$f"); ITEM_KIND+=("$k")
    done < <(compgen -G "$pattern" 2>/dev/null || true)
}

path_size() { # bytes
    local p="$1" kb
    kb=$(du -sk "$p" 2>/dev/null | awk 'NR==1 {print $1}')
    case "$kb" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' $((kb * 1024)) ;; esac
}

# Rime 目录是否被其他输入法共用（Squirrel / Weasel / fcitx5 等）
rime_has_foreign_data() {
    local d="$HOME_DIR/Library/Rime"
    [ -d "$d" ] || return 1
    [ -e "$d/squirrel.yaml" ] && return 0
    [ -e "$d/weasel.yaml" ] && return 0
    [ -e "$d/default.custom.yaml" ] && return 0
    [ -d "$d/sync" ] && return 0
    local f
    for f in "$d"/*.userdb; do
        [ -e "$f" ] || continue
        case "$(basename "$f")" in
            luna_pinyin*) ;;
            *) return 0 ;;
        esac
    done
    return 1
}

collect_user_items() {
    local d="$HOME_DIR/Library"

    # 用户级安装（make install 会装到这里；系统安装器不会）
    add_item "$GROUP_APP" "$d/Input Methods/$APP_NAME.app"
    add_glob "$GROUP_APP" "$d/Input Methods/$APP_NAME.app.*"
    add_glob "$GROUP_APP" "$d/Input Methods/.lo-install.*"

    # 偏好设置（含 ByHost 变体）
    add_item "$GROUP_SETTINGS" "$d/Preferences/$BUNDLE_ID.plist"
    add_item "$GROUP_SETTINGS" "$d/Preferences/$INSTALLER_BUNDLE_ID.plist"
    add_item "$GROUP_SETTINGS" "$d/Preferences/com.lo.inputmethod.plist"
    add_glob "$GROUP_SETTINGS" "$d/Preferences/ByHost/$BUNDLE_ID.*.plist"
    add_glob "$GROUP_SETTINGS" "$d/Preferences/ByHost/$INSTALLER_BUNDLE_ID.*.plist"

    # 翻译缓存 / 日志 / 崩溃报告
    add_item "$GROUP_DATA" "$d/Application Support/$APP_NAME"
    add_item "$GROUP_LOG"  "$d/Logs/$APP_NAME"
    add_item "$GROUP_LOG"  "$d/Logs/Rime/$APP_NAME.log"
    add_glob "$GROUP_LOG"  "$d/Logs/DiagnosticReports/$APP_NAME*.ips"
    add_glob "$GROUP_LOG"  "$d/Logs/DiagnosticReports/$APP_NAME*.crash"

    # 系统为该 App 生成的缓存目录
    add_item "$GROUP_LOG" "$d/Caches/$BUNDLE_ID"
    add_item "$GROUP_LOG" "$d/Caches/$INSTALLER_BUNDLE_ID"
    add_item "$GROUP_LOG" "$d/Saved Application State/$BUNDLE_ID.savedState"
    add_item "$GROUP_LOG" "$d/HTTPStorages/$BUNDLE_ID"
    add_item "$GROUP_LOG" "$d/HTTPStorages/$INSTALLER_BUNDLE_ID"

    # Rime 用户数据（含 LOInputMethod.log、部署缓存 build/、用户词典 userdb）
    if [ "$PURGE" -eq 1 ] && [ -d "$d/Rime" ]; then
        add_item "$GROUP_DATA" "$d/Rime"
    fi

    # 废纸篓中的旧副本：会被 LaunchServices 重新索引成第二条输入法
    if [ "$PURGE" -eq 1 ]; then
        add_glob "$GROUP_APP" "$HOME_DIR/.Trash/$APP_NAME*"
    fi
}

collect_system_items() {
    add_item "$GROUP_APP" "$SYSTEM_DIR/$APP_NAME.app"
    add_glob "$GROUP_APP" "$SYSTEM_DIR/$APP_NAME.app.*"
    add_glob "$GROUP_APP" "$SYSTEM_DIR/.lo-install.*"
    add_glob "$GROUP_LOG" "/Library/Logs/DiagnosticReports/$APP_NAME*.ips"
}

# python3 在未安装命令行工具时会弹出安装器，先做可用性判断
python_usable() {
    [ -x /usr/bin/python3 ] || return 1
    /usr/bin/xcode-select -p >/dev/null 2>&1 || return 1
    /usr/bin/python3 -c 'import plistlib' >/dev/null 2>&1
}

# 输入源启用列表中的残留条目数量
tis_leftover_count() {
    python_usable || { printf '0'; return; }
    /usr/bin/env python3 - "$BUNDLE_ID" <<'PY' 2>/dev/null || printf '0'
import plistlib, subprocess, sys
bundle = sys.argv[1]
total = 0
for domain, key in (("com.apple.HIToolbox", "AppleEnabledInputSources"),
                    ("com.apple.inputsources", "AppleEnabledThirdPartyInputSources")):
    raw = subprocess.run(["defaults", "export", domain, "-"],
                         capture_output=True).stdout
    if not raw:
        continue
    try:
        data = plistlib.loads(raw)
    except Exception:
        continue
    for entry in data.get(key) or []:
        if not isinstance(entry, dict):
            continue
        bid = entry.get("Bundle ID") or entry.get("BundleIdentifier") or ""
        mode = entry.get("Input Mode") or ""
        if bid == bundle or bid.startswith(bundle + ".") or mode.startswith(bundle):
            total += 1
print(total)
PY
}

collect_registration_items() {
    local count
    count=$(tis_leftover_count)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    if [ "$count" -gt 0 ]; then
        ITEM_GROUP+=("$GROUP_REG")
        ITEM_PATH+=("输入源启用列表（AppleEnabledInputSources / AppleEnabledThirdPartyInputSources）")
        ITEM_KIND+=("service")
    fi
    if security find-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
        ITEM_GROUP+=("$GROUP_KEYCHAIN")
        ITEM_PATH+=("钥匙串中的翻译 API Key（服务名 ${KEYCHAIN_SERVICE}）")
        ITEM_KIND+=("service")
    fi
}

scan() {
    ITEM_GROUP=(); ITEM_PATH=(); ITEM_KIND=()
    if [ "$SYSTEM_ONLY" -eq 1 ]; then
        collect_system_items
        collect_registration_items
    elif [ "$USER_ONLY" -eq 1 ]; then
        collect_user_items
        collect_registration_items
    else
        collect_system_items
        collect_user_items
        collect_registration_items
    fi
}

print_items() {
    local i total_bytes=0 size
    if [ "${#ITEM_PATH[@]}" -eq 0 ]; then
        printf 'LO_SCAN\t0\t0\n'
        return 0
    fi
    for i in "${!ITEM_PATH[@]}"; do
        size=0
        [ "${ITEM_KIND[$i]}" = "file" ] && size=$(path_size "${ITEM_PATH[$i]}")
        total_bytes=$((total_bytes + size))
        printf 'LO_ITEM\t%s\t%s\t%s\t%s\n' \
            "${ITEM_GROUP[$i]}" "$size" "${ITEM_KIND[$i]}" "${ITEM_PATH[$i]}"
    done
    printf 'LO_SCAN\t%s\t%s\n' "${#ITEM_PATH[@]}" "$total_bytes"
}

# ---------------------------------------------------------------------------
# 清理动作
# ---------------------------------------------------------------------------
quit_app() {
    step "退出正在运行的语境输入法进程…"
    pkill -x "$APP_NAME" 2>/dev/null || true
    local n=0
    while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$n" -lt 20 ]; do
        sleep 0.1
        n=$((n + 1))
    done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        pkill -9 -x "$APP_NAME" 2>/dev/null || true
        sleep 0.3
    fi
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        warn "进程仍在运行，注销登录后即可彻底释放文件。"
    fi
}

unregister_launch_services() {
    step "清理 LaunchServices 注册（防止输入法列表出现重复项）…"
    [ -x "$LSREGISTER" ] || return 0
    local p
    for p in \
        "$SYSTEM_DIR/$APP_NAME.app" \
        "$HOME_DIR/Library/Input Methods/$APP_NAME.app" \
        "$HOME_DIR/.Trash/$APP_NAME.app"; do
        "$LSREGISTER" -u "$p" >/dev/null 2>&1 || true
    done
    # 旧安装器留下的临时目录也可能被索引
    local f
    for f in "$SYSTEM_DIR/$APP_NAME.app".* "$HOME_DIR/Library/Input Methods/$APP_NAME.app".*; do
        [ -e "$f" ] || continue
        "$LSREGISTER" -u "$f" >/dev/null 2>&1 || true
    done
}

unregister_input_source() {
    if [ "$SKIP_TIS" -eq 1 ]; then
        return 0
    fi
    step "从系统输入源启用列表移除“${APP_DISPLAY_NAME}”…"
    python_usable || { warn "未找到可用的 python3，跳过输入源列表清理；可在系统设置中手动删除。"; return 0; }
    /usr/bin/env python3 - "$BUNDLE_ID" <<'PY'
import plistlib, subprocess, sys, tempfile, os
bundle = sys.argv[1]
for domain, key in (("com.apple.HIToolbox", "AppleEnabledInputSources"),
                    ("com.apple.inputsources", "AppleEnabledThirdPartyInputSources")):
    raw = subprocess.run(["defaults", "export", domain, "-"], capture_output=True).stdout
    if not raw:
        continue
    try:
        data = plistlib.loads(raw)
    except Exception:
        continue
    entries = data.get(key)
    if not isinstance(entries, list):
        continue

    def is_lo(entry):
        if not isinstance(entry, dict):
            return False
        bid = entry.get("Bundle ID") or entry.get("BundleIdentifier") or ""
        mode = entry.get("Input Mode") or ""
        return bid == bundle or bid.startswith(bundle + ".") or mode.startswith(bundle)

    kept = [e for e in entries if not is_lo(e)]
    if len(kept) == len(entries):
        continue
    fd, tmp = tempfile.mkstemp(suffix=".plist")
    os.close(fd)
    try:
        with open(tmp, "wb") as fh:
            plistlib.dump(kept, fh)
        subprocess.run(["defaults", "write", domain, key, tmp], check=False)
    finally:
        os.unlink(tmp)
    print(f"LO_STEP\t已从 {domain}.{key} 移除 {len(entries) - len(kept)} 条残留记录")
PY
}

delete_keychain_items() {
    step "删除钥匙串中的翻译 API Key…"
    local n=0
    while [ "$n" -lt 64 ] && security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; do
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] && say "  已删除 $n 条 Keychain 记录"
    return 0
}

reset_tcc() {
    step "重置辅助功能/输入监听授权（旧签名残留会让新包无法获得权限）…"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset PostEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
}

delete_preferences() {
    step "删除偏好设置…"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    defaults delete "$INSTALLER_BUNDLE_ID" >/dev/null 2>&1 || true
    defaults delete "com.lo.inputmethod" >/dev/null 2>&1 || true
}

backup_user_data() {
    [ -n "$BACKUP_DIR" ] || return 0
    local stamp dest
    stamp=$(date +%Y%m%d-%H%M%S)
    dest="$BACKUP_DIR/${APP_DISPLAY_NAME}备份-$stamp"
    step "备份用户数据到 $dest …"
    if ! mkdir -p "$dest"; then
        warn "无法创建备份目录 ${dest}，继续卸载。"
        return 0
    fi
    if [ -d "$HOME_DIR/Library/Rime" ]; then
        if ! mv "$HOME_DIR/Library/Rime" "$dest/Rime" 2>/dev/null; then
            ditto "$HOME_DIR/Library/Rime" "$dest/Rime" 2>/dev/null && rm -rf "$HOME_DIR/Library/Rime"
        fi
    fi
    local domain
    for domain in "$BUNDLE_ID" "$INSTALLER_BUNDLE_ID" "com.lo.inputmethod"; do
        defaults export "$domain" "$dest/$domain.plist" >/dev/null 2>&1 || true
    done
    say "  备份完成：$dest"
}

remove_rime_selectively() {
    local d="$HOME_DIR/Library/Rime"
    [ -d "$d" ] || return 0
    warn "检测到其他 Rime 输入法（如鼠须管/fcitx5）的用户数据，只清理语境输入法自身的文件。"
    local f
    for f in "$d/build" "$d/installation.yaml" "$d/user.yaml" "$d/$APP_NAME.log"; do
        [ -e "$f" ] && rm -rf "$f" 2>/dev/null && removed_line "$f"
    done
    for f in "$d"/luna_pinyin*; do
        [ -e "$f" ] || continue
        rm -rf "$f" 2>/dev/null && removed_line "$f"
    done
}

remove_items() {
    local i p g rc
    if [ "${#ITEM_PATH[@]}" -eq 0 ]; then
        return 0
    fi
    for i in "${!ITEM_PATH[@]}"; do
        p="${ITEM_PATH[$i]}"
        g="${ITEM_GROUP[$i]}"
        [ "${ITEM_KIND[$i]}" = "service" ] && continue

        case "$p" in
            */Library/Rime)
                if [ "$FORCE_RIME" -eq 1 ] || ! rime_has_foreign_data; then
                    rm -rf "$p" 2>/dev/null && removed_line "$p" || fail_line "$p"
                else
                    RIME_SHARED_KEPT=1
                    remove_rime_selectively
                fi
                continue
                ;;
        esac

        if rm -rf "$p" 2>/dev/null; then
            removed_line "$p"
        else
            fail_line "$p"
        fi
    done
    return 0
}

# 复检：只检查本次计划删除的项是否真的消失。
# Rime 目录若因与其他输入法共用而只做选择性清理，不算残留。
verify_items() {
    local i p remaining=0
    REMAINING_PATHS=()
    if [ "${#ITEM_PATH[@]}" -eq 0 ]; then
        printf '0'
        return 0
    fi
    for i in "${!ITEM_PATH[@]}"; do
        [ "${ITEM_KIND[$i]}" = "service" ] && continue
        p="${ITEM_PATH[$i]}"
        [ -e "$p" ] || [ -L "$p" ] || continue
        if [ "$RIME_SHARED_KEPT" -eq 1 ] && [ "$p" = "$HOME_DIR/Library/Rime" ]; then
            continue
        fi
        remaining=$((remaining + 1))
        REMAINING_PATHS+=("$p")
    done
    printf '%s' "$remaining"
}

system_leftovers_exist() {
    compgen -G "$SYSTEM_DIR/$APP_NAME.app*" >/dev/null 2>&1 && return 0
    compgen -G "$SYSTEM_DIR/.lo-install.*" >/dev/null 2>&1 && return 0
    return 1
}

remove_system_only() {
    local p failed=0
    quit_app
    unregister_launch_services
    for p in "$SYSTEM_DIR/$APP_NAME.app" "$SYSTEM_DIR/$APP_NAME.app".* "$SYSTEM_DIR/.lo-install."*; do
        [ -e "$p" ] || continue
        if rm -rf "$p" 2>/dev/null; then
            removed_line "$p"
        else
            fail_line "$p"
            failed=$((failed + 1))
        fi
    done
    [ "$failed" -eq 0 ]
}

refresh_agent() {
    [ "$KEEP_AGENT" -eq 1 ] && return 0
    step "重启输入法菜单代理，刷新系统输入法列表…"
    killall TextInputMenuAgent 2>/dev/null || true
}

confirm_or_abort() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local count="${#ITEM_PATH[@]}"
    printf '\n即将清理 %s 项语境输入法残留' "$count"
    [ "$PURGE" -eq 1 ] && printf '（含 Rime 词库与用户词典）'
    printf '。是否继续？[y/N] '
    local answer
    read -r answer
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) say "已取消。"; exit 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
scan
print_items

if [ "$MODE" = "dry-run" ]; then
    printf 'LO_DONE\n'
    exit 0
fi

if [ "${#ITEM_PATH[@]}" -eq 0 ]; then
    say "没有发现语境输入法残留，无需清理。"
    printf 'LO_RESULT\t0\t0\t0\nLO_DONE\n'
    exit 0
fi

confirm_or_abort

if [ "$SYSTEM_ONLY" -eq 1 ]; then
    if remove_system_only; then
        printf 'LO_DONE\n'
        exit 0
    fi
    printf 'LO_FAIL\n'
    exit 1
fi

# 有系统级安装时先提权清理：只删掉用户词库却删不掉 /Library 里的旧包，
# 会留下"半卸载"状态，新版本反而更容易被旧包干扰。
if [ "$IS_ROOT" -ne 1 ] && [ "$USER_ONLY" -eq 0 ] && system_leftovers_exist; then
    step "系统级安装需要管理员权限，先清理 /Library/Input Methods…"
    if ! sudo -v; then
        fail_line "未获得管理员权限，已停止，未删除任何用户数据。"
        printf 'LO_FAIL\n'
        exit 1
    fi
    if ! sudo /bin/bash "$SCRIPT_PATH" --system-only --yes; then
        fail_line "系统级清理失败，已停止，未删除用户数据。"
        printf 'LO_FAIL\n'
        exit 1
    fi
    # 系统项已消失，重新收集剩余项，避免统计里出现已删除的路径
    scan
fi

quit_app
unregister_launch_services
unregister_input_source
backup_user_data

# 删除文件（备份时 Rime 已被移走，这里会自然跳过）
delete_preferences
remove_items
delete_keychain_items
if [ "$PURGE" -eq 1 ]; then
    reset_tcc
fi
refresh_agent

# 复检：系统目录可能因权限未删掉，用户目录应全部消失
REMAIN_BEFORE=${#ITEM_PATH[@]}
REMAIN=$(verify_items)
REMOVED=$((REMAIN_BEFORE - REMAIN))
[ "$REMOVED" -lt 0 ] && REMOVED=0
FAILED=$REMAIN

if [ "$REMAIN" -gt 0 ]; then
    warn "仍有 $REMAIN 项残留，可能需要管理员权限或重启后清理："
    for p in "${REMAINING_PATHS[@]}"; do
        printf 'LO_ITEM\t残留\t0\tfile\t%s\n' "$p"
    done
    printf 'LO_RESULT\t%s\t%s\t%s\nLO_FAIL\n' "$REMOVED" "$FAILED" "$REMAIN"
    exit 1
fi

say ""
say "语境输入法已彻底清理（共 $REMOVED 项）。"
say "建议注销并重新登录后再安装新版本，确保系统输入法列表完全刷新。"
printf 'LO_RESULT\t%s\t0\t0\nLO_DONE\n' "$REMOVED"
exit 0

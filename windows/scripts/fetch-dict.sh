#!/usr/bin/env bash
# 语境输入法 Windows 版 - 下载 rime-ice（雾凇拼音）社区词库
#
# 用于 CI 环境（Linux bash on Windows runner）或 macOS 交叉打包场景。
# 从 rime-ice 仓库下载 cn_dicts/ 下的词典文件到 resources/rime/cn_dicts/。
#
# 用法：
#   bash scripts/fetch-dict.sh           # 下载到源码 resources/rime/cn_dicts/
#   bash scripts/fetch-dict.sh <dest>    # 下载到指定目录

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/iDvel/rime-ice/main"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_RIME_DIR="$(cd "$SCRIPT_DIR/../resources/rime" && pwd)"
DEST_DIR="${1:-$SRC_RIME_DIR/cn_dicts}"

DICT_FILES=(
    "8105.dict.yaml"
    "41448.dict.yaml"
    "base.dict.yaml"
    "ext.dict.yaml"
    "tencent.dict.yaml"
    "others.dict.yaml"
)

mkdir -p "$DEST_DIR"

echo "下载 rime-ice 词库到: $DEST_DIR"
echo "----------------------------------------"

download_file() {
    local filename="$1"
    local url="$REPO_RAW/cn_dicts/$filename"
    local target="$DEST_DIR/$filename"

    if [[ -f "$target" ]] && [[ -s "$target" ]]; then
        echo "[跳过] $filename 已存在 ($(wc -c < "$target" | tr -d ' ') bytes)"
        return 0
    fi

    echo "[下载] $filename <- $url"
    local tmp="$target.tmp"
    local ok=0
    for attempt in 1 2 3; do
        if curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$tmp"; then
            ok=1
            break
        fi
        echo "  第 $attempt 次下载失败，重试..."
        sleep 2
    done
    if [[ $ok -ne 1 ]]; then
        echo "[错误] 下载 $filename 失败"
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$target"
    echo "  完成 ($(wc -c < "$target" | tr -d ' ') bytes)"
}

for f in "${DICT_FILES[@]}"; do
    download_file "$f" || {
        echo "词库下载未完成，请重试"
        exit 1
    }
done

echo "----------------------------------------"
echo "全部词库下载完成。"

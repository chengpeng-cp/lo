#!/usr/bin/env bash
# 语镜输入法：下载 rime-ice（雾凇拼音）社区词库
#
# 从 rime-ice 仓库下载 cn_dicts/ 下的词典文件到 Resources/rime/cn_dicts/。
# 这些词库简体、常用词丰富、词频合理，替换原 7 万条繁体+生僻字词典。
# 词库文件较大，不提交进仓库（.gitignore 已忽略 cn_dicts/），由本脚本按需下载。
#
# 用法：
#   bash scripts/fetch-dict.sh           # 下载到源码 Resources/rime/cn_dicts/
#   bash scripts/fetch-dict.sh <dest>    # 下载到指定目录
#
# 跳过已存在的文件；下载失败会重试并报错退出。

set -euo pipefail

# rime-ice 仓库的 raw 文件根
REPO_RAW="https://raw.githubusercontent.com/iDvel/rime-ice/main"

# 默认目标：源码 Resources/rime/cn_dicts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_RIME_DIR="$(cd "$SCRIPT_DIR/../LOInputMethod/Resources/rime" && pwd)"
DEST_DIR="${1:-$SRC_RIME_DIR/cn_dicts}"

# 需要下载的词典文件
# 8105 / 41448 : 通用字（8105 常用字 + 41448 通用字）
# base         : 基础词库
# ext          : 扩展词库
# tencent      : 腾讯词向量词库
# others       : 其他补充
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
    # 重试 3 次
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
        echo "[错误] 下载 $filename 失败，请检查网络或仓库地址"
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
echo "下一步：make install-full 重新部署并触发 Rime 重新编译。"

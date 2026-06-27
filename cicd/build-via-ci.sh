#!/bin/bash
# ============================================================================
# 语境输入法 - macOS 上触发 CI 构建并下载安装包（跨平台发布脚本）
#
# 依赖：
#   brew install gh
#   gh auth login
#
# 用法：
#   ./cicd/build-via-ci.sh                    # 手动触发最新分支构建（双平台）
#   ./cicd/build-via-ci.sh v1.0.0             # 打 tag 发布 Release（双平台）
#   ./cicd/build-via-ci.sh --watch            # 实时观看构建日志
#   ./cicd/build-via-ci.sh --platform mac     # 只构建 macOS
#   ./cicd/build-via-ci.sh --platform windows # 只构建 Windows
#   ./cicd/build-via-ci.sh v1.0.0 --watch     # 打 tag 并观看日志
# ============================================================================

set -e

cd "$(dirname "$0")/.."

# 检查 gh CLI
if ! command -v gh >/dev/null 2>&1; then
    echo "错误：未安装 GitHub CLI"
    echo "  brew install gh"
    echo "  gh auth login"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "错误：未登录 GitHub"
    echo "  gh auth login"
    exit 1
fi

# 解析参数
WATCH=false
TAG=""
PLATFORM="both"
ARGS=("$@")
for arg in "${ARGS[@]}"; do
    case "$arg" in
        --watch) WATCH=true ;;
        --platform) shift_next_platform=true ;;
        mac|windows)
            if [[ "${shift_next_platform:-}" == "true" ]]; then
                PLATFORM="$arg"
                shift_next_platform=false
            fi
            ;;
        v*) TAG="$arg" ;;
        *)
            if [[ -n "$1" && "$1" != "--watch" && "$1" != "--platform" && "$1" != "mac" && "$1" != "windows" ]]; then
                TAG="$1"
            fi
            ;;
    esac
done

# 如果指定 tag,则打 tag 并推送触发 Release 构建（双平台同时触发）
if [[ -n "$TAG" ]]; then
    echo "==> 创建并推送 tag: $TAG"
    git tag "$TAG"
    git push origin "$TAG"

    echo
    echo "==> 已触发双平台自动构建（通常 10-15 分钟）"
    echo "    Release 页面: $(gh repo view --json url -q .url)/releases/tag/$TAG"
    echo
    echo "构建完成后,macOS dmg 和 Windows exe 将自动出现在 Release 页面。"

    if [[ "$WATCH" == "true" ]]; then
        sleep 5
        echo
        echo "==> 观看构建进度..."
        gh run list --limit 4
        echo
        echo "实时日志（Ctrl+C 退出）:"
        # 取最新的两个 run（mac + windows）
        for run_id in $(gh run list --limit 4 --json databaseId -q '.[].databaseId'); do
            gh run watch "$run_id" --exit-status >/dev/null 2>&1 &
        done
        wait
    fi
    exit 0
fi

# 手动触发 workflow
WORKFLOWS=()
case "$PLATFORM" in
    mac)     WORKFLOWS=("build-macos.yml") ;;
    windows) WORKFLOWS=("build-windows.yml") ;;
    both)    WORKFLOWS=("build-macos.yml" "build-windows.yml") ;;
esac

RUN_IDS=()
for wf in "${WORKFLOWS[@]}"; do
    echo "==> 触发 workflow: $wf"
    gh workflow run "$wf"
done

echo
echo "==> 等待 run 启动..."
sleep 3

for wf in "${WORKFLOWS[@]}"; do
    RUN_ID=$(gh run list --workflow="$wf" --limit 1 --json databaseId -q '.[0].databaseId')
    if [[ -n "$RUN_ID" ]]; then
        RUN_IDS+=("$RUN_ID")
        echo "  $wf → Run ID: $RUN_ID"
    fi
done

if [[ ${#RUN_IDS[@]} -eq 0 ]]; then
    echo "错误：未找到 run"
    exit 1
fi

if [[ "$WATCH" == "true" ]]; then
    echo
    echo "==> 实时观看构建日志（Ctrl+C 退出）..."
    for run_id in "${RUN_IDS[@]}"; do
        gh run watch "$run_id" --exit-status >/dev/null 2>&1 &
    done
    wait
else
    echo
    echo "==> 等待构建完成..."
    for run_id in "${RUN_IDS[@]}"; do
        gh run watch "$run_id" --exit-status >/dev/null 2>&1 || true
    done
fi

# 检查构建状态
ALL_SUCCESS=true
for run_id in "${RUN_IDS[@]}"; do
    STATUS=$(gh run view "$run_id" --json status,conclusion -q '.status + "/" + .conclusion')
    echo "==> Run $run_id 状态: $STATUS"
    if [[ "$STATUS" != "completed/success" ]]; then
        ALL_SUCCESS=false
    fi
done

if [[ "$ALL_SUCCESS" != "true" ]]; then
    echo
    echo "错误：部分构建失败"
    for run_id in "${RUN_IDS[@]}"; do
        echo "  查看日志: gh run view $run_id --log"
    done
    exit 1
fi

# 下载 artifact
echo
echo "==> 下载安装包..."
ARTIFACT_DIR=".artifacts"
mkdir -p "$ARTIFACT_DIR"
for run_id in "${RUN_IDS[@]}"; do
    gh run download "$run_id" -D "$ARTIFACT_DIR" 2>/dev/null || true
done

echo
echo "=========================================="
echo "  完成"
echo "=========================================="
echo "安装包位置:"
find "$ARTIFACT_DIR" \( -name "*.exe" -o -name "*.dmg" \) | while read -r f; do
    echo "  $f"
done
echo
echo "可直接双击安装,或分发给用户。"

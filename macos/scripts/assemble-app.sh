#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-version.sh
source "$ROOT_DIR/scripts/lib-version.sh"

DEST="${1:?Usage: assemble-app.sh output.app}"
case "$DEST" in *.app) ;; *) echo 'Output must be an .app bundle' >&2; exit 1 ;; esac
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

# CODESIGN_IDENTITY 可指定稳定的开发证书；默认 ad-hoc（CI 无证书）
IDENTITY="${CODESIGN_IDENTITY:--}"
APP_ID="com.lo.inputmethod.ime"

# 拷贝进来的 helper 必须当场签名，不能留到组装结束再统一补。
# 原因见文件末尾的详细说明：bundle 里只要存在未签名的嵌套二进制，之后的每一步
# 嵌套签名（build-librime.sh 里逐个签 dylib）都可能被 codesign 直接拒绝。
sign_component() {  # sign_component <file> <identifier-suffix>
    codesign --force --options runtime --identifier "$APP_ID.$2" -s "$IDENTITY" "$1"
}

cp "$ROOT_DIR/.build/release/LOInputMethod" "$DEST/Contents/MacOS/"
# 输入源切换助手：输入法进程内选择自身会握手弹跳，必须以独立进程执行 TISSelectInputSource
cp "$ROOT_DIR/.build/release/LOSourceSwitcher" "$DEST/Contents/MacOS/"
sign_component "$DEST/Contents/MacOS/LOSourceSwitcher" LOSourceSwitcher
cp "$ROOT_DIR/LOInputMethod/Info.plist" "$DEST/Contents/"

# 版本号：CI 传入 LO_VERSION（tag 版本）；本地在 tag 上打包时自动取 tag；否则保持 Info.plist 默认值。
# 必须写在拷贝 Info.plist 之后，否则会被源文件覆盖回开发默认值。
VERSION="$(resolve_lo_version "$ROOT_DIR" "$ROOT_DIR/LOInputMethod/Info.plist")"
export LO_VERSION="$VERSION"
stamp_lo_version "$DEST/Contents/Info.plist" "$VERSION"

cp -R "$ROOT_DIR/LOInputMethod/Resources/." "$DEST/Contents/Resources/"
INSTALL_DIR="$DEST" bash "$ROOT_DIR/scripts/build-librime.sh"

# 本地翻译：helper 进程 + ONNX Runtime 动态库
if [ ! -f "$ROOT_DIR/vendor/onnxruntime/lib/libonnxruntime.dylib" ]; then
    bash "$ROOT_DIR/scripts/fetch-onnxruntime.sh"
fi
cp "$ROOT_DIR/.build/release/LOMTEngine" "$DEST/Contents/MacOS/"
sign_component "$DEST/Contents/MacOS/LOMTEngine" LOMTEngine
mkdir -p "$DEST/Contents/Frameworks"

# 架构自检：产物必须包含当前机器的架构。
# 双架构流水线（macos-14 / macos-15-intel）下，如果 .build 里残留了另一台机器的产物，
# 这里就会立刻失败，而不是悄悄打出一个跑不起来的包。
APP_ARCHS="$(lipo -archs "$DEST/Contents/MacOS/LOInputMethod")"
HOST_ARCH="$(uname -m)"
case " $APP_ARCHS " in
    *" $HOST_ARCH "*) ;;
    *)
        echo "构建产物架构为 [$APP_ARCHS]，不含本机架构 $HOST_ARCH" >&2
        echo "请清理 .build 后重新构建（swift package clean）" >&2
        exit 1
        ;;
esac

# ONNX Runtime 上游发布的是 universal2（x86_64 + arm64）。
# 单架构可执行文件就削成同架构以省体积；多架构产物则原样保留——
# 早先这里无条件 lipo -thin，等于把 universal 库强行降级，架构信息一丢就再也做不回通用包。
ORT_LIB="$ROOT_DIR/vendor/onnxruntime/lib/libonnxruntime.1.20.1.dylib"
ORT_DEST="$DEST/Contents/Frameworks/libonnxruntime.1.20.1.dylib"
if [ "$(printf '%s\n' $APP_ARCHS | wc -l | tr -d ' ')" -eq 1 ]; then
    lipo -thin "$APP_ARCHS" "$ORT_LIB" -output "$ORT_DEST"
else
    cp "$ORT_LIB" "$ORT_DEST"
fi
ln -sf libonnxruntime.1.20.1.dylib "$DEST/Contents/Frameworks/libonnxruntime.dylib"
strip -x "$ORT_DEST" 2>/dev/null || true
# `lipo -thin` 会重写文件、`strip` 会削符号表，两者都会让 onnxruntime 原有的签名失效。
# 必须当场重签：bundle 里只要留一个未签名的 Mach-O，后面任何一次嵌套签名都会被 codesign
# 拒绝（Intel 上就是这样一路踩过来的，见文末说明）。
sign_component "$ORT_DEST" "libonnxruntime.1.20.1.dylib"

# Homebrew bottles may require a newer OS than the Swift deployment target.
MIN_OS="$(otool -l "$DEST/Contents/MacOS/LOInputMethod" "$DEST/Contents/Frameworks/"*.dylib | awk '$1 == "minos" {split($2, p, "."); n=p[1]*10000+p[2]*100+p[3]; if(n>max){max=n; version=$2}} END {print version}')"
if [ -n "$MIN_OS" ]; then
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_OS" "$DEST/Contents/Info.plist"
fi
# ------- 签名 -------
#
# 曾经这里只有一句 `codesign --force --deep ... "$DEST"`，arm64 一路绿灯，Intel 必挂：
#   Contents/MacOS/LOInputMethod: code object is not signed at all
#   In subcomponent: Contents/MacOS/LOSourceSwitcher
# 两个原因叠加，正好只在 x86_64 上暴露：
#   1) arm64 的链接器会自动给产物做 ad-hoc 签名，x86_64 不会。于是同一个 helper 在 Intel 上
#      是真·未签名，在 Apple Silicon 上只是“已签名、待替换”，从签名状态上根本看不出差别；
#   2) 与主可执行文件并列的 helper（LOSourceSwitcher / LOMTEngine）不在 codesign 认可的嵌套
#      代码目录（Frameworks / PlugIns / XPCServices）里，`--deep` 不保证覆盖。bundle 里只要
#      存在这样未签名的嵌套二进制，后续任何一次嵌套签名都可能被 codesign 拒绝——因此 helper
#      在拷贝进来的当场就签（见文件开头 sign_component）。
#
# 现在改成全程显式、自内向外：helper（拷贝时已签）→ dylib → bundle 本体，不再依赖 `--deep`
# 的隐式递归。这样还有一个好处：`--deep` 签 bundle 时会把已签好的嵌套二进制重签一遍并改写
# 它们的 identifier，结果随 codesign 版本漂移；显式签名则完全确定。

# 1) helper 与主程序：helper 上面已签，这里补签一次保证幂等一致；
#    主可执行文件被 build-librime.sh 的 install_name_tool 改过，必须重签。
for exe in "$DEST/Contents/MacOS/"*; do
    [ -f "$exe" ] || continue
    file -b "$exe" | grep -q 'Mach-O' || continue
    if [ "$exe" = "$DEST/Contents/MacOS/LOInputMethod" ]; then
        codesign --force --options runtime --identifier "$APP_ID" -s "$IDENTITY" "$exe"
    else
        name="$(printf '%s' "$(basename "$exe")" | tr -c 'A-Za-z0-9._-' '-')"
        sign_component "$exe" "$name"
    fi
done

# 2) Contents/Frameworks：build-librime.sh 已签过 librime 及其依赖，但 onnxruntime 是上面
#    cp + strip 进来的，签名已经失效。统一再签一遍：幂等，代价可忽略。
for lib in "$DEST/Contents/Frameworks/"*; do
    [ -f "$lib" ] || continue
    [ -L "$lib" ] && continue   # 跳过 libonnxruntime.dylib 这类软链，签的是目标文件
    file -b "$lib" | grep -q 'Mach-O' || continue
    name="$(printf '%s' "$(basename "$lib")" | tr -c 'A-Za-z0-9._-' '-')"
    sign_component "$lib" "$name"
done

# 3) 最后签 bundle 本体（不带 --deep）
codesign --force --options runtime --identifier "$APP_ID" -s "$IDENTITY" "$DEST"

# 校验仍用 --deep：这里要的就是把每个嵌套组件都查一遍，漏签必须失败而不是放过
if ! codesign --verify --deep --strict "$DEST"; then
    echo "签名校验失败，逐个列出 bundle 内的 Mach-O 签名状态：" >&2
    for bin in "$DEST/Contents/MacOS/"* "$DEST/Contents/Frameworks/"*; do
        [ -f "$bin" ] || continue
        [ -L "$bin" ] && continue
        file -b "$bin" | grep -q 'Mach-O' || continue
        echo "--- $bin" >&2
        codesign -dvv "$bin" 2>&1 | sed 's/^/    /' >&2 || true
    done
    exit 1
fi
echo "Assembled $DEST (v$VERSION, minimum macOS $MIN_OS, $(lipo -archs "$DEST/Contents/MacOS/LOInputMethod"))"

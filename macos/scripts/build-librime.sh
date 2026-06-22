#!/bin/bash
# 将 librime 及其依赖库打包到应用 Frameworks 目录
# 使应用自包含，不依赖 Homebrew 路径

set -uo pipefail

# 配置
APP_NAME="LOInputMethod"
INSTALL_DIR="${HOME}/Library/Input Methods/${APP_NAME}.app"
FRAMEWORKS_DIR="${INSTALL_DIR}/Contents/Frameworks"
BUILD_DIR=".build/release"

# librime 及其依赖库列表
LIBRARIES=(
    "librime.1.dylib"
    "libglog.2.dylib"
    "libyaml-cpp.0.9.dylib"
    "libgflags.2.3.dylib"
    "libleveldb.1.dylib"
    "libmarisa.0.dylib"
    "libopencc.1.3.dylib"
)

# Homebrew 库路径
HOMEBREW_LIB="/opt/homebrew/lib"

echo "=== 打包 librime 及依赖库到 ${FRAMEWORKS_DIR} ==="

# 创建 Frameworks 目录
mkdir -p "${FRAMEWORKS_DIR}"

# 复制动态库
for lib in "${LIBRARIES[@]}"; do
    src="${HOMEBREW_LIB}/${lib}"
    if [ -f "${src}" ]; then
        echo "复制 ${lib}"
        cp "${src}" "${FRAMEWORKS_DIR}/${lib}"
    else
        echo "警告: 未找到 ${src}，跳过"
    fi
done

# 复制不带版本号的符号链接指向的库
for lib in "${LIBRARIES[@]}"; do
    base_name=$(echo "${lib}" | sed -E 's/\.[0-9]+(\.[0-9]+)?\.dylib$/.dylib/')
    src="${HOMEBREW_LIB}/${base_name}"
    if [ -L "${src}" ]; then
        ln -sf "${lib}" "${FRAMEWORKS_DIR}/${base_name}"
    fi
done

# 修改库的 install_name，使用 @rpath
# 注意：install_name_tool 会打印签名失效警告，这是预期行为，最后统一重新签名
echo ""
echo "=== 修改 install_name 为 @rpath ==="

for lib in "${LIBRARIES[@]}"; do
    dylib="${FRAMEWORKS_DIR}/${lib}"
    if [ -f "${dylib}" ]; then
        # 修改自身的 install_name
        install_name_tool -id "@rpath/${lib}" "${dylib}" 2>/dev/null || true

        # 修改对其他依赖库的引用
        for dep in "${LIBRARIES[@]}"; do
            otool -L "${dylib}" 2>/dev/null | grep -E "(/opt/homebrew/lib/|/usr/local/lib/)${dep}" | awk '{print $1}' | while read ref; do
                install_name_tool -change "${ref}" "@rpath/${dep}" "${dylib}" 2>/dev/null || true
            done
        done
    fi
done

# 设置可执行文件的 rpath
EXECUTABLE="${INSTALL_DIR}/Contents/MacOS/${APP_NAME}"
if [ -f "${EXECUTABLE}" ]; then
    echo ""
    echo "=== 设置可执行文件 rpath ==="
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${EXECUTABLE}" 2>/dev/null || true
    for lib in "${LIBRARIES[@]}"; do
        otool -L "${EXECUTABLE}" 2>/dev/null | grep -E "(/opt/homebrew/lib/|/usr/local/lib/)${lib}" | awk '{print $1}' | while read ref; do
            install_name_tool -change "${ref}" "@rpath/${lib}" "${EXECUTABLE}" 2>/dev/null || true
        done
    done
fi

# 重新签名所有动态库和可执行文件（ad-hoc 签名）
echo ""
echo "=== 重新签名 ==="
for lib in "${LIBRARIES[@]}"; do
    dylib="${FRAMEWORKS_DIR}/${lib}"
    if [ -f "${dylib}" ]; then
        codesign --force --sign - "${dylib}" 2>/dev/null || true
        echo "已签名 ${lib}"
    fi
done
if [ -f "${EXECUTABLE}" ]; then
    codesign --force --sign - "${EXECUTABLE}" 2>/dev/null || true
    echo "已签名可执行文件"
fi

# 复制 Rime 资源文件
RESOURCES_DIR="${INSTALL_DIR}/Contents/Resources/rime"
echo ""
echo "=== 复制 Rime 资源文件 ==="
mkdir -p "${RESOURCES_DIR}"
if [ -d "LOInputMethod/Resources/rime" ]; then
    cp -r LOInputMethod/Resources/rime/* "${RESOURCES_DIR}/"
    echo "已复制 Rime 配置文件"
fi

# 复制 Rime 共享数据（方案和词典）
RIME_SHARED_DATA="/opt/homebrew/share/rime-data"
if [ -d "${RIME_SHARED_DATA}" ]; then
    echo "复制 Rime 共享数据..."
    cp -r "${RIME_SHARED_DATA}"/* "${RESOURCES_DIR}/"
fi

echo ""
echo "=== 打包完成 ==="
echo "动态库位于: ${FRAMEWORKS_DIR}"
echo "Rime 资源位于: ${RESOURCES_DIR}"

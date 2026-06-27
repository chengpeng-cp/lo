# ============================================================================
# 语境输入法 Windows 版 - CMake 构建系统
#
# 用法：
#   cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
#   cmake --build build --config Release
#   cmake --install build  （可选：安装到系统）
#
# 依赖：
#   - Visual Studio 2019+ (MSVC)
#   - Windows SDK 10.0+
#   - librime (通过 vcpkg 或手动安装)
# ============================================================================

cmake_minimum_required(VERSION 3.20)

project(LOInputMethod VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# --- 编译选项 ---
if(MSVC)
    add_compile_options(/utf-8 /W3 /EHsc /Zc:__cplusplus)
    add_compile_options(/D_UNICODE /DUNICODE /DWIN32 /D_WINDOWS)
    add_compile_options(/D_WIN32_WINNT=0x0A00)  # Windows 10
    add_compile_definitions(_ATL_NO_AUTOMATIC_NAMESPACE)
    # 静态链接 CRT，避免目标机器缺少运行时
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# --- 源文件列表 ---
set(LO_SOURCES
    src/core/DllMain.cpp
    src/core/Guids.cpp
    src/core/Log.cpp
    src/core/ClassFactory.cpp
    src/core/TextService.cpp
    src/core/Registration.cpp
    src/rime/RimeEngine.cpp
    src/rime/RimeSessionManager.cpp
    src/ui/CandidateWindow.cpp
    src/ui/TranslationOverlay.cpp
    src/ui/ColorUtils.cpp
    src/ui/DPIUtils.cpp
    src/translation/NetworkClient.cpp
    src/translation/TranslationService.cpp
    src/translation/BingTranslator.cpp
    src/translation/LLMTranslator.cpp
    src/translation/TranslationCache.cpp
    src/translation/TranslationScheduler.cpp
    src/settings/Settings.cpp
    src/settings/SettingsDialog.cpp
)

# --- 资源文件 ---
set(LO_RESOURCES
    resources/app.rc
)

# --- DLL 导出定义文件 ---
set(LO_DEF_FILE src/core/LOInputMethod.def)

# --- 创建 DLL ---
add_library(LOInputMethod SHARED ${LO_SOURCES} ${LO_RESOURCES} ${LO_DEF_FILE})

# 设置模块定义文件（MSVC）
if(MSVC)
    set_target_properties(LOInputMethod PROPERTIES LINK_FLAGS "/DEF:${CMAKE_CURRENT_SOURCE_DIR}/${LO_DEF_FILE}")
endif()

# --- 包含目录 ---
target_include_directories(LOInputMethod PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rime
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ui
    ${CMAKE_CURRENT_SOURCE_DIR}/src/translation
    ${CMAKE_CURRENT_SOURCE_DIR}/src/settings
)

# --- 链接库（Win32 系统库）---
target_link_libraries(LOInputMethod PRIVATE
    ole32
    oleaut32
    uuid
    msctf
    shlwapi
    shell32
    shlobj
    crypt32
    winhttp
    comctl32
    gdi32
    user32
    advapi32
)

# --- 查找 librime ---
# 方式1: vcpkg（推荐）- 在 vcpkg 中安装 librime 后自动找到
find_package(rime CONFIG QUIET)
if(rime_FOUND)
    target_link_libraries(LOInputMethod PRIVATE rime::rime)
    message(STATUS "找到 librime (vcpkg)")
else()
    # 方式2: 手动指定路径
    # set(RIME_ROOT "C:/path/to/librime" CACHE PATH "librime 安装路径")
    set(RIME_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/librime" CACHE PATH "librime 安装路径")
    if(EXISTS "${RIME_ROOT}/include/rime_api.h")
        target_include_directories(LOInputMethod PRIVATE "${RIME_ROOT}/include")
        target_link_directories(LOInputMethod PRIVATE "${RIME_ROOT}/lib")
        # 手动路径模式下链接 rime.lib
        find_library(RIME_LIB NAMES rime rime.lib PATHS "${RIME_ROOT}/lib" NO_DEFAULT_PATH)
        if(RIME_LIB)
            target_link_libraries(LOInputMethod PRIVATE "${RIME_LIB}")
        else()
            # 退而求其次：链接目录已添加，让链接器自行查找
            target_link_libraries(LOInputMethod PRIVATE rime)
        endif()
        message(STATUS "使用手动指定的 librime 路径: ${RIME_ROOT}")
    else()
        message(WARNING "未找到 librime！请通过 vcpkg 安装或设置 RIME_ROOT 变量")
        message(STATUS "  vcpkg install librime")
        message(STATUS "  或将 librime 放到: ${RIME_ROOT}")
    endif()
endif()

# --- 输出目录 ---
set_target_properties(LOInputMethod PROPERTIES
    OUTPUT_NAME "LOInputMethod"
    SUFFIX ".dll"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# --- 拷贝 Rime 配置到输出目录 ---
add_custom_command(TARGET LOInputMethod POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/resources/rime"
        "$<TARGET_FILE_DIR:LOInputMethod>/rime"
    COMMENT "拷贝 Rime 配置文件到输出目录"
)

# --- 安装规则 ---
install(TARGETS LOInputMethod RUNTIME DESTINATION bin)
install(DIRECTORY resources/rime DESTINATION bin)

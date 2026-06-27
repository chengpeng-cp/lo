@echo off
REM ============================================================================
REM 语境输入法 Windows 版 - 构建脚本
REM
REM 用法：
REM   scripts\build.bat            - Debug 构建
REM   scripts\build.bat Release    - Release 构建
REM   scripts\build.bat Release vcpkg - 使用 vcpkg 的 librime
REM
REM 前置条件：
REM   1. Visual Studio 2019+ (含 C++ 工具链)
REM   2. Windows SDK 10.0+
REM   3. librime（通过 vcpkg 安装或手动放置到 third_party/librime）
REM ============================================================================

setlocal enabledelayedexpansion

set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Debug

set VCPKG_FLAG=%2
set VCPKG_TOOLCHAIN=

if /i "%VCPKG_FLAG%"=="vcpkg" (
    if defined VCPKG_ROOT (
        set VCPKG_TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE=!VCPKG_ROOT!/scripts/buildsystems/vcpkg.cmake
        echo 使用 vcpkg: !VCPKG_ROOT!
    ) else (
        echo 错误：未设置 VCPKG_ROOT 环境变量
        exit /b 1
    )
)

echo ==========================================
echo   语境输入法构建 (%CONFIG%)
echo ==========================================

REM --- 查找 Visual Studio ---
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
if not exist "%VSWHERE%" (
    echo 错误：未找到 vswhere，请安装 Visual Studio 2019+
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath`) do set VSINSTALL=%%i

if not defined VSINSTALL (
    echo 错误：未找到 Visual Studio 安装
    exit /b 1
)

echo Visual Studio: %VSINSTALL%

REM --- 加载 MSVC 环境 ---
call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat"

REM --- 构建 ---
set BUILD_DIR=build
set SOURCE_DIR=%~dp0..

echo.
echo [1/3] 下载 rime-ice 词库...
call scripts\fetch-dict.bat
if errorlevel 1 (
    echo 警告：词库下载失败，将使用基础词库
)

echo.
echo [2/3] CMake 配置...
cmake -B %BUILD_DIR% -S "%SOURCE_DIR%" -DCMAKE_BUILD_TYPE=%CONFIG% %VCPKG_TOOLCHAIN%
if errorlevel 1 (
    echo 错误：CMake 配置失败
    exit /b 1
)

echo.
echo [3/3] 编译...
cmake --build %BUILD_DIR% --config %CONFIG% --parallel
if errorlevel 1 (
    echo 错误：编译失败
    exit /b 1
)

echo.
echo ==========================================
echo   构建成功
echo ==========================================
echo 输出: %BUILD_DIR%\bin\%CONFIG%\LOInputMethod.dll
echo.
echo 安装命令:
echo   regsvr32 %BUILD_DIR%\bin\%CONFIG%\LOInputMethod.dll
echo.
echo 卸载命令:
echo   regsvr32 /u %BUILD_DIR%\bin\%CONFIG%\LOInputMethod.dll

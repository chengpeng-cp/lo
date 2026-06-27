@echo off
REM ============================================================================
REM 语境输入法 Windows 版 - 构建脚本
REM
REM 用法：
REM   scripts\build.bat            - Debug 构建（使用预编译 librime）
REM   scripts\build.bat Release    - Release 构建
REM   scripts\build.bat Release vcpkg - 强制使用 vcpkg 的 librime
REM
REM 前置条件：
REM   1. Visual Studio 2019+ (含 C++ 工具链)
REM   2. Windows SDK 10.0+
REM
REM librime 依赖：
REM   默认自动从 GitHub release 下载 MSVC 预编译包到 third_party/librime
REM   或通过 vcpkg 安装（传入 vcpkg 参数）
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

REM --- 下载预编译 librime（如果未使用 vcpkg 且 third_party/librime 不存在）---
if not defined VCPKG_TOOLCHAIN (
    if not exist "%~dp0..\third_party\librime\include\rime_api.h" (
        echo.
        echo [1/4] 下载预编译 librime...
        call "%~dp0fetch-dict.bat" >nul 2>nul
        powershell -ExecutionPolicy Bypass -Command ^
            "$ErrorActionPreference='Stop';" ^
            "$url='https://github.com/rime/librime/releases/download/1.17.0/rime-33e7814-Windows-msvc-x64.7z';" ^
            "Write-Host '下载: '$url;" ^
            "Invoke-WebRequest -Uri $url -OutFile librime.7z;" ^
            "$root='%~dp0..\third_party\librime';" ^
            "New-Item -ItemType Directory -Force -Path $root | Out-Null;" ^
            "7z x librime.7z -o$tmp -y;" ^
            "$dist = Join-Path $tmp 'dist';" ^
            "if (Test-Path $dist) { Move-Item -Path (Join-Path $dist '*') -Destination $root -Force; Remove-Item $dist -Recurse -Force }" ^
            "del librime.7z"
        if errorlevel 1 (
            echo 错误：librime 下载失败
            exit /b 1
        )
        echo librime 已就绪
    ) else (
        echo librime 已存在,跳过下载
    )
)

set BUILD_DIR=build
set SOURCE_DIR=%~dp0..

REM --- 下载词库 ---
echo.
echo [2/4] 下载 rime-ice 词库...
call scripts\fetch-dict.bat
if errorlevel 1 (
    echo 警告：词库下载失败，将使用基础词库
)

REM --- CMake 配置 ---
echo.
if defined VCPKG_TOOLCHAIN (
    echo [3/4] CMake 配置（vcpkg）...
) else (
    echo [3/4] CMake 配置（预编译 librime）...
)
cmake -B %BUILD_DIR% -S "%SOURCE_DIR%" -DCMAKE_BUILD_TYPE=%CONFIG% %VCPKG_TOOLCHAIN% -DRIME_ROOT="%SOURCE_DIR%\third_party\librime"
if errorlevel 1 (
    echo 错误：CMake 配置失败
    exit /b 1
)

REM --- 编译 ---
echo.
echo [4/4] 编译...
cmake --build %BUILD_DIR% --config %CONFIG% --parallel
if errorlevel 1 (
    echo 错误：编译失败
    exit /b 1
)

REM --- 拷贝 rime.dll 到输出目录 ---
if not defined VCPKG_TOOLCHAIN (
    if exist "%SOURCE_DIR%\third_party\librime\bin\rime.dll" (
        copy /Y "%SOURCE_DIR%\third_party\librime\bin\rime.dll" "%BUILD_DIR%\bin\%CONFIG%\rime.dll" >nul
        echo 已拷贝 rime.dll 到输出目录
    )
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

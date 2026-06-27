@echo off
REM ============================================================================
REM 语境输入法 Windows 版 - 一键打包脚本
REM
REM 用法：
REM   scripts\package.bat              - 构建并生成安装包
REM   scripts\package.bat Release vcpkg - Release + vcpkg
REM
REM 输出：dist\语境输入法-Setup-1.0.0.exe
REM
REM 前置条件：
REM   1. scripts\build.bat 的所有依赖
REM   2. NSIS (https://nsis.sourceforge.io) - 安装后设置 PATH
REM ============================================================================

setlocal

set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Release

set VCPKG_FLAG=%2

echo ==========================================
echo   语境输入法打包
echo ==========================================

REM --- 构建 ---
echo.
echo [1/3] 构建输入法 DLL...
call scripts\build.bat %CONFIG% %VCPKG_FLAG%
if errorlevel 1 (
    echo 错误：构建失败
    exit /b 1
)

REM --- 查找 NSIS ---
set NSIS_EXE=
where makensis >nul 2>nul
if %errorlevel%==0 (
    set NSIS_EXE=makensis
) else (
    if exist "%ProgramFiles(x86)%\NSIS\makensis.exe" (
        set NSIS_EXE=%ProgramFiles(x86)%\NSIS\makensis.exe
    ) else (
        if exist "%ProgramFiles%\NSIS\makensis.exe" (
            set NSIS_EXE=%ProgramFiles%\NSIS\makensis.exe
        )
    )
)

if "%NSIS_EXE%"=="" (
    echo 错误：未找到 NSIS，请安装 NSIS
    echo 下载地址: https://nsis.sourceforge.io/Download
    exit /b 1
)

REM --- 准备安装包目录 ---
echo.
echo [2/3] 准备安装包资源...
set DIST_DIR=%~dp0..\dist
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

REM 拷贝 README
copy /Y "%~dp0..\installer\README.txt" "%~dp0..\build\bin\%CONFIG%\README.txt" >nul

REM --- 生成安装包 ---
echo.
echo [3/3] 生成安装包...
pushd "%~dp0..\installer"
"%NSIS_EXE%" installer.nsi
if errorlevel 1 (
    echo 错误：NSIS 打包失败
    popd
    exit /b 1
)
popd

echo.
echo ==========================================
echo   打包完成
echo ==========================================
echo 安装包: %DIST_DIR%\语境输入法-Setup-1.0.0.exe
echo.
echo 分发说明:
echo   - 用户双击安装包即可一键安装
echo   - 安装后需在系统设置中添加语境输入法
echo   - 使用 Win+Space 切换输入法

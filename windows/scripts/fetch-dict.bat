@echo off
REM ============================================================================
REM 语境输入法 Windows 版 - 下载 rime-ice 词库
REM
REM 从 rime-ice 仓库下载 cn_dicts/ 下的词典文件
REM 用法：scripts\fetch-dict.bat
REM ============================================================================

setlocal

set REPO_RAW=https://raw.githubusercontent.com/iDvel/rime-ice/main
set DEST_DIR=%~dp0..\resources\rime\cn_dicts

if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

set DICT_FILES=8105.dict.yaml 41448.dict.yaml base.dict.yaml ext.dict.yaml tencent.dict.yaml others.dict.yaml

echo 下载 rime-ice 词库到: %DEST_DIR%
echo ----------------------------------------

for %%f in (%DICT_FILES%) do (
    if exist "%DEST_DIR%\%%f" (
        echo [跳过] %%f 已存在
    ) else (
        echo [下载] %%f
        curl -fsSL "%REPO_RAW%/cn_dicts/%%f" -o "%DEST_DIR%\%%f"
        if errorlevel 1 (
            echo [错误] 下载 %%f 失败
            exit /b 1
        )
    )
)

echo ----------------------------------------
echo 词库下载完成

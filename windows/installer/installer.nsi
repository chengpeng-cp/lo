; ============================================================================
; 语境输入法 Windows 版 - NSIS 安装脚本
;
; 用法：
;   makensis installer.nsi
;
; 生成：dist/语境输入法-Setup-1.0.0.exe
; 用户双击即可一键安装，安装后自动注册 TSF 输入法
; ============================================================================

!define APP_NAME          "语境输入法"
!define APP_NAME_EN       "LOInputMethod"
!define APP_VERSION       "1.0.0"
!define APP_PUBLISHER     "LO"
!define APP_URL           "https://github.com/lo/inputmethod"
!define APP_REG_KEY       "Software\LOInputMethod"
!define APP_UNINST_KEY    "Software\Microsoft\Windows\CurrentVersion\Uninstall\LOInputMethod"
!define CLSID_STR         "{A8B3C7D2-1E4F-4A6B-9C5D-2E3F7A8B9C0D}"

; --- 包含 ---
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

; --- 基本配置 ---
Name "${APP_NAME}"
OutFile "..\dist\${APP_NAME}-Setup-${APP_VERSION}.exe"
Unicode True
RequestExecutionLevel admin
ShowInstDetails show
SetCompressor /SOLID lzma2

; --- 安装目录 ---
InstallDir "$PROGRAMFILES64\${APP_NAME_EN}"
InstallDirRegKey HKLM "${APP_REG_KEY}" "InstallDir"

; --- 版本信息 ---
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026"
VIAddVersionKey "FileDescription" "${APP_NAME} 安装程序"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"

; ============================================================================
; 界面设置
; ============================================================================

; 图标：如需自定义图标，请将 ICO 文件命名为 app.ico 放入本目录，
; 然后取消下面两行的注释。否则使用 NSIS 默认图标。
; !define MUI_ICON "app.ico"
; !define MUI_UNICON "app.ico"
!define MUI_ABORTWARNING
!define MUI_ABORTWARNING_TEXT "您确定要退出语境输入法安装吗？"

; 欢迎页
!define MUI_WELCOMEPAGE_TITLE "欢迎使用 ${APP_NAME} 安装向导"
!define MUI_WELCOMEPAGE_TEXT "本向导将引导您完成 ${APP_NAME} 的安装。\n\n${APP_NAME} 是一款边写边翻译的智能输入法，支持多种翻译引擎和语言。\n\n点击「下一步」继续。"

; 安装目录页
!define MUI_DIRECTORYPAGE_TEXT_TOP "选择安装目录"

; 完成页
!define MUI_FINISHPAGE_TITLE "${APP_NAME} 安装完成"
!define MUI_FINISHPAGE_TEXT "${APP_NAME} 已成功安装到您的计算机。\n\n您可以在系统设置 > 语言和时间中添加语境输入法。"
!define MUI_FINISHPAGE_RUN_TEXT "查看使用说明"
!define MUI_FINISHPAGE_RUN "$INSTDIR\README.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "立即打开系统语言设置"
!define MUI_FINISHPAGE_SHOWREADME "$WINDIR\System32\control.exe"
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED

; --- 页面 ---
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; --- 卸载页面 ---
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; --- 语言 ---
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; ============================================================================
; 安装区段
; ============================================================================

Section "Install" SecInstall
    SectionIn RO

    ; --- 检查 Windows 版本 ---
    ${IfNot} ${AtLeastWin10}
        MessageBox MB_OK|MB_ICONSTOP "语境输入法需要 Windows 10 或更高版本。"
        Abort
    ${EndIf}

    ; --- 关闭旧进程 ---
    Call KillRunningProcess

    ; --- 安装文件 ---
    SetOutPath "$INSTDIR"
    
    ; 主 DLL
    File "..\build\bin\Release\LOInputMethod.dll"
    
    ; librime 运行时依赖
    File "..\build\bin\Release\rime.dll"
    
    ; Rime 配置
    File /r "..\build\bin\Release\rime\*.*"
    
    ; README
    File "README.txt"

    ; --- 注册 COM 组件 ---
    DetailPrint "注册输入法组件..."
    ExecWait 'regsvr32 /s "$INSTDIR\LOInputMethod.dll"' $0
    ${If} $0 != 0
        DetailPrint "警告：COM 注册返回 $0"
    ${EndIf}

    ; --- 写入注册表 ---
    WriteRegStr HKLM "${APP_REG_KEY}" "InstallDir" "$INSTDIR"
    WriteRegStr HKLM "${APP_REG_KEY}" "Version" "${APP_VERSION}"
    WriteRegStr HKLM "${APP_REG_KEY}" "DLLPath" "$INSTDIR\LOInputMethod.dll"

    ; --- 卸载信息 ---
    WriteRegStr HKLM "${APP_UNINST_KEY}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "${APP_UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKLM "${APP_UNINST_KEY}" "Publisher" "${APP_PUBLISHER}"
    WriteRegStr HKLM "${APP_UNINST_KEY}" "DisplayIcon" "$INSTDIR\LOInputMethod.dll"
    WriteRegStr HKLM "${APP_UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKLM "${APP_UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegDWORD HKLM "${APP_UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${APP_UNINST_KEY}" "NoRepair" 1

    ; --- 估算安装大小 ---
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${APP_UNINST_KEY}" "EstimatedSize" "$0"

    ; --- 创建卸载程序 ---
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; --- 开始菜单快捷方式 ---
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\卸载${APP_NAME}.lnk" \
        "$INSTDIR\uninstall.exe"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\使用说明.lnk" \
        "$INSTDIR\README.txt"

    ; --- 通知 TSF 刷新 ---
    DetailPrint "通知系统刷新输入法列表..."
    ExecWait 'rundll32.exe "$INSTDIR\LOInputMethod.dll",DllRegisterServer' $0

    DetailPrint "安装完成"
SectionEnd

; ============================================================================
; 卸载区段
; ============================================================================

Section "Uninstall"
    ; --- 关闭进程 ---
    Call un.KillRunningProcess

    ; --- 注销 COM ---
    DetailPrint "注销输入法组件..."
    ExecWait 'regsvr32 /u /s "$INSTDIR\LOInputMethod.dll"' $0

    ; --- 删除文件 ---
    Delete "$INSTDIR\LOInputMethod.dll"
    Delete "$INSTDIR\rime.dll"
    Delete "$INSTDIR\uninstall.exe"
    Delete "$INSTDIR\README.txt"
    RMDir /r "$INSTDIR\rime"
    RMDir "$INSTDIR"

    ; --- 删除快捷方式 ---
    RMDir /r "$SMPROGRAMS\${APP_NAME}"

    ; --- 清理注册表 ---
    DeleteRegKey HKLM "${APP_UNINST_KEY}"
    DeleteRegKey HKLM "${APP_REG_KEY}"

    ; --- 清理 TSF 注册 ---
    DeleteRegKey HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}"

    DetailPrint "卸载完成"
SectionEnd

; ============================================================================
; 函数：关闭运行中的进程
; ============================================================================

Function KillRunningProcess
    ; 尝试关闭可能使用中的输入法进程（TSF 进程通常在 explorer/ctfmon 中）
    ExecWait 'taskkill /f /im LOInputMethod.dll' $0
FunctionEnd

Function un.KillRunningProcess
    ExecWait 'taskkill /f /im LOInputMethod.dll' $0
FunctionEnd

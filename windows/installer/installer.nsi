; ============================================================================
; 语境输入法 Windows 版 - NSIS 安装脚本
;
; 用法：
;   makensis installer.nsi
;
; 生成：dist/LOInputMethod-Setup-1.0.0.exe
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
!define PROFILE_GUID_STR  "{C1D2E3F4-5A6B-7C8D-9E0F-1A2B3C4D5E6F}"
!define LANGID_ZH_CN      "0x0804"
!define TIP_CATEGORY_GUID "{534A48CE-4107-4782-AAF4-CEA7D90254B6}"

; --- 包含 ---
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!include "FileFunc.nsh"

; --- 基本配置 ---
Name "${APP_NAME}"
OutFile "..\dist\${APP_NAME_EN}-Setup-${APP_VERSION}.exe"
Unicode True
RequestExecutionLevel admin
ShowInstDetails show
SetCompressor /SOLID lzma

; --- 安装目录（固定，不允许用户选择） ---
InstallDir "$PROGRAMFILES64\${APP_NAME_EN}"

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

!define MUI_ABORTWARNING
!define MUI_ABORTWARNING_TEXT "您确定要退出语境输入法安装吗？"

; 欢迎页
!define MUI_WELCOMEPAGE_TITLE "欢迎使用 ${APP_NAME} 安装向导"
!define MUI_WELCOMEPAGE_TEXT "本向导将引导您完成 ${APP_NAME} 的安装。\n\n${APP_NAME} 是一款边写边翻译的智能输入法，支持多种翻译引擎和语言。\n\n点击「下一步」继续。"

; 完成页
!define MUI_FINISHPAGE_TITLE "${APP_NAME} 安装完成"
!define MUI_FINISHPAGE_TEXT "${APP_NAME} 已成功安装并已设为可用输入法。\n\n按 Win+Space 即可切换到语境输入法开始使用。"
!define MUI_FINISHPAGE_RUN_TEXT "查看使用说明"
!define MUI_FINISHPAGE_RUN "$INSTDIR\README.txt"

; --- 页面（不显示目录选择页，固定安装路径） ---
!insertmacro MUI_PAGE_WELCOME
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

    ; --- 使用 64 位注册表视图（关键！32 位 NSIS 默认写 WOW6432Node） ---
    SetRegView 64

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

    ; ========================================================================
    ; 注册 COM 组件（直接写注册表，不依赖 regsvr32）
    ; ========================================================================
    DetailPrint "注册 COM 组件..."

    ; HKCR\CLSID\{CLSID}
    WriteRegStr HKCR "CLSID\${CLSID_STR}" "" "${APP_NAME}"
    ; HKCR\CLSID\{CLSID}\InprocServer32
    WriteRegStr HKCR "CLSID\${CLSID_STR}\InprocServer32" "" "$INSTDIR\LOInputMethod.dll"
    WriteRegStr HKCR "CLSID\${CLSID_STR}\InprocServer32" "ThreadingModel" "Apartment"

    ; ========================================================================
    ; 注册 TSF 文本服务（机器级，HKLM）
    ; ========================================================================
    DetailPrint "注册 TSF 文本服务..."

    ; 文本服务描述
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}" "" "${APP_NAME}"

    ; 类别注册
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\Category\${TIP_CATEGORY_GUID}" "" ""

    ; 语言配置文件
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\LanguageProfile\0x0000\${LANGID_ZH_CN}" "" "${PROFILE_GUID_STR}"
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\LanguageProfile\0x0000\${LANGID_ZH_CN}\${PROFILE_GUID_STR}" "" "${APP_NAME}"
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\LanguageProfile\0x0000\${LANGID_ZH_CN}\${PROFILE_GUID_STR}" "Description" "${APP_NAME}"
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\LanguageProfile\0x0000\${LANGID_ZH_CN}\${PROFILE_GUID_STR}" "InputMethod" "${APP_NAME}"

    ; 启用配置文件
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\Enable" "${PROFILE_GUID_STR}" ""

    ; 语言栏项目
    WriteRegStr HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}\LangBar\${PROFILE_GUID_STR}" "" "${APP_NAME}"

    ; ========================================================================
    ; 注册用户级 TSF 配置（让输入法自动出现在用户输入法列表中）
    ; CTF\Assemblies 最后一节是 CLSID（不是 Profile GUID）
    ; ========================================================================
    DetailPrint "注册用户输入法配置..."
    WriteRegStr HKCU "SOFTWARE\Microsoft\CTF\Assemblies\0x0000\${LANGID_ZH_CN}\${CLSID_STR}" "" "${APP_NAME}"
    WriteRegStr HKCU "SOFTWARE\Microsoft\CTF\Assemblies\0x0000\${LANGID_ZH_CN}\${CLSID_STR}" "CLSID" "${CLSID_STR}"
    WriteRegStr HKCU "SOFTWARE\Microsoft\CTF\Assemblies\0x0000\${LANGID_ZH_CN}\${CLSID_STR}" "Profile" "${PROFILE_GUID_STR}"
    WriteRegDWORD HKCU "SOFTWARE\Microsoft\CTF\Assemblies\0x0000\${LANGID_ZH_CN}\${CLSID_STR}" "KeyboardLayout" 0

    ; ========================================================================
    ; 也通过 regsvr32 注册（使用 64 位 regsvr32，作为补充）
    ; 32 位 NSIS 默认调 32 位 regsvr32，无法加载 64 位 DLL
    ; 用 Sysnative 绕过文件系统重定向，访问真正的 System32
    ; ========================================================================
    DetailPrint "通过 regsvr32 补充注册..."
    ExecWait '"$WINDIR\Sysnative\regsvr32.exe" /s "$INSTDIR\LOInputMethod.dll"' $0

    ; --- 写入安装信息注册表 ---
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
    SetShellVarContext all
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\卸载${APP_NAME}.lnk" \
        "$INSTDIR\uninstall.exe"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\使用说明.lnk" \
        "$INSTDIR\README.txt"

    ; --- 重启 ctfmon 刷新输入法列表 ---
    DetailPrint "刷新系统输入法列表..."
    ExecWait 'taskkill /f /im ctfmon.exe' $0
    ExecWait '"$WINDIR\System32\ctfmon.exe"' $0

    DetailPrint "安装完成"
SectionEnd

; ============================================================================
; 卸载区段
; ============================================================================

Section "Uninstall"
    ; --- 使用 64 位注册表视图 ---
    SetRegView 64

    ; --- 关闭进程 ---
    Call un.KillRunningProcess

    ; --- 通过 64 位 regsvr32 注销 ---
    DetailPrint "注销输入法组件..."
    ExecWait '"$WINDIR\Sysnative\regsvr32.exe" /u /s "$INSTDIR\LOInputMethod.dll"' $0

    ; --- 删除文件 ---
    Delete "$INSTDIR\LOInputMethod.dll"
    Delete "$INSTDIR\rime.dll"
    Delete "$INSTDIR\uninstall.exe"
    Delete "$INSTDIR\README.txt"
    RMDir /r "$INSTDIR\rime"
    RMDir "$INSTDIR"

    ; --- 删除快捷方式 ---
    SetShellVarContext all
    RMDir /r "$SMPROGRAMS\${APP_NAME}"

    ; --- 清理安装信息注册表 ---
    DeleteRegKey HKLM "${APP_UNINST_KEY}"
    DeleteRegKey HKLM "${APP_REG_KEY}"

    ; --- 清理 COM 注册 ---
    DeleteRegKey HKCR "CLSID\${CLSID_STR}"

    ; --- 清理 TSF 机器级注册 ---
    DeleteRegKey HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID_STR}"

    ; --- 清理用户级 TSF 配置 ---
    DeleteRegKey HKCU "SOFTWARE\Microsoft\CTF\Assemblies\0x0000\${LANGID_ZH_CN}\${CLSID_STR}"

    ; --- 重启 ctfmon ---
    ExecWait 'taskkill /f /im ctfmon.exe' $0
    ExecWait '"$WINDIR\System32\ctfmon.exe"' $0

    DetailPrint "卸载完成"
SectionEnd

; ============================================================================
; 函数：关闭运行中的进程
; ============================================================================

Function KillRunningProcess
    ExecWait 'taskkill /f /im LOInputMethod.dll' $0
FunctionEnd

Function un.KillRunningProcess
    ExecWait 'taskkill /f /im LOInputMethod.dll' $0
FunctionEnd

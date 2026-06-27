#pragma once

// ============================================================================
// 语境输入法 Windows 版 - Rime 引擎封装
// librime C API 的 C++ 封装，提供会话管理、按键处理、候选词获取等能力
// ============================================================================

#include <windows.h>
#include <rime_api.h>
#include <string>
#include <vector>

#include "../core/Globals.h"

// --- Windows 修饰键标志位 ---
// 调用方通过 GetKeyState 检测各修饰键状态后，按位组合传入 ConvertModifiers
#define LO_MOD_SHIFT      0x0001
#define LO_MOD_CONTROL    0x0002
#define LO_MOD_ALT        0x0004
#define LO_MOD_SUPER      0x0008
#define LO_MOD_CAPSLOCK   0x0010

class LORimeEngine {
public:
    LORimeEngine();
    ~LORimeEngine();

    // 禁止拷贝
    LORimeEngine(const LORimeEngine&) = delete;
    LORimeEngine& operator=(const LORimeEngine&) = delete;

    // --- 初始化 / 清理 ---
    // 初始化 Rime 引擎，使用 DLL 同级目录下的 rime 子目录作为共享数据目录，
    // %LOCALAPPDATA%\LOInputMethod\rime 作为用户数据目录
    bool Initialize();
    void Finalize();

    // --- 会话管理 ---
    RimeSessionId CreateSession();
    void DestroySession(RimeSessionId id);

    // --- 按键处理 ---
    // keycode 为 ConvertKeyCode 转换后的 X11 按键码
    // modifiers 为 ConvertModifiers 转换后的 Rime 修饰键掩码
    bool ProcessKey(int keycode, int modifiers, RimeSessionId session);

    // --- 输出获取 ---
    std::wstring GetCommit(RimeSessionId session);
    std::vector<LOCandidate> GetCandidates(RimeSessionId session, int count = 10);
    std::wstring GetPreedit(RimeSessionId session);
    std::wstring GetRawInput(RimeSessionId session);

    // --- 状态查询 ---
    bool IsComposing(RimeSessionId session);
    bool IsAsciiMode(RimeSessionId session);
    void SetAsciiMode(bool enabled, RimeSessionId session);

    // --- 组合控制 ---
    void ClearComposition(RimeSessionId session);
    std::wstring CommitComposition(RimeSessionId session);
    void SelectCandidateOnCurrentPage(int index, RimeSessionId session);
    void ChangePage(bool backward, RimeSessionId session);

    // --- 按键码 / 修饰键转换 ---
    // 将 Windows 虚拟键码转换为 X11 按键码（librime 使用 X11 按键码）
    static int ConvertKeyCode(WPARAM wParam, wchar_t ch);
    // 将 Windows 修饰键标志转换为 Rime 修饰键掩码
    static int ConvertModifiers(DWORD modifiers, int keycode = 0);

    // --- 路径 ---
    std::wstring GetSharedDataDir();

private:
    RimeApi* m_api;
    bool m_initialized;
    std::wstring m_sharedDataDir;
    std::wstring m_userDir;

    std::wstring GetModuleDir();
    std::wstring GetUserDataDir();
    void EnsureUserDirExists();
};

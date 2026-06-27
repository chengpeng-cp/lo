#pragma once

#include <windows.h>
#include <string>
#include <functional>
#include <memory>
#include <vector>

// ============================================================================
// 语境输入法 Windows 版 - 全局定义
// ============================================================================

// --- COM 类 ID (CLSID) ---
// {A8B3C7D2-1E4F-4A6B-9C5D-2E3F7A8B9C0D}
DEFINE_GUID(CLSID_LOTextService,
    0xa8b3c7d2, 0x1e4f, 0x4a6b, 0x9c, 0x5d, 0x2e, 0x3f, 0x7a, 0x8b, 0x9c, 0x0d);

// --- TSF 显示属性 GUID ---
// {B7C4D8E3-2F5A-4B7C-8D6E-3F4A7B9C1D0E}
DEFINE_GUID(GUID_ATTR_INPUT,
    0xb7c4d8e3, 0x2f5a, 0x4b7c, 0x8d, 0x6e, 0x3f, 0x4a, 0x7b, 0x9c, 0x1d, 0x0e);

// --- 应用信息 ---
#define LO_APP_NAME           L"语境输入法"
#define LO_APP_NAME_ASCII     "LOInputMethod"
#define LO_COMPANY_NAME       L"LO"
#define LO_VERSION            L"1.0.0"
#define LO_VERSION_NUM        1,0,0,0

// --- 注册表路径 ---
#define LO_REG_ROOT          L"SOFTWARE\\LOInputMethod"
#define LO_REG_TEXTSVC       L"SOFTWARE\\Microsoft\\CTF\\TIP\\{A8B3C7D2-1E4F-4A6B-9C5D-2E3F7A8B9C0D}"
#define LO_REG_PROFILE       L"LanguageProfile"

// --- 文件路径 ---
#define LO_DATA_DIR          L"\\LOInputMethod"

// --- DLL 全局状态 ---
extern LONG g_serverLockCount;
extern LONG g_classFactoryRefCount;
extern HINSTANCE g_hInstance;

// --- COM 注册/注销 ---
HRESULT RegisterServer();
HRESULT UnregisterServer();

// --- 调试日志 ---
void LOLog(const wchar_t* fmt, ...);
void LOLogA(const char* fmt, ...);

// --- UTF-8 / UTF-16 转换 ---
std::wstring LOUtf8ToWide(const std::string& utf8);
std::string  LOWideToUtf8(const std::wstring& wide);

// --- 候选词结构 ---
struct LOCandidate {
    std::wstring text;
    std::wstring comment;
};

// --- 翻译模式 ---
enum class LOTranslationMode {
    Fluent,    // 自然翻译
    Native,    // 母语级表达
    Literal    // 直译
};

// --- 目标语言 ---
struct LOTargetLanguage {
    std::wstring code;       // BCP 47 代码
    std::wstring displayName; // 显示名
    std::wstring englishName; // 英文名（用于 LLM 提示词）
};

// 获取所有支持的目标语言
const std::vector<LOTargetLanguage>& LOGetTargetLanguages();

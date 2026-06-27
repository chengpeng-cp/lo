#include "Globals.h"
#include <msctf.h>
#include <shlwapi.h>
#include <shlobj.h>

#pragma comment(lib, "shlwapi.lib")

// ============================================================================
// TSF 文本服务 COM 注册
// 注册 COM DLL + TSF 文本服务配置文件 + 语言配置文件
// ============================================================================

// 语言配置文件 GUID
// {C1D2E3F4-5A6B-7C8D-9E0F-1A2B3C4D5E6F}
static const GUID GUID_LZ_PROFILE = 
    { 0xc1d2e3f4, 0x5a6b, 0x7c8d, { 0x9e, 0x0f, 0x1a, 0x2b, 0x3c, 0x4d, 0x5e, 0x6f } };

// 简体中文语言标识
static const LANGID LANG_ZH_CN = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);

// --- 获取 DLL 路径 ---
static std::wstring GetDllPath() {
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(g_hInstance, path, MAX_PATH);
    return std::wstring(path);
}

// --- 写注册表字符串值 ---
static HRESULT RegSetStr(HKEY root, const wchar_t* subkey, const wchar_t* name, const wchar_t* val) {
    HKEY hKey = nullptr;
    DWORD disp = 0;
    LONG result = RegCreateKeyExW(root, subkey, 0, nullptr, 0,
        KEY_WRITE, nullptr, &hKey, &disp);
    if (result != ERROR_SUCCESS) return HRESULT_FROM_WIN32(result);
    RegSetValueExW(hKey, name, 0, REG_SZ, (const BYTE*)val,
        (DWORD)((wcslen(val) + 1) * sizeof(wchar_t)));
    RegCloseKey(hKey);
    return S_OK;
}

// --- 删除注册表键 ---
static void RegDeleteKeyRecursive(HKEY root, const wchar_t* subkey) {
    SHDeleteKeyW(root, subkey);
}

// ============================================================================
// 注册
// ============================================================================

HRESULT RegisterServer() {
    std::wstring dllPath = GetDllPath();

    // 1. 注册 COM 组件：HKCR\CLSID\{CLSID_LOTextService}
    wchar_t clsidStr[64];
    StringFromGUID2(CLSID_LOTextService, clsidStr, _countof(clsidStr));

    std::wstring clsidKey = std::wstring(L"CLSID\\") + clsidStr;
    RegSetStr(HKEY_CLASSES_ROOT, clsidKey.c_str(), nullptr, LO_APP_NAME);

    std::wstring inprocKey = clsidKey + L"\\InprocServer32";
    RegSetStr(HKEY_CLASSES_ROOT, inprocKey.c_str(), nullptr, dllPath.c_str());
    RegSetStr(HKEY_CLASSES_ROOT, inprocKey.c_str(), L"ThreadingModel", L"Apartment");

    // 2. 注册 TSF 文本服务
    // HKLM\SOFTWARE\Microsoft\CTF\TIP\{CLSID}
    std::wstring tipKey = std::wstring(L"SOFTWARE\\Microsoft\\CTF\\TIP\\") + clsidStr;

    // 文本服务描述
    RegSetStr(HKEY_LOCAL_MACHINE, tipKey.c_str(), nullptr, LO_APP_NAME);

    // 类别注册：TSF 文本服务类别
    std::wstring catKey = tipKey + L"\\Category";
    std::wstring catGuidStr = L"{534A48CE-4107-4782-AAF4-CEA7D90254B6}"; // GUID_TFCAT_TIP_KEYBOARD
    RegSetStr(HKEY_LOCAL_MACHINE, catKey.c_str(), catGuidStr.c_str(), L"");

    // 3. 语言配置文件
    // HKLM\SOFTWARE\Microsoft\CTF\TIP\{CLSID}\LanguageProfile
    std::wstring langProfileKey = tipKey + L"\\LanguageProfile";

    wchar_t langIdStr[16];
    swprintf_s(langIdStr, L"0x%04x", LANG_ZH_CN);

    std::wstring langKey = langProfileKey + L"\\0x0000\\" + langIdStr;

    wchar_t profileGuidStr[64];
    StringFromGUID2(GUID_LZ_PROFILE, profileGuidStr, _countof(profileGuidStr));

    RegSetStr(HKEY_LOCAL_MACHINE, langKey.c_str(), nullptr, profileGuidStr);

    // 配置文件详情
    std::wstring profileKey = langKey + L"\\" + profileGuidStr;
    RegSetStr(HKEY_LOCAL_MACHINE, profileKey.c_str(), nullptr, LO_APP_NAME);
    RegSetStr(HKEY_LOCAL_MACHINE, profileKey.c_str(), L"Description", LO_APP_NAME);
    RegSetStr(HKEY_LOCAL_MACHINE, profileKey.c_str(), L"InputMethod", LO_APP_NAME);

    // 启用配置文件
    std::wstring enableKey = tipKey + L"\\Enable";
    RegSetStr(HKEY_LOCAL_MACHINE, enableKey.c_str(), profileGuidStr, L"");

    // 4. 注册语言栏项目
    std::wstring langBarKey = tipKey + L"\\LangBar";
    RegSetStr(HKEY_LOCAL_MACHINE, langBarKey.c_str(), profileGuidStr, LO_APP_NAME);

    LOLog(L"RegisterServer: TSF 注册完成, CLSID=%s, Profile=%s", clsidStr, profileGuidStr);
    return S_OK;
}

// ============================================================================
// 注销
// ============================================================================

HRESULT UnregisterServer() {
    wchar_t clsidStr[64];
    StringFromGUID2(CLSID_LOTextService, clsidStr, _countof(clsidStr));

    // 删除 TSF 注册
    std::wstring tipKey = std::wstring(L"SOFTWARE\\Microsoft\\CTF\\TIP\\") + clsidStr;
    RegDeleteKeyRecursive(HKEY_LOCAL_MACHINE, tipKey.c_str());

    // 删除 COM 注册
    std::wstring clsidKey = std::wstring(L"CLSID\\") + clsidStr;
    RegDeleteKeyRecursive(HKEY_CLASSES_ROOT, clsidKey.c_str());

    LOLog(L"UnregisterServer: TSF 注销完成");
    return S_OK;
}

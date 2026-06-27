#include "Settings.h"
#include <shlobj.h>
#include <wincrypt.h>
#include <sstream>

#pragma comment(lib, "crypt32.lib")

// ============================================================================
// 注册表读写辅助
// ============================================================================

static HKEY OpenSettingsKey(bool create = false) {
    HKEY hKey = nullptr;
    DWORD disposition = 0;
    LONG result = RegCreateKeyExW(HKEY_CURRENT_USER, LO_REG_ROOT,
        0, nullptr, 0, KEY_READ | KEY_WRITE, nullptr, &hKey, &disposition);
    if (result != ERROR_SUCCESS) {
        result = RegOpenKeyExW(HKEY_CURRENT_USER, LO_REG_ROOT,
            0, KEY_READ | KEY_WRITE, &hKey);
    }
    return hKey;
}

static HKEY OpenSettingsKeyRead() {
    HKEY hKey = nullptr;
    RegOpenKeyExW(HKEY_CURRENT_USER, LO_REG_ROOT, 0, KEY_READ, &hKey);
    return hKey;
}

static std::wstring RegGetString(HKEY hKey, const wchar_t* name, const std::wstring& defVal = L"") {
    wchar_t buf[1024];
    DWORD size = sizeof(buf);
    DWORD type = 0;
    if (RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)buf, &size) == ERROR_SUCCESS && type == REG_SZ) {
        return std::wstring(buf, size / sizeof(wchar_t) - (buf[size / sizeof(wchar_t) - 1] == 0 ? 1 : 0));
    }
    return defVal;
}

static double RegGetDouble(HKEY hKey, const wchar_t* name, double defVal) {
    DWORD val;
    DWORD size = sizeof(val);
    DWORD type = 0;
    // 先尝试用字符串存储的 double
    wchar_t buf[64];
    DWORD strSize = sizeof(buf);
    if (RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)buf, &strSize) == ERROR_SUCCESS && type == REG_SZ) {
        try { return std::stod(buf); } catch (...) {}
    }
    // 回退 DWORD（旧格式）
    if (RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)&val, &size) == ERROR_SUCCESS && type == REG_DWORD) {
        return (double)val;
    }
    return defVal;
}

static bool RegGetBool(HKEY hKey, const wchar_t* name, bool defVal) {
    DWORD val;
    DWORD size = sizeof(val);
    DWORD type = 0;
    if (RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)&val, &size) == ERROR_SUCCESS && type == REG_DWORD) {
        return val != 0;
    }
    return defVal;
}

static int RegGetInt(HKEY hKey, const wchar_t* name, int defVal) {
    DWORD val;
    DWORD size = sizeof(val);
    DWORD type = 0;
    if (RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)&val, &size) == ERROR_SUCCESS && type == REG_DWORD) {
        return (int)val;
    }
    return defVal;
}

static void RegSetString(HKEY hKey, const wchar_t* name, const std::wstring& val) {
    RegSetValueExW(hKey, name, 0, REG_SZ, (const BYTE*)val.c_str(), (DWORD)((val.size() + 1) * sizeof(wchar_t)));
}

static void RegSetDouble(HKEY hKey, const wchar_t* name, double val) {
    wchar_t buf[64];
    swprintf_s(buf, L"%.6f", val);
    RegSetValueExW(hKey, name, 0, REG_SZ, (const BYTE*)buf, (DWORD)((wcslen(buf) + 1) * sizeof(wchar_t)));
}

static void RegSetBool(HKEY hKey, const wchar_t* name, bool val) {
    DWORD d = val ? 1 : 0;
    RegSetValueExW(hKey, name, 0, REG_DWORD, (const BYTE*)&d, sizeof(d));
}

// ============================================================================
// DPAPI 加密辅助
// ============================================================================

static std::wstring GetKeyStoragePath() {
    wchar_t path[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, path))) {
        std::wstring dir = std::wstring(path) + L"\\LOInputMethod";
        CreateDirectoryW(dir.c_str(), nullptr);
        return dir + L"\\apikeys.dat";
    }
    return L"apikeys.dat";
}

static std::wstring EncryptString(const std::wstring& plaintext) {
    if (plaintext.empty()) return L"";

    DATA_BLOB input;
    input.pbData = (BYTE*)plaintext.c_str();
    input.cbData = (DWORD)(plaintext.size() * sizeof(wchar_t));

    DATA_BLOB output;
    if (!CryptProtectData(&input, L"LOInputMethod API Key", nullptr, nullptr, nullptr,
        CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        return L"";
    }

    // Base64 编码
    static const wchar_t base64[] = L"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::wstring result;
    result.reserve((output.cbData + 2) / 3 * 4);
    for (DWORD i = 0; i < output.cbData; i += 3) {
        DWORD b0 = output.pbData[i];
        DWORD b1 = (i + 1 < output.cbData) ? output.pbData[i + 1] : 0;
        DWORD b2 = (i + 2 < output.cbData) ? output.pbData[i + 2] : 0;
        result += base64[b0 >> 2];
        result += base64[((b0 & 3) << 4) | (b1 >> 4)];
        result += (i + 1 < output.cbData) ? base64[((b1 & 15) << 2) | (b2 >> 6)] : L'=';
        result += (i + 2 < output.cbData) ? base64[b2 & 63] : L'=';
    }
    LocalFree(output.pbData);
    return result;
}

static std::wstring DecryptString(const std::wstring& ciphertext) {
    if (ciphertext.empty()) return L"";

    // Base64 解码
    static const int8_t decTable[128] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
        52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
        15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1
    };

    std::vector<BYTE> data;
    data.reserve(ciphertext.size() * 3 / 4);
    int val = 0, bits = 0;
    for (wchar_t ch : ciphertext) {
        if (ch >= 128) continue;
        if (ch == L'=') break;
        int d = decTable[ch];
        if (d < 0) continue;
        val = (val << 6) | d;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            data.push_back((BYTE)((val >> bits) & 0xFF));
        }
    }

    DATA_BLOB input;
    input.pbData = data.data();
    input.cbData = (DWORD)data.size();

    DATA_BLOB output;
    if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
        CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        return L"";
    }

    std::wstring result((const wchar_t*)output.pbData, output.cbData / sizeof(wchar_t));
    LocalFree(output.pbData);
    return result;
}

// 从加密文件中读取所有 API 密钥
#include <fstream>
#include <map>

static std::map<std::wstring, std::wstring> LoadAllKeys() {
    std::map<std::wstring, std::wstring> keys;
    std::ifstream file(GetKeyStoragePath(), std::ios::binary);
    if (!file.is_open()) return keys;

    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    file.close();

    // 简单格式：provider\tciphertext\n
    std::string provider, cipher;
    bool inProvider = true;
    for (char c : content) {
        if (c == '\t') { inProvider = false; }
        else if (c == '\n') {
            if (!provider.empty() && !cipher.empty()) {
                keys[LOUtf8ToWide(provider)] = DecryptString(LOUtf8ToWide(cipher));
            }
            provider.clear(); cipher.clear(); inProvider = true;
        } else {
            if (inProvider) provider += c; else cipher += c;
        }
    }
    return keys;
}

static void SaveAllKeys(const std::map<std::wstring, std::wstring>& keys) {
    std::ofstream file(GetKeyStoragePath(), std::ios::binary | std::ios::trunc);
    if (!file.is_open()) return;
    for (auto& [provider, key] : keys) {
        file << LOWideToUtf8(provider) << '\t' << LOWideToUtf8(EncryptString(key)) << '\n';
    }
    file.close();
}

// ============================================================================
// LOSettings 实现
// ============================================================================

LOSettings LOSettings::Load() {
    LOSettings s;
    HKEY hKey = OpenSettingsKeyRead();
    if (!hKey) return s;

    // 翻译
    s.translationEnabled = RegGetBool(hKey, L"translationEnabled", true);
    s.translationProvider = RegGetString(hKey, L"translationProvider", L"bing");
    s.translationModel = LoadModel(s.translationProvider);
    s.customLLMBaseURL = RegGetString(hKey, L"customLLMBaseURL", L"");
    s.translationMode = RegGetString(hKey, L"translationMode", L"fluent");
    s.targetLanguage = RegGetString(hKey, L"targetLanguage", L"en");

    // 悬浮窗
    s.overlayPositionMode = RegGetString(hKey, L"overlayPositionMode", L"draggable");
    s.overlayPosition.x = RegGetInt(hKey, L"overlayPositionX", 0);
    s.overlayPosition.y = RegGetInt(hKey, L"overlayPositionY", 0);
    s.autoDismissInterval = RegGetDouble(hKey, L"autoDismissInterval", 5.0);
    s.overlayOpacity = RegGetDouble(hKey, L"overlayOpacity", 0.85);
    s.overlayBackgroundColor = RegGetString(hKey, L"overlayBackgroundColor", L"1E1E1E");
    s.overlayOriginalTextColor = RegGetString(hKey, L"overlayOriginalTextColor", L"999999");
    s.overlayTranslationTextColor = RegGetString(hKey, L"overlayTranslationTextColor", L"FFFFFF");
    s.overlayTheme = RegGetString(hKey, L"overlayTheme", L"dark");
    s.overlayClickThrough = RegGetBool(hKey, L"overlayClickThrough", false);
    s.overlayMaxWidth = RegGetDouble(hKey, L"overlayMaxWidth", 360);
    s.overlayMaxHeight = RegGetDouble(hKey, L"overlayMaxHeight", 200);
    s.overlayOriginalFontSize = RegGetDouble(hKey, L"overlayOriginalFontSize", 14);
    s.overlayTranslationFontSize = RegGetDouble(hKey, L"overlayTranslationFontSize", 14);
    s.overlayShowOriginalLabel = RegGetBool(hKey, L"overlayShowOriginalLabel", true);
    s.overlayShowTranslationLabel = RegGetBool(hKey, L"overlayShowTranslationLabel", true);

    // 翻译调度
    s.segmentPauseThreshold = RegGetDouble(hKey, L"segmentPauseThreshold", 5.0);
    s.translationDebounceInterval = RegGetDouble(hKey, L"translationDebounceInterval", 0.5);

    // 输入
    s.defaultInputMode = RegGetString(hKey, L"defaultInputMode", L"chinese");

    RegCloseKey(hKey);
    return s;
}

void LOSettings::Save() const {
    HKEY hKey = OpenSettingsKey(true);
    if (!hKey) return;

    RegSetBool(hKey, L"translationEnabled", translationEnabled);
    RegSetString(hKey, L"translationProvider", translationProvider);
    RegSetString(hKey, L"customLLMBaseURL", customLLMBaseURL);
    RegSetString(hKey, L"translationMode", translationMode);
    RegSetString(hKey, L"targetLanguage", targetLanguage);
    RegSetString(hKey, L"overlayPositionMode", overlayPositionMode);

    RegSetDouble(hKey, L"overlayPositionX", (double)overlayPosition.x);
    RegSetDouble(hKey, L"overlayPositionY", (double)overlayPosition.y);
    RegSetDouble(hKey, L"autoDismissInterval", autoDismissInterval);
    RegSetDouble(hKey, L"overlayOpacity", overlayOpacity);
    RegSetString(hKey, L"overlayBackgroundColor", overlayBackgroundColor);
    RegSetString(hKey, L"overlayOriginalTextColor", overlayOriginalTextColor);
    RegSetString(hKey, L"overlayTranslationTextColor", overlayTranslationTextColor);
    RegSetString(hKey, L"overlayTheme", overlayTheme);
    RegSetBool(hKey, L"overlayClickThrough", overlayClickThrough);
    RegSetDouble(hKey, L"overlayMaxWidth", overlayMaxWidth);
    RegSetDouble(hKey, L"overlayMaxHeight", overlayMaxHeight);
    RegSetDouble(hKey, L"overlayOriginalFontSize", overlayOriginalFontSize);
    RegSetDouble(hKey, L"overlayTranslationFontSize", overlayTranslationFontSize);
    RegSetBool(hKey, L"overlayShowOriginalLabel", overlayShowOriginalLabel);
    RegSetBool(hKey, L"overlayShowTranslationLabel", overlayShowTranslationLabel);
    RegSetDouble(hKey, L"segmentPauseThreshold", segmentPauseThreshold);
    RegSetDouble(hKey, L"translationDebounceInterval", translationDebounceInterval);
    RegSetString(hKey, L"defaultInputMode", defaultInputMode);

    // 保存当前提供商模型名
    {
        std::wstring key = L"translationModel_" + translationProvider;
        RegSetString(hKey, key.c_str(), translationModel);
    }

    RegCloseKey(hKey);
}

std::wstring LOSettings::LoadModel(const std::wstring& provider) {
    HKEY hKey = OpenSettingsKeyRead();
    if (!hKey) return L"";
    std::wstring key = L"translationModel_" + provider;
    std::wstring model = RegGetString(hKey, key.c_str(), L"");
    RegCloseKey(hKey);
    return model;
}

std::wstring LOSettings::GetAPIKey(const std::wstring& provider) const {
    auto keys = LoadAllKeys();
    auto it = keys.find(provider);
    return it != keys.end() ? it->second : L"";
}

void LOSettings::SetAPIKey(const std::wstring& provider, const std::wstring& key) const {
    auto keys = LoadAllKeys();
    if (key.empty()) {
        keys.erase(provider);
    } else {
        keys[provider] = key;
    }
    SaveAllKeys(keys);
}

void LOSettings::DeleteAPIKey(const std::wstring& provider) const {
    auto keys = LoadAllKeys();
    keys.erase(provider);
    SaveAllKeys(keys);
}

LOSettings::ThemeColors LOSettings::DarkThemeColors() {
    return { L"1E1E1E", L"999999", L"FFFFFF" };
}

LOSettings::ThemeColors LOSettings::LightThemeColors() {
    return { L"FFFFFF", L"666666", L"1A1A1A" };
}

LOSettings::ThemeColors LOSettings::ThemeColorsFor(const std::wstring& theme) {
    if (theme == L"light") return LightThemeColors();
    if (theme == L"auto") {
        // 判断系统暗色模式
        HKEY hKey;
        DWORD darkMode = 1;
        DWORD size = sizeof(darkMode);
        if (RegOpenKeyExW(HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
            0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            RegQueryValueExW(hKey, L"AppsUseLightTheme", nullptr, nullptr, (LPBYTE)&darkMode, &size);
            RegCloseKey(hKey);
        }
        return darkMode == 0 ? DarkThemeColors() : LightThemeColors();
    }
    return DarkThemeColors();
}

// 全局单例
static LOSettings g_settings;
LOSettings& LOSettingsGet() {
    static bool loaded = false;
    if (!loaded) {
        g_settings = LOSettings::Load();
        loaded = true;
    }
    return g_settings;
}

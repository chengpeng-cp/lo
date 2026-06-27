#include "Globals.h"
#include <cstdio>
#include <cstdarg>
#include <shlobj.h>

static std::wstring GetLogDir() {
    wchar_t path[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, path))) {
        return std::wstring(path) + L"\\LOInputMethod";
    }
    return L"C:\\LOInputMethod";
}

static std::wstring GetLogPath() {
    return GetLogDir() + L"\\translation.log";
}

static void WriteLog(const std::wstring& msg) {
    std::wstring dir = GetLogDir();
    CreateDirectoryW(dir.c_str(), nullptr);

    HANDLE hFile = CreateFileW(GetLogPath().c_str(),
        FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFile == INVALID_HANDLE_VALUE) return;

    SYSTEMTIME st;
    GetLocalTime(&st);
    wchar_t ts[64];
    swprintf_s(ts, L"[%04d-%02d-%02dT%02d:%02d:%02d.%03d] ",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);

    std::wstring line = ts + msg + L"\n";

    DWORD written;
    SetFilePointer(hFile, 0, nullptr, FILE_END);
    WriteFile(hFile, line.c_str(), (DWORD)(line.size() * sizeof(wchar_t)), &written, nullptr);
    CloseHandle(hFile);
}

void LOLog(const wchar_t* fmt, ...) {
    wchar_t buf[2048];
    va_list args;
    va_start(args, fmt);
    vswprintf_s(buf, fmt, args);
    va_end(args);
    WriteLog(buf);
}

void LOLogA(const char* fmt, ...) {
    char buf[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf_s(buf, _countof(buf), _TRUNCATE, fmt, args);
    va_end(args);
    WriteLog(LOUtf8ToWide(buf));
}

// --- UTF-8 / UTF-16 转换 ---

std::wstring LOUtf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return L"";
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    if (len <= 0) return L"";
    std::wstring wide(len - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], len);
    return wide;
}

std::string LOWideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return "";
    int len = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) return "";
    std::string utf8(len - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &utf8[0], len, nullptr, nullptr);
    return utf8;
}

// --- 目标语言列表 ---

const std::vector<LOTargetLanguage>& LOGetTargetLanguages() {
    static const std::vector<LOTargetLanguage> languages = {
        {L"en",      L"English（英语）",                 L"English"},
        {L"en-GB",   L"English (UK)（英语·英国）",        L"British English"},
        {L"zh-Hans", L"简体中文",                        L"Simplified Chinese"},
        {L"zh-Hant", L"繁體中文",                        L"Traditional Chinese"},
        {L"ja",      L"日本語（日语）",                   L"Japanese"},
        {L"ko",      L"한국어（韩语）",                   L"Korean"},
        {L"fr",      L"Français（法语）",                 L"French"},
        {L"de",      L"Deutsch（德语）",                 L"German"},
        {L"es",      L"Español（西班牙语）",              L"Spanish"},
        {L"it",      L"Italiano（意大利语）",             L"Italian"},
        {L"pt",      L"Português（葡萄牙语）",            L"Portuguese"},
        {L"pt-BR",   L"Português (BR)（葡萄牙语·巴西）",  L"Brazilian Portuguese"},
        {L"ru",      L"Русский（俄语）",                  L"Russian"},
        {L"ar",      L"العربية（阿拉伯语）",              L"Arabic"},
        {L"hi",      L"हिन्दी（印地语）",                  L"Hindi"},
        {L"th",      L"ภาษาไทย（泰语）",                  L"Thai"},
        {L"vi",      L"Tiếng Việt（越南语）",             L"Vietnamese"},
        {L"id",      L"Bahasa Indonesia（印尼语）",       L"Indonesian"},
        {L"nl",      L"Nederlands（荷兰语）",             L"Dutch"},
        {L"pl",      L"Polski（波兰语）",                 L"Polish"},
        {L"tr",      L"Türkçe（土耳其语）",               L"Turkish"},
        {L"sv",      L"Svenska（瑞典语）",                L"Swedish"},
        {L"uk",      L"Українська（乌克兰语）",           L"Ukrainian"},
    };
    return languages;
}

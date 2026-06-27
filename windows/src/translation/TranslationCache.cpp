#include "TranslationCache.h"
#include "TranslationService.h"
#include "../core/Globals.h"
#include <shlobj.h>
#include <fstream>
#include <sstream>
#include <cwctype>

// ============================================================================
// 构造 / 析构
// ============================================================================

LOTranslationCache& LOTranslationCache::Shared() {
    static LOTranslationCache instance;
    return instance;
}

LOTranslationCache::LOTranslationCache() {
    InitializeCriticalSection(&m_cs);
    Load();
}

LOTranslationCache::~LOTranslationCache() {
    Save();
    DeleteCriticalSection(&m_cs);
}

// ============================================================================
// 缓存文件路径
// ============================================================================

static std::wstring GetCacheFilePath() {
    wchar_t path[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, path))) {
        std::wstring dir = std::wstring(path) + L"\\LOInputMethod";
        CreateDirectoryW(dir.c_str(), nullptr);
        return dir + L"\\translation_cache.json";
    }
    return L"translation_cache.json";
}

// ============================================================================
// 键生成：targetLang::lowercased_trimmed_text
// ============================================================================

static std::wstring TrimAndLower(const std::wstring& s) {
    size_t start = 0, end = s.size();
    while (start < end && iswspace(s[start])) ++start;
    while (end > start && iswspace(s[end - 1])) --end;
    std::wstring out;
    out.reserve(end - start);
    for (size_t i = start; i < end; ++i) {
        out += (wchar_t)towlower(s[i]);
    }
    return out;
}

std::wstring LOTranslationCache::MakeKey(const std::wstring& text, const std::wstring& targetLang) {
    std::wstring key = targetLang + L"::" + TrimAndLower(text);
    return key;
}

// ============================================================================
// 查询
// ============================================================================

std::wstring LOTranslationCache::Get(const std::wstring& text, const std::wstring& targetLang) {
    std::wstring key = MakeKey(text, targetLang);
    EnterCriticalSection(&m_cs);
    auto it = m_map.find(key);
    if (it == m_map.end()) {
        LeaveCriticalSection(&m_cs);
        return L"";
    }
    // 移到链表头部（最近使用）
    m_lru.splice(m_lru.begin(), m_lru, it->second);
    std::wstring result = it->second->translation;
    LeaveCriticalSection(&m_cs);
    return result;
}

// ============================================================================
// 写入
// ============================================================================

void LOTranslationCache::Set(const std::wstring& text, const std::wstring& translation,
                              const std::wstring& targetLang) {
    if (translation.empty()) return;
    std::wstring key = MakeKey(text, targetLang);

    EnterCriticalSection(&m_cs);
    auto it = m_map.find(key);
    if (it != m_map.end()) {
        // 已存在，更新并移到头部
        it->second->translation = translation;
        m_lru.splice(m_lru.begin(), m_lru, it->second);
        LeaveCriticalSection(&m_cs);
        return;
    }
    // 新条目
    m_lru.push_front({key, translation});
    m_map[key] = m_lru.begin();

    // 超出容量，淘汰尾部（最久未使用）
    if (m_lru.size() > kMaxEntries) {
        auto last = std::prev(m_lru.end());
        m_map.erase(last->key);
        m_lru.pop_back();
    }
    LeaveCriticalSection(&m_cs);

    Save();
}

// ============================================================================
// 清空
// ============================================================================

void LOTranslationCache::Clear() {
    EnterCriticalSection(&m_cs);
    m_lru.clear();
    m_map.clear();
    LeaveCriticalSection(&m_cs);

    // 删除磁盘文件
    std::wstring path = GetCacheFilePath();
    DeleteFileW(path.c_str());
}

// ============================================================================
// 持久化
// ============================================================================

void LOTranslationCache::Load() {
    std::wstring path = GetCacheFilePath();
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) return;

    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    file.close();
    if (content.empty()) return;

    // 解析 JSON 数组 [{"k":"...","v":"..."}, ...]
    LOJsonValue root;
    if (!LOParseJson(content, root) || root.type != LOJsonValue::Array) {
        LOLog(L"[Cache] 缓存文件解析失败\r\n");
        return;
    }

    EnterCriticalSection(&m_cs);
    for (const auto& item : root.arrVal) {
        const LOJsonValue* k = item.Find(L"k");
        const LOJsonValue* v = item.Find(L"v");
        if (!k || !v || k->type != LOJsonValue::String || v->type != LOJsonValue::String) continue;
        if (m_map.find(k->strVal) != m_map.end()) continue;
        m_lru.push_back({k->strVal, v->strVal});
        m_map[k->strVal] = std::prev(m_lru.end());
        if (m_lru.size() > kMaxEntries) {
            auto last = std::prev(m_lru.end());
            m_map.erase(last->key);
            m_lru.pop_back();
        }
    }
    LeaveCriticalSection(&m_cs);
    LOLog(L"[Cache] 已加载 %zu 条缓存\r\n", m_lru.size());
}

void LOTranslationCache::Save() {
    std::wstring path = GetCacheFilePath();

    // 手工构造 JSON 数组
    std::wstring json = L"[";

    EnterCriticalSection(&m_cs);
    bool first = true;
    // 从最新到最旧写入
    for (auto it = m_lru.begin(); it != m_lru.end(); ++it) {
        if (!first) json += L",";
        first = false;
        json += L"{\"k\":\"" + LOEscapeJsonString(it->key) + L"\",\"v\":\"" +
                LOEscapeJsonString(it->translation) + L"\"}";
    }
    LeaveCriticalSection(&m_cs);

    json += L"]";

    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file.is_open()) {
        LOLog(L"[Cache] 无法写入缓存文件: %s\r\n", path.c_str());
        return;
    }
    std::string utf8 = LOWideToUtf8(json);
    file.write(utf8.data(), (std::streamsize)utf8.size());
    file.close();
}

#pragma once

#include <windows.h>
#include <string>
#include <list>
#include <unordered_map>

// ============================================================================
// 翻译结果 LRU 缓存
//   - 最大 1000 条，超出按 LRU 淘汰
//   - 线程安全（CRITICAL_SECTION）
//   - 持久化到 %LOCALAPPDATA%\LOInputMethod\translation_cache.json
//   - 键格式：targetLang::lowercased_trimmed_text
// ============================================================================

class LOTranslationCache {
public:
    static LOTranslationCache& Shared();

    // 查询缓存，未命中返回空字符串
    std::wstring Get(const std::wstring& text, const std::wstring& targetLang);
    // 写入缓存
    void Set(const std::wstring& text, const std::wstring& translation, const std::wstring& targetLang);
    // 清空内存与磁盘缓存
    void Clear();

private:
    LOTranslationCache();
    ~LOTranslationCache();
    LOTranslationCache(const LOTranslationCache&) = delete;
    LOTranslationCache& operator=(const LOTranslationCache&) = delete;

    // 生成键
    static std::wstring MakeKey(const std::wstring& text, const std::wstring& targetLang);
    // 持久化加载/保存
    void Load();
    void Save();

    CRITICAL_SECTION m_cs;

    struct Entry {
        std::wstring key;
        std::wstring translation;
    };
    // 链表头为最近使用，尾部为最久未使用
    std::list<Entry> m_lru;
    std::unordered_map<std::wstring, std::list<Entry>::iterator> m_map;

    static const size_t kMaxEntries = 1000;
};

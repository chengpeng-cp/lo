#pragma once

#include "../core/Globals.h"
#include <string>
#include <vector>
#include <functional>
#include <utility>

// ============================================================================
// 翻译服务接口与共享定义
// ============================================================================

// --- 翻译错误（中文消息）---
class LOTranslationError {
public:
    LOTranslationError() = default;
    explicit LOTranslationError(const std::wstring& msg) : m_message(msg) {}
    const std::wstring& Message() const { return m_message; }
    bool IsError() const { return !m_message.empty(); }
private:
    std::wstring m_message;
};

// --- 提供商配置 ---
struct LOProviderConfig {
    std::wstring id;           // 内部 ID（如 L"bing" L"deepseek"）
    std::wstring displayName;  // 显示名
    std::wstring baseURL;      // API 基础 URL（仅 LLM 用）
    bool isFree = false;       // 是否免费
    bool requiresAPIKey = false;
};

// 获取所有内置提供商配置
const std::vector<LOProviderConfig>& LOGetProviderConfigs();
// 按 ID 查找提供商配置，未找到返回 nullptr
const LOProviderConfig* LOFindProviderConfig(const std::wstring& id);

// --- 翻译服务抽象接口 ---
class LOTranslationService {
public:
    virtual ~LOTranslationService() {}
    // 同步翻译
    virtual std::wstring Translate(const std::wstring& text,
                                   LOTranslationMode mode,
                                   const std::wstring& targetLang) = 0;
    // 流式翻译，onDelta 携带累计增量内容
    virtual std::wstring TranslateStream(const std::wstring& text,
                                         LOTranslationMode mode,
                                         const std::wstring& targetLang,
                                         std::function<void(const std::wstring&)> onDelta) = 0;
    virtual bool IsFree() = 0;
    virtual bool SupportsStream() = 0;
};

// ============================================================================
// 最小 JSON 解析器（仅用于解析已知结构）
// ============================================================================

struct LOJsonValue {
    enum ValueType { kNull, kBool, kNumber, kString, kArray, kObject };
    ValueType valueType = kNull;

    bool boolVal = false;
    double numVal = 0.0;
    std::wstring strVal;
    std::vector<LOJsonValue> arrVal;
    std::vector<std::pair<std::wstring, LOJsonValue>> objVal;

    // 在 Object 中按 key 查找，未找到返回 nullptr
    const LOJsonValue* Find(const std::wstring& key) const;
    // 在 Array 中按下标取值，越界返回 nullptr
    const LOJsonValue* At(size_t i) const;
    // 便捷取字符串
    std::wstring AsString() const { return valueType == kString ? strVal : L""; }
};

// 解析 JSON 文本（UTF-8 输入），失败返回 false
bool LOParseJson(const std::string& utf8, LOJsonValue& out);

// JSON 字符串转义（用于构造请求体）
std::wstring LOEscapeJsonString(const std::wstring& s);

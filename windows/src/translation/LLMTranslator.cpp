#include "LLMTranslator.h"
#include "NetworkClient.h"
#include "../core/Globals.h"
#include "../settings/Settings.h"

// ============================================================================
// 构造 / 析构
// ============================================================================

LOLLMTranslator::LOLLMTranslator(const std::wstring& provider, const std::wstring& model)
    : m_provider(provider), m_model(model) {
    // 确定 baseURL
    const LOProviderConfig* cfg = LOFindProviderConfig(provider);
    if (cfg) {
        m_baseURL = cfg->baseURL;
    }
    if (provider == L"custom") {
        m_baseURL = LOSettingsGet().customLLMBaseURL;
    }
    // 读取 API 密钥
    m_apiKey = LOSettingsGet().GetAPIKey(provider);
}

LOLLMTranslator::~LOLLMTranslator() {}

bool LOLLMTranslator::IsConfigured() const {
    return !m_apiKey.empty() && !m_model.empty() && !m_baseURL.empty();
}

// ============================================================================
// 系统提示词
// ============================================================================

// 根据语言代码查找英文名
static std::wstring LookupEnglishName(const std::wstring& code) {
    for (const auto& lang : LOGetTargetLanguages()) {
        if (lang.code == code) return lang.englishName;
    }
    // 默认：直接用代码
    return code.empty() ? L"English" : code;
}

std::wstring LOLLMTranslator::BuildSystemPrompt(LOTranslationMode mode, const std::wstring& targetLang) {
    std::wstring langName = LookupEnglishName(targetLang);

    std::wstring style;
    switch (mode) {
        case LOTranslationMode::Native:
            style = L"使用母语级、地道自然的表达，符合目标语言的文化与表达习惯，避免翻译腔";
            break;
        case LOTranslationMode::Literal:
            style = L"尽量直译，保持原文的字面意义与句式结构";
            break;
        case LOTranslationMode::Fluent:
        default:
            style = L"译文通顺自然，符合目标语言的表达习惯";
            break;
    }

    return L"你是一个专业翻译引擎。请将用户输入翻译成" + langName +
           L"。" + style +
           L"。只输出译文，不要输出解释、注释或原文，不要输出任何额外内容。";
}

// ============================================================================
// 构造请求体
// ============================================================================

std::string LOLLMTranslator::BuildRequestBody(const std::wstring& text,
                                               LOTranslationMode mode,
                                               const std::wstring& targetLang,
                                               bool stream) {
    std::wstring systemPrompt = BuildSystemPrompt(mode, targetLang);

    // 手工构造 JSON（避免依赖外部库）
    std::wstring body;
    body.reserve(256 + text.size() * 2);
    body += L"{";
    body += L"\"model\":\"" + LOEscapeJsonString(m_model) + L"\",";
    body += L"\"messages\":[";
    body += L"{\"role\":\"system\",\"content\":\"" + LOEscapeJsonString(systemPrompt) + L"\"},";
    body += L"{\"role\":\"user\",\"content\":\"" + LOEscapeJsonString(text) + L"\"}";
    body += L"],";
    body += L"\"temperature\":0.3,";
    body += L"\"max_tokens\":4096,";
    // stream 字段需为小写布尔
    body += L"\"stream\":";
    body += stream ? L"true" : L"false";
    body += L"}";

    return LOWideToUtf8(body);
}

// ============================================================================
// 解析非流式响应
// ============================================================================

std::wstring LOLLMTranslator::ParseResponse(const std::string& resp) {
    LOJsonValue root;
    if (!LOParseJson(resp, root)) {
        LOLog(L"[LLM] 响应 JSON 解析失败: %s\r\n", LOUtf8ToWide(resp).c_str());
        return L"";
    }
    const LOJsonValue* choices = root.Find(L"choices");
    if (!choices || choices->valueType != LOJsonValue::kArray) {
        // 检查错误信息
        const LOJsonValue* err = root.Find(L"error");
        if (err) {
            const LOJsonValue* msg = err->Find(L"message");
            if (msg) {
                LOLog(L"[LLM] API 错误: %s\r\n", msg->strVal.c_str());
                return L"[翻译失败：" + msg->strVal + L"]";
            }
        }
        return L"";
    }
    const LOJsonValue* first = choices->At(0);
    if (!first) return L"";
    const LOJsonValue* message = first->Find(L"message");
    if (!message) return L"";
    const LOJsonValue* content = message->Find(L"content");
    if (!content || content->valueType != LOJsonValue::kString) return L"";
    return content->strVal;
}

// ============================================================================
// 翻译（非流式）
// ============================================================================

std::wstring LOLLMTranslator::Translate(const std::wstring& text,
                                         LOTranslationMode mode,
                                         const std::wstring& targetLang) {
    if (text.empty()) return L"";
    if (!IsConfigured()) {
        return L"[翻译失败：未配置 API 密钥或模型]";
    }

    std::string body = BuildRequestBody(text, mode, targetLang, false);

    std::vector<std::pair<std::string, std::string>> headers;
    headers.emplace_back("Content-Type", "application/json; charset=UTF-8");
    headers.emplace_back("Authorization", "Bearer " + LOWideToUtf8(m_apiKey));

    std::string resp;
    if (!LONetworkClient::Shared().Request(m_baseURL, body, headers, true, resp)) {
        LOLog(L"[LLM] 翻译请求失败，provider=%s\r\n", m_provider.c_str());
        return L"[翻译失败：网络错误]";
    }

    std::wstring result = ParseResponse(resp);
    if (result.empty()) {
        return L"[翻译失败：响应解析错误]";
    }
    return result;
}

// ============================================================================
// 翻译（流式）
// ============================================================================

std::wstring LOLLMTranslator::TranslateStream(const std::wstring& text,
                                                LOTranslationMode mode,
                                                const std::wstring& targetLang,
                                                std::function<void(const std::wstring&)> onDelta) {
    if (text.empty()) return L"";
    if (!IsConfigured()) {
        if (onDelta) onDelta(L"[翻译失败：未配置 API 密钥或模型]");
        return L"[翻译失败：未配置 API 密钥或模型]";
    }

    std::string body = BuildRequestBody(text, mode, targetLang, true);

    std::vector<std::pair<std::string, std::string>> headers;
    headers.emplace_back("Content-Type", "application/json; charset=UTF-8");
    headers.emplace_back("Authorization", "Bearer " + LOWideToUtf8(m_apiKey));
    headers.emplace_back("Accept", "text/event-stream");

    std::wstring accumulated;

    bool ok = LONetworkClient::Shared().RequestStream(m_baseURL, body, headers,
        [&](const std::string& line) -> bool {
            // 检测 [DONE]
            if (line == "[DONE]") return false; // 结束

            // 解析 JSON
            LOJsonValue chunk;
            if (!LOParseJson(line, chunk)) return true; // 跳过无法解析的行
            const LOJsonValue* choices = chunk.Find(L"choices");
            if (!choices || choices->valueType != LOJsonValue::kArray) return true;
            const LOJsonValue* first = choices->At(0);
            if (!first) return true;
            const LOJsonValue* delta = first->Find(L"delta");
            if (!delta) return true;
            const LOJsonValue* content = delta->Find(L"content");
            if (!content || content->valueType != LOJsonValue::kString) return true;

            accumulated += content->strVal;
            if (onDelta) onDelta(accumulated);
            return true;
        });

    if (!ok && accumulated.empty()) {
        LOLog(L"[LLM] 流式翻译请求失败，provider=%s\r\n", m_provider.c_str());
        return L"[翻译失败：网络错误]";
    }

    return accumulated;
}

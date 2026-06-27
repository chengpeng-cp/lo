#include "BingTranslator.h"
#include "NetworkClient.h"
#include "../core/Globals.h"

// token 缓存时长 9 分钟（Edge 接口 token 通常 10 分钟有效）
static const ULONGLONG kTokenCacheMs = 9ull * 60 * 1000;

// ============================================================================
// 构造 / 析构
// ============================================================================

LOBingTranslator::LOBingTranslator() {}
LOBingTranslator::~LOBingTranslator() {}

// ============================================================================
// 获取 token
// ============================================================================

std::wstring LOBingTranslator::GetToken() {
    ULONGLONG now = GetTickCount64();
    if (!m_token.empty() && (now - m_tokenTimeMs) < kTokenCacheMs) {
        return m_token;  // 缓存有效
    }

    std::string resp;
    if (!LONetworkClient::Shared().Request(
            L"https://edge.microsoft.com/translate/auth", "",
            {}, false, resp)) {
        LOLog(L"[Bing] 获取 token 失败\r\n");
        return L"";
    }

    // 响应为纯文本 JWT（ASCII），转成 wstring
    m_token = LOUtf8ToWide(resp);
    m_tokenTimeMs = now;
    if (m_token.empty()) {
        LOLog(L"[Bing] token 为空\r\n");
        return L"";
    }
    LOLog(L"[Bing] token 已刷新，长度=%zu\r\n", m_token.size());
    return m_token;
}

// ============================================================================
// 翻译
// ============================================================================

std::wstring LOBingTranslator::Translate(const std::wstring& text,
                                           LOTranslationMode mode,
                                           const std::wstring& targetLang) {
    (void)mode;  // Bing 接口不支持翻译模式
    if (text.empty()) return L"";

    std::wstring token = GetToken();
    if (token.empty()) {
        return L"[翻译失败：无法获取令牌]";
    }

    // 构造请求体 [{"Text":"..."}]
    std::wstring bodyW = L"[{\"Text\":\"" + LOEscapeJsonString(text) + L"\"}]";
    std::string body = LOWideToUtf8(bodyW);

    // 构造 URL
    std::wstring url = L"https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=" + targetLang;

    std::vector<std::pair<std::string, std::string>> headers;
    headers.emplace_back("Authorization", "Bearer " + LOWideToUtf8(token));
    headers.emplace_back("Content-Type", "application/json; charset=UTF-8");

    std::string resp;
    if (!LONetworkClient::Shared().Request(url, body, headers, true, resp)) {
        LOLog(L"[Bing] 翻译请求失败\r\n");
        return L"[翻译失败：网络错误]";
    }

    // 解析响应 [{"translations":[{"text":"..."}]}]
    LOJsonValue root;
    if (!LOParseJson(resp, root) || root.type != LOJsonValue::Array) {
        LOLog(L"[Bing] 响应 JSON 解析失败: %s\r\n", LOUtf8ToWide(resp).c_str());
        return L"[翻译失败：响应解析错误]";
    }

    const LOJsonValue* first = root.At(0);
    if (!first) return L"[翻译失败：响应为空]";
    const LOJsonValue* translations = first->Find(L"translations");
    if (!translations || translations->type != LOJsonValue::Array) return L"[翻译失败：无 translations 字段]";
    const LOJsonValue* firstTrans = translations->At(0);
    if (!firstTrans) return L"[翻译失败：translations 为空]";
    const LOJsonValue* textVal = firstTrans->Find(L"text");
    if (!textVal || textVal->type != LOJsonValue::String) return L"[翻译失败：无 text 字段]";

    return textVal->strVal;
}

std::wstring LOBingTranslator::TranslateStream(const std::wstring& text,
                                                LOTranslationMode mode,
                                                const std::wstring& targetLang,
                                                std::function<void(const std::wstring&)> onDelta) {
    // Bing 不支持流式，直接同步翻译并一次性回调
    std::wstring result = Translate(text, mode, targetLang);
    if (onDelta && !result.empty()) onDelta(result);
    return result;
}

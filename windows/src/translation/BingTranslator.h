#pragma once

#include "TranslationService.h"

// ============================================================================
// Bing 翻译（基于 Microsoft Edge 翻译接口，免费）
//   1. GET https://edge.microsoft.com/translate/auth 获取 JWT token（纯文本）
//   2. POST https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to={lang}
//      请求体 [{"Text":"..."}]，Header Authorization: Bearer {token}
//   token 缓存 9 分钟
// ============================================================================

class LOBingTranslator : public LOTranslationService {
public:
    LOBingTranslator();
    ~LOBingTranslator() override;

    std::wstring Translate(const std::wstring& text,
                           LOTranslationMode mode,
                           const std::wstring& targetLang) override;
    std::wstring TranslateStream(const std::wstring& text,
                                  LOTranslationMode mode,
                                  const std::wstring& targetLang,
                                  std::function<void(const std::wstring&)> onDelta) override;
    bool IsFree() override { return true; }
    bool SupportsStream() override { return false; }

private:
    // 获取（必要时刷新）缓存的 token，失败返回空
    std::wstring GetToken();

    std::wstring m_token;
    ULONGLONG m_tokenTimeMs = 0;  // token 获取时的系统毫秒时间
};

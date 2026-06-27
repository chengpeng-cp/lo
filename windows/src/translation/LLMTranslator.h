#pragma once

#include "TranslationService.h"
#include "../settings/Settings.h"
#include <functional>

// ============================================================================
// LLM 翻译（OpenAI 兼容协议）
//   - 构造时传入提供商 ID 与模型名
//   - baseURL 按提供商确定（deepseek/glm/qwen/kimi/minimax/openai/volcengine/custom）
//   - API 密钥从设置读取
//   - 支持流式与非流式
// ============================================================================

class LOLLMTranslator : public LOTranslationService {
public:
    LOLLMTranslator(const std::wstring& provider, const std::wstring& model);
    ~LOLLMTranslator() override;

    std::wstring Translate(const std::wstring& text,
                           LOTranslationMode mode,
                           const std::wstring& targetLang) override;
    std::wstring TranslateStream(const std::wstring& text,
                                  LOTranslationMode mode,
                                  const std::wstring& targetLang,
                                  std::function<void(const std::wstring&)> onDelta) override;

    bool IsFree() override { return false; }
    bool SupportsStream() override { return true; }

    // 是否可用（API 密钥与模型均已配置）
    bool IsConfigured() const;

private:
    // 构造系统提示词
    std::wstring BuildSystemPrompt(LOTranslationMode mode, const std::wstring& targetLang);
    // 构造请求体 JSON（UTF-8）
    std::string BuildRequestBody(const std::wstring& text,
                                  LOTranslationMode mode,
                                  const std::wstring& targetLang,
                                  bool stream);
    // 解析非流式响应，提取 choices[0].message.content
    std::wstring ParseResponse(const std::string& resp);

    std::wstring m_provider;
    std::wstring m_model;
    std::wstring m_baseURL;   // 完整的 chat/completions URL
    std::wstring m_apiKey;
};

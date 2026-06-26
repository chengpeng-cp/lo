import Foundation

// MARK: - 翻译提供商

/// 翻译提供商配置，涵盖大模型（OpenAI 兼容）和免费翻译引擎
enum TranslationProvider: String, CaseIterable {

    // 免费翻译（无需 API Key），作为默认选择
    case bing

    // 大模型（需要 API Key，均兼容 OpenAI Chat Completions 接口）
    case deepseek
    case glm
    case qwen
    case kimi
    case minimax
    case openai
    case volcengine
    case custom

    // MARK: - 显示信息

    /// 下拉框显示名
    var displayName: String {
        switch self {
        case .deepseek:   return "DeepSeek（深度求索）"
        case .glm:        return "GLM（智谱）"
        case .qwen:       return "Qwen（通义千问）"
        case .kimi:       return "Kimi（月之暗面）"
        case .minimax:    return "MiniMax"
        case .openai:     return "OpenAI"
        case .volcengine: return "火山引擎（豆包）"
        case .custom:     return "自定义（OpenAI 兼容）"
        case .bing:       return "语境翻译（免费）"
        }
    }

    /// 是否为免费翻译引擎（无需 API Key）
    var isFree: Bool {
        return self == .bing
    }

    /// 是否需要 API Key
    var requiresAPIKey: Bool { !isFree }

    // MARK: - 大模型配置

    /// API 端点（OpenAI 兼容的 Chat Completions 接口）
    var baseURL: String {
        switch self {
        case .deepseek:   return "https://api.deepseek.com/v1/chat/completions"
        case .glm:        return "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .qwen:       return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .kimi:       return "https://api.moonshot.cn/v1/chat/completions"
        case .minimax:    return "https://api.minimax.chat/v1/text/chatcompletion_v2"
        case .openai:     return "https://api.openai.com/v1/chat/completions"
        case .volcengine: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .custom:     return ""   // 由用户在设置中填写
        case .bing:       return ""
        }
    }

    // MARK: - 辅助

    /// 所有 LLM 提供商（需要 API Key）
    static var llmProviders: [TranslationProvider] {
        return allCases.filter { $0.requiresAPIKey }
    }

    /// 所有免费提供商
    static var freeProviders: [TranslationProvider] {
        return allCases.filter { $0.isFree }
    }

    /// 从字符串安全创建，未知值回退到 bing（语境翻译）
    static func from(_ rawValue: String) -> TranslationProvider {
        return TranslationProvider(rawValue: rawValue) ?? .bing
    }
}

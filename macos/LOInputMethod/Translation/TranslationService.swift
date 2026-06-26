import Foundation

// MARK: - 翻译模式

/// 翻译模式，控制翻译的风格
enum TranslationMode: String, CaseIterable {
    /// 自然翻译：流畅自然的翻译
    case fluent
    /// 母语级表达：以英语母语者的方式表达
    case native
    /// 直译：逐字逐句翻译
    case literal

    /// 模式的中文显示名
    var displayName: String {
        switch self {
        case .fluent: return "自然翻译"
        case .native: return "母语级表达"
        case .literal: return "直译"
        }
    }
}

// MARK: - 目标语言

/// 翻译目标语言，rawValue 为 Bing/标准 BCP 47 语言代码
enum TargetLanguage: String, CaseIterable {
    case english = "en"
    case englishUK = "en-GB"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case portugueseBR = "pt-BR"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case swedish = "sv"
    case ukrainian = "uk"

    /// 下拉框显示名（母语名 + 中文名）
    var displayName: String {
        switch self {
        case .english:            return "English（英语）"
        case .englishUK:          return "English (UK)（英语·英国）"
        case .chineseSimplified:  return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .japanese:           return "日本語（日语）"
        case .korean:             return "한국어（韩语）"
        case .french:             return "Français（法语）"
        case .german:             return "Deutsch（德语）"
        case .spanish:            return "Español（西班牙语）"
        case .italian:            return "Italiano（意大利语）"
        case .portuguese:         return "Português（葡萄牙语）"
        case .portugueseBR:       return "Português (BR)（葡萄牙语·巴西）"
        case .russian:            return "Русский（俄语）"
        case .arabic:             return "العربية（阿拉伯语）"
        case .hindi:              return "हिन्दी（印地语）"
        case .thai:               return "ภาษาไทย（泰语）"
        case .vietnamese:         return "Tiếng Việt（越南语）"
        case .indonesian:         return "Bahasa Indonesia（印尼语）"
        case .dutch:              return "Nederlands（荷兰语）"
        case .polish:             return "Polski（波兰语）"
        case .turkish:            return "Türkçe（土耳其语）"
        case .swedish:            return "Svenska（瑞典语）"
        case .ukrainian:          return "Українська（乌克兰语）"
        }
    }

    /// 语言的英文名称，用于 LLM 提示词
    var englishName: String {
        switch self {
        case .english:            return "English"
        case .englishUK:          return "British English"
        case .chineseSimplified:  return "Simplified Chinese"
        case .chineseTraditional: return "Traditional Chinese"
        case .japanese:           return "Japanese"
        case .korean:             return "Korean"
        case .french:             return "French"
        case .german:             return "German"
        case .spanish:            return "Spanish"
        case .italian:            return "Italian"
        case .portuguese:         return "Portuguese"
        case .portugueseBR:       return "Brazilian Portuguese"
        case .russian:            return "Russian"
        case .arabic:             return "Arabic"
        case .hindi:              return "Hindi"
        case .thai:               return "Thai"
        case .vietnamese:         return "Vietnamese"
        case .indonesian:         return "Indonesian"
        case .dutch:              return "Dutch"
        case .polish:             return "Polish"
        case .turkish:            return "Turkish"
        case .swedish:            return "Swedish"
        case .ukrainian:          return "Ukrainian"
        }
    }
}

// MARK: - 翻译服务协议

/// 翻译服务协议，定义翻译接口
protocol TranslationServiceProtocol {
    /// 翻译文本（非流式，等全部生成后一次性返回）
    /// - Parameters:
    ///   - text: 待翻译的文本
    ///   - mode: 翻译模式
    ///   - targetLanguage: 目标语言
    /// - Returns: 翻译结果
    func translate(text: String, mode: TranslationMode, targetLanguage: TargetLanguage) async throws -> String

    /// 流式翻译：每收到一段增量文本回调 onDelta（增量片段，非全量）
    /// - Parameters:
    ///   - text: 待翻译的文本
    ///   - mode: 翻译模式
    ///   - targetLanguage: 目标语言
    ///   - onDelta: 增量回调，参数为本次新增的文本片段
    /// - Returns: 完整翻译结果
    func translateStream(text: String, mode: TranslationMode, targetLanguage: TargetLanguage, onDelta: @escaping (String) -> Void) async throws -> String
}

// MARK: - 流式默认实现

extension TranslationServiceProtocol {

    /// 默认流式实现：不支持流式的引擎（如 Bing）回退到一次性翻译，
    /// 将完整结果作为单个增量回调，调用方无需区分引擎类型
    func translateStream(text: String, mode: TranslationMode, targetLanguage: TargetLanguage, onDelta: @escaping (String) -> Void) async throws -> String {
        let result = try await translate(text: text, mode: mode, targetLanguage: targetLanguage)
        onDelta(result)
        return result
    }
}

// MARK: - 翻译错误

/// 翻译相关错误
enum TranslationError: LocalizedError {
    /// API 密钥未配置
    case apiKeyNotConfigured
    /// 网络请求失败
    case networkError(Error)
    /// 响应解析失败
    case invalidResponse
    /// API 返回错误
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured: return "API 密钥未配置，请在设置中填写"
        case .networkError(let error): return "网络请求失败：\(error.localizedDescription)"
        case .invalidResponse: return "翻译响应解析失败"
        case .apiError(let message): return "翻译服务错误：\(message)"
        }
    }
}

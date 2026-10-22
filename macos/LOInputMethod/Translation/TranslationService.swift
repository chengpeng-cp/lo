import Foundation

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
}

// MARK: - 翻译服务协议

/// 翻译服务协议，定义翻译接口
protocol TranslationServiceProtocol {
    /// 翻译文本
    /// - Parameters:
    ///   - text: 待翻译的文本
    ///   - targetLanguage: 目标语言
    /// - Returns: 翻译结果
    func translate(text: String, targetLanguage: TargetLanguage) async throws -> String
}

// MARK: - 翻译错误

/// 翻译相关错误
enum TranslationError: LocalizedError {
    /// 网络请求失败
    case networkError(Error)
    /// 响应解析失败
    case invalidResponse
    /// API 返回错误
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error): return "网络请求失败：\(error.localizedDescription)"
        case .invalidResponse: return "翻译响应解析失败"
        case .apiError(let message): return "翻译服务错误：\(message)"
        }
    }
}

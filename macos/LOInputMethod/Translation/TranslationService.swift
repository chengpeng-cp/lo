import Foundation

// MARK: - 目标语言

/// 翻译目标语言，rawValue 为语言代码（BCP 47 或 ISO 639）。
/// 使用结构体而不是枚举，以便承载不同引擎的完整语言列表。
struct TargetLanguage: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ code: String) {
        self.rawValue = code
    }

    static let english = TargetLanguage("en")
    static let englishUK = TargetLanguage("en-GB")
    static let chineseSimplified = TargetLanguage("zh-Hans")
    static let chineseTraditional = TargetLanguage("zh-Hant")
    static let japanese = TargetLanguage("ja")
    static let korean = TargetLanguage("ko")
    static let french = TargetLanguage("fr")
    static let german = TargetLanguage("de")
    static let spanish = TargetLanguage("es")
    static let italian = TargetLanguage("it")
    static let portuguese = TargetLanguage("pt")
    static let portugueseBR = TargetLanguage("pt-BR")
    static let russian = TargetLanguage("ru")
    static let arabic = TargetLanguage("ar")
    static let hindi = TargetLanguage("hi")
    static let thai = TargetLanguage("th")
    static let vietnamese = TargetLanguage("vi")
    static let indonesian = TargetLanguage("id")
    static let dutch = TargetLanguage("nl")
    static let polish = TargetLanguage("pl")
    static let turkish = TargetLanguage("tr")
    static let swedish = TargetLanguage("sv")
    static let ukrainian = TargetLanguage("uk")

    /// 在线引擎支持的语言（保留此列表供默认值使用）
    static let allCases: [TargetLanguage] = [
        .english, .englishUK, .chineseSimplified, .chineseTraditional, .japanese,
        .korean, .french, .german, .spanish, .italian, .portuguese, .portugueseBR,
        .russian, .arabic, .hindi, .thai, .vietnamese, .indonesian, .dutch,
        .polish, .turkish, .swedish, .ukrainian
    ]

    /// 下拉框显示名（母语名 + 中文名）
    var displayName: String {
        MTLanguageCatalog.displayName(for: rawValue)
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

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

// MARK: - 翻译服务协议

/// 翻译服务协议，定义翻译接口
protocol TranslationServiceProtocol {
    /// 翻译文本
    /// - Parameters:
    ///   - text: 待翻译的文本
    ///   - mode: 翻译模式
    /// - Returns: 翻译结果
    func translate(text: String, mode: TranslationMode) async throws -> String
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

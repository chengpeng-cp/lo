import Foundation

// MARK: - Google 翻译器

/// 基于 Google Translate API 的翻译器
/// 使用 Google Cloud Translation API v2 进行翻译
class GoogleTranslator: TranslationServiceProtocol {

    /// API 端点
    private let endpoint = URL(string: "https://translation.googleapis.com/language/translate/v2")!

    /// 源语言
    private let sourceLanguage = "zh"

    /// 目标语言
    private let targetLanguage = "en"

    /// 请求超时时间
    private let timeoutInterval: TimeInterval = 15

    // MARK: - 翻译服务协议

    func translate(text: String, mode: TranslationMode) async throws -> String {
        // 获取 API 密钥
        guard let apiKey = LOSettings.load().getAPIKey(provider: "google"), !apiKey.isEmpty else {
            throw TranslationError.apiKeyNotConfigured
        }

        // 构建请求 URL（GET 请求，参数在 URL 中）
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "source", value: sourceLanguage),
            URLQueryItem(name: "target", value: targetLanguage),
            URLQueryItem(name: "format", value: "text")
        ]

        // Google Translate API 不区分翻译模式，但可以通过添加提示来引导
        // 对于母语级模式，添加格式提示
        if mode == .native {
            components.queryItems?.append(URLQueryItem(name: "q", value: "Express this naturally as a native English speaker: \(text)"))
        }

        guard let url = components.url else {
            throw TranslationError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval

        // 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.networkError(error)
        }

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = errorBody["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        return try parseResponse(data)
    }

    // MARK: - 私有方法

    /// 解析 Google Translate API 的 JSON 响应
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let translations = dataDict["translations"] as? [[String: Any]],
              let firstTranslation = translations.first,
              let translatedText = firstTranslation["translatedText"] as? String else {
            throw TranslationError.invalidResponse
        }

        return translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

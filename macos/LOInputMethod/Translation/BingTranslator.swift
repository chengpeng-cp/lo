import Foundation

// MARK: - 必应翻译器（免费）

/// 基于微软 Edge 翻译接口的免费翻译器
/// 利用 Edge 浏览器内置翻译的 auth 端点获取 token，无需 API Key
/// 微软服务在国内可正常访问，作为无 API Key 时的兜底方案
class BingTranslator: TranslationServiceProtocol {

    /// Token 端点（Edge 浏览器内置翻译使用）
    private let authEndpoint = URL(string: "https://edge.microsoft.com/translate/auth")!

    /// 翻译端点
    private let translateEndpoint = URL(string: "https://api.cognitive.microsofttranslator.com/translate")!

    /// 目标语言
    private let targetLanguage = "en"

    /// 请求超时时间
    private let timeoutInterval: TimeInterval = 10

    /// 缓存的 token 及过期时间
    private var cachedToken: String?
    private var tokenExpiry: Date = Date.distantPast

    // MARK: - 翻译服务协议

    func translate(text: String, mode: TranslationMode) async throws -> String {
        debugLog("[Bing] 开始翻译: text='\(text)' (长度=\(text.count))")

        // 获取 auth token
        let token = try await getAuthToken()

        // 构建请求 URL
        var components = URLComponents(url: translateEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: targetLanguage)
        ]

        guard let url = components.url else {
            throw TranslationError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval

        // 请求体：数组格式，每个元素包含 Text 字段
        let body: [[String: String]] = [["Text": text]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        debugLog("[Bing] 请求翻译")

        // 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("[Bing] 网络请求失败: \(error.localizedDescription)")
            throw TranslationError.networkError(error)
        }

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("[Bing] 响应类型异常")
            throw TranslationError.invalidResponse
        }
        debugLog("[Bing] HTTP 状态码: \(httpResponse.statusCode), 响应长度: \(data.count) bytes")

        guard httpResponse.statusCode == 200 else {
            let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? "(二进制)"
            debugLog("[Bing] 非 200 响应体: \(bodySnippet)")
            // 401/403 可能是 token 过期，清除缓存重试
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                cachedToken = nil
                tokenExpiry = Date.distantPast
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        let result = try parseResponse(data)
        debugLog("[Bing] 翻译结果: '\(result)'")
        return result
    }

    // MARK: - 私有方法

    /// 获取 auth token（带缓存，token 有效期约 10 分钟）
    private func getAuthToken() async throws -> String {
        // 检查缓存（提前 1 分钟过期）
        if let token = cachedToken, Date() < tokenExpiry.addingTimeInterval(-60) {
            return token
        }

        debugLog("[Bing] 获取 auth token")

        var request = URLRequest(url: authEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("[Bing] 获取 token 失败: \(error.localizedDescription)")
            throw TranslationError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            debugLog("[Bing] 获取 token 响应异常")
            throw TranslationError.invalidResponse
        }

        guard let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw TranslationError.invalidResponse
        }

        // 缓存 token，有效期设为 9 分钟（保守估计）
        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(540)

        debugLog("[Bing] 获取 token 成功")
        return token
    }

    /// 解析微软翻译 API 的 JSON 响应
    /// 返回数组格式：[{"translations": [{"text": "翻译结果", "to": "en"}]}]
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstResult = json.first,
              let translations = firstResult["translations"] as? [[String: Any]],
              let firstTranslation = translations.first,
              let text = firstTranslation["text"] as? String else {
            throw TranslationError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

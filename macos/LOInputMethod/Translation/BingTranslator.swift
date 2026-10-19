import Foundation

/// 微软 Edge 免费翻译。2026 年旧 /translate/auth 端点已停用，
/// 新接口直接接收字符串数组，不需要 API Key 或临时 token。
class BingTranslator: TranslationServiceProtocol {
    private let endpoint = URL(string: "https://edge.microsoft.com/translate/translatetext")!
    private let session: URLSession

    init(session: URLSession = TranslationNetwork.shared) {
        self.session = session
    }

    func translate(text: String, mode: TranslationMode, targetLanguage: TargetLanguage) async throws -> String {
        try Task.checkCancellation()
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "isEnterpriseClient", value: "false"),
            URLQueryItem(name: "to", value: targetLanguage.rawValue)
        ]
        guard let url = components.url else { throw TranslationError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: [text])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            debugLog("[Bing] 网络请求失败")
            throw TranslationError.networkError(error)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
        debugLog("[Bing] HTTP 状态码=\(response.statusCode)，响应长度=\(data.count)")
        guard response.statusCode == 200 else {
            throw TranslationError.apiError("微软免费翻译暂不可用（HTTP \(response.statusCode)），请稍后重试或在设置中配置其他翻译服务")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let translations = json.first?["translations"] as? [[String: Any]],
              let text = translations.first?["text"] as? String else {
            throw TranslationError.invalidResponse
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.invalidResponse }
        debugLog("[Bing] 翻译完成，长度=\(result.count)")
        return result
    }
}

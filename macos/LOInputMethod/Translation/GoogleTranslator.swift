import Foundation

// MARK: - Google 翻译器

/// 基于 Google 翻译免费网页接口的翻译器
/// 调用 translate.googleapis.com/translate_a/single，无需 API Key
/// 注：该接口为非官方接口，存在被限流（429）的可能，仅适合个人/轻量场景
class GoogleTranslator: TranslationServiceProtocol {

    /// 免费网页接口端点
    private let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!

    /// 源语言（auto 为自动检测）
    private let sourceLanguage = "auto"

    /// 目标语言
    private let targetLanguage = "en"

    /// 请求超时时间（Google 免费接口网络不可达时快速失败）
    private let timeoutInterval: TimeInterval = 8

    // MARK: - 翻译服务协议

    func translate(text: String, mode: TranslationMode) async throws -> String {
        // 免费网页接口无需 API Key
        debugLog("[Google] 开始翻译: mode=\(mode.rawValue) text='\(text)' (长度=\(text.count))")

        // 构建请求 URL（GET 请求，参数在 URL 中）
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "sl", value: sourceLanguage),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "q", value: text)
        ]

        guard let url = components.url else {
            throw TranslationError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        // 模拟浏览器请求头，降低被限流的概率
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        debugLog("[Google] 请求 URL: \(url.absoluteString)")

        // 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("[Google] 网络请求失败: \(error.localizedDescription)")
            throw TranslationError.networkError(error)
        }

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("[Google] 响应类型异常")
            throw TranslationError.invalidResponse
        }
        debugLog("[Google] HTTP 状态码: \(httpResponse.statusCode), 响应长度: \(data.count) bytes")

        guard httpResponse.statusCode == 200 else {
            let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? "(二进制)"
            debugLog("[Google] 非 200 响应体: \(bodySnippet)")
            if httpResponse.statusCode == 429 {
                throw TranslationError.apiError("请求过于频繁，已被谷歌限流，请稍后重试")
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        let result = try parseResponse(data)
        debugLog("[Google] 翻译结果: '\(result)'")
        return result
    }

    // MARK: - 私有方法

    /// 解析 Google 翻译免费网页接口的 JSON 响应
    /// 返回的是嵌套数组，翻译结果在 data[0]，每个元素 item[0] 为翻译片段，需拼接
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 0 else {
            throw TranslationError.invalidResponse
        }

        // data[0] 是翻译片段数组，每个元素形如 [translatedText, originalText, ...]
        guard let segments = json[0] as? [[Any]] else {
            throw TranslationError.invalidResponse
        }

        // 拼接所有翻译片段
        var result = ""
        for segment in segments {
            if segment.count > 0, let translated = segment[0] as? String {
                result += translated
            }
        }

        guard !result.isEmpty else {
            throw TranslationError.invalidResponse
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

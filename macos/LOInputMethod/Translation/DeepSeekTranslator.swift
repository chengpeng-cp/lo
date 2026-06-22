import Foundation

// MARK: - DeepSeek 翻译器

/// 基于 DeepSeek API 的翻译器
/// 使用 deepseek-chat 模型进行翻译
class DeepSeekTranslator: TranslationServiceProtocol {

    /// API 端点
    private let endpoint = URL(string: "https://api.deepseek.com/v1/chat/completions")!

    /// 模型名称
    private let model = "deepseek-chat"

    /// 请求超时时间
    private let timeoutInterval: TimeInterval = 30

    // MARK: - 翻译服务协议

    func translate(text: String, mode: TranslationMode) async throws -> String {
        // 获取 API 密钥
        guard let apiKey = LOSettings.load().getAPIKey(provider: "deepseek"), !apiKey.isEmpty else {
            throw TranslationError.apiKeyNotConfigured
        }

        // 构建请求
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval

        // 构建请求体
        let systemPrompt = Self.systemPrompt(for: mode)
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
            // 尝试解析错误信息
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

    /// 根据翻译模式生成系统提示词
    private static func systemPrompt(for mode: TranslationMode) -> String {
        switch mode {
        case .fluent:
            return "你是一个专业的翻译助手。请将用户输入的中文翻译成自然流畅的英文。翻译应当准确传达原文含义，同时符合英文的表达习惯。只输出翻译结果，不要添加任何解释或注释。"
        case .native:
            return "你是一个英语母语级别的翻译助手。请将用户输入的中文翻译成地道的英文，就像英语母语者会说的话一样。使用自然的习语、搭配和表达方式，避免翻译腔。只输出翻译结果，不要添加任何解释或注释。"
        case .literal:
            return "你是一个翻译助手。请将用户输入的中文逐字逐句直译成英文，尽量保持原文的语法结构和词语对应关系。只输出翻译结果，不要添加任何解释或注释。"
        }
    }

    /// 解析 DeepSeek API 的 JSON 响应
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }

        // 解析 choices 数组
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

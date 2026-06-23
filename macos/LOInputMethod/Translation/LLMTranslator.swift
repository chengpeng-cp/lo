import Foundation

// MARK: - 大模型翻译器（OpenAI 兼容）

/// 通用大模型翻译器，兼容所有 OpenAI Chat Completions 接口的提供商
/// 支持 DeepSeek、GLM、Qwen、Kimi、MiniMax、OpenAI、火山引擎等
class LLMTranslator: TranslationServiceProtocol {

    /// 提供商
    private let provider: TranslationProvider

    /// 模型名称
    private let model: String

    /// 请求超时时间
    private let timeoutInterval: TimeInterval = 30

    // MARK: - 初始化

    init(provider: TranslationProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    // MARK: - 翻译服务协议

    func translate(text: String, mode: TranslationMode) async throws -> String {
        // 自定义提供商需要从设置读取 baseURL
        let endpoint: URL
        if provider == .custom {
            let settings = LOSettings.load()
            let urlStr = settings.customLLMBaseURL
            guard !urlStr.isEmpty else {
                throw TranslationError.apiError("自定义提供商未配置 API 端点")
            }
            guard let url = URL(string: urlStr) else {
                throw TranslationError.apiError("自定义 API 端点格式无效")
            }
            endpoint = url
        } else {
            guard let url = URL(string: provider.baseURL) else {
                throw TranslationError.invalidResponse
            }
            endpoint = url
        }

        // 获取 API 密钥
        guard let apiKey = LOSettings.load().getAPIKey(provider: provider.rawValue), !apiKey.isEmpty else {
            throw TranslationError.apiKeyNotConfigured
        }

        debugLog("[LLM] \(provider.rawValue) 开始翻译: model=\(model) mode=\(mode.rawValue) text='\(text)' (长度=\(text.count))")

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
            "max_tokens": 4096
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        debugLog("[LLM] \(provider.rawValue) 请求: model=\(model) mode=\(mode.rawValue)")

        // 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("[LLM] \(provider.rawValue) 网络请求失败: \(error.localizedDescription)")
            throw TranslationError.networkError(error)
        }

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("[LLM] \(provider.rawValue) 响应类型异常")
            throw TranslationError.invalidResponse
        }
        debugLog("[LLM] \(provider.rawValue) HTTP 状态码: \(httpResponse.statusCode), 响应长度: \(data.count) bytes")

        guard httpResponse.statusCode == 200 else {
            let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? "(二进制)"
            debugLog("[LLM] \(provider.rawValue) 非 200 响应体: \(bodySnippet)")
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = errorBody["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        let result = try parseResponse(data)
        debugLog("[LLM] \(provider.rawValue) 翻译结果: '\(result)' (长度=\(result.count))")
        return result
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

    /// 解析 OpenAI 兼容 API 的 JSON 响应
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

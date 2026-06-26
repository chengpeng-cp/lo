import Foundation

// MARK: - 大模型翻译器（OpenAI 兼容）

/// 通用大模型翻译器，兼容所有 OpenAI Chat Completions 接口的提供商
/// 支持 DeepSeek、GLM、Qwen、Kimi、MiniMax、OpenAI、火山引擎等
/// 支持流式（SSE）输出，边生成边返回，降低首字延迟
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

    func translate(text: String, mode: TranslationMode, targetLanguage: TargetLanguage) async throws -> String {
        let request = try buildRequest(text: text, mode: mode, targetLanguage: targetLanguage, stream: false)

        debugLog("[LLM] \(provider.rawValue) 开始翻译: model=\(model) mode=\(mode.rawValue) target=\(targetLanguage.rawValue) text='\(text)' (长度=\(text.count))")

        // 发送请求（复用共享 session 的连接池）
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await TranslationNetwork.shared.data(for: request)
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

    // MARK: - 流式翻译（SSE）

    func translateStream(text: String, mode: TranslationMode, targetLanguage: TargetLanguage, onDelta: @escaping (String) -> Void) async throws -> String {
        let request = try buildRequest(text: text, mode: mode, targetLanguage: targetLanguage, stream: true)

        debugLog("[LLM] \(provider.rawValue) 流式翻译开始: model=\(model) mode=\(mode.rawValue) target=\(targetLanguage.rawValue) text='\(text)' (长度=\(text.count))")

        // 流式请求：用 bytes(for:) 逐块读取 SSE 响应
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await TranslationNetwork.shared.bytes(for: request)
        } catch {
            debugLog("[LLM] \(provider.rawValue) 流式请求失败: \(error.localizedDescription)")
            throw TranslationError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("[LLM] \(provider.rawValue) 流式响应类型异常")
            throw TranslationError.invalidResponse
        }
        debugLog("[LLM] \(provider.rawValue) 流式 HTTP 状态码: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            // 非 200：读取完整 body 报错
            var bodyData = Data()
            for try await byte in bytes {
                bodyData.append(byte)
            }
            let bodySnippet = String(data: bodyData.prefix(500), encoding: .utf8) ?? "(二进制)"
            debugLog("[LLM] \(provider.rawValue) 流式非 200 响应体: \(bodySnippet)")
            if let errorBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let errorDict = errorBody["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 逐行解析 SSE：每行形如 "data: {json}"，以 "data: [DONE]" 结束
        var accumulated = ""
        for try await line in bytes.lines {
            // 任务被取消时立即终止（用户已输入新内容）
            if Task.isCancelled {
                debugLog("[LLM] \(provider.rawValue) 流式翻译已取消")
                throw CancellationError()
            }

            // SSE 事件以 "data:" 前缀开始，跳过空行与注释行（如 ": keep-alive"）
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

            // 流结束标记
            if payload == "[DONE]" { break }

            // 解析 JSON，提取 choices[0].delta.content
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any] else {
                continue
            }

            // 首个 chunk 可能只含 role 无 content，跳过
            guard let content = delta["content"] as? String, !content.isEmpty else { continue }

            accumulated += content
            onDelta(content)
        }

        let result = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("[LLM] \(provider.rawValue) 流式翻译完成: '\(result)' (长度=\(result.count))")
        return result
    }

    // MARK: - 私有方法

    /// 构建翻译请求（流式与非流式共用）
    /// - Parameter stream: 是否启用流式（SSE）
    /// - Returns: 配置好的 URLRequest
    private func buildRequest(text: String, mode: TranslationMode, targetLanguage: TargetLanguage, stream: Bool) throws -> URLRequest {
        // 解析端点
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

        // 构建请求
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 流式请求需要接收 text/event-stream
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.timeoutInterval = timeoutInterval

        // 构建请求体
        let systemPrompt = Self.systemPrompt(for: mode, targetLanguage: targetLanguage)
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]
        if stream {
            body["stream"] = true
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let streamTag = stream ? " [stream]" : ""
        debugLog("[LLM] \(provider.rawValue) 请求: model=\(model) mode=\(mode.rawValue) target=\(targetLanguage.rawValue)\(streamTag)")

        return request
    }

    /// 根据翻译模式和目标语言生成系统提示词
    /// 自动识别源语言，不限定输入语言
    private static func systemPrompt(for mode: TranslationMode, targetLanguage: TargetLanguage) -> String {
        let lang = targetLanguage.englishName
        switch mode {
        case .fluent:
            return "你是一个专业的翻译助手。请将用户输入的文字翻译成自然流畅的\(lang)，自动识别输入语言。翻译应当准确传达原文含义，同时符合\(lang)的表达习惯。只输出翻译结果，不要添加任何解释或注释。"
        case .native:
            return "你是一个\(lang)母语级别的翻译助手。请将用户输入的文字翻译成地道的\(lang)，自动识别输入语言，就像\(lang)母语者会说的话一样。使用自然的习语、搭配和表达方式，避免翻译腔。只输出翻译结果，不要添加任何解释或注释。"
        case .literal:
            return "你是一个翻译助手。请将用户输入的文字逐字逐句直译成\(lang)，自动识别输入语言，尽量保持原文的语法结构和词语对应关系。只输出翻译结果，不要添加任何解释或注释。"
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

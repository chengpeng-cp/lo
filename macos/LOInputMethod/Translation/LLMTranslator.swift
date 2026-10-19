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
    private let session: URLSession

    /// 请求超时时间
    private let timeoutInterval: TimeInterval = 30

    // MARK: - 初始化

    init(provider: TranslationProvider, model: String, session: URLSession = TranslationNetwork.shared) {
        self.provider = provider
        self.model = model
        self.session = session
    }

    // MARK: - 翻译服务协议

    func translate(text: String, mode: TranslationMode, targetLanguage: TargetLanguage) async throws -> String {
        let request = try buildRequest(text: text, mode: mode, targetLanguage: targetLanguage, stream: false)

        debugLog("[LLM] \(provider.rawValue) 开始翻译: model=\(model) mode=\(mode.rawValue) target=\(targetLanguage.rawValue) (长度=\(text.count))")

        // 发送请求（复用共享 session 的连接池）
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            debugLog("[LLM] \(provider.rawValue) 网络请求失败")
            throw TranslationError.networkError(error)
        }

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("[LLM] \(provider.rawValue) 响应类型异常")
            throw TranslationError.invalidResponse
        }
        debugLog("[LLM] \(provider.rawValue) HTTP 状态码: \(httpResponse.statusCode), 响应长度: \(data.count) bytes")

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = errorBody["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        let result = try parseResponse(data)
        debugLog("[LLM] \(provider.rawValue) 翻译完成，长度=\(result.count)")
        return result
    }

    // MARK: - 流式翻译（SSE）

    func translateStream(text: String, mode: TranslationMode, targetLanguage: TargetLanguage, onDelta: @escaping (String) -> Void) async throws -> String {
        let request = try buildRequest(text: text, mode: mode, targetLanguage: targetLanguage, stream: true)

        debugLog("[LLM] \(provider.rawValue) 流式翻译开始: model=\(model) mode=\(mode.rawValue) target=\(targetLanguage.rawValue) (长度=\(text.count))")

        // 流式请求：用 bytes(for:) 逐块读取 SSE 响应
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            debugLog("[LLM] \(provider.rawValue) 流式请求失败")
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
                guard bodyData.count < 1_048_576 else { throw TranslationError.invalidResponse }
                bodyData.append(byte)
            }
            if let errorBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let errorDict = errorBody["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 某些兼容端点忽略 stream=true 并返回普通 JSON。
        if httpResponse.mimeType == "application/json" {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1_048_576 else { throw TranslationError.invalidResponse }
                data.append(byte)
            }
            let result = try parseResponse(data)
            onDelta(result)
            return result
        }

        var decoder = LLMStreamDecoder()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let delta = try decoder.consume(payload), !delta.isEmpty {
                onDelta(delta)
            }
            if decoder.isDone { break }
        }
        let result = try decoder.result()
        debugLog("[LLM] \(provider.rawValue) 流式翻译完成，长度=\(result.count)")
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
            guard let url = URL(string: urlStr), TranslationNetwork.isAllowedEndpoint(url) else {
                throw TranslationError.apiError("自定义 API 端点格式无效")
            }
            endpoint = url
        } else {
            guard let url = URL(string: provider.baseURL), TranslationNetwork.isAllowedEndpoint(url) else {
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

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.invalidResponse }
        return result
    }
}

/// 将截断流、服务端错误和正常结束区分开，避免把半截译文作为成功结果缓存。
struct LLMStreamDecoder {
    private(set) var accumulated = ""
    private(set) var isDone = false
    private var hasFinishReason = false

    mutating func consume(_ payload: String) throws -> String? {
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" {
            isDone = true
            return nil
        }
        guard let data = payload.data(using: .utf8), data.count <= 1_048_576,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }
        if let error = json["error"] as? [String: Any] {
            throw TranslationError.apiError(error["message"] as? String ?? "流式请求失败")
        }
        guard let choices = json["choices"] as? [[String: Any]] else {
            throw TranslationError.invalidResponse
        }
        // usage 统计帧允许 choices 为空。
        guard let first = choices.first else { return nil }
        if let reason = first["finish_reason"] as? String {
            guard reason == "stop" else {
                throw TranslationError.apiError("翻译未完整生成（\(reason)）")
            }
            hasFinishReason = true
        }
        guard let delta = first["delta"] as? [String: Any] else {
            throw TranslationError.invalidResponse
        }
        guard let content = delta["content"] as? String, !content.isEmpty else { return nil }
        guard accumulated.utf8.count + content.utf8.count <= 1_048_576 else {
            throw TranslationError.invalidResponse
        }
        accumulated += content
        return content
    }

    func result() throws -> String {
        let result = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (isDone || hasFinishReason), !result.isEmpty else {
            throw TranslationError.invalidResponse
        }
        return result
    }
}

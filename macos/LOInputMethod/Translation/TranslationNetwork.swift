import Foundation

// MARK: - 翻译网络会话

/// 翻译专用的共享 URLSession，复用连接池以减少重复 TCP/TLS 握手开销
/// 所有翻译器（LLM、Bing）统一使用此 session，后续请求可复用已建立的连接
enum TranslationNetwork {

    /// 共享 URLSession（复用连接池）
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        // 复用 keep-alive 连接，后续请求免重复 TCP/TLS 握手
        config.httpShouldUsePipelining = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        // 等待网络可用，避免瞬时断网直接失败
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: TranslationRedirectDelegate(), delegateQueue: nil)
    }()

    /// 云端必须使用 HTTPS；允许本机 HTTP 以连接本地模型服务。
    static func isAllowedEndpoint(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.fragment == nil,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if url.scheme?.lowercased() == "https" { return true }
        return url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// 预热与指定 URL 的连接（提前建立 TCP+TLS，后续请求可复用）
    /// 静默处理所有错误，仅用于优化首次请求延迟，不保证成功
    /// - Parameter url: 需要预热连接的目标 URL
    static func warmup(url: URL) {
        guard isAllowedEndpoint(url) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        // 用共享 session 发起，连接建立后进入连接池供后续复用
        let task = shared.dataTask(with: request) { _, _, _ in
            // 忽略结果：无论状态码如何，连接已建立并可复用
        }
        task.resume()
    }
}

/// 不将翻译正文和凭证重定向到其他 origin，也拒绝 HTTPS 降级。
private final class TranslationRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              TranslationNetwork.isAllowedEndpoint(target),
              original.scheme?.lowercased() == target.scheme?.lowercased(),
              original.host?.lowercased() == target.host?.lowercased(),
              original.port == target.port else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

// Compiled with the production Translation sources by run-translation-regressions.sh.
// LOSettings and home directory are isolated; no user credentials or files are read.
import Foundation
import Darwin

let regressionHome = FileManager.default.temporaryDirectory.appendingPathComponent("lo-translation-regression-\(UUID().uuidString)")
func NSHomeDirectory() -> String { regressionHome.path }
func debugLog(_ message: String) {}

struct LOSettings {
    static var value = LOSettings()
    var translationEnabled = true
    var translationProvider = "custom"
    var translationModel = "synthetic-test-model"
    var customLLMBaseURL = "https://synthetic.test/v1/chat/completions"
    var translationMode = "fluent"
    var targetLanguage = "en"
    var segmentPauseThreshold = 3600.0
    var translationDebounceInterval = 3600.0
    static func load() -> LOSettings { value }
    func getAPIKey(provider: String) -> String? { "synthetic-test-key-not-a-real-credential" }
}

final class SyntheticURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Split UTF-8 and JSON at arbitrary byte boundaries as real network reads do.
            for offset in stride(from: 0, to: data.count, by: 7) {
                client?.urlProtocol(self, didLoad: data.subdata(in: offset..<min(offset + 7, data.count)))
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class DelayedTranslator: TranslationServiceProtocol {
    var delay: UInt64 = 80_000_000
    var output = "synthetic-final"
    func translate(text: String, mode: TranslationMode, targetLanguage: TargetLanguage) async throws -> String {
        try? await Task.sleep(nanoseconds: delay) // Deliberately ignores cancellation.
        return output
    }
    func translateStream(text: String, mode: TranslationMode, targetLanguage: TargetLanguage, onDelta: @escaping (String) -> Void) async throws -> String {
        try? await Task.sleep(nanoseconds: delay)
        onDelta("stale-synthetic-delta")
        return output
    }
}

extension TranslationScheduler {
    static func regressionInstance(_ service: TranslationServiceProtocol) -> TranslationScheduler {
        let scheduler = TranslationScheduler()
        scheduler.translator = service
        return scheduler
    }
    func regressionFire() { executeTranslation() }
    func regressionPrime(_ text: String, _ result: String) {
        let config = settings
        let context = [config.translationProvider, config.translationModel, config.customLLMBaseURL, config.translationMode, translator is BingTranslator ? "free" : "llm"].joined(separator: "\u{1F}")
        cache.set(text: text, translation: result, targetLanguage: config.targetLanguage, context: context)
    }
}
extension TranslationCache {
    func regressionFlush() { persistenceQueue.sync {} }
}

@main struct TranslationRegression {
    static var checks = 0
    static func check(_ condition: Bool, _ description: String) {
        precondition(condition, "FAILED: \(description)")
        checks += 1
        print("PASS: \(description)")
    }
    static func mustThrow(_ description: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure("FAILED: \(description)") }
        catch { checks += 1; print("PASS: \(description)") }
    }
    static func mustThrowAsync(_ description: String, _ body: () async throws -> Void) async {
        do { try await body(); preconditionFailure("FAILED: \(description)") }
        catch { checks += 1; print("PASS: \(description)") }
    }
    @MainActor static func main() async throws {
        defer { try? FileManager.default.removeItem(at: regressionHome) }
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--live-bing") {
            let text = "这是一个用于发布前检查的合成测试句子。"
            let result = try await BingTranslator().translate(text: text, mode: .fluent, targetLanguage: .english)
            check(!result.isEmpty && result != text, "real Bing network translation of synthetic text")
            print("LIVE synthetic result: \(result)")
            return
        }
        let mockConfiguration = URLSessionConfiguration.ephemeral
        mockConfiguration.protocolClasses = [SyntheticURLProtocol.self]
        let mockSession = URLSession(configuration: mockConfiguration)
        check(TranslationNetwork.isAllowedEndpoint(URL(string: "https://example.test/v1")!), "HTTPS custom endpoint accepted")
        check(TranslationNetwork.isAllowedEndpoint(URL(string: "http://127.0.0.1:8080/v1")!), "local model HTTP accepted")
        check(!TranslationNetwork.isAllowedEndpoint(URL(string: "http://example.test/v1")!), "remote cleartext rejected")
        check(!TranslationNetwork.isAllowedEndpoint(URL(string: "https://user:pass@example.test/v1")!), "embedded URL credentials rejected")
        check(!TranslationNetwork.isAllowedEndpoint(URL(string: "https://example.test/v1#fragment")!), "URL fragment rejected")

        var decoder = LLMStreamDecoder()
        check(try decoder.consume("{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}") == nil, "role-only SSE chunk accepted")
        check(try decoder.consume("{\"choices\":[{\"delta\":{\"content\":\"Hello 🌍\"}}]}") == "Hello 🌍", "Unicode SSE text preserved")
        mustThrow("truncated SSE rejected") { _ = try decoder.result() }
        _ = try decoder.consume("{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
        check(try decoder.result() == "Hello 🌍", "finish reason completes stream")
        mustThrow("SSE API errors surfaced") { _ = try decoder.consume("{\"error\":{\"message\":\"synthetic failure\"}}") }
        mustThrow("malformed SSE JSON rejected") { _ = try decoder.consume("{invalid}") }
        mustThrow("output token truncation rejected") { _ = try decoder.consume("{\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}") }
        var empty = LLMStreamDecoder()
        _ = try empty.consume("[DONE]")
        mustThrow("empty stream rejected") { _ = try empty.result() }

        let cacheURL = regressionHome.appendingPathComponent("cache.json")
        let cache = TranslationCache(cacheFileURL: cacheURL)
        cache.set(text: "US", translation: "美国", targetLanguage: "zh", context: "one")
        check(cache.get(text: "us", targetLanguage: "zh", context: "one") == nil, "cache preserves source case")
        check(cache.get(text: "US", targetLanguage: "zh", context: "two") == nil, "cache isolates provider/model/mode context")
        check(cache.get(text: "US", targetLanguage: "en", context: "one") == nil, "cache isolates target language")
        cache.set(text: "blank", translation: " \n", targetLanguage: "en")
        check(cache.get(text: "blank", targetLanguage: "en") == nil, "blank output never cached")
        for i in 0..<1050 { cache.set(text: "source-\(i)", translation: "result-\(i)", targetLanguage: "en") }
        check(cache.get(text: "source-0", targetLanguage: "en") == nil, "LRU capacity enforced")
        check(cache.get(text: "source-1049", targetLanguage: "en") == "result-1049", "newest LRU entry retained")
        cache.clear()
        cache.regressionFlush()
        let reloaded = TranslationCache(cacheFileURL: cacheURL)
        check(reloaded.get(text: "source-1049", targetLanguage: "en") == nil, "clear survives pending writes and reload")

        let llm = LLMTranslator(provider: .custom, model: "synthetic-test-model", session: mockSession)
        SyntheticURLProtocol.handler = { request in
            check(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer synthetic-") == true, "request uses only isolated synthetic credential")
            return (200, ["Content-Type":"text/event-stream"], Data("data: {\"choices\":[{\"delta\":{\"content\":\"Hello 🌍\"}}]}\r\n\r\ndata: [DONE]\r\n\r\n".utf8))
        }
        var deltas = ""
        let result = try await llm.translateStream(text: "合成测试", mode: .fluent, targetLanguage: .english) { deltas += $0 }
        check(result == "Hello 🌍" && deltas == result, "stream network chunks decode UTF-8 and CRLF")
        SyntheticURLProtocol.handler = { _ in (200, ["Content-Type":"application/json"], Data("{\"choices\":[{\"message\":{\"content\":\"JSON fallback\"}}]}".utf8)) }
        let fallback = try await llm.translateStream(text: "合成测试", mode: .fluent, targetLanguage: .english) { _ in }
        check(fallback == "JSON fallback", "JSON response to streaming request supported")
        SyntheticURLProtocol.handler = { _ in (200, ["Content-Type":"text/event-stream"], Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8)) }
        await mustThrowAsync("network EOF without finish rejected") { _ = try await llm.translateStream(text: "合成测试", mode: .fluent, targetLanguage: .english) { _ in } }
        SyntheticURLProtocol.handler = { _ in (429, ["Content-Type":"application/json"], Data("{\"error\":{\"message\":\"synthetic rate limit\"}}".utf8)) }
        await mustThrowAsync("HTTP 429 fails streaming") { _ = try await llm.translateStream(text: "合成测试", mode: .fluent, targetLanguage: .english) { _ in } }

        var translationCount = 0
        SyntheticURLProtocol.handler = { request in
            translationCount += 1
            check(request.url!.path == "/translate/translatetext", "Bing uses supported Microsoft endpoint")
            check(request.value(forHTTPHeaderField: "Authorization") == nil, "Bing needs no user key or retired auth token")
            check(request.url!.query!.contains("to=en"), "Bing language query retained")
            let body = request.httpBody ?? {
                guard let stream = request.httpBodyStream else { return Data() }
                stream.open()
                defer { stream.close() }
                var data = Data()
                var bytes = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let read = stream.read(&bytes, maxLength: bytes.count)
                    if read <= 0 { break }
                    data.append(contentsOf: bytes.prefix(read))
                }
                return data
            }()
            check((try? JSONSerialization.jsonObject(with: body)) as? [String] == ["合成测试"], "Bing body is string array for new endpoint")
            return (200, [:], Data("[{\"translations\":[{\"text\":\"synthetic Bing result\"}]}]".utf8))
        }
        let bing = BingTranslator(session: mockSession)
        let bingResult = try await bing.translate(text: "合成测试", mode: .fluent, targetLanguage: .english)
        check(bingResult == "synthetic Bing result" && translationCount == 1, "Bing translates directly without token roundtrip")
        SyntheticURLProtocol.handler = { _ in (429, [:], Data()) }
        await mustThrowAsync("Bing service error is actionable failure") { _ = try await bing.translate(text: "合成测试", mode: .fluent, targetLanguage: .english) }

        let fake = DelayedTranslator()
        let scheduler = TranslationScheduler.regressionInstance(fake)
        var callbacks: [String] = []
        scheduler.onTranslationDelta = { text, _ in callbacks.append("delta:\(text)") }
        scheduler.onTranslationReady = { text, _ in callbacks.append("ready:\(text)") }
        scheduler.onTranslationFailed = { text, _ in callbacks.append("failed:\(text)") }
        scheduler.commit(text: "旧请求")
        scheduler.regressionFire()
        try await Task.sleep(nanoseconds: 10_000_000)
        scheduler.reset()
        try await Task.sleep(nanoseconds: 150_000_000)
        check(callbacks.isEmpty, "reset suppresses late delta and completion from cancellation-ignoring provider")
        scheduler.commit(text: "旧请求")
        scheduler.regressionFire()
        try await Task.sleep(nanoseconds: 10_000_000)
        scheduler.regressionPrime("旧请求新输入", "cached-final")
        scheduler.commit(text: "新输入")
        scheduler.regressionFire()
        try await Task.sleep(nanoseconds: 150_000_000)
        check(callbacks == ["ready:旧请求新输入"], "cache hit invalidates running request and queued delta")
        scheduler.reset()
        callbacks = []
        scheduler.commit(text: "模式更换")
        scheduler.regressionFire()
        try await Task.sleep(nanoseconds: 10_000_000)
        scheduler.updateTranslator()
        try await Task.sleep(nanoseconds: 150_000_000)
        check(callbacks.isEmpty, "provider replacement invalidates running request")
        scheduler.reset()
        print("\(checks) translation regression checks passed. All traffic used URLProtocol synthetic responses.")
    }
}

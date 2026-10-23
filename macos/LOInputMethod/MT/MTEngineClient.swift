import Foundation
import LOMTCore

// MARK: - 本地翻译引擎客户端

/// 管理 `LOMTEngine` 子进程：启动、JSON Lines 收发、超时、崩溃重启与空闲卸载。
/// 进程崩溃只会让当前请求失败，不影响输入法主进程。
final class MTEngineClient {

    enum ClientError: Error, LocalizedError {
        case helperMissing
        case circuitOpen
        case code(MTErrorCode, String)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing: return "本地翻译组件缺失，请重新安装输入法"
            case .circuitOpen: return "本地引擎多次异常，已暂时停用"
            case .code(_, let message): return message
            case .transport(let detail): return "本地引擎通信失败：\(detail)"
            }
        }

        var errorCode: MTErrorCode? {
            switch self {
            case .code(let code, _): return code
            case .helperMissing: return .modelNotFound
            case .circuitOpen: return .engineError
            case .transport: return .engineError
            }
        }

        var isRetryable: Bool {
            errorCode?.isRetryable ?? false
        }
    }

    static let shared = MTEngineClient()

    private let stateQueue = DispatchQueue(label: "lo.mt.engine.client")
    private let ioQueue = DispatchQueue(label: "lo.mt.engine.io")

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<MTEngineResponse, Error>] = [:]
    private var timeouts: [Int: DispatchWorkItem] = [:]
    private var consecutiveFailures = 0
    private var circuitOpen = false
    private var lastActivity = Date()
    private var idleTimer: DispatchSourceTimer?
    private var loadedModelID: String?

    /// 空闲多久后卸载模型权重（分钟）。进程本身保留，避免反复冷启动。
    var idleUnloadMinutes: Double = 10 {
        didSet { restartIdleTimer() }
    }

    private init() {}

    // MARK: - 公开接口

    func load(model: String, directory: URL) async throws {
        let response = try await send(MTEngineRequest(id: 0, op: "load", model: model,
                                                     dir: directory.path), timeoutMs: 20_000)
        guard response.ok else {
            let code = MTErrorCode(rawValue: response.code ?? "") ?? .engineError
            throw ClientError.code(code, response.message ?? "本地模型加载失败")
        }
        stateQueue.sync { loadedModelID = model }
    }

    func translate(text: String, source: String?, target: String,
                   timeoutMs: Int = 1500) async throws -> String {
        let response = try await send(MTEngineRequest(id: 0, op: "translate",
                                                     text: text, src: source, tgt: target,
                                                     timeoutMs: timeoutMs),
                                      timeoutMs: timeoutMs)
        guard response.ok, let translated = response.text else {
            let code = MTErrorCode(rawValue: response.code ?? "") ?? .engineError
            throw ClientError.code(code, response.message ?? "本地翻译失败")
        }
        return translated
    }

    /// 卸载模型权重（进程保留）
    func unload() async {
        _ = try? await send(MTEngineRequest(id: 0, op: "unload"), timeoutMs: 5_000)
        stateQueue.sync { loadedModelID = nil }
    }

    var currentModelID: String? {
        stateQueue.sync { loadedModelID }
    }

    func shutdown() {
        stateQueue.sync {
            timeouts.values.forEach { $0.cancel() }
            timeouts.removeAll()
            if let stdinHandle, let process, process.isRunning {
                stdinHandle.write(Data("{\"id\":0,\"op\":\"shutdown\"}\n".utf8))
            }
            stdinHandle = nil
            stdoutHandle = nil
            process = nil
            waiting.values.forEach { $0.resume(throwing: ClientError.transport("本地引擎已关闭")) }
            waiting.removeAll()
        }
    }

    /// 用户在设置里重新启用本地翻译时调用，解除熔断
    func resetCircuitBreaker() {
        stateQueue.sync {
            circuitOpen = false
            consecutiveFailures = 0
        }
    }

    // MARK: - 请求发送

    private func send(_ request: MTEngineRequest, timeoutMs: Int) async throws -> MTEngineResponse {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                if self.circuitOpen {
                    continuation.resume(throwing: ClientError.circuitOpen)
                    return
                }
                do {
                    try self.ensureProcessLocked()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let id = self.nextID
                self.nextID += 1
                var payload = request
                payload.id = id

                guard let handle = self.stdinHandle,
                      let data = try? JSONEncoder().encode(payload) else {
                    continuation.resume(throwing: ClientError.transport("无法编码请求"))
                    return
                }

                self.waiting[id] = continuation
                self.lastActivity = Date()

                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.stateQueue.async {
                        guard let pending = self.waiting.removeValue(forKey: id) else { return }
                        self.timeouts.removeValue(forKey: id)
                        // 超时后进程可能卡住，直接终止以便下次重启
                        self.terminateLocked()
                        pending.resume(throwing: ClientError.code(.timeout, "本地翻译超时"))
                    }
                }
                self.timeouts[id] = work
                self.stateQueue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: work)

                var line = data
                line.append(0x0A)
                do {
                    try handle.write(contentsOf: line)
                } catch {
                    self.waiting.removeValue(forKey: id)
                    self.timeouts.removeValue(forKey: id)?.cancel()
                    continuation.resume(throwing: ClientError.transport("写入本地引擎失败"))
                }
            }
        }
    }

    // MARK: - 进程生命周期

    private func ensureProcessLocked() throws {
        if let process, process.isRunning, stdinHandle != nil { return }
        terminateLocked()

        guard let helper = Self.resolveHelper() else {
            throw ClientError.helperMissing
        }

        let process = Process()
        process.executableURL = helper
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.stateQueue.async {
                self.handleProcessExitLocked()
            }
        }

        do {
            try process.run()
        } catch {
            throw ClientError.transport("无法启动本地引擎")
        }

        self.process = process
        self.stdinHandle = inputPipe.fileHandleForWriting
        self.stdoutHandle = outputPipe.fileHandleForReading
        self.buffer.removeAll(keepingCapacity: true)

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty { return }
            self.stateQueue.async {
                self.consumeLocked(data)
            }
        }

        consecutiveFailures = 0
        restartIdleTimer()
    }

    private func handleProcessExitLocked() {
        stdoutHandle?.readabilityHandler = nil
        stdinHandle = nil
        stdoutHandle = nil
        process = nil
        loadedModelID = nil

        let pending = waiting.values
        waiting.removeAll()
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        pending.forEach { $0.resume(throwing: ClientError.transport("本地引擎意外退出")) }

        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            circuitOpen = true
        }
    }

    private func terminateLocked() {
        stdoutHandle?.readabilityHandler = nil
        stdinHandle = nil
        stdoutHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        loadedModelID = nil
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: - 响应解析

    private func consumeLocked(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let response = try? JSONDecoder().decode(MTEngineResponse.self, from: Data(line)) else {
                continue
            }
            timeouts.removeValue(forKey: response.id)?.cancel()
            guard let continuation = waiting.removeValue(forKey: response.id) else { continue }
            lastActivity = Date()
            continuation.resume(returning: response)
        }
    }

    // MARK: - 空闲卸载

    private func restartIdleTimer() {
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            guard let self, self.process != nil else { return }
            let idle = Date().timeIntervalSince(self.lastActivity)
            guard idle > self.idleUnloadMinutes * 60 else { return }
            guard let handle = self.stdinHandle else { return }
            handle.write(Data("{\"id\":0,\"op\":\"unload\"}\n".utf8))
            self.loadedModelID = nil
        }
        timer.resume()
        idleTimer = timer
    }

    // MARK: - helper 定位

    static func resolveHelper() -> URL? {
        if let override = ProcessInfo.processInfo.environment["LO_MT_ENGINE_PATH"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        if let executable = Bundle.main.executableURL {
            let candidate = executable.deletingLastPathComponent().appendingPathComponent("LOMTEngine")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

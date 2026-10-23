import CryptoKit
import Foundation
import LOMTCore

// MARK: - 模型下载器

/// 按文件下载模型，支持 Range 续传、SHA-256 校验、镜像回退。
/// 全局同一时间只允许一个下载任务。
final class MTDownloader {

    enum DownloadError: Error, LocalizedError {
        case busy
        case insufficientDisk(required: Int64, available: Int64)
        case http(Int)
        case checksumMismatch(String)
        case cancelled
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .busy: return "已有模型正在下载"
            case .insufficientDisk(let required, let available):
                return "磁盘空间不足：需要 \(Self.mb(required))，可用 \(Self.mb(available))"
            case .http(let code): return "下载失败（HTTP \(code)）"
            case .checksumMismatch(let name): return "文件校验失败：\(name)"
            case .cancelled: return "下载已取消"
            case .transport(let detail): return "网络错误：\(detail)"
            }
        }

        static func mb(_ bytes: Int64) -> String {
            String(format: "%.0f MB", Double(bytes) / 1_048_576)
        }
    }

    static let shared = MTDownloader()

    private let store = MTModelStore.shared
    private let queue = DispatchQueue(label: "lo.mt.download")
    private var running = false
    private var currentDelegate: FileFetchDelegate?
    private var currentTask: URLSessionDataTask?

    private init() {}

    var isRunning: Bool {
        queue.sync { running }
    }

    func cancel() {
        queue.async {
            self.currentTask?.cancel()
            self.currentTask = nil
        }
    }

    /// 下载并安装模型。progress 回调在主线程，参数为（已下载字节, 总字节）
    func download(_ manifest: MTModelManifest,
                  progress: @escaping (Int64, Int64) -> Void) async throws {
        let alreadyRunning: Bool = queue.sync {
            if running { return true }
            running = true
            return false
        }
        if alreadyRunning { throw DownloadError.busy }
        defer { queue.sync { running = false } }

        let required = manifest.bytes * 2
        let available = store.freeDiskSpace()
        if available > 0 && available < required {
            throw DownloadError.insufficientDisk(required: required, available: available)
        }

        let destination = store.directory(for: manifest.id)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let partialDirectory = store.downloadsDirectory.appendingPathComponent(manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)

        var completed: Int64 = 0
        let total = manifest.bytes

        for file in manifest.files {
            let target = destination.appendingPathComponent(file.path)
            if (try? verify(target, sha256: file.sha256, size: file.bytes)) != nil {
                completed += file.bytes
                report(progress, completed, total)
                continue
            }
            let partial = partialDirectory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)

            var lastError: Error = DownloadError.transport("没有可用的下载源")
            var succeeded = false
            for candidate in file.urls {
                guard let url = URL(string: candidate) else { continue }
                do {
                    try await fetch(url: url, to: partial, expectedBytes: file.bytes) { received in
                        self.report(progress, completed + received, total)
                    }
                    try verify(partial, sha256: file.sha256, size: file.bytes)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.moveItem(at: partial, to: target)
                    completed += file.bytes
                    self.report(progress, completed, total)
                    succeeded = true
                    break
                } catch is CancellationError {
                    try? FileManager.default.removeItem(at: partial)
                    throw DownloadError.cancelled
                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: partial)
                }
            }
            if !succeeded { throw lastError }
        }

        let manifestURL = destination.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try Data("ok".utf8).write(to: destination.appendingPathComponent(".complete"), options: .atomic)
        store.discardPartial(manifest.id)
    }

    // MARK: - 单文件下载

    private func fetch(url: URL,
                       to destination: URL,
                       expectedBytes: Int64,
                       onProgress: @escaping (Int64) -> Void) async throws {
        var existing: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let size = attributes[.size] as? Int64 {
            existing = size
        }
        if existing >= expectedBytes, expectedBytes > 0 {
            onProgress(existing)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)

        let delegate = FileFetchDelegate(destination: destination,
                                         startOffset: existing,
                                         onProgress: onProgress)
        currentDelegate = delegate
        let task = session.dataTask(with: request)
        task.delegate = delegate
        currentTask = task
        defer { currentTask = nil; currentDelegate = nil }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - 校验

    private func verify(_ url: URL, sha256: String, size: Int64) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? Int64) ?? 0
        guard actualSize == size else {
            throw DownloadError.checksumMismatch(url.lastPathComponent)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else {
            throw DownloadError.checksumMismatch(url.lastPathComponent)
        }
    }

    private func report(_ progress: @escaping (Int64, Int64) -> Void, _ done: Int64, _ total: Int64) {
        DispatchQueue.main.async { progress(done, total) }
    }
}

// MARK: - 流式写入

private final class FileFetchDelegate: NSObject, URLSessionDataDelegate {

    let destination: URL
    let startOffset: Int64
    let onProgress: (Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>?

    private var handle: FileHandle?
    private var received: Int64
    private var finished = false

    init(destination: URL, startOffset: Int64, onProgress: @escaping (Int64) -> Void) {
        self.destination = destination
        self.startOffset = startOffset
        self.onProgress = onProgress
        self.received = startOffset
        super.init()
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: destination)
        if startOffset == 0 {
            try? handle?.truncate(atOffset: 0)
        } else {
            try? handle?.seekToEnd()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse,
           http.statusCode != 200 && http.statusCode != 206 {
            finish(.failure(MTDownloader.DownloadError.http(http.statusCode)))
            completionHandler(.cancel)
            return
        }
        // 服务端忽略 Range 时从头写入
        if let http = response as? HTTPURLResponse, http.statusCode == 200, startOffset > 0 {
            try? handle?.truncate(atOffset: 0)
            try? handle?.seek(toOffset: 0)
            received = 0
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handle?.write(data)
        received += Int64(data.count)
        onProgress(received)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            finish(.failure(CancellationError()))
        } else if let error {
            finish(.failure(MTDownloader.DownloadError.transport(error.localizedDescription)))
        } else {
            finish(.success(()))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        try? handle?.close()
        handle = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}

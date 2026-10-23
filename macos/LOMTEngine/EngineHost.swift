import Foundation
import LOMTCore

// MARK: - 请求分发
//
// 轻量档的中→日/法/德… 需要「中→英 → 英→目标」两步，
// 因此最多同时驻留两个语言包；切换目标时按最久未使用淘汰。

final class EngineHost {

    private var engines: [String: ONNXEngine] = [:]
    private var residentOrder: [String] = []
    private let residentLimit = 2

    private var loadedModelID: String?
    private var totalRequests = 0
    private var totalMilliseconds = 0
    private(set) var shouldExit = false

    func handle(_ request: MTEngineRequest) -> MTEngineResponse {
        switch request.op {
        case "hello":
            return MTEngineResponse(id: request.id, ok: true,
                                    engine: "onnx",
                                    protocolVersion: MTProtocolVersion.current,
                                    engines: ["onnx"],
                                    arch: Self.architecture,
                                    ramBytes: Self.physicalMemory)

        case "load":
            return load(request)

        case "unload":
            engines.removeAll()
            residentOrder.removeAll()
            loadedModelID = nil
            return MTEngineResponse(id: request.id, ok: true, loaded: false)

        case "translate":
            return translate(request)

        case "stats":
            let average = totalRequests > 0 ? totalMilliseconds / totalRequests : 0
            return MTEngineResponse(id: request.id, ok: true,
                                    model: loadedModelID,
                                    loaded: !engines.isEmpty,
                                    requests: totalRequests,
                                    avgMs: average)

        case "shutdown":
            engines.removeAll()
            residentOrder.removeAll()
            loadedModelID = nil
            shouldExit = true
            return MTEngineResponse(id: request.id, ok: true)

        default:
            return .failure(id: request.id, code: .engineError, message: "未知操作：\(request.op)")
        }
    }

    // MARK: - 加载

    private func load(_ request: MTEngineRequest) -> MTEngineResponse {
        guard let directory = request.dir, !directory.isEmpty else {
            return .failure(id: request.id, code: .modelNotFound, message: "缺少模型目录")
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(MTModelManifest.self, from: data) else {
            return .failure(id: request.id, code: .modelCorrupt, message: "manifest.json 缺失或损坏")
        }
        if let model = request.model, !model.isEmpty, model != manifest.id {
            return .failure(id: request.id, code: .protocolMismatch,
                            message: "请求的模型 \(model) 与目录中的 \(manifest.id) 不一致")
        }

        if engines[manifest.id] != nil {
            loadedModelID = manifest.id
            touch(manifest.id)
            return MTEngineResponse(id: request.id, ok: true,
                                    ms: 0, engine: "onnx", model: manifest.id, loaded: true)
        }

        let started = Date()
        do {
            // 超出驻留上限时淘汰最久未使用的语言包
            while engines.count >= residentLimit, let oldest = residentOrder.first {
                residentOrder.removeFirst()
                engines.removeValue(forKey: oldest)
            }
            let created = try ONNXEngine(manifest: manifest, directory: url)
            engines[manifest.id] = created
            residentOrder.append(manifest.id)
            loadedModelID = manifest.id
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            return MTEngineResponse(id: request.id, ok: true,
                                    ms: elapsed, engine: "onnx", model: manifest.id, loaded: true)
        } catch {
            return .failure(id: request.id, code: .modelCorrupt,
                            message: error.localizedDescription)
        }
    }

    // MARK: - 翻译

    private func translate(_ request: MTEngineRequest) -> MTEngineResponse {
        let modelID = (request.model?.isEmpty == false ? request.model : nil) ?? loadedModelID
        guard let modelID, let engine = engines[modelID] else {
            return .failure(id: request.id, code: .modelNotFound, message: "尚未加载本地模型")
        }
        guard let text = request.text, !text.isEmpty else {
            return .failure(id: request.id, code: .engineError, message: "待翻译文本为空")
        }
        loadedModelID = modelID
        touch(modelID)

        let started = Date()
        do {
            let result = try engine.translate(text, src: request.src, tgt: request.tgt)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            totalRequests += 1
            totalMilliseconds += elapsed
            return MTEngineResponse(id: request.id, ok: true, text: result,
                                    ms: elapsed, engine: "onnx", model: modelID)
        } catch {
            return .failure(id: request.id, code: .engineError,
                            message: error.localizedDescription)
        }
    }

    private func touch(_ id: String) {
        residentOrder.removeAll { $0 == id }
        residentOrder.append(id)
    }

    // MARK: - 环境信息

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static var physicalMemory: Int64 {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return value
    }
}

import COrtBridge
import Foundation
import LOMTCore

// MARK: - ONNX 推理引擎
//
// 两种模型族共用一个 C 桥接：
// - opus-mt（Marian）：SentencePiece + vocab.json，解码从 <pad> 开始；
// - m2m100：BPE + 目标语言标记，解码从 __xx__ 开始。

final class ONNXEngine {

    enum EngineError: Error, LocalizedError {
        case load(String)
        case inference(String)

        var errorDescription: String? {
            switch self {
            case .load(let detail): return "本地模型加载失败：\(detail)"
            case .inference(let detail): return "本地翻译推理失败：\(detail)"
            }
        }
    }

    private var handle: OpaquePointer?
    private let manifest: MTModelManifest
    private let source: SentencePieceModel?
    private let target: SentencePieceModel?
    private let bpe: BPETokenizer?

    init(manifest: MTModelManifest, directory: URL) throws {
        self.manifest = manifest

        if manifest.engine == "onnx-m2m100" {
            guard let name = manifest.tokenizer, !name.isEmpty else {
                throw EngineError.load("缺少 tokenizer.json")
            }
            self.bpe = try BPETokenizer(tokenizerURL: directory.appendingPathComponent(name))
            self.source = nil
            self.target = nil
        } else {
            self.bpe = nil
            self.source = try SentencePieceModel(
                spmURL: directory.appendingPathComponent(manifest.sourceSpm),
                vocabURL: directory.appendingPathComponent(manifest.vocab))
            self.target = try SentencePieceModel(
                spmURL: directory.appendingPathComponent(manifest.targetSpm),
                vocabURL: directory.appendingPathComponent(manifest.vocab))
        }

        let encoder = directory.appendingPathComponent(manifest.encoder).path
        let decoder = directory.appendingPathComponent(manifest.decoder).path
        var error: UnsafeMutablePointer<CChar>?
        let created = encoder.withCString { encoderPath in
            decoder.withCString { decoderPath in
                lo_engine_create(encoderPath, decoderPath, &error)
            }
        }
        guard let created else {
            let message = error.map { String(cString: $0) } ?? "未知错误"
            if let error { lo_engine_free_string(error) }
            throw EngineError.load(message)
        }
        self.handle = created
    }

    deinit {
        if let handle { lo_engine_destroy(handle) }
    }

    var identifier: String { manifest.id }

    /// 翻译一段文本。src/tgt 仅用于校验与语言选择，实际方向由模型决定。
    func translate(_ text: String, src: String?, tgt: String?) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let limit = max(8, min(manifest.maxNewTokens, trimmed.count * 4 + 16))

        if let bpe {
            let code = BPETokenizer.languageCode(tgt ?? manifest.tgt)
            guard let languageID = bpe.languageToken(for: code) else {
                throw EngineError.inference("本地多语模型不支持目标语言：\(code)")
            }
            let sourceIDs = bpe.encode(trimmed)
            guard !sourceIDs.isEmpty else { return "" }
            let produced = try run(sourceIDs: sourceIDs,
                                   eosID: bpe.eosId,
                                   startTokens: [Int64(bpe.eosId), Int64(languageID)],
                                   stopID: bpe.eosId,
                                   limit: limit)
            return bpe.decode(produced)
        }

        guard let source, let target else {
            throw EngineError.inference("分词器未初始化")
        }
        if let src, !src.isEmpty, src != "auto", src != manifest.src {
            throw EngineError.inference("模型方向不匹配（需要 \(manifest.src)→\(manifest.tgt)）")
        }
        if let tgt, !tgt.isEmpty, tgt != manifest.tgt {
            throw EngineError.inference("模型方向不匹配（需要 \(manifest.src)→\(manifest.tgt)）")
        }

        let sourceIDs = source.encode(trimmed)
        guard !sourceIDs.isEmpty else { return "" }
        let produced = try run(sourceIDs: sourceIDs,
                               eosID: source.eosId,
                               startTokens: [Int64(source.padId)],
                               stopID: source.eosId,
                               limit: limit)
        return target.decode(produced)
    }

    // MARK: - 编码 + 贪心解码

    private func run(sourceIDs: [Int],
                     eosID: Int,
                     startTokens: [Int64],
                     stopID: Int,
                     limit: Int) throws -> [Int] {
        var ids = sourceIDs.map(Int64.init)
        guard !ids.isEmpty else { return [] }
        ids.append(Int64(eosID))

        var hidden: UnsafeMutablePointer<Float>?
        var encodedLength: Int32 = 0
        var hiddenDimension: Int32 = 0
        var error: UnsafeMutablePointer<CChar>?

        let encodeResult: Int32 = ids.withUnsafeBufferPointer { buffer in
            lo_engine_encode(handle, buffer.baseAddress, Int32(buffer.count),
                             &hidden, &encodedLength, &hiddenDimension, &error)
        }
        guard encodeResult == 0, let hidden else {
            let message = error.map { String(cString: $0) } ?? "编码失败"
            if let error { lo_engine_free_string(error) }
            throw EngineError.inference(message)
        }
        defer { lo_engine_free_buffer(hidden) }

        var tokens = startTokens
        var produced: [Int] = []

        for _ in 0..<limit {
            var logits: UnsafeMutablePointer<Float>?
            var vocabulary: Int32 = 0
            var decodeError: UnsafeMutablePointer<CChar>?
            let decodeResult: Int32 = tokens.withUnsafeBufferPointer { buffer in
                lo_engine_decode(handle, buffer.baseAddress, Int32(buffer.count),
                                 hidden, encodedLength, &logits, &vocabulary, &decodeError)
            }
            guard decodeResult == 0, let logits else {
                let message = decodeError.map { String(cString: $0) } ?? "解码失败"
                if let decodeError { lo_engine_free_string(decodeError) }
                throw EngineError.inference(message)
            }
            let count = Int(vocabulary)
            var bestIndex = 0
            var bestValue = -Float.infinity
            for index in 0..<count where logits[index] > bestValue {
                bestValue = logits[index]
                bestIndex = index
            }
            lo_engine_free_buffer(logits)

            if bestIndex == stopID { break }
            produced.append(bestIndex)
            tokens.append(Int64(bestIndex))
        }

        return produced
    }
}

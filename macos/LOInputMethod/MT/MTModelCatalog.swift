import Foundation
import LOMTCore

// MARK: - 模型目录
//
// 本地翻译分三个档位，模型都不随安装包分发：
// - 轻量：OPUS-MT 按方向分发，首发只提供「中 → 英」，约 111 MB；
// - 多语：M2M100-418M 一个包覆盖 100 种语言互译，约 630 MB；
// - 高质量：Hy-MT2-1.8B（GGUF），当前只提供下载入口，推理随后续版本接入。

enum MTModelCatalog {

    /// 轻量档语言包（按方向一个包）
    struct Pack {
        let id: String
        let source: String
        let target: String
        let sourceName: String
        let targetName: String
        let xenovaRepo: String
        let helsinkiRepo: String
    }

    // MARK: - 轻量档

    static let packs: [Pack] = [
        Pack(id: "opus-mt-zh-en", source: "zh", target: "en",
             sourceName: "中文", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-zh-en", helsinkiRepo: "Helsinki-NLP/opus-mt-zh-en")
    ]

    /// 语言包估算体积（encoder + decoder + 分词资源）
    static let estimatedBytes: Int64 = 115_970_953

    private static let encoderBytes: Int64 = 52_899_742
    private static let decoderBytes: Int64 = 59_842_102

    private static let verifiedSizes: [String: (vocab: Int64, source: Int64, target: Int64)] = [
        "opus-mt-zh-en": (1_617_902, 804_677, 806_530)
    ]

    private static let verifiedHashes: [String: (encoder: String, decoder: String, vocab: String, source: String, target: String)] = [
        "opus-mt-zh-en": (
            "84d5e171b626bc8b6b220d022ac58696e9528c25deeacca62b5cbf4364547a99",
            "debcc3054b9ff9aaed972bd6e251a459abe1e2f1402da1efa63163dc2f46ef73",
            "c0f79ee4c413ccb24cd808a0c727eec85b2130f23c82802cc1caeb07b5f0d458",
            "e27a3a1b539f4959ec72ea60e453f49156289f95d4e6000b29332efc45616203",
            "6a881f4717cd7265f53fea54fd3dc689c767c05338fac7a4590f3088cb2d7855")
    ]

    private static func urls(_ repo: String, _ path: String) -> [String] {
        [
            "https://huggingface.co/\(repo)/resolve/main/\(path)",
            "https://hf-mirror.com/\(repo)/resolve/main/\(path)"
        ]
    }

    /// 生成一个语言包的 manifest
    static func manifest(for pack: Pack) -> MTModelManifest {
        let sizes = verifiedSizes[pack.id]
        let hashes = verifiedHashes[pack.id]
        let total = sizes.map { encoderBytes + decoderBytes + $0.vocab + $0.source + $0.target }
            ?? estimatedBytes

        func file(_ name: String,
                  bytes: Int64,
                  hash: String?,
                  repo: String,
                  remotePath: String) -> MTModelFile {
            MTModelFile(path: name, bytes: bytes, sha256: hash, urls: urls(repo, remotePath))
        }

        return MTModelManifest(
            id: pack.id,
            displayName: "\u{2066}\(pack.sourceName) → \(pack.targetName)\u{2067}",
            tier: "light",
            src: pack.source,
            tgt: pack.target,
            bytes: total,
            licenseName: "Apache-2.0 / CC-BY-4.0",
            licenseURL: "https://huggingface.co/\(pack.helsinkiRepo)",
            attribution: "Helsinki-NLP OPUS-MT",
            encoder: "encoder_model_quantized.onnx",
            decoder: "decoder_model_quantized.onnx",
            vocab: "vocab.json",
            sourceSpm: "source.spm",
            targetSpm: "target.spm",
            maxNewTokens: 256,
            files: [
                file("encoder_model_quantized.onnx", bytes: encoderBytes,
                     hash: hashes?.encoder, repo: pack.xenovaRepo,
                     remotePath: "onnx/encoder_model_quantized.onnx"),
                file("decoder_model_quantized.onnx", bytes: decoderBytes,
                     hash: hashes?.decoder, repo: pack.xenovaRepo,
                     remotePath: "onnx/decoder_model_quantized.onnx"),
                file("vocab.json", bytes: sizes?.vocab ?? 0,
                     hash: hashes?.vocab, repo: pack.helsinkiRepo,
                     remotePath: "vocab.json"),
                file("source.spm", bytes: sizes?.source ?? 0,
                     hash: hashes?.source, repo: pack.helsinkiRepo,
                     remotePath: "source.spm"),
                file("target.spm", bytes: sizes?.target ?? 0,
                     hash: hashes?.target, repo: pack.helsinkiRepo,
                     remotePath: "target.spm")
            ])
    }

    /// 轻量档全部语言包（设置页展示）
    static let lightModels: [MTModelManifest] = packs.map(manifest(for:))

    // MARK: - 多语档（M2M100-418M）

    static let multiModelID = "m2m100-418m"

    static let multiModel: MTModelManifest = {
        let encoder: Int64 = 287_856_370
        let decoder: Int64 = 339_181_945
        let tokenizer: Int64 = 7_988_527
        let repo = "Xenova/m2m100_418M"
        return MTModelManifest(
            id: multiModelID,
            displayName: "多语翻译 · M2M100 418M",
            tier: "multi",
            engine: "onnx-m2m100",
            src: "multi",
            tgt: "multi",
            bytes: encoder + decoder + tokenizer,
            minRAMBytes: 8 * 1024 * 1024 * 1024,
            licenseName: "MIT",
            licenseURL: "https://huggingface.co/facebook/m2m100_418M",
            attribution: "M2M100 · Meta AI，ONNX 量化版由 Xenova 提供",
            encoder: "encoder_model_quantized.onnx",
            decoder: "decoder_model_quantized.onnx",
            vocab: "",
            sourceSpm: "",
            targetSpm: "",
            tokenizer: "tokenizer.json",
            maxNewTokens: 256,
            files: [
                MTModelFile(path: "encoder_model_quantized.onnx", bytes: encoder,
                            sha256: "13a94e354a9140764eb81102d77d3ec6952d796e6f113c651eeb3c3443da0386",
                            urls: urls(repo, "onnx/encoder_model_quantized.onnx")),
                MTModelFile(path: "decoder_model_quantized.onnx", bytes: decoder,
                            sha256: "6015e31c8976659aedb06058c4dadf0f400d087a3f9830f838e68f220d79bcb6",
                            urls: urls(repo, "onnx/decoder_model_quantized.onnx")),
                MTModelFile(path: "tokenizer.json", bytes: tokenizer,
                            sha256: "03d9e111731c2d71f39a2c2a88499743e4c251385d07f0384b4349a23ba54363",
                            urls: urls(repo, "tokenizer.json"))
            ])
    }()

    // MARK: - 高质量档（Hy-MT2-1.8B，仅下载）

    static let qualityModelID = "hy-mt2-1.8b-q4"

    static let qualityModel: MTModelManifest = {
        let size: Int64 = 1_133_080_448
        let repo = "tencent/Hy-MT2-1.8B-GGUF"
        return MTModelManifest(
            id: qualityModelID,
            displayName: "高质量翻译 · Hy-MT2 1.8B",
            tier: "quality",
            engine: "gguf",
            src: "multi",
            tgt: "multi",
            bytes: size,
            minRAMBytes: 16 * 1024 * 1024 * 1024,
            licenseName: "Apache-2.0",
            licenseURL: "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF",
            attribution: "Tencent Hunyuan Hy-MT2",
            encoder: "",
            decoder: "",
            vocab: "",
            sourceSpm: "",
            targetSpm: "",
            maxNewTokens: 256,
            files: [
                MTModelFile(path: "Hy-MT2-1.8B-Q4_K_M.gguf", bytes: size,
                            sha256: "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699",
                            urls: urls(repo, "Hy-MT2-1.8B-Q4_K_M.gguf"))
            ])
    }()

    // MARK: - 查询

    static func pack(withID id: String) -> Pack? {
        packs.first { $0.id == id }
    }

    static func manifest(forSource src: String, target: String) -> MTModelManifest? {
        let wanted = normalized(target)
        guard let pack = packs.first(where: { $0.source == src && normalized($0.target) == wanted }) else {
            return nil
        }
        return manifest(for: pack)
    }

    static func normalized(_ language: String) -> String {
        switch language {
        case "zh-Hans", "zh-Hant", "zh_CN", "zh_TW", "zh": return "zh"
        case "ja-JP": return "ja"
        case "ko-KR": return "ko"
        default: return String(language.prefix(2)).lowercased()
        }
    }

    /// 统一的体积文案（与磁盘占用一致，1 MB = 1048576 字节）
    static func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1000 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

import Foundation
import LOMTCore

// MARK: - 模型目录
//
// 轻量档按语言方向分发 OPUS-MT（ONNX INT8），模型都不随安装包分发。
// 目前开放的中文直译 ONNX 模型只有「中 → 英」，因此本地档只提供该方向；
// 其他目标语言继续使用在线翻译。

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
        let verified: Bool
    }

    // MARK: - 语言包

    static let packs: [Pack] = [
        Pack(id: "opus-mt-zh-en", source: "zh", target: "en",
             sourceName: "中文", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-zh-en", helsinkiRepo: "Helsinki-NLP/opus-mt-zh-en",
             verified: true)
    ]

    private static let verifiedSizes: [String: (encoder: Int64, decoder: Int64,
                                              vocab: Int64, source: Int64, target: Int64)] = [
        "opus-mt-zh-en": (52_899_742, 59_842_102, 1_617_902, 804_677, 806_530)
    ]

    private static let verifiedHashes: [String: (encoder: String, decoder: String, vocab: String, source: String, target: String)] = [
        "opus-mt-zh-en": (
            "84d5e171b626bc8b6b220d022ac58696e9528c25deeacca62b5cbf4364547a99",
            "debcc3054b9ff9aaed972bd6e251a459abe1e2f1402da1efa63163dc2f46ef73",
            "c0f79ee4c413ccb24cd808a0c727eec85b2130f23c82802cc1caeb07b5f0d458",
            "e27a3a1b539f4959ec72ea60e453f49156289f95d4e6000b29332efc45616203",
            "6a881f4717cd7265f53fea54fd3dc689c767c05338fac7a4590f3088cb2d7855")
    ]

    /// 下载源顺序：ModelScope（国内最快）→ HF 镜像 → HuggingFace
    private static func urls(_ repo: String, _ path: String) -> [String] {
        let escaped = path.replacingOccurrences(of: "/", with: "%2F")
        return [
            "https://modelscope.cn/api/v1/models/\(repo)/repo?Revision=master&FilePath=\(escaped)",
            "https://hf-mirror.com/\(repo)/resolve/main/\(path)",
            "https://huggingface.co/\(repo)/resolve/main/\(path)"
        ]
    }

    static func manifest(for pack: Pack) -> MTModelManifest {
        let sizes = verifiedSizes[pack.id]
        let hashes = verifiedHashes[pack.id]
        let total = sizes.map { $0.encoder + $0.decoder + $0.vocab + $0.source + $0.target } ?? 0

        func file(_ name: String, bytes: Int64, hash: String?,
                  repo: String, remotePath: String) -> MTModelFile {
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
                file("encoder_model_quantized.onnx", bytes: sizes?.encoder ?? 0,
                     hash: hashes?.encoder, repo: pack.xenovaRepo,
                     remotePath: "onnx/encoder_model_quantized.onnx"),
                file("decoder_model_quantized.onnx", bytes: sizes?.decoder ?? 0,
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

    static let lightModels: [MTModelManifest] = packs.map(manifest(for:))

    // MARK: - 目标语言与所需语言包

    /// 设置页展示：目标语言需要的语言包（中文直译，最多一个）
    static func packs(forTarget target: String) -> [MTModelManifest] {
        guard let manifest = manifest(forSource: "zh", target: target) else { return [] }
        return [manifest]
    }

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

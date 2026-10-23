import Foundation
import LOMTCore

// MARK: - 语言包目录
//
// 轻量档按「语言包」分发：每个包是一个方向的 OPUS-MT 模型（ONNX INT8）。
// 模型不随安装包分发，用户在设置里按需下载。
//
// 已校验（SHA-256）的两个中英方向优先保证完整性；其余方向使用
// HTTPS + 下载后大小/分词文件校验，首次加载失败会在设置页明确提示。

enum MTModelCatalog {

    /// 语言包描述（UI 展示 + 生成 manifest）
    struct Pack {
        let id: String
        let source: String
        let target: String
        let sourceName: String
        let targetName: String
        let xenovaRepo: String
        let helsinkiRepo: String
        /// 已验证的语言包：文件大小与 SHA-256
        let verified: Bool
    }

    // MARK: - 目录

    static let packs: [Pack] = [
        Pack(id: "opus-mt-zh-en", source: "zh", target: "en",
             sourceName: "中文", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-zh-en", helsinkiRepo: "Helsinki-NLP/opus-mt-zh-en",
             verified: true),
        Pack(id: "opus-mt-en-zh", source: "en", target: "zh",
             sourceName: "English", targetName: "中文",
             xenovaRepo: "Xenova/opus-mt-en-zh", helsinkiRepo: "Helsinki-NLP/opus-mt-en-zh",
             verified: true),
        Pack(id: "opus-mt-en-jap", source: "en", target: "ja",
             sourceName: "English", targetName: "日本語",
             xenovaRepo: "Xenova/opus-mt-en-jap", helsinkiRepo: "Helsinki-NLP/opus-mt-en-jap",
             verified: false),
        Pack(id: "opus-mt-ja-en", source: "ja", target: "en",
             sourceName: "日本語", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-ja-en", helsinkiRepo: "Helsinki-NLP/opus-mt-ja-en",
             verified: false),
        Pack(id: "opus-mt-ko-en", source: "ko", target: "en",
             sourceName: "한국어", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-ko-en", helsinkiRepo: "Helsinki-NLP/opus-mt-ko-en",
             verified: false),
        Pack(id: "opus-mt-en-fr", source: "en", target: "fr",
             sourceName: "English", targetName: "Français",
             xenovaRepo: "Xenova/opus-mt-en-fr", helsinkiRepo: "Helsinki-NLP/opus-mt-en-fr",
             verified: false),
        Pack(id: "opus-mt-fr-en", source: "fr", target: "en",
             sourceName: "Français", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-fr-en", helsinkiRepo: "Helsinki-NLP/opus-mt-fr-en",
             verified: false),
        Pack(id: "opus-mt-en-de", source: "en", target: "de",
             sourceName: "English", targetName: "Deutsch",
             xenovaRepo: "Xenova/opus-mt-en-de", helsinkiRepo: "Helsinki-NLP/opus-mt-en-de",
             verified: false),
        Pack(id: "opus-mt-de-en", source: "de", target: "en",
             sourceName: "Deutsch", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-de-en", helsinkiRepo: "Helsinki-NLP/opus-mt-de-en",
             verified: false),
        Pack(id: "opus-mt-en-es", source: "en", target: "es",
             sourceName: "English", targetName: "Español",
             xenovaRepo: "Xenova/opus-mt-en-es", helsinkiRepo: "Helsinki-NLP/opus-mt-en-es",
             verified: false),
        Pack(id: "opus-mt-es-en", source: "es", target: "en",
             sourceName: "Español", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-es-en", helsinkiRepo: "Helsinki-NLP/opus-mt-es-en",
             verified: false),
        Pack(id: "opus-mt-en-ru", source: "en", target: "ru",
             sourceName: "English", targetName: "Русский",
             xenovaRepo: "Xenova/opus-mt-en-ru", helsinkiRepo: "Helsinki-NLP/opus-mt-en-ru",
             verified: false),
        Pack(id: "opus-mt-ru-en", source: "ru", target: "en",
             sourceName: "Русский", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-ru-en", helsinkiRepo: "Helsinki-NLP/opus-mt-ru-en",
             verified: false),
        Pack(id: "opus-mt-en-ar", source: "en", target: "ar",
             sourceName: "English", targetName: "العربية",
             xenovaRepo: "Xenova/opus-mt-en-ar", helsinkiRepo: "Helsinki-NLP/opus-mt-en-ar",
             verified: false),
        Pack(id: "opus-mt-ar-en", source: "ar", target: "en",
             sourceName: "العربية", targetName: "English",
             xenovaRepo: "Xenova/opus-mt-ar-en", helsinkiRepo: "Helsinki-NLP/opus-mt-ar-en",
             verified: false)
    ]

    /// 语言包估算体积（encoder + decoder + 分词资源）
    static let estimatedBytes: Int64 = 115_970_953

    private static let encoderBytes: Int64 = 52_899_742
    private static let decoderBytes: Int64 = 59_842_102

    private static let verifiedSizes: [String: (vocab: Int64, source: Int64, target: Int64)] = [
        "opus-mt-zh-en": (1_617_902, 804_677, 806_530),
        "opus-mt-en-zh": (1_617_791, 806_435, 804_600)
    ]

    private static let verifiedHashes: [String: (encoder: String, decoder: String, vocab: String, source: String, target: String)] = [
        "opus-mt-zh-en": (
            "84d5e171b626bc8b6b220d022ac58696e9528c25deeacca62b5cbf4364547a99",
            "debcc3054b9ff9aaed972bd6e251a459abe1e2f1402da1efa63163dc2f46ef73",
            "c0f79ee4c413ccb24cd808a0c727eec85b2130f23c82802cc1caeb07b5f0d458",
            "e27a3a1b539f4959ec72ea60e453f49156289f95d4e6000b29332efc45616203",
            "6a881f4717cd7265f53fea54fd3dc689c767c05338fac7a4590f3088cb2d7855"),
        "opus-mt-en-zh": (
            "d3b7912bf6a9bd27e4c074c2df91d4ff3d5b4bc5f7f6c8d7cc9c805c98fbafee",
            "2c66a3981099b40edbb3a0d65e015d05964d42fecb9780f8422776eff5939112",
            "f1832ca38f7aa158b9a944ff583e4901e6b37d9d4ad9241f03838e636e9cfb03",
            "5775ddc9e3ff2fae91554da56468ad35ff56edaba870fea74447bc7234bfdaa8",
            "81dc94efa84e4025ef38d25d5d07429fe41e3eb29d44003f1db6fe98487b0052")
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
        let total: Int64
        if let sizes {
            total = encoderBytes + decoderBytes + sizes.vocab + sizes.source + sizes.target
        } else {
            total = estimatedBytes
        }

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

    /// 全部语言包（设置页展示）
    static let lightModels: [MTModelManifest] = packs.map(manifest(for:))

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
}

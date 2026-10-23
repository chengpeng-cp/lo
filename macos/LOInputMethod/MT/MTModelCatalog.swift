import Foundation
import LOMTCore

// MARK: - 模型目录
//
// 轻量档按语言方向分发 OPUS-MT（ONNX INT8），模型都不随安装包分发。
// 由于开放的中文直译模型有限，除「中 → 英」外的目标语言通过英语中转：
// 中文 → English → 目标语言，因此需要中→英和英→目标两个语言包。

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
             verified: true),
        Pack(id: "opus-mt-en-zh", source: "en", target: "zh",
             sourceName: "English", targetName: "中文",
             xenovaRepo: "Xenova/opus-mt-en-zh", helsinkiRepo: "Helsinki-NLP/opus-mt-en-zh",
             verified: true),
        Pack(id: "opus-mt-en-jap", source: "en", target: "ja",
             sourceName: "English", targetName: "日本語",
             xenovaRepo: "Xenova/opus-mt-en-jap", helsinkiRepo: "Helsinki-NLP/opus-mt-en-jap",
             verified: false),
        Pack(id: "opus-mt-en-fr", source: "en", target: "fr",
             sourceName: "English", targetName: "Français",
             xenovaRepo: "Xenova/opus-mt-en-fr", helsinkiRepo: "Helsinki-NLP/opus-mt-en-fr",
             verified: false),
        Pack(id: "opus-mt-en-de", source: "en", target: "de",
             sourceName: "English", targetName: "Deutsch",
             xenovaRepo: "Xenova/opus-mt-en-de", helsinkiRepo: "Helsinki-NLP/opus-mt-en-de",
             verified: false),
        Pack(id: "opus-mt-en-es", source: "en", target: "es",
             sourceName: "English", targetName: "Español",
             xenovaRepo: "Xenova/opus-mt-en-es", helsinkiRepo: "Helsinki-NLP/opus-mt-en-es",
             verified: false),
        Pack(id: "opus-mt-en-ru", source: "en", target: "ru",
             sourceName: "English", targetName: "Русский",
             xenovaRepo: "Xenova/opus-mt-en-ru", helsinkiRepo: "Helsinki-NLP/opus-mt-en-ru",
             verified: false),
        Pack(id: "opus-mt-en-ar", source: "en", target: "ar",
             sourceName: "English", targetName: "العربية",
             xenovaRepo: "Xenova/opus-mt-en-ar", helsinkiRepo: "Helsinki-NLP/opus-mt-en-ar",
             verified: false)
    ]

    /// 未校验语言包的估算体积
    static let estimatedBytes: Int64 = 116_000_000

    private static let verifiedSizes: [String: (encoder: Int64, decoder: Int64,
                                              vocab: Int64, source: Int64, target: Int64)] = [
        "opus-mt-zh-en": (52_899_742, 59_842_102, 1_617_902, 804_677, 806_530),
        "opus-mt-en-zh": (52_899_742, 59_842_102, 1_617_791, 806_435, 804_600)
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

    static func manifest(for pack: Pack) -> MTModelManifest {
        let sizes = verifiedSizes[pack.id]
        let hashes = verifiedHashes[pack.id]
        let total = sizes.map { $0.encoder + $0.decoder + $0.vocab + $0.source + $0.target }
            ?? estimatedBytes

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

    /// 轻量档支持的目标语言（与 `MTLanguageCatalog.lightCodes` 保持一致）
    private static let lightRoutes: [String: [String]] = [
        "en": ["opus-mt-zh-en"],
        "zh": ["opus-mt-en-zh"],
        "ja": ["opus-mt-zh-en", "opus-mt-en-jap"],
        "fr": ["opus-mt-zh-en", "opus-mt-en-fr"],
        "de": ["opus-mt-zh-en", "opus-mt-en-de"],
        "es": ["opus-mt-zh-en", "opus-mt-en-es"],
        "ru": ["opus-mt-zh-en", "opus-mt-en-ru"],
        "ar": ["opus-mt-zh-en", "opus-mt-en-ar"]
    ]

    /// 设置页展示：目标语言需要的语言包（按执行顺序）
    static func packs(forTarget target: String) -> [MTModelManifest] {
        let code = normalized(target)
        let ids = lightRoutes[code] ?? []
        return ids.compactMap { id in packs.first { $0.id == id } }.map(manifest(for:))
    }

    /// 运行时路由：优先直达，其次经英语中转；返回空表示不支持
    static func route(forSource src: String, target: String) -> [MTModelManifest] {
        if let direct = manifest(forSource: src, target: target) { return [direct] }
        guard src != "en" else { return [] }
        let code = normalized(target)
        guard code != "en" else { return [] }
        guard let first = manifest(forSource: src, target: "en"),
              let second = manifest(forSource: "en", target: target) else { return [] }
        return [first, second]
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

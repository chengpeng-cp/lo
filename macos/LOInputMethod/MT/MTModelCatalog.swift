import Foundation
import LOMTCore

// MARK: - 内置模型目录
//
// 第一版只提供中↔英两个方向的轻量模型（OPUS-MT，ONNX INT8）。
// 模型不随安装包分发：用户点「下载」时按文件从 HuggingFace / 镜像获取，
// 下载完成后校验 SHA-256，再写入 manifest.json 与 .complete 标记。
//
// 新增语言对时只需在此追加一条 spec，并在设置页读取目录即可。

enum MTModelCatalog {

    /// 每个文件的下载源：官方源优先，镜像兜底
    private static func urls(_ repo: String, _ path: String) -> [String] {
        [
            "https://huggingface.co/\(repo)/resolve/main/\(path)",
            "https://hf-mirror.com/\(repo)/resolve/main/\(path)"
        ]
    }

    private static func file(_ path: String,
                             bytes: Int64,
                             sha256: String,
                             repo: String,
                             remotePath: String? = nil) -> MTModelFile {
        MTModelFile(path: path, bytes: bytes, sha256: sha256,
                    urls: urls(repo, remotePath ?? path))
    }

    static let zhToEn = MTModelManifest(
        id: "opus-mt-zh-en",
        displayName: "中文 → English",
        tier: "light",
        src: "zh",
        tgt: "en",
        bytes: 52_899_742 + 59_842_102 + 1_617_902 + 804_677 + 806_530,
        licenseName: "CC-BY-4.0",
        licenseURL: "https://huggingface.co/Helsinki-NLP/opus-mt-zh-en",
        attribution: "Helsinki-NLP OPUS-MT（CC-BY-4.0）",
        encoder: "encoder_model_quantized.onnx",
        decoder: "decoder_model_quantized.onnx",
        vocab: "vocab.json",
        sourceSpm: "source.spm",
        targetSpm: "target.spm",
        maxNewTokens: 256,
        files: [
            file("encoder_model_quantized.onnx", bytes: 52_899_742,
                 sha256: "84d5e171b626bc8b6b220d022ac58696e9528c25deeacca62b5cbf4364547a99",
                 repo: "Xenova/opus-mt-zh-en", remotePath: "onnx/encoder_model_quantized.onnx"),
            file("decoder_model_quantized.onnx", bytes: 59_842_102,
                 sha256: "debcc3054b9ff9aaed972bd6e251a459abe1e2f1402da1efa63163dc2f46ef73",
                 repo: "Xenova/opus-mt-zh-en", remotePath: "onnx/decoder_model_quantized.onnx"),
            file("vocab.json", bytes: 1_617_902,
                 sha256: "c0f79ee4c413ccb24cd808a0c727eec85b2130f23c82802cc1caeb07b5f0d458",
                 repo: "Helsinki-NLP/opus-mt-zh-en"),
            file("source.spm", bytes: 804_677,
                 sha256: "e27a3a1b539f4959ec72ea60e453f49156289f95d4e6000b29332efc45616203",
                 repo: "Helsinki-NLP/opus-mt-zh-en"),
            file("target.spm", bytes: 806_530,
                 sha256: "6a881f4717cd7265f53fea54fd3dc689c767c05338fac7a4590f3088cb2d7855",
                 repo: "Helsinki-NLP/opus-mt-zh-en")
        ])

    static let enToZh = MTModelManifest(
        id: "opus-mt-en-zh",
        displayName: "English → 中文",
        tier: "light",
        src: "en",
        tgt: "zh",
        bytes: 52_899_742 + 59_842_102 + 1_617_791 + 806_435 + 804_600,
        licenseName: "Apache-2.0",
        licenseURL: "https://huggingface.co/Helsinki-NLP/opus-mt-en-zh",
        attribution: "Helsinki-NLP OPUS-MT（Apache-2.0）",
        encoder: "encoder_model_quantized.onnx",
        decoder: "decoder_model_quantized.onnx",
        vocab: "vocab.json",
        sourceSpm: "source.spm",
        targetSpm: "target.spm",
        maxNewTokens: 256,
        files: [
            file("encoder_model_quantized.onnx", bytes: 52_899_742,
                 sha256: "d3b7912bf6a9bd27e4c074c2df91d4ff3d5b4bc5f7f6c8d7cc9c805c98fbafee",
                 repo: "Xenova/opus-mt-en-zh", remotePath: "onnx/encoder_model_quantized.onnx"),
            file("decoder_model_quantized.onnx", bytes: 59_842_102,
                 sha256: "2c66a3981099b40edbb3a0d65e015d05964d42fecb9780f8422776eff5939112",
                 repo: "Xenova/opus-mt-en-zh", remotePath: "onnx/decoder_model_quantized.onnx"),
            file("vocab.json", bytes: 1_617_791,
                 sha256: "f1832ca38f7aa158b9a944ff583e4901e6b37d9d4ad9241f03838e636e9cfb03",
                 repo: "Helsinki-NLP/opus-mt-en-zh"),
            file("source.spm", bytes: 806_435,
                 sha256: "5775ddc9e3ff2fae91554da56468ad35ff56edaba870fea74447bc7234bfdaa8",
                 repo: "Helsinki-NLP/opus-mt-en-zh"),
            file("target.spm", bytes: 804_600,
                 sha256: "81dc94efa84e4025ef38d25d5d07429fe41e3eb29d44003f1db6fe98487b0052",
                 repo: "Helsinki-NLP/opus-mt-en-zh")
        ])

    /// 全部轻量模型（设置页按这些条目渲染）
    static let lightModels: [MTModelManifest] = [zhToEn, enToZh]

    /// 支持的方向（src>tgt）
    static func manifest(forSource src: String, target: String) -> MTModelManifest? {
        lightModels.first { $0.src == src && normalized($0.tgt) == normalized(target) }
    }

    static func normalized(_ language: String) -> String {
        switch language {
        case "zh-Hans", "zh-Hant", "zh": return "zh"
        default: return language.lowercased()
        }
    }
}

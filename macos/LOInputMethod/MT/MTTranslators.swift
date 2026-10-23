import Foundation
import NaturalLanguage
import LOMTCore

// MARK: - 翻译引擎选项

/// 设置页「翻译引擎」下拉框的四个选项
enum MTEngineMode: String, CaseIterable {
    case online
    case light
    case multi
    case quality

    var displayName: String {
        switch self {
        case .online: return "语境翻译（在线）"
        case .light: return "本地翻译 · 轻量（中译英）"
        case .multi: return "本地翻译 · 多语（418M）"
        case .quality: return "本地翻译 · 高质量（1.8B）"
        }
    }

    var detail: String {
        switch self {
        case .online:
            return "在线翻译由微软 Edge 提供，无需下载、联网即用；文本会发送到微软服务器。"
        case .light:
            return "中 → 英语言包约 \(MTModelCatalog.sizeText(MTModelCatalog.lightModels[0].bytes))，离线可用、文本不出本机。"
        case .multi:
            return "M2M100 418M，一个模型覆盖 100 种语言互译，约 \(MTModelCatalog.sizeText(MTModelCatalog.multiModel.bytes))。"
        case .quality:
            return "Hy-MT2 1.8B，覆盖 33 种语言，约 \(MTModelCatalog.sizeText(MTModelCatalog.qualityModel.bytes))；推理正在接入，当前先提供下载。"
        }
    }

    /// 兼容旧版本的 local / localFirst 取值
    static func from(_ raw: String) -> MTEngineMode {
        switch raw {
        case "local", "localFirst", "light": return .light
        case "multi", "m2m100": return .multi
        case "quality": return .quality
        default: return .online
        }
    }

    /// 是否使用本地模型
    var isLocal: Bool { self != .online }
}

// MARK: - 语言判断

enum MTTextLanguage {

    /// 判断源语言：优先使用系统语言识别，短文本用 CJK 比例兜底
    static func source(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "zh" }

        let cjkCount = trimmed.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
        }.count

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let dominant = recognizer.dominantLanguage?.rawValue

        // 日文含假名，优先判为日文；纯汉字且识别置信度低时按中文处理
        if let dominant {
            switch dominant {
            case "ja": return "ja"
            case "ko": return "ko"
            case "zh-Hans", "zh-Hant", "zh": return "zh"
            case "ar": return "ar"
            case "ru": return "ru"
            case "fr": return "fr"
            case "de": return "de"
            case "es": return "es"
            case "en": return "en"
            default: break
            }
        }

        if cjkCount > 0 { return "zh" }
        return "en"
    }
}

// MARK: - 本地翻译

enum LocalMTError: LocalizedError {
    case modelMissing(String)
    case unsupportedPair(String)
    case engine(String)
    case qualityNotReady

    var errorDescription: String? {
        switch self {
        case .modelMissing(let detail): return "尚未下载该模型：\(detail)"
        case .unsupportedPair(let detail): return "本地翻译暂不支持该语言方向：\(detail)"
        case .engine(let detail): return detail
        case .qualityNotReady: return "高质量档的推理正在接入，下载的模型将在后续版本启用"
        }
    }
}

/// 本地模型翻译器：轻量档按方向选包，多语档使用整包。
final class LocalMTTranslator: TranslationServiceProtocol {

    private let store = MTModelStore.shared
    private let client = MTEngineClient.shared

    func translate(text: String, targetLanguage: TargetLanguage) async throws -> String {
        let mode = MTEngineMode.from(LOSettings.load().mtEngineMode)
        let target = MTModelCatalog.normalized(targetLanguage.rawValue)

        if mode == .multi {
            let manifest = MTModelCatalog.multiModel
            guard store.installedPack(manifest) else {
                throw LocalMTError.modelMissing("多语包（M2M100 418M）")
            }
            let source = MTTextLanguage.source(for: text)
            if source == target { return text }
            return try await run(manifest, text: text, source: source, target: target)
        }

        let source = MTTextLanguage.source(for: text)
        guard let manifest = store.installedModel(forSource: source, target: target) else {
            let pair = "\(source)→\(target)"
            if MTModelCatalog.manifest(forSource: source, target: target) != nil {
                throw LocalMTError.modelMissing(pair)
            }
            throw LocalMTError.unsupportedPair(pair)
        }
        return try await run(manifest, text: text, source: source, target: target)
    }

    private func run(_ manifest: MTModelManifest,
                     text: String,
                     source: String,
                     target: String) async throws -> String {
        let directory = store.directory(for: manifest.id)
        let needsLoad = client.currentModelID != manifest.id
        if needsLoad {
            try await client.load(model: manifest.id, directory: directory)
        }
        let timeout = needsLoad ? 8000 : 2000
        do {
            return try await client.translate(text: text, source: source,
                                              target: target, timeoutMs: timeout)
        } catch let error as MTEngineClient.ClientError {
            throw LocalMTError.engine(error.localizedDescription)
        }
    }
}

// MARK: - 在线/本地混合

/// 按设置里的引擎选项选择后端，并按开关决定是否回退在线。
final class HybridTranslator: TranslationServiceProtocol {

    private let online = BingTranslator()
    private let local = LocalMTTranslator()

    func translate(text: String, targetLanguage: TargetLanguage) async throws -> String {
        let settings = LOSettings.load()
        let mode = MTEngineMode.from(settings.mtEngineMode)

        switch mode {
        case .online:
            return try await online.translate(text: text, targetLanguage: targetLanguage)

        case .quality:
            if settings.mtFallbackOnline {
                debugLog("[MT] 高质量模型推理未就绪，回退在线")
                return try await online.translate(text: text, targetLanguage: targetLanguage)
            }
            throw LocalMTError.qualityNotReady

        case .light, .multi:
            do {
                let result = try await local.translate(text: text, targetLanguage: targetLanguage)
                debugLog("[MT] 本地翻译完成 length=\(result.count)")
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard settings.mtFallbackOnline else { throw error }
                debugLog("[MT] 本地不可用，回退在线：\(error.localizedDescription)")
                return try await online.translate(text: text, targetLanguage: targetLanguage)
            }
        }
    }
}

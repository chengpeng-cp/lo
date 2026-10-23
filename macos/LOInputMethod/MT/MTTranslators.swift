import Foundation
import NaturalLanguage
import LOMTCore

// MARK: - 翻译引擎选项

/// 设置页「翻译引擎」下拉框的三个选项
enum MTEngineMode: String, CaseIterable {
    case online
    case light
    case quality

    var displayName: String {
        switch self {
        case .online: return "语境翻译（在线）"
        case .light: return "本地翻译 · 轻量"
        case .quality: return "本地翻译 · 高质量（即将支持）"
        }
    }

    var detail: String {
        switch self {
        case .online:
            return "在线翻译由微软 Edge 提供，无需下载、联网即用；文本会发送到微软服务器。"
        case .light:
            return "每个语言包约 111 MB，离线可用、文本不出本机；按需要下载语言方向。"
        case .quality:
            return "1.8B 专用翻译模型，支持 33 种语言，正在适配，后续版本提供。"
        }
    }

    /// 兼容旧版本的 local / localFirst 取值
    static func from(_ raw: String) -> MTEngineMode {
        switch raw {
        case "local", "localFirst", "light": return .light
        case "quality": return .quality
        default: return .online
        }
    }
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
        case .modelMissing(let detail): return "尚未下载该语言包：\(detail)"
        case .unsupportedPair(let detail): return "本地翻译暂不支持该语言方向：\(detail)"
        case .engine(let detail): return detail
        case .qualityNotReady: return "高质量本地模型即将支持"
        }
    }
}

/// 本地模型翻译器：按源语言自动选择对应语言包，必要时懒加载。
final class LocalMTTranslator: TranslationServiceProtocol {

    private let store = MTModelStore.shared
    private let client = MTEngineClient.shared

    func translate(text: String, targetLanguage: TargetLanguage) async throws -> String {
        let source = MTTextLanguage.source(for: text)
        let target = MTModelCatalog.normalized(targetLanguage.rawValue)

        guard let manifest = store.installedModel(forSource: source, target: target) else {
            let pair = "\(source)→\(target)"
            if MTModelCatalog.manifest(forSource: source, target: target) != nil {
                throw LocalMTError.modelMissing(pair)
            }
            throw LocalMTError.unsupportedPair(pair)
        }

        let directory = store.directory(for: manifest.id)
        let needsLoad = client.currentModelID != manifest.id
        if needsLoad {
            try await client.load(model: manifest.id, directory: directory)
        }
        let timeout = needsLoad ? 6000 : 1500
        do {
            return try await client.translate(text: text, source: source,
                                              target: manifest.tgt, timeoutMs: timeout)
        } catch let error as MTEngineClient.ClientError {
            throw LocalMTError.engine(error.localizedDescription)
        }
    }

    /// 语言包是否覆盖指定目标语言（用于设置页提示）
    static func covers(targetLanguage: TargetLanguage) -> Bool {
        let target = MTModelCatalog.normalized(targetLanguage.rawValue)
        return MTModelCatalog.packs.contains { MTModelCatalog.normalized($0.target) == target }
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
                debugLog("[MT] 高质量模型未就绪，回退在线")
                return try await online.translate(text: text, targetLanguage: targetLanguage)
            }
            throw LocalMTError.qualityNotReady

        case .light:
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

import Foundation
import LOMTCore

// MARK: - 引擎模式

enum MTEngineMode: String, CaseIterable {
    case online
    case localFirst
    case local

    var displayName: String {
        switch self {
        case .online: return "在线"
        case .localFirst: return "本地优先"
        case .local: return "仅本地"
        }
    }

    var detail: String {
        switch self {
        case .online:
            return "始终使用免费的在线翻译，不下载任何模型"
        case .localFirst:
            return "优先本地模型；未安装、不支持或超时则自动联网"
        case .local:
            return "只使用本地模型；未安装或语言不支持时直接提示，不联网"
        }
    }

    static func from(_ raw: String) -> MTEngineMode {
        MTEngineMode(rawValue: raw) ?? .online
    }
}

// MARK: - 语言判断

enum MTTextLanguage {

    /// 粗略判断源语言：包含一定比例的 CJK 字符即视为中文
    static func source(for text: String) -> String {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return "zh" }
        var cjk = 0
        var latin = 0
        for scalar in scalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                cjk += 1
            case 0x41...0x5A, 0x61...0x7A:
                latin += 1
            default:
                break
            }
        }
        if cjk == 0 { return "en" }
        if latin == 0 { return "zh" }
        return cjk >= latin ? "zh" : "en"
    }
}

// MARK: - 本地翻译

enum LocalMTError: LocalizedError {
    case modelMissing(String)
    case unsupportedPair(String)
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let detail): return "本地模型未安装：\(detail)"
        case .unsupportedPair(let detail): return "本地模型不支持该语言方向：\(detail)"
        case .engine(let detail): return detail
        }
    }
}

/// 本地模型翻译器：按源语言自动选择中→英或英→中模型，必要时懒加载。
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
        // 首次加载模型需要更宽的预算
        let timeout = needsLoad ? 6000 : 1500
        do {
            return try await client.translate(text: text, source: source,
                                              target: manifest.tgt, timeoutMs: timeout)
        } catch let error as MTEngineClient.ClientError {
            throw LocalMTError.engine(error.localizedDescription)
        }
    }
}

// MARK: - 在线/本地混合

/// 按设置里的引擎模式选择后端，并执行回退策略。
final class HybridTranslator: TranslationServiceProtocol {

    private let online = BingTranslator()
    private let local = LocalMTTranslator()

    func translate(text: String, targetLanguage: TargetLanguage) async throws -> String {
        let mode = MTEngineMode.from(LOSettings.load().mtEngineMode)
        switch mode {
        case .online:
            return try await online.translate(text: text, targetLanguage: targetLanguage)
        case .local:
            return try await local.translate(text: text, targetLanguage: targetLanguage)
        case .localFirst:
            do {
                let result = try await local.translate(text: text, targetLanguage: targetLanguage)
                debugLog("[MT] 本地翻译完成 length=\(result.count)")
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                debugLog("[MT] 本地翻译不可用，回退在线：\(error.localizedDescription)")
                return try await online.translate(text: text, targetLanguage: targetLanguage)
            }
        }
    }
}

import Foundation
import LOMTCore

// MARK: - 翻译引擎选项

/// 设置页「翻译引擎」下拉框的两个选项
enum MTEngineMode: String, CaseIterable {
    case online
    case light

    var displayName: String {
        switch self {
        case .online: return "语境翻译（在线）"
        case .light: return "本地翻译 · 轻量"
        }
    }

    var detail: String {
        switch self {
        case .online:
            return "在线翻译由微软 Edge 提供，无需下载、联网即用；文本会发送到微软服务器。"
        case .light:
            return "中 → 英语言包约 111 MB，离线可用、文本不出本机。"
        }
    }

    /// 兼容旧版本取值（local / localFirst / multi / quality 统一回落到轻量档）
    static func from(_ raw: String) -> MTEngineMode {
        switch raw {
        case "local", "localFirst", "light", "multi", "quality": return .light
        default: return .online
        }
    }

    /// 是否使用本地模型
    var isLocal: Bool { self != .online }
}

// MARK: - 本地翻译

enum LocalMTError: LocalizedError {
    case modelMissing(String)
    case unsupportedPair(String)
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let detail): return "尚未下载该模型：\(detail)"
        case .unsupportedPair(let detail): return "本地翻译暂不支持该语言方向：\(detail)"
        case .engine(let detail): return detail
        }
    }
}

/// 本地模型翻译器：语境输入法的输入默认是中文，直接使用「中文 → 目标语言」语言包。
final class LocalMTTranslator: TranslationServiceProtocol {

    private let store = MTModelStore.shared
    private let client = MTEngineClient.shared

    func translate(text: String, targetLanguage: TargetLanguage) async throws -> String {
        let target = MTModelCatalog.normalized(MTLanguageCatalog.normalizedCode(targetLanguage.rawValue))

        guard let manifest = MTModelCatalog.manifest(forSource: "zh", target: target) else {
            throw LocalMTError.unsupportedPair("zh→\(target)")
        }
        guard store.isInstalled(manifest.id) else {
            throw LocalMTError.modelMissing(manifest.displayName)
        }
        return try await run(manifest, text: text, source: "zh", target: target)
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
        let timeout = needsLoad ? 6000 : 1500
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

        case .light:
            do {
                let result = try await local.translate(text: text, targetLanguage: targetLanguage)
                debugLog("[MT] 本地翻译完成 length=\(result.count)")
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // 在线引擎不覆盖该语言时，回退也只会得到接口错误，直接给出本地提示
                guard settings.mtFallbackOnline,
                      MTLanguageCatalog.onlineCodes.contains(targetLanguage.rawValue) else { throw error }
                debugLog("[MT] 本地不可用，回退在线：\(error.localizedDescription)")
                return try await online.translate(text: text, targetLanguage: targetLanguage)
            }
        }
    }
}

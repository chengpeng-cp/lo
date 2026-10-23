import Foundation

// MARK: - 目标语言能力目录
//
// 目标语言由当前引擎决定：
// - 在线：微软 Edge 支持的常用语言；
// - 轻量：语言包只覆盖部分方向（中→英，以及经英语中转的日语/法语/德语/西语/俄语/阿语和英→中）。
//
// 显示名优先使用「母语名（中文名）」，无法识别的代码回退为大写代码。

enum MTLanguageCatalog {

    /// 在线引擎支持的目标语言（面向中文输入，不含简繁中文）
    static let onlineCodes: [String] = [
        "en", "en-GB", "ja", "ko", "fr", "de", "es", "it",
        "pt", "pt-BR", "ru", "ar", "hi", "th", "vi", "id", "nl", "pl", "tr", "sv", "uk"
    ]

    /// 轻量档：目前开放的中文直译 ONNX 模型只有英文
    static let lightCodes: [String] = ["en"]

    /// 常用语言固定排在前面，其余按中文名排序
    private static let pinnedCodes: [String] = [
        "en", "zh", "ja", "ko", "fr", "de", "es", "ru", "ar", "pt", "it", "th", "vi", "id", "ms", "hi"
    ]

    static func codes(for mode: MTEngineMode) -> [String] {
        let source: [String]
        switch mode {
        case .online: source = onlineCodes
        case .light: source = lightCodes
        }
        guard source.count > pinnedCodes.count else { return source }
        let pinned = pinnedCodes.filter { source.contains($0) }
        let rest = source.filter { !pinned.contains($0) }
            .sorted { chineseName(for: $0) < chineseName(for: $1) }
        return pinned + rest
    }

    static func supports(_ code: String, mode: MTEngineMode) -> Bool {
        codes(for: mode).contains(code)
    }

    static func defaultCode(for mode: MTEngineMode) -> String {
        "en"
    }

    /// 能力说明（设置页目标语言下方的一行提示）
    static func capabilityText(for mode: MTEngineMode, count: Int) -> String {
        switch mode {
        case .online: return "在线翻译支持 \(count) 种常用语言。"
        case .light: return "本地轻量目前支持中文 → English；其他语言请使用在线翻译。"
        }
    }

    // MARK: - 展示名

    private static let specialNames: [String: String] = [
        "en": "English（英语）",
        "en-GB": "English (UK)（英语·英国）",
        "zh": "简体中文",
        "zh-Hans": "简体中文",
        "zh-Hant": "繁體中文",
        "pt": "Português（葡萄牙语）",
        "pt-BR": "Português (BR)（葡萄牙语·巴西）",
        "yue": "粤语（Cantonese）"
    ]

    static func displayName(for code: String) -> String {
        if let special = specialNames[code] { return special }
        let zh = chineseName(for: code)
        let native = nativeName(for: code)
        if let native, !native.isEmpty, native.caseInsensitiveCompare(zh) != .orderedSame {
            return "\(native)（\(zh)）"
        }
        return zh
    }

    private static func chineseName(for code: String) -> String {
        let base = baseCode(code)
        let localized = Locale(identifier: "zh-Hans").localizedString(forLanguageCode: base)
        return localized ?? code.uppercased()
    }

    private static func nativeName(for code: String) -> String? {
        let base = baseCode(code)
        guard let name = Locale(identifier: base).localizedString(forLanguageCode: base),
              !name.isEmpty else { return nil }
        // 拉丁文语言名统一首字母大写（Locale 会返回 français / español 这类小写形式）
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static func baseCode(_ code: String) -> String {
        if let dash = code.firstIndex(of: "-") {
            return String(code[..<dash])
        }
        if let underscore = code.firstIndex(of: "_") {
            return String(code[..<underscore])
        }
        return code
    }

    /// 语言代码归一化：保留三字母代码，只去掉地区后缀
    static func normalizedCode(_ raw: String) -> String {
        switch raw {
        case "zh-Hans", "zh_CN", "zh": return "zh"
        case "zh-Hant", "zh_TW": return "zh-Hant"
        default: return baseCode(raw).lowercased()
        }
    }
}

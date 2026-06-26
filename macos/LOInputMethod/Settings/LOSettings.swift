import AppKit
import Foundation
import Security

// MARK: - 语境设置

/// 语境输入法的设置数据模型
/// 普通设置使用 UserDefaults 持久化，API 密钥使用 Keychain 持久化
struct LOSettings {

    // MARK: - 设置项

    /// 是否启用翻译功能（关闭后仅作为普通输入法使用，不翻译、不显示悬浮窗）
    var translationEnabled: Bool = true

    /// 翻译服务提供商：bing / deepseek / glm / qwen / kimi / minimax / openai / volcengine / custom
    var translationProvider: String = "bing"

    /// 当前提供商的翻译模型（内存中的当前值，持久化按提供商分别存储）
    var translationModel: String = ""

    /// 自定义提供商的 API 端点（仅 provider == custom 时使用）
    var customLLMBaseURL: String = ""

    /// 翻译模式：fluent / native / literal
    var translationMode: String = "fluent"

    /// 翻译目标语言（语言代码，如 en / ja / fr，见 TargetLanguage）
    var targetLanguage: String = "en"

    /// 悬浮窗位置模式：fixed（固定屏幕右侧）/ draggable（可自由拖动）/ followCursor（跟随光标）
    var overlayPositionMode: String = "draggable"

    /// 构造翻译浮窗配置
    var overlayConfig: OverlayConfig {
        return OverlayConfig(
            positionMode: OverlayPositionMode(rawValue: overlayPositionMode) ?? .draggable,
            autoDismissInterval: autoDismissInterval,
            opacity: CGFloat(overlayOpacity),
            backgroundColor: NSColor(hex: overlayBackgroundColor) ?? NSColor(white: 0.12, alpha: 1.0),
            originalTextColor: NSColor(hex: overlayOriginalTextColor) ?? NSColor(white: 0.6, alpha: 1.0),
            translationTextColor: NSColor(hex: overlayTranslationTextColor) ?? NSColor.white,
            theme: overlayTheme,
            clickThrough: overlayClickThrough,
            maxWidth: CGFloat(overlayMaxWidth),
            maxHeight: CGFloat(overlayMaxHeight),
            originalFontSize: CGFloat(overlayOriginalFontSize),
            translationFontSize: CGFloat(overlayTranslationFontSize),
            showOriginalLabel: overlayShowOriginalLabel,
            showTranslationLabel: overlayShowTranslationLabel
        )
    }

    /// 深色主题预设颜色
    static let darkThemeColors = (bg: "1E1E1E", original: "999999", translation: "FFFFFF")

    /// 浅色主题预设颜色
    static let lightThemeColors = (bg: "FFFFFF", original: "666666", translation: "1A1A1A")

    /// 根据主题获取预设颜色（用于切换主题时更新颜色设置）
    static func themeColors(for theme: String) -> (bg: String, original: String, translation: String) {
        switch theme {
        case "light": return lightThemeColors
        case "auto":
            // 跟随系统：根据当前外观返回对应预设
            if #available(macOS 10.14, *) {
                let isDark = NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark ? darkThemeColors : lightThemeColors
            }
            return darkThemeColors
        default: return darkThemeColors
        }
    }

    /// 悬浮窗位置（仅 draggable 模式下记忆使用）
    var overlayPosition: NSPoint = NSPoint(x: 0, y: 0)

    /// 悬浮窗自动消失时间（秒）
    var autoDismissInterval: Double = 5.0

    /// 悬浮窗透明度（0.0 ~ 1.0）
    var overlayOpacity: Double = 0.85

    /// 悬浮窗背景颜色（hex 格式，如 "1E1E1E"）
    var overlayBackgroundColor: String = "1E1E1E"

    /// 待翻译文字颜色（hex 格式）
    var overlayOriginalTextColor: String = "999999"

    /// 翻译文字颜色（hex 格式）
    var overlayTranslationTextColor: String = "FFFFFF"

    /// 悬浮窗主题：dark（深色）/ light（浅色）/ auto（跟随系统）
    var overlayTheme: String = "dark"

    /// 悬浮窗点击穿透（开启后鼠标可穿透悬浮窗点击后方内容）
    var overlayClickThrough: Bool = false

    /// 悬浮窗最大宽度（pt）
    var overlayMaxWidth: Double = 360

    /// 悬浮窗最大高度（pt，翻译区超过此高度后滚动）
    var overlayMaxHeight: Double = 200

    /// 原文字体大小
    var overlayOriginalFontSize: Double = 14

    /// 翻译字体大小
    var overlayTranslationFontSize: Double = 14

    /// 是否显示"原文"标签
    var overlayShowOriginalLabel: Bool = true

    /// 是否显示"翻译"标签
    var overlayShowTranslationLabel: Bool = true

    /// 新段落间隔时间（秒）：超过该时间无新输入，下次提交将开启新段落
    var segmentPauseThreshold: Double = 5.0

    /// 翻译间隔时间（秒）：连续快速提交候选词时，只翻译最后一次
    var translationDebounceInterval: Double = 0.5

    /// 默认输入模式：chinese / english
    var defaultInputMode: String = "chinese"

    /// Shift 键行为：toggle_ascii（切 Rime 内部中英文，对齐微信）/ switch_source（切系统ABC）
    /// 默认 toggle_ascii：不切系统输入源，输入法进程始终驻留，可再次按 Shift 切回中文
    var shiftBehavior: String = "toggle_ascii"

    /// Shift 长按阈值（秒），超过则触发 CapsLock 大写
    var shiftLongPressThreshold: Double = 0.4

    // MARK: - UserDefaults 键名

    private enum Keys {
        static let translationEnabled = "LO_translationEnabled"
        static let translationProvider = "LO_translationProvider"
        static let translationModelPrefix = "LO_translationModel_" // 按提供商分别存储：LO_translationModel_deepseek
        static let customLLMBaseURL = "LO_customLLMBaseURL"
        static let translationMode = "LO_translationMode"
        static let targetLanguage = "LO_targetLanguage"
        static let overlayPositionMode = "LO_overlayPositionMode"
        static let overlayFixedPositionLegacy = "LO_overlayFixedPosition"
        static let overlayPositionX = "LO_overlayPositionX"
        static let overlayPositionY = "LO_overlayPositionY"
        static let autoDismissInterval = "LO_autoDismissInterval"
        static let overlayOpacity = "LO_overlayOpacity"
        static let overlayBackgroundColor = "LO_overlayBackgroundColor"
        static let overlayOriginalTextColor = "LO_overlayOriginalTextColor"
        static let overlayTranslationTextColor = "LO_overlayTranslationTextColor"
        static let overlayTheme = "LO_overlayTheme"
        static let overlayClickThrough = "LO_overlayClickThrough"
        static let overlayMaxWidth = "LO_overlayMaxWidth"
        static let overlayMaxHeight = "LO_overlayMaxHeight"
        static let overlayOriginalFontSize = "LO_overlayOriginalFontSize"
        static let overlayTranslationFontSize = "LO_overlayTranslationFontSize"
        static let overlayShowOriginalLabel = "LO_overlayShowOriginalLabel"
        static let overlayShowTranslationLabel = "LO_overlayShowTranslationLabel"
        static let segmentPauseThreshold = "LO_segmentPauseThreshold"
        static let translationDebounceInterval = "LO_translationDebounceInterval"
        static let defaultInputMode = "LO_defaultInputMode"
        static let shiftBehavior = "LO_shiftBehavior"
        static let shiftLongPressThreshold = "LO_shiftLongPressThreshold"
    }

    // MARK: - Keychain 配置

    /// Keychain 服务名
    private static let keychainService = "com.lo.inputmethod"

    // MARK: - 加载与保存

    /// 从 UserDefaults 加载设置
    static func load() -> LOSettings {
        let defaults = UserDefaults.standard
        var settings = LOSettings()

        // translationEnabled 使用 object(forKey:) 判断是否曾存储过，
        // 避免首次安装时 bool(forKey:) 返回 false 导致默认关闭
        if defaults.object(forKey: Keys.translationEnabled) != nil {
            settings.translationEnabled = defaults.bool(forKey: Keys.translationEnabled)
        }
        settings.translationProvider = defaults.string(forKey: Keys.translationProvider) ?? "bing"
        // 加载当前提供商对应的模型名
        settings.translationModel = defaults.string(forKey: Keys.translationModelPrefix + settings.translationProvider) ?? ""
        settings.customLLMBaseURL = defaults.string(forKey: Keys.customLLMBaseURL) ?? ""
        settings.translationMode = defaults.string(forKey: Keys.translationMode) ?? "fluent"
        settings.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "en"
        debugLog("[Settings] 加载设置: targetLanguage=\(settings.targetLanguage)")
        // 位置模式：优先读新键，不存在则从旧键迁移
        if let mode = defaults.string(forKey: Keys.overlayPositionMode) {
            settings.overlayPositionMode = mode
        } else if defaults.object(forKey: Keys.overlayFixedPositionLegacy) != nil {
            // 旧版本用 bool 存储，转换为新枚举
            settings.overlayPositionMode = defaults.bool(forKey: Keys.overlayFixedPositionLegacy) ? "fixed" : "draggable"
        }
        let posX = defaults.double(forKey: Keys.overlayPositionX)
        let posY = defaults.double(forKey: Keys.overlayPositionY)
        settings.overlayPosition = NSPoint(x: posX, y: posY)
        settings.autoDismissInterval = defaults.double(forKey: Keys.autoDismissInterval)
        if settings.autoDismissInterval == 0 { settings.autoDismissInterval = 5.0 }
        settings.overlayOpacity = defaults.double(forKey: Keys.overlayOpacity)
        if settings.overlayOpacity == 0 { settings.overlayOpacity = 0.85 }
        settings.overlayBackgroundColor = defaults.string(forKey: Keys.overlayBackgroundColor) ?? "1E1E1E"
        settings.overlayOriginalTextColor = defaults.string(forKey: Keys.overlayOriginalTextColor) ?? "999999"
        settings.overlayTranslationTextColor = defaults.string(forKey: Keys.overlayTranslationTextColor) ?? "FFFFFF"
        settings.overlayTheme = defaults.string(forKey: Keys.overlayTheme) ?? "dark"
        settings.overlayClickThrough = defaults.bool(forKey: Keys.overlayClickThrough)
        settings.overlayMaxWidth = defaults.double(forKey: Keys.overlayMaxWidth)
        if settings.overlayMaxWidth == 0 { settings.overlayMaxWidth = 360 }
        settings.overlayMaxHeight = defaults.double(forKey: Keys.overlayMaxHeight)
        if settings.overlayMaxHeight == 0 { settings.overlayMaxHeight = 200 }
        settings.overlayOriginalFontSize = defaults.double(forKey: Keys.overlayOriginalFontSize)
        if settings.overlayOriginalFontSize == 0 { settings.overlayOriginalFontSize = 14 }
        settings.overlayTranslationFontSize = defaults.double(forKey: Keys.overlayTranslationFontSize)
        if settings.overlayTranslationFontSize == 0 { settings.overlayTranslationFontSize = 14 }
        settings.overlayShowOriginalLabel = defaults.object(forKey: Keys.overlayShowOriginalLabel) != nil
            ? defaults.bool(forKey: Keys.overlayShowOriginalLabel)
            : true
        settings.overlayShowTranslationLabel = defaults.object(forKey: Keys.overlayShowTranslationLabel) != nil
            ? defaults.bool(forKey: Keys.overlayShowTranslationLabel)
            : true
        settings.segmentPauseThreshold = defaults.double(forKey: Keys.segmentPauseThreshold)
        if settings.segmentPauseThreshold == 0 { settings.segmentPauseThreshold = 5.0 }
        settings.translationDebounceInterval = defaults.double(forKey: Keys.translationDebounceInterval)
        if settings.translationDebounceInterval == 0 { settings.translationDebounceInterval = 0.5 }

        settings.defaultInputMode = defaults.string(forKey: Keys.defaultInputMode) ?? "chinese"
        settings.shiftBehavior = defaults.string(forKey: Keys.shiftBehavior) ?? "toggle_ascii"
        settings.shiftLongPressThreshold = defaults.double(forKey: Keys.shiftLongPressThreshold)
        if settings.shiftLongPressThreshold == 0 { settings.shiftLongPressThreshold = 0.4 }

        return settings
    }

    /// 保存设置到 UserDefaults
    func save() {
        let defaults = UserDefaults.standard

        defaults.set(translationEnabled, forKey: Keys.translationEnabled)
        defaults.set(translationProvider, forKey: Keys.translationProvider)
        // 按提供商分别存储模型名
        defaults.set(translationModel, forKey: Keys.translationModelPrefix + translationProvider)
        defaults.set(customLLMBaseURL, forKey: Keys.customLLMBaseURL)
        defaults.set(translationMode, forKey: Keys.translationMode)
        defaults.set(targetLanguage, forKey: Keys.targetLanguage)
        defaults.set(overlayPositionMode, forKey: Keys.overlayPositionMode)
        defaults.set(Double(overlayPosition.x), forKey: Keys.overlayPositionX)
        defaults.set(Double(overlayPosition.y), forKey: Keys.overlayPositionY)
        defaults.set(autoDismissInterval, forKey: Keys.autoDismissInterval)
        defaults.set(overlayOpacity, forKey: Keys.overlayOpacity)
        defaults.set(overlayBackgroundColor, forKey: Keys.overlayBackgroundColor)
        defaults.set(overlayOriginalTextColor, forKey: Keys.overlayOriginalTextColor)
        defaults.set(overlayTranslationTextColor, forKey: Keys.overlayTranslationTextColor)
        defaults.set(overlayTheme, forKey: Keys.overlayTheme)
        defaults.set(overlayClickThrough, forKey: Keys.overlayClickThrough)
        defaults.set(overlayMaxWidth, forKey: Keys.overlayMaxWidth)
        defaults.set(overlayMaxHeight, forKey: Keys.overlayMaxHeight)
        defaults.set(overlayOriginalFontSize, forKey: Keys.overlayOriginalFontSize)
        defaults.set(overlayTranslationFontSize, forKey: Keys.overlayTranslationFontSize)
        defaults.set(overlayShowOriginalLabel, forKey: Keys.overlayShowOriginalLabel)
        defaults.set(overlayShowTranslationLabel, forKey: Keys.overlayShowTranslationLabel)
        defaults.set(segmentPauseThreshold, forKey: Keys.segmentPauseThreshold)
        defaults.set(translationDebounceInterval, forKey: Keys.translationDebounceInterval)
        defaults.set(defaultInputMode, forKey: Keys.defaultInputMode)
        defaults.set(shiftBehavior, forKey: Keys.shiftBehavior)
        defaults.set(shiftLongPressThreshold, forKey: Keys.shiftLongPressThreshold)
        
        // 强制同步，确保设置立即写入磁盘
        defaults.synchronize()
    }

    /// 加载指定提供商保存的模型名（切换提供商时调用）
    /// - Parameter provider: 提供商 rawValue
    /// - Returns: 该提供商上次保存的模型名，无则返回空字符串
    static func loadModel(forProvider provider: String) -> String {
        return UserDefaults.standard.string(forKey: Keys.translationModelPrefix + provider) ?? ""
    }

    // MARK: - Keychain API 密钥管理

    /// 获取指定提供商的 API 密钥
    /// - Parameter provider: 提供商名称（deepseek / glm / qwen / kimi / minimax / openai / volcengine / custom）
    /// - Returns: API 密钥，如果不存在则返回 nil
    func getAPIKey(provider: String) -> String? {
        let key = "apikey_\(provider)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LOSettings.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }

        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    /// 设置指定提供商的 API 密钥
    /// - Parameters:
    ///   - provider: 提供商名称（deepseek / glm / qwen / kimi / minimax / openai / volcengine / custom）
    ///   - key: API 密钥
    func setAPIKey(provider: String, key: String) {
        let account = "apikey_\(provider)"
        guard let keyData = key.data(using: .utf8) else { return }

        // 先尝试删除已有的密钥
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LOSettings.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 添加新密钥
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LOSettings.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// 删除指定提供商的 API 密钥（用户清空输入框时调用，确保旧密钥被移除）
    /// - Parameter provider: 提供商名称
    func deleteAPIKey(provider: String) {
        let account = "apikey_\(provider)"
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LOSettings.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
}

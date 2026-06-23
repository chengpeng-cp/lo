import Foundation
import Security

// MARK: - 语镜设置

/// 语镜输入法的设置数据模型
/// 普通设置使用 UserDefaults 持久化，API 密钥使用 Keychain 持久化
struct LOSettings {

    // MARK: - 设置项

    /// 翻译服务提供商：deepseek / glm / qwen / kimi / minimax / openai / volcengine / custom / bing
    var translationProvider: String = "deepseek"

    /// 当前提供商的翻译模型（内存中的当前值，持久化按提供商分别存储）
    var translationModel: String = ""

    /// 自定义提供商的 API 端点（仅 provider == custom 时使用）
    var customLLMBaseURL: String = ""

    /// 翻译模式：fluent / native / literal
    var translationMode: String = "fluent"

    /// 悬浮窗位置模式：fixed（固定屏幕右侧）/ draggable（可自由拖动）/ followCursor（跟随光标）
    var overlayPositionMode: String = "draggable"

    /// 构造翻译浮窗配置
    var overlayConfig: OverlayConfig {
        return OverlayConfig(
            positionMode: OverlayPositionMode(rawValue: overlayPositionMode) ?? .draggable,
            autoDismissInterval: autoDismissInterval,
            opacity: CGFloat(overlayOpacity)
        )
    }

    /// 悬浮窗位置（仅 draggable 模式下记忆使用）
    var overlayPosition: NSPoint = NSPoint(x: 0, y: 0)

    /// 悬浮窗自动消失时间（秒）
    var autoDismissInterval: Double = 5.0

    /// 悬浮窗透明度（0.0 ~ 1.0）
    var overlayOpacity: Double = 0.85

    /// 段落断句时间（秒）：超过该时间无新输入，下次提交将开启新段落
    var segmentPauseThreshold: Double = 5.0

    /// 翻译防抖时间（秒）：连续快速提交候选词时，只翻译最后一次
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
        static let translationProvider = "LO_translationProvider"
        static let translationModelPrefix = "LO_translationModel_" // 按提供商分别存储：LO_translationModel_deepseek
        static let customLLMBaseURL = "LO_customLLMBaseURL"
        static let translationMode = "LO_translationMode"
        static let overlayPositionMode = "LO_overlayPositionMode"
        static let overlayFixedPositionLegacy = "LO_overlayFixedPosition"
        static let overlayPositionX = "LO_overlayPositionX"
        static let overlayPositionY = "LO_overlayPositionY"
        static let autoDismissInterval = "LO_autoDismissInterval"
        static let overlayOpacity = "LO_overlayOpacity"
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

        settings.translationProvider = defaults.string(forKey: Keys.translationProvider) ?? "deepseek"
        // 加载当前提供商对应的模型名
        settings.translationModel = defaults.string(forKey: Keys.translationModelPrefix + settings.translationProvider) ?? ""
        settings.customLLMBaseURL = defaults.string(forKey: Keys.customLLMBaseURL) ?? ""
        settings.translationMode = defaults.string(forKey: Keys.translationMode) ?? "fluent"
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

        defaults.set(translationProvider, forKey: Keys.translationProvider)
        // 按提供商分别存储模型名
        defaults.set(translationModel, forKey: Keys.translationModelPrefix + translationProvider)
        defaults.set(customLLMBaseURL, forKey: Keys.customLLMBaseURL)
        defaults.set(translationMode, forKey: Keys.translationMode)
        defaults.set(overlayPositionMode, forKey: Keys.overlayPositionMode)
        defaults.set(Double(overlayPosition.x), forKey: Keys.overlayPositionX)
        defaults.set(Double(overlayPosition.y), forKey: Keys.overlayPositionY)
        defaults.set(autoDismissInterval, forKey: Keys.autoDismissInterval)
        defaults.set(overlayOpacity, forKey: Keys.overlayOpacity)
        defaults.set(segmentPauseThreshold, forKey: Keys.segmentPauseThreshold)
        defaults.set(translationDebounceInterval, forKey: Keys.translationDebounceInterval)
        defaults.set(defaultInputMode, forKey: Keys.defaultInputMode)
        defaults.set(shiftBehavior, forKey: Keys.shiftBehavior)
        defaults.set(shiftLongPressThreshold, forKey: Keys.shiftLongPressThreshold)
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
}

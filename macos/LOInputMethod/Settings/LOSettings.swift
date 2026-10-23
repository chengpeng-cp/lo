import AppKit
import Foundation

// MARK: - 语境设置

/// 语境输入法的设置数据模型
/// 所有设置使用 UserDefaults 持久化
struct LOSettings {

    // MARK: - 设置项

    /// 是否调用翻译服务（关闭后不发任何翻译请求，悬浮窗/播报只使用原文）
    var translationEnabled: Bool = true

    /// 是否显示翻译悬浮窗（独立于翻译开关；翻译关闭时只显示原文）
    var overlayEnabled: Bool = true

    /// 翻译目标语言（语言代码，如 en / ja / fr，见 TargetLanguage）
    var targetLanguage: String = "en"

    /// 本地翻译引擎模式：online（仅在线）/ localFirst（本地优先，失败回退）/ local（仅本地）
    var mtEngineMode: String = "online"

    /// 本地推理进程空闲多久后卸载模型权重（分钟）
    var mtIdleUnloadMinutes: Double = 10

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
            translationFontSize: CGFloat(overlayTranslationFontSize)
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
    var overlayOriginalFontSize: Double = 12

    /// 翻译字体大小
    var overlayTranslationFontSize: Double = 15

    /// 新段落间隔时间（秒）：超过该时间无新输入，下次提交将开启新段落
    var segmentPauseThreshold: Double = 5.0

    /// 翻译间隔时间（秒）：连续快速提交候选词时，只翻译最后一次
    var translationDebounceInterval: Double = 0.5

    /// 默认输入模式：chinese / english
    var defaultInputMode: String = "chinese"

    /// Shift 键行为：toggle_ascii（只切 Rime 内部中英文）/ switch_source（切系统 ABC ↔ 语境）
    /// 默认 toggle_ascii：与微信输入法一致，中英文切换完全在输入法内部完成。
    /// switch_source 依赖 TISSelectInputSource，只更新全局菜单栏，不更新已运行应用
    /// （尤其 Electron 类应用）的输入上下文，会出现菜单栏显示语境但实际输入英文。
    var shiftBehavior: String = "toggle_ascii"

    /// Shift 长按阈值（秒），超过则触发 CapsLock 大写
    var shiftLongPressThreshold: Double = 0.4

    /// 是否语音播报翻译结果（使用系统语音合成，离线免费）
    var speechEnabled: Bool = false

    /// 语音播报语速（AVSpeechUtterance 的 rate，0.5 为系统默认）
    var speechRate: Double = 0.5

    // MARK: - UserDefaults 键名

    private enum Keys {
        static let translationEnabled = "LO_translationEnabled"
        static let targetLanguage = "LO_targetLanguage"
        static let mtEngineMode = "LO_mtEngineMode"
        static let mtIdleUnloadMinutes = "LO_mtIdleUnloadMinutes"
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
        static let segmentPauseThreshold = "LO_segmentPauseThreshold"
        static let translationDebounceInterval = "LO_translationDebounceInterval"
        static let defaultInputMode = "LO_defaultInputMode"
        static let shiftBehavior = "LO_shiftBehavior"
        static let shiftLongPressThreshold = "LO_shiftLongPressThreshold"
        static let speechEnabled = "LO_speechEnabled"
        static let speechRate = "LO_speechRate"
        static let overlayEnabled = "LO_overlayEnabled"
    }

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
        settings.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "en"
        settings.mtEngineMode = defaults.string(forKey: Keys.mtEngineMode) ?? "online"
        settings.mtIdleUnloadMinutes = defaults.double(forKey: Keys.mtIdleUnloadMinutes)
        if settings.mtIdleUnloadMinutes == 0 { settings.mtIdleUnloadMinutes = 10 }
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
        if settings.overlayOriginalFontSize == 0 { settings.overlayOriginalFontSize = 12 }
        settings.overlayTranslationFontSize = defaults.double(forKey: Keys.overlayTranslationFontSize)
        if settings.overlayTranslationFontSize == 0 { settings.overlayTranslationFontSize = 15 }
        settings.segmentPauseThreshold = defaults.double(forKey: Keys.segmentPauseThreshold)
        if settings.segmentPauseThreshold == 0 { settings.segmentPauseThreshold = 5.0 }
        settings.translationDebounceInterval = defaults.double(forKey: Keys.translationDebounceInterval)
        if settings.translationDebounceInterval == 0 { settings.translationDebounceInterval = 0.5 }

        settings.defaultInputMode = defaults.string(forKey: Keys.defaultInputMode) ?? "chinese"
        settings.shiftBehavior = defaults.string(forKey: Keys.shiftBehavior) ?? "toggle_ascii"
        settings.shiftLongPressThreshold = defaults.double(forKey: Keys.shiftLongPressThreshold)
        if settings.shiftLongPressThreshold == 0 { settings.shiftLongPressThreshold = 0.4 }

        // 语音播报默认关闭，需用户主动开启
        if defaults.object(forKey: Keys.speechEnabled) != nil {
            settings.speechEnabled = defaults.bool(forKey: Keys.speechEnabled)
        }
        settings.speechRate = defaults.double(forKey: Keys.speechRate)
        if settings.speechRate == 0 { settings.speechRate = 0.5 }
        // 悬浮窗默认开启，与翻译解耦
        if defaults.object(forKey: Keys.overlayEnabled) != nil {
            settings.overlayEnabled = defaults.bool(forKey: Keys.overlayEnabled)
        }

        return settings
    }

    /// 保存设置到 UserDefaults
    func save() {
        let defaults = UserDefaults.standard

        defaults.set(translationEnabled, forKey: Keys.translationEnabled)
        defaults.set(targetLanguage, forKey: Keys.targetLanguage)
        defaults.set(mtEngineMode, forKey: Keys.mtEngineMode)
        defaults.set(mtIdleUnloadMinutes, forKey: Keys.mtIdleUnloadMinutes)
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
        defaults.set(segmentPauseThreshold, forKey: Keys.segmentPauseThreshold)
        defaults.set(translationDebounceInterval, forKey: Keys.translationDebounceInterval)
        defaults.set(defaultInputMode, forKey: Keys.defaultInputMode)
        defaults.set(shiftBehavior, forKey: Keys.shiftBehavior)
        defaults.set(shiftLongPressThreshold, forKey: Keys.shiftLongPressThreshold)
        defaults.set(speechEnabled, forKey: Keys.speechEnabled)
        defaults.set(speechRate, forKey: Keys.speechRate)
        defaults.set(overlayEnabled, forKey: Keys.overlayEnabled)
        
        // 强制同步，确保设置立即写入磁盘
        defaults.synchronize()
    }
}

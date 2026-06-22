import AppKit

// MARK: - 翻译浮窗配置

/// 翻译浮窗的配置项
struct OverlayConfig {
    /// 是否固定位置（屏幕右侧），否则可拖动
    var isFixedPosition: Bool = true

    /// 自动消失间隔（秒），0 表示不自动消失
    var autoDismissInterval: TimeInterval = 5.0

    /// 窗口不透明度 (0.0 ~ 1.0)
    var opacity: CGFloat = 0.95
}

// MARK: - 翻译浮窗

/// 独立的翻译浮窗，显示在屏幕上不抢焦点
/// 关键特性：nonactivatingPanel + becomesKeyOnlyIfNeeded 确保不抢键盘焦点
/// 单例：所有 LOInputController 共享同一个浮窗，避免多 client 创建多个浮窗
class LOTranslationOverlay {

    // MARK: - 单例

    /// 共享单例（IMK 会为每个 client 创建新的 LOInputController，
    /// 若每个 controller 各持一个 overlay 会出现多个悬浮窗，故用单例）
    static let shared = LOTranslationOverlay(config: LOSettings.load().overlayConfig)

    // MARK: - 常量

    /// UserDefaults 存储键
    private static let positionKey = "LOTranslationOverlay.savedPosition"

    /// 浮窗边距
    private enum Layout {
        static let screenEdgeMargin: CGFloat = 16
        static let fadeOutDuration: TimeInterval = 0.3
    }

    // MARK: - 属性

    /// 底层面板
    private let panel: NSPanel

    /// 内容视图
    private let overlayView: LOTranslationOverlayView

    /// 配置
    var config: OverlayConfig {
        didSet { applyConfig() }
    }

    /// 自动消失定时器
    private var dismissTimer: Timer?

    /// 淡出动画
    private var fadeAnimation: NSAnimation?

    // MARK: - 初始化

    init(config: OverlayConfig = OverlayConfig()) {
        self.config = config

        // 创建非激活面板，关键：不抢焦点
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 关键设置：确保不抢焦点
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.canHide = false
        panel.hidesOnDeactivate = false

        // 外观设置
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // 创建内容视图
        overlayView = LOTranslationOverlayView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        panel.contentView = overlayView

        applyConfig()
    }

    // MARK: - 显示模式

    /// 显示加载状态
    /// - Parameter originalText: 原文
    func showLoading(originalText: String) {
        cancelDismissTimer()
        overlayView.showLoading(originalText: originalText)
        resizeAndShow()
    }

    /// 显示翻译结果
    /// - Parameters:
    ///   - originalText: 原文
    ///   - translation: 翻译结果
    func show(originalText: String, translation: String) {
        cancelDismissTimer()
        overlayView.update(original: originalText, translation: translation)
        resizeAndShow()
        scheduleDismissTimer()
    }

    /// 静默更新原文（防抖期间使用，不闪烁）
    /// - Parameter text: 新的原文
    func silentUpdateOriginal(_ text: String) {
        overlayView.updateOriginalOnly(text)
        resizeAndShow()
    }

    /// 更新翻译结果（结果到达时调用）
    /// - Parameter text: 翻译结果
    func updateTranslation(_ text: String) {
        cancelDismissTimer()
        overlayView.updateTranslation(text)
        resizeAndShow()
        scheduleDismissTimer()
    }

    /// 隐藏浮窗
    func hide() {
        cancelDismissTimer()
        fadeOutAndHide()
    }

    /// 浮窗是否可见
    var isVisible: Bool {
        return panel.isVisible
    }

    // MARK: - 私有方法

    /// 应用配置
    private func applyConfig() {
        panel.isMovableByWindowBackground = !config.isFixedPosition
        panel.alphaValue = config.opacity
    }

    /// 调整尺寸并显示
    private func resizeAndShow() {
        let size = overlayView.preferredSize()
        guard size.width > 0 && size.height > 0 else { return }

        // 保存当前位置
        var currentOrigin = panel.frame.origin

        // 如果面板不可见，计算初始位置
        if !panel.isVisible {
            currentOrigin = calculatePosition(size: size)
        }

        // 更新内容尺寸
        overlayView.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(NSRect(origin: currentOrigin, size: size), display: true)

        if !panel.isVisible {
            panel.alphaValue = config.opacity
            panel.orderFront(nil)
        }
    }

    /// 计算浮窗位置
    /// - Parameter size: 浮窗尺寸
    /// - Returns: 浮窗左下角坐标
    private func calculatePosition(size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let screenRect = screen.visibleFrame

        if config.isFixedPosition {
            // 固定模式：屏幕右侧垂直居中
            let x = screenRect.maxX - size.width - Layout.screenEdgeMargin
            let y = screenRect.midY - size.height / 2
            return NSPoint(x: x, y: y)
        } else {
            // 可移动模式：尝试恢复上次保存的位置
            if let saved = loadSavedPosition() {
                // 确保保存的位置在当前屏幕可见区域内
                let adjusted = clampToVisibleFrame(
                    origin: saved,
                    size: size,
                    screenRect: screenRect
                )
                return adjusted
            }
            // 没有保存位置，默认放在右侧
            let x = screenRect.maxX - size.width - Layout.screenEdgeMargin
            let y = screenRect.midY - size.height / 2
            return NSPoint(x: x, y: y)
        }
    }

    /// 确保位置在屏幕可见区域内（处理 Dock、菜单栏、刘海）
    private func clampToVisibleFrame(origin: NSPoint, size: NSSize, screenRect: NSRect) -> NSPoint {
        var x = origin.x
        var y = origin.y

        // 左边界
        if x < screenRect.minX {
            x = screenRect.minX + Layout.screenEdgeMargin
        }
        // 右边界
        if x + size.width > screenRect.maxX {
            x = screenRect.maxX - size.width - Layout.screenEdgeMargin
        }
        // 下边界
        if y < screenRect.minY {
            y = screenRect.minY + Layout.screenEdgeMargin
        }
        // 上边界
        if y + size.height > screenRect.maxY {
            y = screenRect.maxY - size.height - Layout.screenEdgeMargin
        }

        return NSPoint(x: x, y: y)
    }

    // MARK: - 自动消失

    /// 启动自动消失定时器
    private func scheduleDismissTimer() {
        guard config.autoDismissInterval > 0 else { return }
        cancelDismissTimer()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: config.autoDismissInterval,
            repeats: false
        ) { [weak self] _ in
            self?.fadeOutAndHide()
        }
    }

    /// 取消自动消失定时器
    private func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    /// 淡出动画后隐藏
    private func fadeOutAndHide() {
        guard panel.isVisible else { return }

        // 使用简单的 alpha 动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Layout.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = self.config.opacity
            // 可移动模式下保存位置
            if !self.config.isFixedPosition {
                self.savePosition(self.panel.frame.origin)
            }
        })
    }

    // MARK: - 位置持久化

    /// 保存浮窗位置到 UserDefaults
    private func savePosition(_ origin: NSPoint) {
        let pointData = NSStringFromPoint(origin)
        UserDefaults.standard.set(pointData, forKey: Self.positionKey)
    }

    /// 从 UserDefaults 加载保存的位置
    private func loadSavedPosition() -> NSPoint? {
        guard let pointData = UserDefaults.standard.string(forKey: Self.positionKey) else { return nil }
        return NSPointFromString(pointData)
    }
}

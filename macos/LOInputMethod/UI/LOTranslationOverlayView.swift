import AppKit

// MARK: - 翻译浮窗视图

/// 翻译浮窗内容视图，显示原文和翻译结果
/// 样式参考官网产品演示：原文/翻译分别带小标题，中间以简约分割线隔开，
/// 复制按钮位于翻译标题一行右侧。
/// 翻译区使用 NSScrollView + NSTextView，支持多行换行、自动拓展高度，
/// 内容超过最大行数时进入滚动模式并自动滚动到最新内容（底部）。
class LOTranslationOverlayView: NSView {

    // MARK: - 常量

    /// 状态色（不可自定义，固定用于加载/错误状态）
    private enum Theme {
        static let loadingTextColor = NSColor(white: 0.5, alpha: 1.0)
        static let errorTextColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.55, alpha: 1.0)
        static let titleTextColor = NSColor(white: 0.5, alpha: 1.0)
        static let dividerColor = NSColor(white: 0.24, alpha: 1.0)
        static let disabledCopyColor = NSColor(white: 0.35, alpha: 1.0)
    }

    /// 可配置的颜色（由设置驱动）
    private var backgroundColor: NSColor = NSColor(white: 0.12, alpha: 1.0)
    private var originalTextColor: NSColor = NSColor(white: 0.6, alpha: 1.0)
    private var translationTextColor: NSColor = NSColor.white

    /// 布局间距
    private enum Layout {
        static let padding: CGFloat = 16
        static let labelSpacing: CGFloat = 6
        static let sectionSpacing: CGFloat = 12
        static let textFontSize: CGFloat = 14
        static let titleFontSize: CGFloat = 11
        static let cornerRadius: CGFloat = 12
        static let maxWidth: CGFloat = 360
        static let copyButtonSize: CGFloat = 18

        /// 翻译区最大高度（约 9 行），超过此高度后启用滚动
        static let translationMaxHeight: CGFloat = 200

        /// 翻译区最小高度（避免内容很少时过窄）
        static let translationMinHeight: CGFloat = 20

        /// 内容区最小宽度（避免内容很短时窗口过窄）
        static let minContentWidth: CGFloat = 120
    }

    // MARK: - 属性

    /// 原文标题标签
    private let originalTitleLabel: NSTextField

    /// 原文标签（多行自动换行，不截断）
    private let originalLabel: NSTextField

    /// 原文与翻译之间的分割线
    private let dividerView: NSView

    /// 翻译标题标签
    private let translationTitleLabel: NSTextField

    /// 翻译结果滚动容器
    private let translationScrollView: NSScrollView

    /// 翻译结果文本视图
    private let translationTextView: NSTextView

    /// 是否正在加载中
    private var isLoading = false

    /// 复制按钮
    private let copyButton: NSButton

    /// 是否有有效的翻译结果可复制
    private var hasValidTranslation = false

    /// 标记下次布局完成后需要滚动到底部
    private var needsScrollToBottom = false

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        // 原文标题
        originalTitleLabel = LOTranslationOverlayView.makeTitleLabel(text: "原文")

        // 创建原文标签
        originalLabel = NSTextField(labelWithString: "")
        originalLabel.font = NSFont.systemFont(ofSize: Layout.textFontSize, weight: .regular)
        originalLabel.textColor = originalTextColor
        originalLabel.lineBreakMode = .byWordWrapping
        originalLabel.maximumNumberOfLines = 0
        originalLabel.isSelectable = false
        originalLabel.isEditable = false
        originalLabel.cell?.truncatesLastVisibleLine = false
        originalLabel.cell?.wraps = true
        originalLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        originalLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 分割线
        dividerView = NSView()
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = Theme.dividerColor.cgColor

        // 翻译标题
        translationTitleLabel = LOTranslationOverlayView.makeTitleLabel(text: "翻译")

        // 创建翻译文本视图（可滚动、可换行、不截断）
        translationTextView = NSTextView()
        translationTextView.font = NSFont.systemFont(ofSize: Layout.textFontSize, weight: .medium)
        translationTextView.textColor = translationTextColor
        translationTextView.backgroundColor = .clear
        translationTextView.isEditable = false
        translationTextView.isSelectable = true
        translationTextView.isRichText = false
        translationTextView.drawsBackground = false
        translationTextView.textContainerInset = NSSize(width: 0, height: 0)
        translationTextView.textContainer?.lineFragmentPadding = 0
        translationTextView.textContainer?.widthTracksTextView = true
        translationTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        // 自动换行
        translationTextView.isHorizontallyResizable = false
        translationTextView.isVerticallyResizable = true
        translationTextView.autoresizingMask = [.width]
        // 默认空段落属性，确保换行正确
        translationTextView.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            return style
        }()

        // 滚动容器
        translationScrollView = NSScrollView()
        translationScrollView.documentView = translationTextView
        translationScrollView.hasVerticalScroller = true
        translationScrollView.hasHorizontalScroller = false
        translationScrollView.autohidesScrollers = true
        translationScrollView.scrollerStyle = .overlay
        translationScrollView.drawsBackground = false
        translationScrollView.borderType = .noBorder
        translationScrollView.verticalScrollElasticity = .allowed

        // 创建复制按钮
        copyButton = NSButton()
        let copySymbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制翻译内容")?.withSymbolConfiguration(copySymbolConfig)
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = originalTextColor
        copyButton.imageScaling = .scaleProportionallyDown
        copyButton.toolTip = "复制翻译内容"

        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        originalTitleLabel = LOTranslationOverlayView.makeTitleLabel(text: "原文")
        originalLabel = NSTextField(labelWithString: "")
        dividerView = NSView()
        translationTitleLabel = LOTranslationOverlayView.makeTitleLabel(text: "翻译")
        translationTextView = NSTextView()
        translationScrollView = NSScrollView()
        copyButton = NSButton()
        super.init(coder: coder)
        setupView()
    }

    // MARK: - 视图设置

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.masksToBounds = true

        // 添加子视图（不使用 Auto Layout 约束，改用手动 layout 避免 NSPanel
        // 根据 contentView fitting size 自动压缩窗口宽度）
        addSubview(originalTitleLabel)
        addSubview(originalLabel)
        addSubview(dividerView)
        addSubview(translationTitleLabel)
        addSubview(translationScrollView)
        addSubview(copyButton)

        // 配置复制按钮
        copyButton.target = self
        copyButton.action = #selector(copyTranslation)
    }

    /// 创建统一的小标题标签
    private static func makeTitleLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: Layout.titleFontSize, weight: .medium)
        label.textColor = Theme.titleTextColor
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.isSelectable = false
        label.isEditable = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }

    // MARK: - 绘制背景

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: Layout.cornerRadius, yRadius: Layout.cornerRadius)
        path.fill()
    }

    // MARK: - 公开方法

    /// 更新颜色配置（由 LOTranslationOverlay.applyConfig 调用）
    func updateColors(
        backgroundColor: NSColor,
        originalTextColor: NSColor,
        translationTextColor: NSColor
    ) {
        self.backgroundColor = backgroundColor
        self.originalTextColor = originalTextColor
        self.translationTextColor = translationTextColor

        // 原文标签颜色
        originalLabel.textColor = originalTextColor

        // 复制按钮颜色随可用状态变化
        updateCopyButtonAppearance()

        // 翻译文本颜色：仅在显示有效翻译时更新（loading/error 状态保持原色）
        if !isLoading && hasValidTranslation {
            translationTextView.textColor = translationTextColor
        }

        needsDisplay = true
    }

    /// 显示加载状态
    /// - Parameter originalText: 原文
    func showLoading(originalText: String) {
        isLoading = true
        hasValidTranslation = false
        originalLabel.stringValue = originalText
        setTranslationText("翻译中...")
        translationTextView.textColor = Theme.loadingTextColor
        updateCopyButtonAppearance()
        needsDisplay = true
    }

    /// 显示翻译结果
    /// - Parameters:
    ///   - original: 原文
    ///   - translation: 翻译结果
    func update(original: String, translation: String) {
        isLoading = false
        hasValidTranslation = true
        originalLabel.stringValue = original
        setTranslationText(translation)
        translationTextView.textColor = translationTextColor
        updateCopyButtonAppearance()
        needsDisplay = true
    }

    /// 显示翻译错误
    /// - Parameters:
    ///   - originalText: 原文
    ///   - error: 错误信息
    func showError(originalText: String, error: String) {
        isLoading = false
        hasValidTranslation = false
        originalLabel.stringValue = originalText
        setTranslationText("⚠️ \(error)")
        translationTextView.textColor = Theme.errorTextColor
        updateCopyButtonAppearance()
        needsDisplay = true
    }

    /// 仅更新原文（防抖期间使用，避免闪烁）
    /// - Parameter text: 新的原文
    func updateOriginalOnly(_ text: String) {
        originalLabel.stringValue = text
    }

    /// 仅更新翻译结果
    /// - Parameter text: 翻译结果文本
    func updateTranslation(_ text: String) {
        isLoading = false
        hasValidTranslation = true
        setTranslationText(text)
        translationTextView.textColor = translationTextColor
        updateCopyButtonAppearance()
        needsDisplay = true
    }

    /// 计算显示内容所需的最小尺寸
    /// - Returns: 建议的视图尺寸
    /// 核心逻辑：用 layoutManager 准确测量翻译实际占用宽度，取原文和翻译中较宽者，
    /// 不小于最小宽度，不大于最大宽度。避免短原文限制长翻译导致提前换行。
    func preferredSize() -> NSSize {
        let padding = Layout.padding
        let maxContentWidth = Layout.maxWidth - padding * 2

        // 用 layoutManager 在最大宽度下测量翻译实际占用尺寸（和渲染完全一致）
        let (translationUsedWidth, translationFullHeight) = measureTranslationLayout(maxWidth: maxContentWidth)
        let translationHeight = min(
            max(translationFullHeight, Layout.translationMinHeight),
            Layout.translationMaxHeight
        )

        // 原文在最大宽度下的占用宽度
        let originalSizeFull = originalLabel.sizeThatFits(
            NSSize(width: maxContentWidth, height: .greatestFiniteMagnitude)
        )

        // 内容宽度 = 两者最宽者 + 2pt 余量（防浮点误差导致翻译恰好换行），
        // 不小于最小宽度，不大于最大宽度
        let contentWidth = min(
            max(translationUsedWidth + 2, originalSizeFull.width, Layout.minContentWidth),
            maxContentWidth
        )
        let viewWidth = contentWidth + padding * 2

        // 用确定的宽度测量各部分高度
        let originalTitleSize = originalTitleLabel.sizeThatFits(
            NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        let originalSize = originalLabel.sizeThatFits(
            NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        let translationTitleSize = translationTitleLabel.sizeThatFits(
            NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )

        let contentHeight = originalTitleSize.height
            + Layout.labelSpacing
            + originalSize.height
            + Layout.sectionSpacing
            + 1 // divider
            + Layout.sectionSpacing
            + translationTitleSize.height
            + Layout.labelSpacing
            + translationHeight

        let result = NSSize(
            width: viewWidth,
            height: contentHeight + padding * 2
        )
        return result
    }

    // MARK: - 私有方法

    /// 设置翻译文本，标记需要在布局完成后滚动到底部
    private func setTranslationText(_ text: String) {
        translationTextView.string = text
        // 布局完成后再滚动，避免尺寸未更新时滚动位置错误
        needsScrollToBottom = true
    }

    /// 将翻译文本视图滚动到底部
    private func scrollToBottom() {
        // 强制布局完成，确保 bounds 正确
        if let layoutManager = translationTextView.layoutManager,
           let textContainer = translationTextView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }

        let documentView = translationScrollView.documentView
        guard let documentView = documentView else { return }
        let bottom = NSPoint(
            x: 0,
            y: max(0, documentView.bounds.maxY - translationScrollView.bounds.height)
        )
        translationScrollView.contentView.scroll(to: bottom)
        // 同步滚动条位置
        translationScrollView.reflectScrolledClipView(translationScrollView.contentView)
    }

    override func layout() {
        super.layout()

        let padding = Layout.padding
        let contentWidth = bounds.width - padding * 2
        guard contentWidth > 0 else { return }

        // macOS 坐标系：左下角原点，从顶部向下布局
        var y = bounds.maxY - padding

        // 原文标题
        let origTitleH = originalTitleLabel.sizeThatFits(
            NSSize(width: contentWidth, height: .greatestFiniteMagnitude)).height
        originalTitleLabel.frame = NSRect(x: padding, y: y - origTitleH,
                                          width: contentWidth, height: origTitleH)
        y -= origTitleH + Layout.labelSpacing

        // 原文
        let origH = originalLabel.sizeThatFits(
            NSSize(width: contentWidth, height: .greatestFiniteMagnitude)).height
        originalLabel.frame = NSRect(x: padding, y: y - origH,
                                     width: contentWidth, height: origH)
        y -= origH + Layout.sectionSpacing

        // 分割线
        dividerView.frame = NSRect(x: padding, y: y - 1, width: contentWidth, height: 1)
        y -= 1 + Layout.sectionSpacing

        // 翻译标题 + 复制按钮（同一行）
        let transTitleH = translationTitleLabel.sizeThatFits(
            NSSize(width: contentWidth, height: .greatestFiniteMagnitude)).height
        let titleRowH = max(transTitleH, Layout.copyButtonSize)
        translationTitleLabel.frame = NSRect(
            x: padding, y: y - transTitleH,
            width: contentWidth - Layout.copyButtonSize - Layout.labelSpacing,
            height: transTitleH)
        copyButton.frame = NSRect(
            x: bounds.maxX - padding - Layout.copyButtonSize,
            y: y - titleRowH / 2 - Layout.copyButtonSize / 2,
            width: Layout.copyButtonSize, height: Layout.copyButtonSize)
        y -= titleRowH + Layout.labelSpacing

        // 翻译滚动视图（填满剩余空间）
        let scrollH = y - padding
        translationScrollView.frame = NSRect(x: padding, y: padding,
                                             width: contentWidth, height: max(0, scrollH))

        if needsScrollToBottom {
            scrollToBottom()
            needsScrollToBottom = false
        }
    }

    /// 用 layoutManager 测量翻译在指定最大宽度下的实际占用尺寸
    /// 和实际渲染完全一致，避免 NSString.size 的浮点误差。
    /// - Parameter maxWidth: 可用最大宽度
    /// - Returns: (实际占用宽度, 实际占用高度)
    private func measureTranslationLayout(maxWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        guard !translationTextView.string.isEmpty else {
            return (0, Layout.translationMinHeight)
        }

        let textContainer = translationTextView.textContainer!
        let layoutManager = translationTextView.layoutManager!

        // 临时设置容器宽度为最大宽度进行测量
        let oldTracksWidth = textContainer.widthTracksTextView
        let oldSize = textContainer.containerSize

        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        // 恢复原状
        textContainer.widthTracksTextView = oldTracksWidth
        textContainer.containerSize = oldSize

        let width = ceil(usedRect.width)
        let height = ceil(usedRect.height) + 1 // +1pt 安全余量防止末行截断
        return (width, height)
    }

    /// 根据当前状态更新复制按钮样式
    private func updateCopyButtonAppearance() {
        copyButton.isEnabled = hasValidTranslation
        copyButton.contentTintColor = hasValidTranslation ? originalTextColor : Theme.disabledCopyColor
    }

    // MARK: - 复制

    /// 复制翻译结果到剪贴板
    @objc private func copyTranslation() {
        guard hasValidTranslation else { return }
        let text = translationTextView.string
        guard !text.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 视觉反馈：临时切换为对勾图标
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已复制")?.withSymbolConfiguration(symbolConfig)
        copyButton.contentTintColor = NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制翻译内容")?.withSymbolConfiguration(symbolConfig)
            self.updateCopyButtonAppearance()
        }
    }
}

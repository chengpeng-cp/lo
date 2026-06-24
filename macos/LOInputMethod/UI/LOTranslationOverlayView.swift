import AppKit

// MARK: - 翻译浮窗视图

/// 翻译浮窗内容视图，显示原文和翻译结果
/// 原文灰色显示，翻译白色显示，半透明深色背景
/// 翻译区使用 NSScrollView + NSTextView，支持多行换行、自动拓展高度，
/// 内容超过最大行数时进入滚动模式并自动滚动到最新内容（底部）。
class LOTranslationOverlayView: NSView {

    // MARK: - 常量

    /// 状态色（不可自定义，固定用于加载/错误状态）
    private enum Theme {
        static let loadingTextColor = NSColor(white: 0.5, alpha: 1.0)
        static let errorTextColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.55, alpha: 1.0)
    }

    /// 可配置的颜色（由设置驱动）
    private var backgroundColor: NSColor = NSColor(white: 0.12, alpha: 1.0)
    private var originalTextColor: NSColor = NSColor(white: 0.6, alpha: 1.0)
    private var translationTextColor: NSColor = NSColor.white

    /// 布局间距
    private enum Layout {
        static let padding: CGFloat = 14
        static let labelSpacing: CGFloat = 8
        static let fontSize: CGFloat = 14
        static let cornerRadius: CGFloat = 10
        static let maxWidth: CGFloat = 360
        static let copyButtonSize: CGFloat = 18

        /// 翻译区最大高度（约 9 行），超过此高度后启用滚动
        static let translationMaxHeight: CGFloat = 200

        /// 翻译区最小高度（避免内容很少时过窄）
        static let translationMinHeight: CGFloat = 20
    }

    // MARK: - 属性

    /// 原文标签（多行自动换行，不截断）
    private let originalLabel: NSTextField

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

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        // 创建原文标签
        originalLabel = NSTextField(labelWithString: "")
        originalLabel.font = NSFont.systemFont(ofSize: Layout.fontSize, weight: .regular)
        originalLabel.textColor = originalTextColor
        originalLabel.lineBreakMode = .byWordWrapping
        originalLabel.maximumNumberOfLines = 0
        originalLabel.isSelectable = false
        originalLabel.isEditable = false
        originalLabel.cell?.truncatesLastVisibleLine = false
        originalLabel.cell?.wraps = true
        originalLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        originalLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 创建翻译文本视图（可滚动、可换行、不截断）
        translationTextView = NSTextView()
        translationTextView.font = NSFont.systemFont(ofSize: Layout.fontSize, weight: .medium)
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
        originalLabel = NSTextField(labelWithString: "")
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

        // 添加子视图
        addSubview(originalLabel)
        addSubview(translationScrollView)
        addSubview(copyButton)

        // 禁用自动翻译约束
        originalLabel.translatesAutoresizingMaskIntoConstraints = false
        translationScrollView.translatesAutoresizingMaskIntoConstraints = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        // 配置复制按钮
        copyButton.target = self
        copyButton.action = #selector(copyTranslation)

        // 设置约束
        NSLayoutConstraint.activate([
            // 原文标签
            originalLabel.topAnchor.constraint(equalTo: topAnchor, constant: Layout.padding),
            originalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.padding),
            originalLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -Layout.labelSpacing),

            // 翻译滚动视图
            translationScrollView.topAnchor.constraint(
                equalTo: originalLabel.bottomAnchor, constant: Layout.labelSpacing
            ),
            translationScrollView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Layout.padding
            ),
            translationScrollView.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Layout.padding
            ),
            translationScrollView.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -Layout.padding
            ),

            // 复制按钮
            copyButton.topAnchor.constraint(equalTo: topAnchor, constant: Layout.padding),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.padding),
            copyButton.widthAnchor.constraint(equalToConstant: Layout.copyButtonSize),
            copyButton.heightAnchor.constraint(equalToConstant: Layout.copyButtonSize),
        ])
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

        // 原文标签与复制按钮颜色始终更新
        originalLabel.textColor = originalTextColor
        copyButton.contentTintColor = originalTextColor

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
        needsDisplay = true
    }

    /// 显示翻译错误
    /// - Parameters:
    ///   - originalText: 原文
    ///   - error: 错误信息
    func showError(originalText: String, error: String) {
        isLoading = false
        originalLabel.stringValue = originalText
        setTranslationText("⚠️ \(error)")
        translationTextView.textColor = Theme.errorTextColor
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
        needsDisplay = true
    }

    /// 计算显示内容所需的最小尺寸
    /// - Returns: 建议的视图尺寸
    func preferredSize() -> NSSize {
        let maxWidth = Layout.maxWidth - Layout.padding * 2
        let originalMaxWidth = maxWidth - Layout.copyButtonSize - Layout.labelSpacing

        let originalSize = originalLabel.sizeThatFits(
            NSSize(width: originalMaxWidth, height: .greatestFiniteMagnitude)
        )

        // 翻译区高度：内容实际高度，但不超过最大高度（超出则滚动）
        let translationContentHeight = measureTranslationHeight(width: maxWidth)
        let translationHeight = min(
            max(translationContentHeight, Layout.translationMinHeight),
            Layout.translationMaxHeight
        )

        let contentWidth = max(originalSize.width, maxWidth)
        let contentHeight = originalSize.height
            + Layout.labelSpacing
            + translationHeight

        return NSSize(
            width: min(contentWidth + Layout.padding * 2, Layout.maxWidth),
            height: contentHeight + Layout.padding * 2
        )
    }

    // MARK: - 私有方法

    /// 设置翻译文本，并自动滚动到底部（显示最新内容）
    private func setTranslationText(_ text: String) {
        translationTextView.string = text
        // 滚动到底部，确保用户始终看到最新内容
        scrollToBottom()
    }

    /// 将翻译文本视图滚动到底部
    private func scrollToBottom() {
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

    /// 测量翻译内容在指定宽度下的自然高度
    /// - Parameter width: 可用宽度
    /// - Returns: 文本内容高度
    private func measureTranslationHeight(width: CGFloat) -> CGFloat {
        guard !translationTextView.string.isEmpty else { return Layout.translationMinHeight }
        let font = translationTextView.font ?? NSFont.systemFont(ofSize: Layout.fontSize)
        let style = translationTextView.defaultParagraphStyle ?? NSParagraphStyle.default

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
        ]

        let attributed = NSAttributedString(string: translationTextView.string, attributes: attributes)
        // width 减去 lineFragmentPadding（已在 setupView 中设为 0，这里无需调整）
        let boundingRect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        // 向上取整避免因浮点误差导致少算一行
        return ceil(boundingRect.height)
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
            self.copyButton.contentTintColor = self.originalTextColor
        }
    }
}

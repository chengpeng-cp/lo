import AppKit

// MARK: - 翻译浮窗视图

/// 翻译浮窗内容视图，显示原文和翻译结果
/// 原文灰色显示，翻译白色显示，半透明深色背景
class LOTranslationOverlayView: NSView {

    // MARK: - 常量

    /// 深色主题配色
    private enum Theme {
        static let backgroundColor = NSColor(white: 0.12, alpha: 0.92)
        static let originalTextColor = NSColor(white: 0.6, alpha: 1.0)
        static let translationTextColor = NSColor.white
        static let loadingTextColor = NSColor(white: 0.5, alpha: 1.0)
    }

    /// 布局间距
    private enum Layout {
        static let padding: CGFloat = 14
        static let labelSpacing: CGFloat = 8
        static let fontSize: CGFloat = 14
        static let cornerRadius: CGFloat = 10
        static let maxWidth: CGFloat = 360
    }

    // MARK: - 属性

    /// 原文标签
    private let originalLabel: NSTextField

    /// 翻译结果标签
    private let translationLabel: NSTextField

    /// 是否正在加载中
    private var isLoading = false

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        // 创建原文标签
        originalLabel = NSTextField(labelWithString: "")
        originalLabel.font = NSFont.systemFont(ofSize: Layout.fontSize, weight: .regular)
        originalLabel.textColor = Theme.originalTextColor
        originalLabel.lineBreakMode = .byTruncatingTail
        originalLabel.maximumNumberOfLines = 2
        originalLabel.isSelectable = false
        originalLabel.isEditable = false
        originalLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        originalLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 创建翻译标签
        translationLabel = NSTextField(labelWithString: "")
        translationLabel.font = NSFont.systemFont(ofSize: Layout.fontSize, weight: .medium)
        translationLabel.textColor = Theme.translationTextColor
        translationLabel.lineBreakMode = .byTruncatingTail
        translationLabel.maximumNumberOfLines = 3
        translationLabel.isSelectable = false
        translationLabel.isEditable = false
        translationLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        translationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        originalLabel = NSTextField(labelWithString: "")
        translationLabel = NSTextField(labelWithString: "")
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
        addSubview(translationLabel)

        // 禁用自动翻译约束
        originalLabel.translatesAutoresizingMaskIntoConstraints = false
        translationLabel.translatesAutoresizingMaskIntoConstraints = false

        // 设置约束
        NSLayoutConstraint.activate([
            // 原文标签
            originalLabel.topAnchor.constraint(equalTo: topAnchor, constant: Layout.padding),
            originalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.padding),
            originalLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.padding),
            originalLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.maxWidth - Layout.padding * 2),

            // 翻译标签
            translationLabel.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: Layout.labelSpacing),
            translationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.padding),
            translationLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.padding),
            translationLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.maxWidth - Layout.padding * 2),
            translationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.padding),
        ])
    }

    // MARK: - 绘制背景

    override func draw(_ dirtyRect: NSRect) {
        Theme.backgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: Layout.cornerRadius, yRadius: Layout.cornerRadius)
        path.fill()
    }

    // MARK: - 公开方法

    /// 显示加载状态
    /// - Parameter originalText: 原文
    func showLoading(originalText: String) {
        isLoading = true
        originalLabel.stringValue = originalText
        translationLabel.stringValue = "翻译中..."
        translationLabel.textColor = Theme.loadingTextColor
        needsDisplay = true
    }

    /// 显示翻译结果
    /// - Parameters:
    ///   - original: 原文
    ///   - translation: 翻译结果
    func update(original: String, translation: String) {
        isLoading = false
        originalLabel.stringValue = original
        translationLabel.stringValue = translation
        translationLabel.textColor = Theme.translationTextColor
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
        translationLabel.stringValue = text
        translationLabel.textColor = Theme.translationTextColor
        needsDisplay = true
    }

    /// 计算显示内容所需的最小尺寸
    /// - Returns: 建议的视图尺寸
    func preferredSize() -> NSSize {
        let maxWidth = Layout.maxWidth - Layout.padding * 2

        let originalSize = originalLabel.sizeThatFits(NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let translationSize = translationLabel.sizeThatFits(NSSize(width: maxWidth, height: .greatestFiniteMagnitude))

        let contentWidth = max(originalSize.width, translationSize.width)
        let contentHeight = originalSize.height + Layout.labelSpacing + translationSize.height

        return NSSize(
            width: min(contentWidth + Layout.padding * 2, Layout.maxWidth),
            height: contentHeight + Layout.padding * 2
        )
    }
}

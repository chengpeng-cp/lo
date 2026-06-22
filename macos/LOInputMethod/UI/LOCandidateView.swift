import AppKit

// MARK: - 候选词视图

/// 候选词列表视图，以水平排列方式显示候选词
/// 每个候选词包含序号和文本，支持高亮选中状态
class LOCandidateView: NSView {

    // MARK: - 常量

    /// 深色主题配色
    private enum Theme {
        static let backgroundColor = NSColor(white: 0.15, alpha: 0.95)
        static let textColor = NSColor.white
        static let indexColor = NSColor(white: 0.6, alpha: 1.0)
        /// 高亮候选词的强调色（下划线 + 序号），对齐系统/微信输入法
        static let highlightColor = NSColor.systemBlue
        /// 高亮候选词文本仍为白色（无填充背景，靠下划线区分）
        static let highlightTextColor = NSColor.white
        static let separatorColor = NSColor(white: 0.3, alpha: 0.5)
    }

    /// 布局间距
    private enum Layout {
        static let cellPadding: CGFloat = 8
        static let cellSpacing: CGFloat = 2
        static let indexTextGap: CGFloat = 3
        static let fontSize: CGFloat = 16
        static let indexFontSize: CGFloat = 13
        static let cornerRadius: CGFloat = 6
        static let verticalPadding: CGFloat = 6
        /// 高亮下划线距底部偏移
        static let underlineBottomInset: CGFloat = 2
        /// 高亮下划线粗细
        static let underlineThickness: CGFloat = 2
    }

    // MARK: - 属性

    /// 候选词列表
    var candidates: [Candidate] = [] {
        didSet { needsLayout = true }
    }

    /// 当前高亮的候选词索引
    var highlightedIndex: Int = -1 {
        didSet { needsDisplay = true }
    }

    /// 候选词点击回调
    var onCandidateSelected: ((Int) -> Void)?

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.masksToBounds = true
    }

    // MARK: - 布局

    /// 计算显示所有候选词所需的最小尺寸
    /// - Returns: 建议的视图尺寸
    func preferredSize() -> NSSize {
        guard !candidates.isEmpty else {
            return NSSize(width: 0, height: 0)
        }

        var totalWidth: CGFloat = 0
        let textHeight = Layout.fontSize

        for (index, candidate) in candidates.enumerated() {
            let indexStr = "\(index + 1)"
            let indexWidth = indexStr.size(withAttributes: indexAttributes()).width
            let textWidth = candidate.text.size(withAttributes: textAttributes()).width
            let cellWidth = Layout.cellPadding + indexWidth + Layout.indexTextGap + textWidth + Layout.cellPadding
            totalWidth += cellWidth

            // 非最后一个候选词，添加间距
            if index < candidates.count - 1 {
                totalWidth += Layout.cellSpacing
            }
        }

        let height = Layout.verticalPadding + textHeight + Layout.verticalPadding
        return NSSize(width: totalWidth, height: height)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 绘制背景
        Theme.backgroundColor.setFill()
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: Layout.cornerRadius, yRadius: Layout.cornerRadius)
        bgPath.fill()

        guard !candidates.isEmpty else { return }

        var cellX: CGFloat = 0
        let cellHeight = bounds.height

        for (index, candidate) in candidates.enumerated() {
            let indexStr = "\(index + 1)"
            let indexWidth = indexStr.size(withAttributes: indexAttributes()).width
            let textWidth = candidate.text.size(withAttributes: textAttributes()).width
            let cellWidth = Layout.cellPadding + indexWidth + Layout.indexTextGap + textWidth + Layout.cellPadding

            let cellRect = NSRect(x: cellX, y: 0, width: cellWidth, height: cellHeight)

            // 绘制高亮：底部下划线（对齐系统/微信输入法，不填充整个 cell）
            if index == highlightedIndex {
                Theme.highlightColor.setStroke()
                let underlineY = cellRect.minY + Layout.underlineBottomInset
                let underlinePath = NSBezierPath()
                underlinePath.move(to: NSPoint(x: cellRect.minX + 2, y: underlineY))
                underlinePath.line(to: NSPoint(x: cellRect.maxX - 2, y: underlineY))
                underlinePath.lineWidth = Layout.underlineThickness
                underlinePath.lineCapStyle = .round
                underlinePath.stroke()
            }

            // 绘制序号（高亮时用强调色，非高亮用灰色）
            let indexPoint = NSPoint(
                x: cellX + Layout.cellPadding,
                y: (cellHeight - Layout.indexFontSize) / 2
            )
            indexStr.draw(at: indexPoint, withAttributes: indexAttributes(highlighted: index == highlightedIndex))

            // 绘制候选词文本
            let textPoint = NSPoint(
                x: cellX + Layout.cellPadding + indexWidth + Layout.indexTextGap,
                y: (cellHeight - Layout.fontSize) / 2
            )
            candidate.text.draw(at: textPoint, withAttributes: textAttributes(highlighted: index == highlightedIndex))

            // 绘制分隔线（非最后一个）
            if index < candidates.count - 1 {
                Theme.separatorColor.setStroke()
                let separatorPath = NSBezierPath()
                separatorPath.move(to: NSPoint(x: cellX + cellWidth + Layout.cellSpacing / 2, y: 4))
                separatorPath.line(to: NSPoint(x: cellX + cellWidth + Layout.cellSpacing / 2, y: cellHeight - 4))
                separatorPath.lineWidth = 0.5
                separatorPath.stroke()
            }

            cellX += cellWidth + Layout.cellSpacing
        }
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        guard let index = candidateIndex(at: clickPoint) else { return }
        onCandidateSelected?(index)
    }

    // MARK: - 私有方法

    /// 获取指定位置的候选词索引
    private func candidateIndex(at point: NSPoint) -> Int? {
        var cellX: CGFloat = 0

        for (index, candidate) in candidates.enumerated() {
            let indexStr = "\(index + 1)"
            let indexWidth = indexStr.size(withAttributes: indexAttributes()).width
            let textWidth = candidate.text.size(withAttributes: textAttributes()).width
            let cellWidth = Layout.cellPadding + indexWidth + Layout.indexTextGap + textWidth + Layout.cellPadding

            if point.x >= cellX && point.x <= cellX + cellWidth {
                return index
            }
            cellX += cellWidth + Layout.cellSpacing
        }
        return nil
    }

    /// 序号文本属性
    private func indexAttributes(highlighted: Bool = false) -> [NSAttributedString.Key: Any] {
        // 高亮时用强调色（蓝），非高亮用灰色。下划线样式下序号本身即高亮标识。
        let color = highlighted ? Theme.highlightColor : Theme.indexColor
        return [
            .font: NSFont.monospacedSystemFont(ofSize: Layout.indexFontSize, weight: highlighted ? .semibold : .regular),
            .foregroundColor: color
        ]
    }

    /// 候选词文本属性
    private func textAttributes(highlighted: Bool = false) -> [NSAttributedString.Key: Any] {
        let color = highlighted ? Theme.highlightTextColor : Theme.textColor
        return [
            .font: NSFont.systemFont(ofSize: Layout.fontSize, weight: .medium),
            .foregroundColor: color
        ]
    }
}

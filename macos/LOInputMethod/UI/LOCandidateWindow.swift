import AppKit
import InputMethodKit

// MARK: - 候选词窗口

/// 候选词浮动窗口，显示在光标附近
/// 使用 NSPanel 实现，支持光标跟随定位和翻页
class LOCandidateWindow {

    // MARK: - 属性

    /// 底层面板
    private let panel: NSPanel

    /// 候选词视图
    private let candidateView: LOCandidateView

    /// 当前候选词列表
    private(set) var candidates: [Candidate] = []

    /// 当前高亮索引
    private(set) var selectedIndex: Int = 0

    /// 候选词选中回调
    var onCandidateSelected: ((Int) -> Void)?

    /// 翻页回调
    var onPageChange: ((Bool) -> Void)?

    // MARK: - 初始化

    init() {
        // 创建无边框弹出菜单级别的面板
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false

        // 创建候选词视图
        candidateView = LOCandidateView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        candidateView.onCandidateSelected = { [weak self] index in
            self?.handleCandidateClick(index)
        }
        panel.contentView = candidateView
    }

    // MARK: - 显示/隐藏

    /// 显示候选词窗口
    /// - Parameters:
    ///   - candidates: 候选词列表
    ///   - client: 输入法客户端，用于获取光标位置
    func show(candidates: [Candidate], client: IMKTextInput?) {
        self.candidates = candidates
        selectedIndex = 0
        candidateView.candidates = candidates
        candidateView.highlightedIndex = 0

        // 计算所需尺寸
        let size = candidateView.preferredSize()
        guard size.width > 0 else {
            hide()
            return
        }

        // 更新视图和面板尺寸
        candidateView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)

        // 定位到光标附近
        positionNearCursor(client: client)

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    /// 隐藏候选词窗口
    func hide() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// 窗口是否可见
    var isVisible: Bool {
        return panel.isVisible
    }

    // MARK: - 导航

    /// 高亮下一个候选词
    func selectNext() {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % candidates.count
        candidateView.highlightedIndex = selectedIndex
    }

    /// 高亮上一个候选词
    func selectPrevious() {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + candidates.count) % candidates.count
        candidateView.highlightedIndex = selectedIndex
    }

    /// 方向键导航候选词（对齐微信输入法）
    /// - → / ↓：移到下一个候选词；已在最后一个时翻下一页
    /// - ← / ↑：移到上一个候选词；已在第一个时翻上一页
    /// - Returns: 是否已处理（true 表示事件被吞，false 表示放行给 Rime）
    func navigateByArrow(forward: Bool) -> Bool {
        guard !candidates.isEmpty else { return false }

        if forward {
            if selectedIndex < candidates.count - 1 {
                // 列表内后移
                selectedIndex += 1
                candidateView.highlightedIndex = selectedIndex
            } else {
                // 已在最后一个，翻下一页
                onPageChange?(false)
            }
        } else {
            if selectedIndex > 0 {
                // 列表内前移
                selectedIndex -= 1
                candidateView.highlightedIndex = selectedIndex
            } else {
                // 已在第一个，翻上一页
                onPageChange?(true)
            }
        }
        return true
    }

    /// 翻页：向下翻页
    func pageDown() {
        onPageChange?(false)
    }

    /// 翻页：向上翻页
    func pageUp() {
        onPageChange?(true)
    }

    /// 获取当前选中的候选词索引
    func selectedCandidateIndex() -> Int {
        return selectedIndex
    }

    // MARK: - 定位

    /// 将窗口定位到光标附近
    /// - Parameter client: 输入法客户端，用于获取光标位置
    private func positionNearCursor(client: IMKTextInput?) {
        guard let client = client else {
            // 无客户端时，定位到屏幕中央
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(
                    x: screenRect.midX - panel.frame.width / 2,
                    y: screenRect.midY - panel.frame.height / 2
                ))
            }
            return
        }

        // 通过 IMKTextInput 获取光标位置
        var rect = NSRect.zero

        // 尝试获取光标所在字符的屏幕坐标
        let _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)

        if rect.origin.x != 0 || rect.origin.y != 0 {
            // 成功获取光标位置，将候选词窗口放在光标下方
            positionBelowCursor(rect, screen: NSScreen.main)
        } else {
            // 无法获取光标位置，使用鼠标位置
            let mouseLocation = NSEvent.mouseLocation
            positionBelowCursor(
                NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 0, height: 0),
                screen: NSScreen.main
            )
        }
    }

    /// 将窗口定位到光标矩形下方
    private func positionBelowCursor(_ cursorRect: NSRect, screen: NSScreen?) {
        guard let screen = screen else { return }
        let screenRect = screen.visibleFrame
        let panelSize = panel.frame.size

        // 默认放在光标下方
        var originX = cursorRect.origin.x
        var originY = cursorRect.origin.y - panelSize.height - 4

        // 水平方向：确保不超出屏幕右侧
        if originX + panelSize.width > screenRect.maxX {
            originX = screenRect.maxX - panelSize.width - 4
        }
        // 水平方向：确保不超出屏幕左侧
        if originX < screenRect.minX {
            originX = screenRect.minX + 4
        }

        // 垂直方向：如果下方空间不足，放到光标上方
        if originY < screenRect.minY {
            originY = cursorRect.origin.y + cursorRect.height + 4
        }
        // 垂直方向：确保不超出屏幕上方
        if originY + panelSize.height > screenRect.maxY {
            originY = screenRect.maxY - panelSize.height - 4
        }

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    // MARK: - 事件处理

    /// 处理候选词点击
    private func handleCandidateClick(_ index: Int) {
        selectedIndex = index
        onCandidateSelected?(index)
    }
}

import AppKit

// MARK: - 设置窗口控制器

/// 语镜设置窗口控制器
/// 管理"语镜设置"窗口的生命周期和交互
class LOSettingsWindow: NSWindowController {

    /// 单例，确保只有一个设置窗口
    static let shared = LOSettingsWindow()

    /// 设置视图
    private var settingsView: LOSettingsView!

    /// 滚动视图
    private var scrollView: NSScrollView!

    // MARK: - 初始化

    private init() {
        // 创建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "语镜设置"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        // 创建滚动视图（内容超过窗口高度时自动滚动）
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        scrollView = NSScrollView(frame: NSRect(origin: .zero, size: contentSize))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        // 自动布局：滚动视图钉到窗口内容四边
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = scrollView

        // 创建设置视图（Auto Layout，高度由内容撑开）
        settingsView = LOSettingsView(frame: NSRect(origin: .zero, size: contentSize))
        settingsView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = settingsView

        // 约束设置视图：宽度跟随 clipView（避免水平滚动），上下贴合
        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            settingsView.topAnchor.constraint(equalTo: clipView.topAnchor),
            settingsView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            // 约束 bottom，让内容自然撑高；clipView 会处理滚动
            settingsView.bottomAnchor.constraint(lessThanOrEqualTo: clipView.bottomAnchor),
            // 宽度等于 clipView 宽度，防止水平滚动条出现
            settingsView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
            // 最小高度兜底：即便内容尚未布局完成，documentView 也至少有窗口内容高度，
            // 避免 Auto Layout 在小屏上把高度塌缩为 0 导致内容不可见
            settingsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: - 公开接口

    /// 显示设置窗口并带到前台
    func show() {
        guard let window = window else { return }

        // 刷新设置数据
        settingsView.reloadSettings()

        // 1. 先激活本进程，确保非激活的 LSUIElement 后台 app 能让窗口成为 key window。
        //    AppDelegate.openSettings() 已激活一次，这里再确认一次（重复激活无害）。
        NSApp.activate(ignoringOtherApps: true)

        // 2. 多屏正确居中：跟随当前鼠标所在屏，而不是 NSScreen.main（菜单栏屏=内置屏）。
        //    这样从外接显示器点击输入法菜单时，设置窗口出现在用户当前操作的那块屏上。
        centerOnCurrentScreen(window)

        // 3. 布局完成后再读取尺寸日志，避免读到未布局的初始值
        window.contentView?.layoutSubtreeIfNeeded()
        let frame = settingsView.frame
        debugLog("设置窗口打开, 视图尺寸: \(Int(frame.width))x\(Int(frame.height))")

        // 4. 显示窗口并带到前台；orderFrontRegardless 作为非激活兜底
        window.makeKeyAndOrderFront(nil)
        if !window.isKeyWindow {
            window.orderFrontRegardless()
        }

        // 5. 滚动到顶部，确保「语境设置」首屏可见
        //    AppKit 坐标系原点在左下角，documentView 顶部 = y 最大处。
        //    layoutSubtreeIfNeeded 后 bounds 已是真实内容高度，坐标可信。
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            // 滚动到 documentView 顶部：构造顶部 1pt 矩形
            let docHeight = self.settingsView.bounds.height
            let topRect = NSRect(
                origin: NSPoint(x: 0, y: max(docHeight - 1, 0)),
                size: NSSize(width: self.settingsView.bounds.width, height: 1)
            )
            self.scrollView.contentView.scrollToVisible(topRect)
        }
    }

    /// 将窗口在「当前鼠标所在屏」的 visibleFrame 内居中
    /// 多屏场景下跟随鼠标，避免窗口跑到内置屏（NSScreen.main = 菜单栏屏）
    private func centerOnCurrentScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        // 找到鼠标所在的屏幕
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main
        guard let screen = screen else {
            window.center()
            return
        }
        let screenRect = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: screenRect.midX - windowSize.width / 2,
            y: screenRect.midY - windowSize.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

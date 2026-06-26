import AppKit

// MARK: - 设置窗口控制器

/// 语境设置窗口控制器
/// 管理"语境设置"窗口的生命周期和交互
class LOSettingsWindow: NSWindowController {

    /// 单例，确保只有一个设置窗口
    static let shared = LOSettingsWindow()

    /// 设置视图
    private var settingsView: LOSettingsView!

    // MARK: - 初始化

    private init() {
        // 创建窗口（固定内容尺寸，避免被内容撑大）
        let windowSize = NSSize(width: 780, height: 520)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "语境输入法设置"
        window.isReleasedWhenClosed = false
        // 固定窗口内容尺寸：不允许用户或内容改变窗口大小
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize
        window.center()

        super.init(window: window)

        // 监听窗口关闭事件，确保关闭时保存所有未提交的编辑
        window.delegate = self

        // 创建设置视图（内部已包含左侧 tab 导航与右侧滚动内容区）
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        settingsView = LOSettingsView(frame: NSRect(origin: .zero, size: contentSize))
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = settingsView

        // 设置视图钉到窗口内容四边
        NSLayoutConstraint.activate([
            settingsView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            settingsView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            settingsView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
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

// MARK: - NSWindowDelegate

extension LOSettingsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时提交所有未保存的编辑并保存设置，
        // 确保用户在输入框中填写但未按回车/未切换焦点的内容不会丢失
        settingsView.commitAndSave()
    }
}

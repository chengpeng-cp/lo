import AppKit

// MARK: - 应用入口

/// 语境输入法入口，创建应用并设置代理
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

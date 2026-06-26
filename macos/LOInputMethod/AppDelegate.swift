import AppKit
import InputMethodKit

// MARK: - 应用代理

/// 语境输入法应用代理，负责初始化输入法服务器
class AppDelegate: NSObject, NSApplicationDelegate {

    /// 单例引用，供输入法菜单（IMK menu）作为 target 强引用，
    /// 避免 NSApp.delegate 在 LSUIElement 后台 app 时序下为 nil
    static var shared: AppDelegate!

    /// 输入法服务器，负责与系统输入法框架通信
    var server: IMKServer?

    /// 设置窗口
    var settingsWindow: LOSettingsWindow?

    /// Rime 引擎
    let rimeEngine = RimeEngine()

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 记录单例引用，供菜单 target 使用
        AppDelegate.shared = self

        // 写调试日志到 Rime 用户目录
        let logPath = NSHomeDirectory() + "/Library/Rime/LOInputMethod.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let startMsg = "[\(timestamp)] === 输入法进程启动 ===\n"
        if let data = startMsg.data(using: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }

        // 初始化 Rime 引擎
        rimeEngine.initialize()

        // 初始化 IMKServer，连接名需与 Info.plist 中 InputMethodConnectionName 一致
        server = IMKServer(
            name: "LOInputMethod_Connection",
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

        // 追加日志
        let serverMsg = "[\(timestamp)] IMKServer 已创建\n"
        if let data = serverMsg.data(using: .utf8),
           let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }

        // CapsLock 中英切换：靠 Info.plist 的 TICapsLockLanguageSwitchCapable=true
        // 交给 macOS 系统原生处理（对齐 fcitx5-macos 方案）。
        // 不使用 CGEventTap（那样需要辅助功能权限且 TCC 绑定签名易失效）。
        // LOInputSourceSwitcher 代码保留备用，如需启用可在此调用 .shared.start()。
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 终止 Rime 引擎
        rimeEngine.finalize()
    }

    // MARK: - 菜单动作

    /// 打开设置窗口
    @objc func openSettings() {
        // LSUIElement 后台 app：先激活本进程，确保设置窗口能成为 key window
        // 否则 makeKeyAndOrderFront 在非激活 app 下会被系统立即收起，点击无反应
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            settingsWindow = LOSettingsWindow.shared
        }
        settingsWindow?.show()
    }

    /// 退出应用
    @objc func quit() {
        NSApp.terminate(nil)
    }
}

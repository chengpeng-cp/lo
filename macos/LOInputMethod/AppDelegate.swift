import AppKit
import InputMethodKit
import Carbon.HIToolbox

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

        // 安装器会在用户会话注册输入源；这里也覆盖 make install 和手动替换 bundle。
        ensureInputSourceRegistered()

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

        // 中英文切换：短按 Shift 在语境与系统 ABC 之间互切。
        // 轮询修饰键状态，不依赖 App 转发 flagsChanged，也不需要辅助功能权限。
        LOShiftMonitor.shared.start()
    }

    private func ensureInputSourceRegistered() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.lo.inputmethod.ime"
        let modeID = "\(bundleId).pinyin"
        let filter = [kTISPropertyInputSourceID as String: modeID] as CFDictionary

        func localizedModeName() -> String? {
            guard let unmanaged = TISCreateInputSourceList(filter, true) else { return nil }
            let sources = unmanaged.takeRetainedValue() as? [TISInputSource] ?? []
            for source in sources {
                guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                      let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
                    continue
                }
                let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
                let name = Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String
                if id == modeID, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return name
                }
            }
            return nil
        }

        if localizedModeName() == nil || inputSource(id: bundleId, includeAll: true) == nil {
            let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
            if status != noErr {
                debugLog("输入源注册失败：status=\(status)")
            } else if let name = localizedModeName() {
                debugLog("输入源已注册：\(name)")
            } else {
                debugLog("输入源已注册，但系统仍未读取到非空名称：\(modeID)")
            }
        }

        // TIS 的「已选中」与「已启用」是两份状态。若旧安装残留了选中模式，
        // 但父输入法或模式未进入启用列表，就会出现菜单栏可见、键盘设置缺失。
        if let error = enableInputSources() {
            debugLog("输入源已注册，但未能加入启用列表：\(error)")
        } else {
            debugLog("输入法父来源和拼音模式均已启用")
        }
    }

    /// 带模式的输入法需要先启用 bundle 父来源，再启用具体输入模式。
    /// TIS API 在部分 macOS 版本上可能对键盘模式静默无操作，因此持久化
    /// System Settings 实际读取的输入源偏好并回读验证。
    /// 注意：这里不要调用 TISEnableInputSource —— 它会弹出
    /// 「允许“语境输入法”启用“语境输入法”？」的系统提示，且每次启动都会重复。
    private func enableInputSources() -> String? {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return "无法读取输入法 Bundle ID"
        }

        // 只写入第三方输入源列表。同时写入 com.apple.HIToolbox 的
        // AppleEnabledInputSources 会让 macOS 15 把同一模式枚举两次，
        // 系统设置里出现重复的输入法条目。
        let thirdPartyEntries: [[String: String]] = [
            [
                "Bundle ID": bundleId,
                "Input Mode": "\(bundleId).pinyin",
                "InputSourceKind": "Input Mode"
            ],
            ["Bundle ID": bundleId, "InputSourceKind": "Keyboard Input Method"]
        ]

        return persistEnabledInputSourcePreferences(
            domain: "com.apple.inputsources",
            key: "AppleEnabledThirdPartyInputSources",
            required: thirdPartyEntries
        )
    }

    private func persistEnabledInputSourcePreferences(
        domain domainName: String,
        key keyName: String,
        required: [[String: String]]
    ) -> String? {
        let domain = domainName as CFString
        let key = keyName as CFString
        var entries = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
        for item in required where !entries.contains(where: { current in
            item.allSatisfy { current[$0.key] as? String == $0.value }
        }) {
            entries.append(item)
        }

        CFPreferencesSetAppValue(key, entries as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            return "无法保存 \(domainName).\(keyName)"
        }

        let persisted = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
        for item in required where !persisted.contains(where: { current in
            item.allSatisfy { current[$0.key] as? String == $0.value }
        }) {
            return "系统偏好 \(domainName).\(keyName) 未保存输入源 \(item["Input Mode"] ?? item["Bundle ID"] ?? "unknown")"
        }
        return nil
    }

    private func inputSource(id: String, includeAll: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let unmanaged = TISCreateInputSourceList(filter, includeAll) else { return nil }
        let sources = unmanaged.takeRetainedValue() as? [TISInputSource] ?? []
        return sources.first
    }

    func applicationWillTerminate(_ notification: Notification) {
        LOShiftMonitor.shared.stop()
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

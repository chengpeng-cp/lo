import InputMethodKit
import CRime
import AppKit
import os.log

// MARK: - 调试日志

/// 写入日志文件（~/Library/Rime/LOInputMethod.log）
func debugLog(_ message: String) {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    let logPath = home + "/Library/Rime/LOInputMethod.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}

// MARK: - 输入控制器

/// 语镜输入法控制器，处理按键输入和候选词显示
@objc(LOInputController)
class LOInputController: IMKInputController {

    /// Rime 引擎
    let rimeEngine: RimeEngine

    /// 会话管理器
    let sessionManager: RimeSessionManager

    /// 当前客户端的会话 ID
    private var currentSession: RimeSessionId = 0

    /// 候选词窗口
    private let candidateWindow: LOCandidateWindow

    /// 翻译浮窗（单例，所有 controller 共享，避免多 client 多个悬浮窗）
    private var translationOverlay: LOTranslationOverlay { LOTranslationOverlay.shared }

    /// 翻译调度器（单例，负责防抖、累积、缓存和翻译请求）
    private var translationScheduler: TranslationScheduler { TranslationScheduler.shared }

    /// 用户设置
    private var userSettings = LOSettings.load()

    /// 上一次的修饰键状态，用于 flagsChanged 事件计算变化量
    /// （Shift 短按切换中英文由 Rime ascii_composer 在 keyDown 路径处理，
    ///  此处仅保留以兼容潜在的 flagsChanged 判定，CapsLock 已交由
    ///  LOInputSourceSwitcher 的 CGEventTap 处理，不在此分支处理）
    private var lastModifiers: NSEvent.ModifierFlags = []

    /// 当前处于激活状态的控制器（用于 CGEventTap 切走前提交预编辑文本）
    private static weak var activeController: LOInputController?

    // MARK: - 初始化

    /// IMK 指定初始化方法（系统实际通过此方法创建 controller）
    /// 必须重写此方法而非无参 init()，否则 IMK 走父类默认实现，
    /// 子类存储属性不会初始化，导致 SIGTRAP 崩溃
    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        self.rimeEngine = RimeEngine()
        self.sessionManager = RimeSessionManager(engine: rimeEngine)
        self.candidateWindow = LOCandidateWindow()
        super.init(server: server, delegate: delegate, client: client)

        debugLog("=== LOInputController 初始化 (server:delegate:client:) ===")

        // 设置候选词选中回调
        candidateWindow.onCandidateSelected = { [weak self] index in
            self?.handleCandidateSelected(index)
        }

        // 设置翻页回调
        candidateWindow.onPageChange = { [weak self] backward in
            self?.handlePageChange(backward: backward)
        }

        // 配置翻译调度器回调：连接 TranslationScheduler ↔ LOTranslationOverlay
        // TranslationScheduler 是 @MainActor，需在 MainActor 上下文中设置回调
        MainActor.assumeIsolated {
            // 防抖期间：静默更新悬浮窗上行原文（不闪烁）
            translationScheduler.onOriginalUpdate = { [weak self] text in
                self?.translationOverlay.silentUpdateOriginal(text)
            }
            // 翻译开始：显示 loading
            translationScheduler.onTranslationStart = { [weak self] text in
                self?.translationOverlay.showLoading(originalText: text)
            }
            // 翻译完成：更新译文
            translationScheduler.onTranslationReady = { [weak self] original, translation in
                self?.translationOverlay.show(originalText: original, translation: translation)
            }
        }

        // 监听设置变更：实时更新悬浮窗配置（位置模式、透明度、自动消失等）
        NotificationCenter.default.addObserver(
            forName: .LOSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettingsToOverlay()
        }
    }

    /// 将用户设置应用到翻译悬浮窗
    private func applySettingsToOverlay() {
        let s = LOSettings.load()
        userSettings = s
        LOTranslationOverlay.shared.config = s.overlayConfig
    }

    // MARK: - 激活控制器与预编辑提交

    /// 让当前激活的控制器把未提交的预编辑文本提交给客户端。
    /// 由 LOInputSourceSwitcher 在真正切到 ABC 前调用，避免 deactivateServer 阶段插入无效。
    static func commitActiveRawPreedit() {
        activeController?.commitRawPreedit()
    }

    /// 提交当前未转换的原始按键输入，使其保留在输入框中。
    /// 使用 raw input（不含音节分隔空格），并用 markedRange 替换当前预编辑区。
    private func commitRawPreedit() {
        guard currentSession != 0 && rimeEngine.isComposing(session: currentSession) else {
            debugLog("commitRawPreedit: 未在组合输入状态")
            return
        }
        guard let textInput = client() as? IMKTextInput else {
            debugLog("commitRawPreedit: client 无法转换为 IMKTextInput")
            return
        }
        guard let rawInput = rimeEngine.getRawInput(session: currentSession), !rawInput.isEmpty else {
            debugLog("commitRawPreedit: raw input 为空")
            return
        }
        let markedRange = textInput.markedRange()
        debugLog("commitRawPreedit: rawInput='\(rawInput)'，markedRange=\(NSStringFromRange(markedRange))")
        // 用 raw input 直接替换 marked text 区域，避免音节分隔空格，也避免先清空再插入导致的丢失。
        textInput.insertText(rawInput, replacementRange: markedRange)
        rimeEngine.clearComposition(session: currentSession)
        debugLog("commitRawPreedit: 已提交 '\(rawInput)'")
    }

    // MARK: - 输入法生命周期

    /// 输入法被激活时调用
    override func activateServer(_ client: Any!) {
        super.activateServer(client)

        // 标记当前控制器为激活状态，供 CGEventTap 切输入法前提交预编辑文本。
        LOInputController.activeController = self

        // 重置修饰键状态：用空集初始化，让首次 flagsChanged 自然计算 changes
        lastModifiers = []

        // 为当前客户端获取或创建 Rime 会话
        if let client = client {
            currentSession = sessionManager.sessionForClient(client)
        }

        // 根据用户设置的「默认输入模式」初始化 Rime ascii_mode
        // 新建会话时 Rime 默认重置为中文（schema reset:0），此处确保 defaultInputMode 生效
        if currentSession != 0 {
            let wantAscii = (userSettings.defaultInputMode == "english")
            let currentAscii = rimeEngine.isAsciiMode(session: currentSession)
            if currentAscii != wantAscii {
                rimeEngine.setAsciiMode(wantAscii, session: currentSession)
                debugLog("激活时按设置初始化 ascii_mode: \(wantAscii ? "英文" : "中文")")
            }
        }

        // 如果正在组合输入，显示候选词窗口
        if currentSession != 0 && rimeEngine.isComposing(session: currentSession) {
            let candidates = rimeEngine.getCandidates(session: currentSession)
            if !candidates.isEmpty {
                candidateWindow.show(
                    candidates: candidates,
                    client: client as? IMKTextInput
                )
            }
        }
    }

    /// 输入法被停用时调用
    override func deactivateServer(_ client: Any!) {
        super.deactivateServer(client)

        // 如果切走前没有提交过预编辑文本，在这里做最后一次兜底提交。
        // 实际提交动作通常在 LOInputSourceSwitcher 切到 ABC 前完成，
        // 因为 deactivateServer 阶段客户端可能已不接受 insertText。
        if currentSession != 0 && rimeEngine.isComposing(session: currentSession) {
            if let textInput = client as? IMKTextInput,
               let preedit = rimeEngine.getPreedit(session: currentSession),
               !preedit.isEmpty {
                textInput.setMarkedText(
                    "",
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
                textInput.insertText(preedit, replacementRange: NSRange(location: NSNotFound, length: 0))
                debugLog("deactivateServer 兜底提交: '\(preedit)'")
            }
            rimeEngine.clearComposition(session: currentSession)
        }

        // 隐藏候选词窗口
        candidateWindow.hide()
        // 移除当前客户端的会话
        if let client = client {
            sessionManager.removeSession(for: client)
        }
        currentSession = 0

        // 取消激活控制器标记
        if LOInputController.activeController === self {
            LOInputController.activeController = nil
        }
    }

    // MARK: - 按键处理

    /// 注册输入法需要识别的事件类型
    /// 必须重写此方法并显式包含 .flagsChanged，否则 IMK 默认只把 .keyDown
    /// 发给 controller，Shift 等修饰键的按下/释放事件不会进入 handle(_:client:)。
    /// 这正是之前 Shift 在不同 app（尤其 Electron app）表现不一致的根因。
    override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask(arrayLiteral: .keyDown, .flagsChanged).rawValue)
    }

    /// 处理按键事件
    /// - Parameters:
    ///   - event: 键盘事件
    ///   - client: 输入法客户端
    /// - Returns: 是否已处理该按键
    override func handle(_ event: NSEvent!, client: Any!) -> Bool {
        guard currentSession != 0 else { return false }

        // 修饰键变化事件：放行交由 Rime ascii_composer 处理 Shift 短按切换中英文。
        // CapsLock 的中英互切不在此处理——已交由 LOInputSourceSwitcher 的 CGEventTap
        // 在系统层拦截原生 CapsLock 事件并自行切换输入源（对齐微信输入法）。
        if event.type == .flagsChanged {
            return false
        }

        // Command 组合键（Cmd+V 粘贴、Cmd+C 复制、Cmd+X 剪切、Cmd+A 全选等）
        // 不交给 Rime 处理，直接放行让系统/客户端处理，否则粘贴等功能会失效。
        if event.modifierFlags.contains(.command) {
            // 若正在组合输入，先清除预编辑文本，避免干扰客户端的命令操作
            if rimeEngine.isComposing(session: currentSession) {
                rimeEngine.commitComposition(session: currentSession)
                updateUI(client: client)
            }
            return false
        }

        // 方向键控制候选词（对齐成熟输入法）：
        // 候选词窗口可见时，←/→ 在当页候选词之间移动；到边界则翻页。
        // ↓/↑ 直接向后/向前翻页（展开/收起多行候选词）。
        // 不在组合输入时放行，让 Rime/客户端处理光标移动。
        // macOS keyCode：←=123 →=124 ↓=125 ↑=126
        if rimeEngine.isComposing(session: currentSession) && candidateWindow.isVisible {
            switch event.keyCode {
            case 124: // → 下一个候选
                candidateWindow.navigateByArrow(forward: true)
                return true
            case 123: // ← 上一个候选
                candidateWindow.navigateByArrow(forward: false)
                return true
            case 125: // ↓ 向后翻页
                handlePageChange(backward: false)
                return true
            case 126: // ↑ 向前翻页
                handlePageChange(backward: true)
                return true
            default:
                break
            }
        }

        // 空格选词：候选词窗口可见时，选中当前高亮候选词并提交。
        // 不交给 Rime 默认（Rime 会选第一个，忽略方向键移动过的高亮）。
        // macOS keyCode: 空格=49
        if event.keyCode == 49
            && rimeEngine.isComposing(session: currentSession)
            && candidateWindow.isVisible
            && !candidateWindow.candidates.isEmpty {
            handleCandidateSelected(candidateWindow.selectedCandidateIndex())
            return true
        }

        // 转换按键码和修饰键
        let keycode = RimeEngine.convertKeyCode(event.keyCode, chars: event.characters)
        let modifiers = RimeEngine.convertModifiers(event.modifierFlags.rawValue, keycode: keycode)

        // 忽略无法识别的按键
        guard keycode != 0 else { return false }

        // 将按键交给 Rime 处理
        let handled = rimeEngine.processKey(keycode, modifiers: modifiers, session: currentSession)

        // 检查是否有提交文本
        if let commitText = rimeEngine.getCommit(session: currentSession) {
            // 将提交文本发送给客户端
            if let textInput = client as? IMKTextInput {
                textInput.insertText(commitText, replacementRange: NSRange(location: NSNotFound, length: 0))
            }

            // 提交文本交给翻译调度器（防抖累积 + 中文过滤 + 翻译请求）
            // 调度器会在防抖期间静默更新悬浮窗原文，1 秒无新输入后触发翻译
            let commitTextCopy = commitText
            Task { @MainActor in
                TranslationScheduler.shared.commit(text: commitTextCopy)
            }
        }

        // 更新候选词窗口和预编辑文本
        updateUI(client: client)

        return handled
    }

    // MARK: - 切换系统英文输入法
    // CapsLock 互切已交由 LOInputSourceSwitcher（CGEventTap）统一处理，
    // controller 不再持有相关逻辑。

    // MARK: - UI 更新

    /// 更新候选词窗口和预编辑文本
    private func updateUI(client: Any?) {
        guard currentSession != 0 else { return }

        if rimeEngine.isComposing(session: currentSession) {
            // 正在组合输入：更新预编辑文本和候选词
            let preedit = rimeEngine.getPreedit(session: currentSession) ?? ""
            if let textInput = client as? IMKTextInput {
                // 使用属性字符串显式去掉 marked text 的默认蓝色背景，
                // 改为仅保留一条细下划线，与系统/微信输入法风格一致。
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor.textColor,
                    .backgroundColor: NSColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.separatorColor
                ]
                let attributedPreedit = NSAttributedString(string: preedit, attributes: attributes)
                let cursor = preedit.utf16.count
                textInput.setMarkedText(
                    attributedPreedit,
                    selectionRange: NSRange(location: cursor, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            }

            // 获取候选词并显示
            let candidates = rimeEngine.getCandidates(session: currentSession)
            if candidates.isEmpty {
                candidateWindow.hide()
            } else {
                candidateWindow.show(
                    candidates: candidates,
                    client: client as? IMKTextInput
                )
            }
        } else {
            // 不在组合状态：清除预编辑文本，隐藏候选词窗口
            if let textInput = client as? IMKTextInput {
                textInput.setMarkedText(
                    "",
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            }
            candidateWindow.hide()
        }
    }

    // MARK: - 输入法菜单

    /// 返回输入法菜单（显示在菜单栏输入法名称下方）
    /// 类似微信输入法的底部菜单
    /// 对齐 Squirrel：菜单项 target = self（controller），action 指向 controller 上的
    /// @objc 方法再转发到 AppDelegate，比直接跨对象 target 更可靠地响应 IMK 菜单点击
    override func menu() -> NSMenu! {
        let menu = NSMenu()

        // 语镜设置
        let settingsItem = NSMenuItem(
            title: "语镜设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: "退出语镜",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - 菜单动作（转发到 AppDelegate）

    /// 打开设置窗口（菜单项 target = self 时的转发入口）
    @objc func openSettings() {
        debugLog("菜单点击：openSettings (controller 转发)")
        // 先激活本进程，确保 LSUIElement 后台 app 能让窗口成为 key window
        NSApp.activate(ignoringOtherApps: true)
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.openSettings()
        } else {
            debugLog("警告：NSApp.delegate 不是 AppDelegate，直接调用 shared")
            AppDelegate.shared?.openSettings()
        }
    }

    /// 退出应用
    @objc func quit() {
        debugLog("菜单点击：quit (controller 转发)")
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.quit()
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 候选词交互

    /// 处理候选词被选中
    /// - Parameter index: 候选词索引
    private func handleCandidateSelected(_ index: Int) {
        guard currentSession != 0 else { return }
        rimeEngine.selectCandidateOnCurrentPage(index: index, session: currentSession)

        // 检查是否有提交文本
        if let commitText = rimeEngine.getCommit(session: currentSession) {
            // 提交文本到客户端
            if let textInput = client() as IMKTextInput? {
                textInput.insertText(commitText, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            // 提交给翻译调度器，与空格提交走同一路径，确保累积前面内容
            let commitTextCopy = commitText
            Task { @MainActor in
                TranslationScheduler.shared.commit(text: commitTextCopy)
            }
        }

        // 更新 UI
        updateUI(client: client())
    }

    /// 处理翻页
    /// - Parameter backward: 是否向前翻页
    private func handlePageChange(backward: Bool) {
        guard currentSession != 0 else { return }
        rimeEngine.changePage(backward: backward, session: currentSession)

        // 翻页后更新候选词
        let candidates = rimeEngine.getCandidates(session: currentSession)
        candidateWindow.show(
            candidates: candidates,
            client: client() as IMKTextInput?
        )
    }
}

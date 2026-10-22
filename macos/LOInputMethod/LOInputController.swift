import InputMethodKit
import CRime
import AppKit
import os.log

// MARK: - 调试日志

/// 写入日志文件（~/Library/Logs/LOInputMethod/translation.log）
/// 项目 log/ 目录下有软链接指向此文件，方便开发时查看
func debugLog(_ message: String) {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    let logDir = home + "/Library/Logs/LOInputMethod"
    let logPath = logDir + "/translation.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"

    // 确保日志目录存在
    let fm = FileManager.default
    if !fm.fileExists(atPath: logDir) {
        try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    }

    if let data = line.data(using: .utf8) {
        if fm.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            fm.createFile(atPath: logPath, contents: data)
        }
    }
}

/// IMK 客户端对 insertText 的插入范围处理方式不一致，需要按客户端能力区分。
///
/// 1. 组合中：替换 marked text 区域。
/// 2. Electron/Chromium 客户端（Trae、VS Code、Chrome 等）非组合态：不指定插入范围。
///    它们用隐藏 textarea 承载输入，`selectedRange()` 返回的是那个 textarea 的选区，
///    换行到空行后恒为 {0,0}，用它会把标点插到文档开头（表现为「空白行打不出符号」）。
///    这类客户端的标记是 `markedRange()` 返回 `{NSNotFound, NSIntegerMax}`。
/// 3. 原生 AppKit 客户端（TextEdit 等）：沿用编辑器当前选区，语义与插入点一致。
enum LOTextInsertion {
    /// IMK 用 `{NSNotFound, NSIntegerMax}` 表示「没有标记文本」
    static func isAbsentMarkedRange(_ range: NSRange) -> Bool {
        range.location == NSNotFound && range.length >= NSIntegerMax
    }

    static func replacementRange(markedRange: NSRange, selectedRange: NSRange) -> NSRange {
        if markedRange.location != NSNotFound {
            return markedRange
        }
        if isAbsentMarkedRange(markedRange) {
            return NSRange(location: NSNotFound, length: 0)
        }
        return selectedRange
    }
}

// MARK: - 输入控制器

/// 语境输入法控制器，处理按键输入和候选词显示
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

    /// Caps Lock 的输入源切换有时会先触发 commitComposition，再送达 flagsChanged。
    /// 记录上次状态，以便在系统回调顺序靠前时识别这次切源。
    private var lastCapsLockState = false

    private var settingsObserver: NSObjectProtocol?

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

        // 配置翻译调度器回调：连接 TranslationScheduler ↔ 悬浮窗 / 语音播报
        // 三者相互独立：悬浮窗由 overlayEnabled 控制，播报由 speechEnabled 控制
        MainActor.assumeIsolated {
            // 防抖期间：静默更新悬浮窗上行原文（不闪烁）
            translationScheduler.onOriginalUpdate = { text in
                guard LOSettings.load().overlayEnabled else { return }
                LOTranslationOverlay.shared.silentUpdateOriginal(text)
            }
            // 翻译开始：显示 loading
            translationScheduler.onTranslationStart = { text in
                guard LOSettings.load().overlayEnabled else { return }
                LOTranslationOverlay.shared.showLoading(originalText: text)
            }
            // 文本段完成：译文为 nil 表示未调用翻译（仅显示/播报原文）
            translationScheduler.onTranslationReady = { original, translation in
                if LOSettings.load().overlayEnabled {
                    if let translation = translation {
                        LOTranslationOverlay.shared.show(originalText: original, translation: translation)
                    } else {
                        LOTranslationOverlay.shared.showOriginalOnly(originalText: original)
                    }
                }
                // 播报只在文本段完成时触发一次；流式增量不播，避免重复朗读
                if let translation = translation {
                    SpeechPlayer.shared.speakTranslation(translation)
                } else {
                    SpeechPlayer.shared.speakTranslation(original)
                }
            }
            // 翻译失败：显示错误，避免悬浮窗卡在 loading 状态
            translationScheduler.onTranslationFailed = { original, error in
                guard LOSettings.load().overlayEnabled else { return }
                LOTranslationOverlay.shared.showError(originalText: original, error: error)
            }
        }

        // 监听设置变更：实时更新悬浮窗配置（位置模式、透明度、自动消失等）
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .LOSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettingsToOverlay()
        }
    }

    deinit {
        if let settingsObserver = settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        sessionManager.removeAllSessions()
    }

    /// 将用户设置应用到翻译悬浮窗
    private func applySettingsToOverlay() {
        let s = LOSettings.load()
        userSettings = s
        LOTranslationOverlay.shared.config = s.overlayConfig
        // 关闭播报时立即停止正在朗读的内容（activateServer 与设置通知都在主线程）
        MainActor.assumeIsolated {
            SpeechPlayer.shared.reloadSettings()
        }
    }

    // MARK: - 激活控制器与预编辑提交

    /// 让当前激活的控制器提交未上屏的预编辑文本。
    /// 由 Shift 切系统 ABC 前调用，避免 deactivateServer 阶段插入无效。
    static func commitActiveRawPreedit() {
        guard let controller = activeController,
              controller.currentSession != 0,
              controller.rimeEngine.isComposing(session: controller.currentSession) else {
            return
        }
        controller.commitRawPreedit()
    }

    /// 由 LOShiftMonitor 调用：切换当前客户端的 Rime 中英文模式
    static func toggleActiveAsciiMode() {
        activeController?.toggleAsciiModeFromMonitor()
    }

    private func toggleAsciiModeFromMonitor() {
        guard currentSession != 0 else { return }
        commitRawPreedit(to: client() as? IMKTextInput)
        let nextAscii = !rimeEngine.isAsciiMode(session: currentSession)
        rimeEngine.setAsciiMode(nextAscii, session: currentSession)
        debugLog("Shift 短按：切换为\(nextAscii ? "英文(ascii_mode)" : "中文")")
        updateUI(client: client())
    }

    /// 提交当前未转换的原始按键输入，使其保留在输入框中。
    /// 使用 raw input（不含音节分隔空格），并用 markedRange 替换当前预编辑区。
    private func commitRawPreedit(to suppliedClient: IMKTextInput? = nil) {
        guard currentSession != 0 && rimeEngine.isComposing(session: currentSession) else {
            debugLog("commitRawPreedit: 未在组合输入状态")
            return
        }
        guard let textInput = suppliedClient ?? client() else {
            debugLog("commitRawPreedit: client 无法转换为 IMKTextInput")
            return
        }
        guard let rawInput = rimeEngine.getRawInput(session: currentSession), !rawInput.isEmpty else {
            debugLog("commitRawPreedit: raw input 为空")
            return
        }
        let replacementRange = LOTextInsertion.replacementRange(
            markedRange: textInput.markedRange(),
            selectedRange: textInput.selectedRange()
        )
        // 用 raw input 直接替换 marked text 区域，避免音节分隔空格，也避免先清空再插入导致的丢失。
        textInput.insertText(rawInput, replacementRange: replacementRange)
        rimeEngine.clearComposition(session: currentSession)
        candidateWindow.hide()
    }

    // MARK: - 输入法生命周期

    /// 读取客户端所属 App 的 bundle ID，用于诊断日志
    private static func clientBundleID(_ client: Any?) -> String {
        guard let c = client as? IMKTextInput else { return String(describing: client) }
        return c.bundleIdentifier()
    }

    /// 输入法被激活时调用
    override func activateServer(_ client: Any!) {
        super.activateServer(client)
        let hadSession = currentSession != 0
        debugLog("[DIAG] activateServer client=\(Self.clientBundleID(client)) 已有session=\(hadSession)")

        // 标记当前控制器为激活状态，供 CGEventTap 切输入法前提交预编辑文本。
        LOInputController.activeController = self

        // 设置光标位置提供者，供翻译浮窗跟随光标模式定位使用
        LOTranslationOverlay.shared.cursorPositionProvider = { [weak self] in
            guard let self = self,
                  let client = self.client() else { return nil }
            var rect = NSRect.zero
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            return rect
        }

        applySettingsToOverlay()
        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)

        // 为当前客户端获取或创建 Rime 会话
        if let client = client {
            currentSession = sessionManager.sessionForClient(client)
            debugLog("[DIAG] activateServer session=\(currentSession)")
        } else {
            debugLog("[DIAG] activateServer client=nil！")
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
                    client: client as? IMKTextInput,
                    highlightedIndex: rimeEngine.getHighlightedCandidateIndex(session: currentSession)
                )
            }
        }
    }

    /// 输入法被停用时调用
    override func deactivateServer(_ client: Any!) {
        debugLog("[DIAG] deactivateServer client=\(Self.clientBundleID(client)) session=\(currentSession)")
        // 如果切走前没有提交过预编辑文本，在这里做最后一次兜底提交。
        // deactivateServer 阶段部分客户端已不接受 insertText，因此尽量提前提交。
        commitRawPreedit(to: client as? IMKTextInput)
        super.deactivateServer(client)

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

    /// 客户端在移动光标、结束编辑等情况下也会显式要求提交组合文本。
    override func commitComposition(_ sender: Any!) {
        let capsLockIsOn = NSEvent.modifierFlags.contains(.capsLock)
        if capsLockIsOn != lastCapsLockState {
            lastCapsLockState = capsLockIsOn
            debugLog("commitComposition: 检测到 Caps Lock 输入源切换，提交原始预编辑文本")
            commitRawPreedit(to: (sender as? IMKTextInput) ?? client())
            return
        }
        commitCurrentComposition(to: (sender as? IMKTextInput) ?? client())
    }

    private func insertCommit(_ text: String, to textInput: IMKTextInput) {
        let marked = textInput.markedRange()
        let selected = textInput.selectedRange()
        let replacementRange = LOTextInsertion.replacementRange(
            markedRange: marked,
            selectedRange: selected
        )
        debugLog("[DIAG] insertCommit text=\"\(text)\" marked=\(fmt(marked)) selected=\(fmt(selected)) target=\(fmt(replacementRange)) client=\(textInput.bundleIdentifier() ?? "?")")
        textInput.insertText(text, replacementRange: replacementRange)
        Task { @MainActor in
            TranslationScheduler.shared.commit(text: text)
        }
    }

    private func fmt(_ range: NSRange) -> String {
        range.location == NSNotFound ? "{NSNotFound,\(range.length)}" : "{\(range.location),\(range.length)}"
    }

    private func commitCurrentComposition(to textInput: IMKTextInput?) {
        guard currentSession != 0, let textInput = textInput else { return }
        if let text = rimeEngine.commitComposition(session: currentSession) {
            insertCommit(text, to: textInput)
        }
        updateUI(client: textInput)
    }

    /// default.yaml 将 Shift 配置为 noop，由此处识别短按。
    private func handleFlagsChanged(_ event: NSEvent, client: Any?) -> Bool {
        // Caps Lock 在 macOS 上负责切换到 ASCII 输入源。先于系统执行切源，
        // 把 Rime 的预编辑区按用户输入的原始拼音提交（例如 nihao），否则
        // 系统停用输入法时可能先按当前高亮候选提交成中文。
        if event.keyCode == 57 {
            let capsLockIsOn = event.modifierFlags.contains(.capsLock)
            if capsLockIsOn != lastCapsLockState {
                commitRawPreedit(to: client as? IMKTextInput)
            }
            lastCapsLockState = capsLockIsOn
            return false // 保留给 macOS 完成输入源切换
        }

        // Shift 短按由 LOShiftMonitor 轮询识别：不依赖 App 转发 flagsChanged，
        // 因此在微信/飞书里也能稳定切换，且不需要辅助功能权限。
        return false
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
        guard let event = event else { return false }
        guard currentSession != 0 else { return false }

        if event.type == .flagsChanged {
            return handleFlagsChanged(event, client: client)
        }
        guard event.type == .keyDown else { return false }
        LOShiftMonitor.shared.noteKeyDown(keyCode: event.keyCode)

        // 快捷复制翻译内容：Control+Command+逗号（⌃⌘,）
        // 在 Command 放行逻辑之前拦截，确保不被放行给系统
        if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.control) {
            if event.characters == "," || event.charactersIgnoringModifiers == "," {
                if LOTranslationOverlay.shared.copyLastTranslation() {
                    // 若正在组合输入，先清除预编辑文本
                    if rimeEngine.isComposing(session: currentSession) {
                        commitCurrentComposition(to: client as? IMKTextInput)
                    }
                    return true
                }
            }
        }

        // Command 组合键（Cmd+V 粘贴、Cmd+C 复制、Cmd+X 剪切、Cmd+A 全选等）
        // 不交给 Rime 处理，直接放行让系统/客户端处理，否则粘贴等功能会失效。
        if event.modifierFlags.contains(.command) {
            // 若正在组合输入，先清除预编辑文本，避免干扰客户端的命令操作
            if rimeEngine.isComposing(session: currentSession) {
                commitCurrentComposition(to: client as? IMKTextInput)
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
                _ = candidateWindow.navigateByArrow(forward: true)
                return true
            case 123: // ← 上一个候选
                _ = candidateWindow.navigateByArrow(forward: false)
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

        // 通知翻译调度器用户正在输入：拼音组合期间没有 commit 事件产生，
        // 但用户并未停顿，应刷新段落超时基准，避免前面已 commit 的数字/字母被丢弃。
        if rimeEngine.isComposing(session: currentSession) {
            let preedit = rimeEngine.getPreedit(session: currentSession) ?? ""
            let preeditCopy = preedit
            Task { @MainActor in
                TranslationScheduler.shared.noteTyping(preedit: preeditCopy)
            }
        }

        // 检查是否有提交文本
        if let commitText = rimeEngine.getCommit(session: currentSession) {
            // 将提交文本发送给客户端
            if let textInput = client as? IMKTextInput {
                insertCommit(commitText, to: textInput)
            }
        } else if !handled {
            // Rime 未处理该按键（handled=false），系统会直接把字符插入客户端。
            // 这种情况发生在中文模式非组合状态下输入数字、英文字母等 ASCII 字符：
            // Rime 的 express_editor 不消费这些键，字符由系统直接输出，
            // 但翻译调度器需要感知这些字符才能把它们纳入翻译段落。
            // 此处主动把可打印字符交给调度器，避免「3」等数字被翻译遗漏。
            if let chars = event.characters, chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 0x20 && scalar.value <= 0x7E,
               !rimeEngine.isComposing(session: currentSession) {
                let commitTextCopy = chars
                Task { @MainActor in
                    TranslationScheduler.shared.commit(text: commitTextCopy)
                }
            }
        }

        // 更新候选词窗口和预编辑文本
        updateUI(client: client)

        return handled
    }

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
                let replacementRange = LOTextInsertion.replacementRange(
                    markedRange: textInput.markedRange(),
                    selectedRange: textInput.selectedRange()
                )
                textInput.setMarkedText(
                    attributedPreedit,
                    selectionRange: NSRange(location: cursor, length: 0),
                    replacementRange: replacementRange
                )
            }

            // 获取候选词并显示
            let candidates = rimeEngine.getCandidates(session: currentSession)
            if candidates.isEmpty {
                candidateWindow.hide()
            } else {
                candidateWindow.show(
                    candidates: candidates,
                    client: client as? IMKTextInput,
                    highlightedIndex: rimeEngine.getHighlightedCandidateIndex(session: currentSession)
                )
            }
        } else {
            // 不在组合状态：清除预编辑文本，隐藏候选词窗口
            if let textInput = client as? IMKTextInput {
                let markedRange = textInput.markedRange()
                if markedRange.location != NSNotFound {
                    debugLog("[DIAG] clearMarked marked=\(fmt(markedRange)) client=\(textInput.bundleIdentifier() ?? "?")")
                    textInput.setMarkedText(
                        "",
                        selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: markedRange
                    )
                }
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

        // 语境输入法设置
        let settingsItem = NSMenuItem(
            title: "语境输入法设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: "退出语境输入法",
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
        guard currentSession != 0, candidateWindow.candidates.indices.contains(index) else { return }
        rimeEngine.selectCandidateOnCurrentPage(index: index, session: currentSession)

        // 检查是否有提交文本
        if let commitText = rimeEngine.getCommit(session: currentSession) {
            // 提交文本到客户端
            if let textInput = client() as IMKTextInput? {
                insertCommit(commitText, to: textInput)
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
            client: client() as IMKTextInput?,
            highlightedIndex: rimeEngine.getHighlightedCandidateIndex(session: currentSession)
        )
    }
}

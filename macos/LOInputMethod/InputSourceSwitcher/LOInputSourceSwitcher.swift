import AppKit
import Carbon.HIToolbox

// MARK: - 输入源切换器（CGEventTap 方案，对齐微信输入法）

/// 用 CGEventTap 在系统层面拦截 CapsLock，阻止 macOS 原生输入法切换，
/// 再由自己控制 ABC ↔ 语境 互切。
///
/// 为什么需要 CGEventTap：
/// - NSEvent flagsChanged 路线拦不住 macOS 原生 CapsLock 切输入法——
///   `TISSelectInputSource` 刚切回语境，系统原生 CapsLock 处理立刻又切走。
/// - CGEventTap 在 `.headInsertEventTap` 吞掉 CapsLock 事件（返回 nil），
///   原生 flagsChanged 和原生切换都一并被阻断，再由本类自己 toggle。
/// - 微信输入法即用此方案。
///
/// 事件路径设计（关键：一次物理按键只 toggle 一次）：
/// - 按下 CapsLock：先收到 keyDown，吞掉并 toggle，记录时间戳。
/// - 紧接着系统会发 flagsChanged：吞掉（阻断原生切换），但因距上次 toggle
///   很近（< dedupInterval）而不再 toggle。
/// - 部分外接键盘/机型 CapsLock 只发 flagsChanged 不发 keyDown：此时由
///   flagsChanged 的「CapsLock 状态翻转」兜底触发一次 toggle，状态机保证
///   只在真正翻转时切一次。
///
/// 需要辅助功能（Accessibility）权限。首次启动时系统会弹窗请求授权。
class LOInputSourceSwitcher {

    // MARK: - 单例

    static let shared = LOInputSourceSwitcher()

    // MARK: - 属性

    /// CGEventTap 引用
    private var eventTap: CFMachPort?

    /// RunLoop source
    private var runLoopSource: CFRunLoopSource?

    /// 缓存语境自身的输入源（切 ABC 前捕获，切回时用）
    private var cachedSelfInputSource: TISInputSource?

    /// 当前是否在 ABC 模式（用于决定下次 CapsLock 切到哪边）
    private var isInABCMode = false

    /// 是否已启动
    private var isStarted = false

    /// 上一次 CapsLock 锁定状态，用于 flagsChanged 状态机兜底
    private var lastCapsLockOn = false

    /// 上一次 toggle 的时间，用于 keyDown/flagsChanged 去重（避免一次按键切两次）
    private var lastToggleTime: TimeInterval = 0

    /// 去重窗口：keyDown 和随后的 flagsChanged 间隔若小于此值，flagsChanged 不再 toggle
    private let dedupInterval: TimeInterval = 0.2

    // MARK: - 启动

    /// 启动 CGEventTap 拦截 CapsLock
    /// 需要辅助功能权限，否则 tap 创建失败。
    func start() {
        guard !isStarted else { return }

        // 先读取当前 CapsLock 状态作为状态机基准，避免启动瞬间误判
        lastCapsLockOn = (NSEvent.modifierFlags.contains(.capsLock))

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let switcher = Unmanaged<LOInputSourceSwitcher>.fromOpaque(refcon).takeUnretainedValue()
                return switcher.handleEvent(type: type, event: event)
            },
            userInfo: nil
        ) else {
            // CGEventTap 创建失败：通常是没有辅助功能权限
            debugLog("CGEventTap 创建失败，可能缺少辅助功能权限。请在系统设置→隐私与安全性→辅助功能中授权语境。")
            requestAccessibilityPermission()
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isStarted = true
        debugLog("CGEventTap 已启动，拦截 CapsLock 切换（初始 capsLock=\(lastCapsLockOn)）")
    }

    /// 停止 CGEventTap
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isStarted = false
    }

    // MARK: - 辅助功能权限

    /// 请求辅助功能权限（触发系统弹窗）
    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 检查是否有辅助功能权限
    var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - 事件处理

    /// CGEventTap 回调处理
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 检查 tap 是否被系统禁用（权限丢失等），自动重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        // 只处理 CapsLock 键（keyCode 57）
        guard keycode == kVK_CapsLock else {
            return Unmanaged.passUnretained(event)
        }

        // CapsLock keyDown：拦截（返回 nil 吞掉），执行切换
        if type == .keyDown {
            debugLog("CGEventTap 拦截 CapsLock keyDown, isInABCMode=\(isInABCMode)")
            toggleInputSource()
            // 返回 nil 吞掉事件：阻止 macOS 原生 CapsLock 切换，
            // 同时其后续 flagsChanged 也会被本回调吞掉（见下方分支）
            return nil
        }

        // CapsLock flagsChanged：吞掉（阻止原生处理 + 阻止菜单栏图标乱跳）。
        // 但要处理「只发 flagsChanged 不发 keyDown」的兜底场景：
        // 用状态机判断 CapsLock 是否真的翻转，且距上次 keyDown toggle 足够远才兜底 toggle。
        if type == .flagsChanged {
            // CGEventFlags 用 maskAlphaShift 表示 CapsLock 锁定状态
            // （对应 NSEvent.ModifierFlags.capsLock）
            let nowOn = event.flags.contains(.maskAlphaShift)
            // 距上次 keyDown toggle 太近，认为是同一物理按键的后半段，吞掉但不重复 toggle
            let now = Date().timeIntervalSince1970
            if nowOn != lastCapsLockOn, now - lastToggleTime > dedupInterval {
                debugLog("CGEventTap flagsChanged 兜底 toggle (nowOn=\(nowOn))")
                toggleInputSource()
            }
            lastCapsLockOn = nowOn
            // 始终吞掉 flagsChanged，阻止 macOS 原生 CapsLock 切输入法
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - 输入源切换

    /// 切换输入源：在语境 ↔ ABC 之间互切
    private func toggleInputSource() {
        lastToggleTime = Date().timeIntervalSince1970

        if isInABCMode {
            // 当前在 ABC，切回语境
            switchToLo()
        } else {
            // 当前在语境，切到 ABC
            switchToABC()
        }
    }

    /// 切到系统 ABC 英文输入法
    private func switchToABC() {
        // 切走前先把语境当前未提交的预编辑文本提交给客户端，
        // 否则 deactivateServer 阶段再插入往往无效（对齐微信输入法）。
        LOInputController.commitActiveRawPreedit()

        // 切 ABC 前缓存当前输入源（语境）
        if cachedSelfInputSource == nil, let raw = TISCopyCurrentKeyboardInputSource() {
            let source = raw.takeRetainedValue()
            let id = inputSourceID(source) ?? "(unknown)"
            if id.contains("lo.inputmethod") {
                cachedSelfInputSource = source
                debugLog("缓存语境源: \(id)")
            }
        }

        guard let raw = TISCopyCurrentASCIICapableKeyboardInputSource() else {
            debugLog("切 ABC 失败：找不到 ASCII 输入源")
            return
        }
        let source = raw.takeRetainedValue()
        let status = TISSelectInputSource(source)
        isInABCMode = true
        debugLog("切到 ABC: status=\(status)")
    }

    /// 切回语境输入法
    private func switchToLo() {
        // 优先用缓存的语境源
        if let source = cachedSelfInputSource {
            _ = TISEnableInputSource(source)
            let status = TISSelectInputSource(source)
            isInABCMode = false
            debugLog("切回语境(缓存): status=\(status)")
            return
        }

        // 缓存为空：尝试用 TISCopyCurrentKeyboardInputSource 找语境
        // （此时当前是 ABC，这个方法返回 ABC 不是语境，无法用）
        debugLog("切回语境失败：无缓存源，请用 Ctrl+Space 手动切回")
    }

    // MARK: - 辅助

    /// 获取输入源的 sourceID
    private func inputSourceID(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, "TISPropertyInputSourceID" as CFString) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

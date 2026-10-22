import AppKit
import Carbon.HIToolbox

// MARK: - Shift 短按判定核心（纯逻辑，便于回归测试）

/// 一次 Shift 短按观测的进行中状态
struct LOShiftTapState {
    var downAt: TimeInterval?
    var cancelled = false
    var sawNonModifierKey = false
}

/// 轮询喂入修饰键状态并判定是否构成「短按 Shift」。
/// 取消规则：Shift 期间按过其他键、按过鼠标、或按住超过阈值，都不算一次切换，
/// 避免 Shift+字母、Shift+方向键、Shift+点击选中被误判。
enum LOShiftTapDecision {

    /// - Parameters:
    ///   - shiftDown: 本次轮询时 Shift 是否按下
    ///   - now: 当前单调时钟（ProcessInfo.systemUptime）
    ///   - state: 跨轮询保存的观测状态
    ///   - otherModifiersHeld: Shift 之外是否还有 Cmd/Ctrl/Option 按下
    ///   - mouseButtonDown: 是否有鼠标键按下
    ///   - nonModifierKeyDown: 是否有非修饰键处于按下状态（ABC 激活时输入法
    ///     收不到 keyDown，用全局按键状态识别 Shift+A 这类组合）
    ///   - threshold: 长按阈值（秒）
    /// - Returns: 是否应触发一次切换
    static func evaluate(
        shiftDown: Bool,
        now: TimeInterval,
        state: inout LOShiftTapState,
        otherModifiersHeld: Bool,
        mouseButtonDown: Bool,
        nonModifierKeyDown: @autoclosure () -> Bool,
        threshold: TimeInterval
    ) -> Bool {
        if shiftDown {
            if state.downAt == nil {
                state.downAt = now
                // 进入时已经按着鼠标（Shift+点击）不算切换
                state.cancelled = mouseButtonDown
            } else if mouseButtonDown {
                state.cancelled = true
            }
            if otherModifiersHeld {
                state.cancelled = true
            }
            if !state.sawNonModifierKey, nonModifierKeyDown() {
                state.sawNonModifierKey = true
            }
            return false
        }

        guard let start = state.downAt else {
            // Shift 早已按下（如激活输入法时已按住）：松开不算切换
            state.sawNonModifierKey = false
            return false
        }
        state.downAt = nil

        let duration = now - start
        let isShortTap = !state.cancelled && !state.sawNonModifierKey && duration >= 0 && duration < threshold
        state.sawNonModifierKey = false
        return isShortTap
    }
}

// MARK: - Shift 短按监听（免辅助功能权限）

/// 通过轮询修饰键状态识别「短按 Shift」。
///
/// 为什么不用 IMK 的 flagsChanged：
/// 微信/飞书等应用不会把修饰键事件转给输入法，`handleFlagsChanged` 收不到，
/// Shift 就被当成普通修饰键，按住打字只会输出大写英文。轮询 `NSEvent.modifierFlags`
/// 不依赖 App 的事件转发，也不需要辅助功能权限。
///
/// 短按行为由 `LOSettings.shiftBehavior` 决定：
/// - toggle_ascii：只切 Rime 内部中英文（默认，与微信输入法一致）
/// - switch_source：切系统 ABC ↔ 语境
///
/// 取消规则：Shift 期间按过其他键、按过鼠标、或按住超过阈值，都不算一次切换，
/// 避免 Shift+字母、Shift+方向键、Shift+点击选中被误判。
final class LOShiftMonitor {

    static let shared = LOShiftMonitor()

    private var timer: Timer?
    private var tapState = LOShiftTapState()
    /// 防止 App Nap 把 30ms 轮询降频，导致短按漏判
    private var activity: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var settings = LOSettings.load()

    /// 30ms 一次，短按识别延迟可忽略
    private let pollInterval: TimeInterval = 0.03

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // .common 模式保证菜单弹出、窗口拖动时仍能识别
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Detect short Shift taps for Chinese/English switching"
        )
        debugLog("Shift 轮询已启动（无需辅助功能权限）")
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .LOSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.settings = LOSettings.load()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tapState = LOShiftTapState()
        if let settingsObserver = settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        if let activity = activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    /// 任意非修饰键按下都取消本次短按
    func noteKeyDown(keyCode: UInt16) {
        guard !RimeEngine.isModifierKeycode(keyCode) else { return }
        if tapState.downAt != nil || NSEvent.modifierFlags.contains(.shift) {
            tapState.sawNonModifierKey = true
        }
    }

    private func poll() {
        let flags = NSEvent.modifierFlags
        let toggled = LOShiftTapDecision.evaluate(
            shiftDown: flags.contains(.shift),
            now: ProcessInfo.processInfo.systemUptime,
            state: &tapState,
            otherModifiersHeld: flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            // ABC 激活时输入法收不到 keyDown，用全局按键状态识别 Shift+A 这类组合
            nonModifierKeyDown: hasNonModifierKeyDown(),
            threshold: settings.shiftLongPressThreshold > 0 ? settings.shiftLongPressThreshold : 0.4
        )
        guard toggled else { return }

        if settings.shiftBehavior == "switch_source" {
            _ = LOSystemInputSourceSwitcher.shared.toggleFromShift()
            return
        }

        // toggle_ascii：只有当前确实在语境里才切内部模式，别影响其他输入法
        guard isCurrentInputSourceLO() else { return }
        LOInputController.toggleActiveAsciiMode()
    }

    private func isCurrentInputSourceLO() -> Bool {
        guard let raw = TISCopyCurrentKeyboardInputSource() else { return false }
        let source = raw.takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id.hasPrefix("com.lo.inputmethod")
    }

    /// Shift 之外是否有按键处于按下状态。用于 ABC 激活、收不到 keyDown 的场景。
    private func hasNonModifierKeyDown() -> Bool {
        // 左右 Command/Shift/CapsLock/Option/Control/Fn
        for keyCode in 0...127 where !Self.modifierKeyCodes.contains(CGKeyCode(keyCode)) {
            if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode)) {
                return true
            }
        }
        return false
    }

    private static let modifierKeyCodes: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

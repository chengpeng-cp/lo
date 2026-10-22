import AppKit
import Carbon.HIToolbox

// MARK: - 系统输入源切换器（Shift 短按）

/// 在语境与系统 ABC 之间切换。状态以 TIS 当前输入源为准，
/// 不依赖 CGEventTap，因此不需要辅助功能权限。
final class LOSystemInputSourceSwitcher {

    static let shared = LOSystemInputSourceSwitcher()

    /// 切到 ABC 前缓存的语境输入源，用于下一次 Shift 切回
    private var cachedLOSource: TISInputSource?

    /// 本次由 Shift 切到的 ABC 输入源 ID；只有当前源仍是它时才切回
    private var switchedABCSourceID: String?

    private init() {}

    /// Shift 短按触发。返回是否执行了切换。
    func toggleFromShift() -> Bool {
        guard let raw = TISCopyCurrentKeyboardInputSource() else { return false }
        let current = raw.takeRetainedValue()
        guard let currentID = inputSourceID(current) else { return false }
        debugLog("[DIAG] toggleFromShift current=\(currentID) switchedABC=\(switchedABCSourceID ?? "nil")")

        if currentID.hasPrefix(loBundleID) {
            return switchToABC(from: current)
        }
        if let switchedABCSourceID, currentID == switchedABCSourceID {
            return switchToLO()
        }

        // 当前是其他输入法：清掉上次记录，避免以后手动选中同一个 ABC 时被误切回
        switchedABCSourceID = nil
        return false
    }

    private var loBundleID: String {
        Bundle.main.bundleIdentifier ?? "com.lo.inputmethod.ime"
    }

    /// 助手可执行文件路径：优先 app bundle 内，其次开发构建时的同级目录
    private var helperURL: URL? {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/LOSourceSwitcher")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        if let exe = Bundle.main.executableURL {
            let sibling = exe.deletingLastPathComponent()
                .appendingPathComponent("LOSourceSwitcher")
            if FileManager.default.isExecutableFile(atPath: sibling.path) {
                return sibling
            }
        }
        return nil
    }

    /// 通过独立助手进程选择输入源。
    /// 输入法进程内 TISSelectInputSource 选择自身时激活握手会弹跳
    /// （activateServer 后立刻 deactivateServer），必须由外部进程执行。
    private func selectViaHelper(_ sourceID: String) -> Bool {
        guard let helper = helperURL else {
            debugLog("切换助手不存在，回退进程内选择")
            return false
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = [sourceID]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            debugLog("切换助手启动失败: \(error.localizedDescription)")
            return false
        }
        // 给助手 1.5s 预算；超时则按失败处理（进程稍后台结束，不影响系统状态）
        let waitResult = done.wait(timeout: .now() + 1.5)
        if waitResult == .timedOut {
            debugLog("切换助手超时")
            process.terminate()
            return false
        }
        let ok = process.terminationStatus == 0
        if !ok {
            debugLog("切换助手退出码 \(process.terminationStatus)")
        }
        return ok
    }

    private func switchToABC(from current: TISInputSource) -> Bool {
        // 切走前先提交未上屏的拼音，避免 deactivateServer 阶段插入无效
        LOInputController.commitActiveRawPreedit()
        cachedLOSource = current

        guard let raw = TISCopyCurrentASCIICapableKeyboardInputSource() else {
            debugLog("Shift 切 ABC 失败：找不到 ASCII 输入源")
            return false
        }
        let abc = raw.takeRetainedValue()
        guard let abcID = inputSourceID(abc) else {
            debugLog("Shift 切 ABC 失败：输入源没有 ID")
            return false
        }

        // 助手进程选择：离开 IME 的路径进程内也可用，但统一走助手保持行为一致
        let selected = selectViaHelper(abcID) || TISSelectInputSource(abc) == noErr
        guard selected else {
            debugLog("Shift 切 ABC 失败：助手与进程内选择均返回失败")
            return false
        }

        switchedABCSourceID = abcID
        debugLog("Shift 短按：切到 ABC (\(abcID))")
        return true
    }

    private func switchToLO() -> Bool {
        guard cachedLOSource != nil || findLOSource() != nil else {
            debugLog("Shift 切回语境失败：找不到语境输入源")
            return false
        }
        let source = cachedLOSource!
        guard let sourceID = inputSourceID(source) else {
            debugLog("Shift 切回语境失败：输入源没有 ID")
            return false
        }

        // 不要调用 TISEnableInputSource：它会弹出「允许“语境输入法”启用
        // “语境输入法”？」的系统提示，且每次调用都会重复弹出。
        // 输入源在安装时已启用，切换到已启用源只需要 TISSelectInputSource。
        // 必须经助手进程执行：进程内选择自身会握手弹跳（见 selectViaHelper 注释）。
        let selected = selectViaHelper(sourceID) || TISSelectInputSource(source) == noErr
        guard selected else {
            debugLog("Shift 切回语境失败：助手与进程内选择均返回失败")
            return false
        }

        switchedABCSourceID = nil
        debugLog("Shift 短按：切回语境")
        return true
    }

    private func findLOSource() -> TISInputSource? {
        // 只查已启用的输入源，避免把未启用的条目设成当前源
        guard let raw = TISCreateInputSourceList(nil, false) else { return nil }
        let sources = raw.takeRetainedValue() as? [TISInputSource] ?? []
        let modeID = "\(loBundleID).pinyin"

        if let exact = sources.first(where: { inputSourceID($0) == modeID }) {
            cachedLOSource = exact
            return exact
        }
        if let any = sources.first(where: { inputSourceID($0)?.hasPrefix(loBundleID) == true }) {
            cachedLOSource = any
            return any
        }
        return nil
    }

    private func inputSourceID(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

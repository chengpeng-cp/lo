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
        let status = TISSelectInputSource(abc)
        guard status == noErr else {
            debugLog("Shift 切 ABC 失败：status=\(status)")
            return false
        }

        switchedABCSourceID = abcID
        debugLog("Shift 短按：切到 ABC (\(abcID))")
        return true
    }

    private func switchToLO() -> Bool {
        guard let source = cachedLOSource ?? findLOSource() else {
            debugLog("Shift 切回语境失败：找不到语境输入源")
            return false
        }

        _ = TISEnableInputSource(source)
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            debugLog("Shift 切回语境失败：status=\(status)")
            return false
        }

        switchedABCSourceID = nil
        debugLog("Shift 短按：切回语境")
        return true
    }

    private func findLOSource() -> TISInputSource? {
        guard let raw = TISCreateInputSourceList(nil, true) else { return nil }
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

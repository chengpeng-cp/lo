import Carbon.HIToolbox
import Foundation

// MARK: - 输入源切换助手
//
// 为什么需要独立进程：
// 在输入法进程内调用 TISSelectInputSource 选择 IMK 输入法（尤其是选择自身）时，
// macOS 只更新菜单栏；系统虽会发起激活握手（activateServer 被调用），
// 但握手随即弹跳（立刻 deactivateServer），焦点应用的输入上下文仍停留在
// 原输入法，按键按 ABC 行为直达应用（表现为「菜单显示语境、输入小写英文」）。
// 由外部进程调用 TISSelectInputSource 则走完整握手，焦点应用正常切换。
// im-select、HammerSpoon 等工具均依赖这一外部调用路径。
//
// 用法: LOSourceSwitcher <inputSourceID>
// 退出码: 0 = 选择成功；1 = 未找到输入源或选择失败；2 = 参数缺失

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: LOSourceSwitcher <inputSourceID>\n".data(using: .utf8)!)
    exit(2)
}
let wanted = CommandLine.arguments[1]

func sourceID(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

// 只在已启用列表中查找；TISSelectInputSource 对未启用源会失败或触发启用弹窗
guard let rawList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
    exit(1)
}

let target = rawList.first { sourceID($0) == wanted }
    ?? rawList.first { sourceID($0)?.hasPrefix(wanted) == true }

guard let source = target else {
    FileHandle.standardError.write("input source not found: \(wanted)\n".data(using: .utf8)!)
    exit(1)
}

let status = TISSelectInputSource(source)
if status != noErr {
    FileHandle.standardError.write("TISSelectInputSource(\(wanted)) status=\(status)\n".data(using: .utf8)!)
    exit(1)
}
exit(0)

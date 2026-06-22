import Foundation
import CRime
import AppKit

// MARK: - Rime C 宏的 Swift 等价实现

/// 等价于 RIME_STRUCT_INIT 宏，设置 data_size 字段
@inline(__always)
private func rimeStructInit<T>(type: T.Type, value: inout T) {
    // data_size = sizeof(Type) - sizeof(data_size)
    // 在 C 中，data_size 是 int，占 4 字节（在结构体开头）
    let totalSize = MemoryLayout<T>.size
    let dataSize = totalSize - MemoryLayout<Int32>.size
    withUnsafeMutablePointer(to: &value) {
        $0.withMemoryRebound(to: Int32.self, capacity: 1) {
            $0.pointee = Int32(dataSize)
        }
    }
}

// MARK: - 候选词

/// Rime 候选词
struct Candidate {
    /// 候选词文本
    let text: String
    /// 候选词注释（如拼音提示）
    let comment: String?
}

// MARK: - Rime 引擎

/// librime C API 的 Swift 封装
/// 通过 rime_get_api() 获取 API 指针，调用其中的函数指针
class RimeEngine {

    /// librime API 指针
    private let api: UnsafeMutablePointer<RimeApi>

    /// 是否已初始化
    private(set) var initialized = false

    /// 部署是否完成
    private(set) var deploymentReady = false

    // MARK: - 初始化

    init() {
        // 获取 librime API 入口
        api = rime_get_api()
    }

    /// 初始化 Rime 引擎
    /// - Parameter sharedDataDir: 共享数据目录（方案、词典等）
    /// - Parameter userDir: 用户数据目录（用户词典、配置等）
    func initialize(sharedDataDir: String = RimeConfig.sharedDataDir,
                    userDir: String = RimeConfig.userDir) {
        guard !initialized else { return }

        // 确保用户数据目录存在
        RimeConfig.ensureUserDirExists()

        // 设置 Rime 特征参数
        var traits = RimeTraits()
        rimeStructInit(type: RimeTraits.self, value: &traits)
        // 使用 strdup 将 Swift String 转为 C 字符串指针
        // Rime 会在内部使用这些指针，setup/initialize 返回后不再需要
        let sharedDataDirC = strdup(sharedDataDir)
        let userDirC = strdup(userDir)
        let distNameC = strdup("语镜输入法")
        let distCodeNameC = strdup("lo")
        let distVersionC = strdup("0.1")
        let appNameC = strdup("rime.lo")

        traits.shared_data_dir = UnsafePointer(sharedDataDirC)
        traits.user_data_dir = UnsafePointer(userDirC)
        traits.distribution_name = UnsafePointer(distNameC)
        traits.distribution_code_name = UnsafePointer(distCodeNameC)
        traits.distribution_version = UnsafePointer(distVersionC)
        traits.app_name = UnsafePointer(appNameC)

        // 先 setup 再 initialize
        api.pointee.setup(&traits)
        api.pointee.initialize(&traits)

        // 释放 strdup 分配的内存（Rime 内部已复制了这些字符串）
        free(sharedDataDirC)
        free(userDirC)
        free(distNameC)
        free(distCodeNameC)
        free(distVersionC)
        free(appNameC)

        // 等待部署完成（同步阻塞，确保 schema 已加载）
        if api.pointee.start_maintenance(1) != 0 {
            api.pointee.join_maintenance_thread()
        }

        deploymentReady = true
        initialized = true
    }

    // MARK: - 会话管理

    /// 创建新的输入会话
    /// - Returns: 会话 ID
    func createSession() -> RimeSessionId {
        return api.pointee.create_session()
    }

    /// 销毁指定会话
    /// - Parameter id: 会话 ID
    func destroySession(_ id: RimeSessionId) {
        _ = api.pointee.destroy_session(id)
    }

    // MARK: - 按键处理

    /// 处理按键输入
    /// - Parameters:
    ///   - keycode: 按键码
    ///   - modifiers: 修饰键掩码
    ///   - session: 会话 ID
    /// - Returns: Rime 是否处理了该按键
    func processKey(_ keycode: Int32, modifiers: Int32, session: RimeSessionId) -> Bool {
        guard session != 0 else { return false }
        return api.pointee.process_key(session, keycode, modifiers) != 0
    }

    // MARK: - 输出获取

    /// 获取已提交的文本
    /// - Parameter session: 会话 ID
    /// - Returns: 提交的文本，如果没有则返回 nil
    func getCommit(session: RimeSessionId) -> String? {
        guard session != 0 else { return nil }
        var commit = RimeCommit()
        rimeStructInit(type: RimeCommit.self, value: &commit)
        guard api.pointee.get_commit(session, &commit) != 0 else { return nil }
        let text = String(cString: commit.text)
        _ = api.pointee.free_commit(&commit)
        return text
    }

    /// 获取当前上下文（包含候选词菜单和组合信息）
    /// - Parameter session: 会话 ID
    /// - Returns: RimeContext 指针，调用者需负责释放
    func getContext(session: RimeSessionId) -> RimeContext? {
        guard session != 0 else { return nil }
        var ctx = RimeContext()
        rimeStructInit(type: RimeContext.self, value: &ctx)
        guard api.pointee.get_context(session, &ctx) != 0 else { return nil }
        return ctx
    }

    /// 释放 RimeContext
    /// - Parameter ctx: 上下文指针
    func freeContext(_ ctx: inout RimeContext) {
        _ = api.pointee.free_context(&ctx)
    }

    /// 获取候选词列表
    /// - Parameters:
    ///   - session: 会话 ID
    ///   - count: 最多获取的候选词数量
    /// - Returns: 候选词数组
    func getCandidates(session: RimeSessionId, count: Int = 10) -> [Candidate] {
        guard session != 0 else { return [] }
        var ctx = RimeContext()
        rimeStructInit(type: RimeContext.self, value: &ctx)
        guard api.pointee.get_context(session, &ctx) != 0 else {
            return []
        }
        defer { _ = api.pointee.free_context(&ctx) }

        let menu = ctx.menu
        var result: [Candidate] = []
        let numCandidates = min(Int(menu.num_candidates), count)
        for i in 0..<numCandidates {
            let c = menu.candidates.advanced(by: i).pointee
            let text = String(cString: c.text)
            let comment = c.comment != nil ? String(cString: c.comment!) : nil
            result.append(Candidate(text: text, comment: comment))
        }
        return result
    }

    /// 获取预编辑文本
    /// - Parameter session: 会话 ID
    /// - Returns: 预编辑文本
    func getPreedit(session: RimeSessionId) -> String? {
        guard session != 0 else { return nil }
        var ctx = RimeContext()
        rimeStructInit(type: RimeContext.self, value: &ctx)
        guard api.pointee.get_context(session, &ctx) != 0 else { return nil }
        defer { _ = api.pointee.free_context(&ctx) }

        let preedit = ctx.composition.preedit
        guard preedit != nil else { return nil }
        return String(cString: preedit!)
    }

    /// 获取用户实际按键输入的原始字符串（不含音节分隔空格）
    /// - Parameter session: 会话 ID
    /// - Returns: 原始输入字符串
    func getRawInput(session: RimeSessionId) -> String? {
        guard session != 0 else { return nil }
        guard let raw = api.pointee.get_input(session) else { return nil }
        return String(cString: raw)
    }

    /// 判断当前是否正在组合输入
    /// - Parameter session: 会话 ID
    /// - Returns: 是否正在组合
    func isComposing(session: RimeSessionId) -> Bool {
        guard session != 0 else { return false }
        var status = RimeStatus()
        rimeStructInit(type: RimeStatus.self, value: &status)
        guard api.pointee.get_status(session, &status) != 0 else { return false }
        defer { _ = api.pointee.free_status(&status) }
        return status.is_composing != 0
    }

    /// 选择当前页的候选词
    /// - Parameters:
    ///   - index: 候选词在当前页的索引
    ///   - session: 会话 ID
    func selectCandidateOnCurrentPage(index: Int, session: RimeSessionId) {
        guard session != 0 else { return }
        _ = api.pointee.select_candidate_on_current_page(session, index)
    }

    /// 判断当前是否为 ASCII（英文）模式
    /// - Parameter session: 会话 ID
    /// - Returns: 是否为 ASCII 模式
    func isAsciiMode(session: RimeSessionId) -> Bool {
        guard session != 0 else { return false }
        var status = RimeStatus()
        rimeStructInit(type: RimeStatus.self, value: &status)
        guard api.pointee.get_status(session, &status) != 0 else { return false }
        defer { _ = api.pointee.free_status(&status) }
        return status.is_ascii_mode != 0
    }

    /// 设置 ASCII（英文）模式
    /// - Parameters:
    ///   - enabled: 是否启用 ASCII 模式
    ///   - session: 会话 ID
    func setAsciiMode(_ enabled: Bool, session: RimeSessionId) {
        guard session != 0 else { return }
        api.pointee.set_option(session, "ascii_mode", enabled ? 1 : 0)
    }

    /// 提交当前组合中的文本（如果有）
    /// - Parameter session: 会话 ID
    /// - Returns: 提交的文本，如果没有则返回 nil
    func commitComposition(session: RimeSessionId) -> String? {
        guard session != 0 else { return nil }
        // 发送 Escape 取消组合，或者使用 commit_composition
        api.pointee.commit_composition(session)
        return getCommit(session: session)
    }

    /// 清空当前组合状态（不提交任何文本）
    /// - Parameter session: 会话 ID
    func clearComposition(session: RimeSessionId) {
        guard session != 0 else { return }
        _ = api.pointee.clear_composition(session)
    }

    /// 翻页
    /// - Parameters:
    ///   - backward: 是否向前翻页
    ///   - session: 会话 ID
    func changePage(backward: Bool, session: RimeSessionId) {
        guard session != 0 else { return }
        _ = api.pointee.change_page(session, backward ? 1 : 0)
    }

    // MARK: - macOS 按键码转换

    /// 将 macOS NSEvent keyCode 转换为 Rime 按键码
    /// - Parameters:
    ///   - keyCode: macOS 虚拟按键码
    ///   - chars: 按键产生的字符（用于字母键）
    /// - Returns: Rime 按键码
    static func convertKeyCode(_ keyCode: UInt16, chars: String? = nil) -> Int32 {
        // 字母键：优先使用字符转换
        if let chars = chars, chars.count == 1 {
            let scalar = chars.unicodeScalars.first!
            if scalar.value >= UInt32(UnicodeScalar("a").value)
                && scalar.value <= UInt32(UnicodeScalar("z").value) {
                return Int32(scalar.value)
            }
            if scalar.value >= UInt32(UnicodeScalar("A").value)
                && scalar.value <= UInt32(UnicodeScalar("Z").value) {
                // 转为小写
                return Int32(scalar.value + 32)
            }
        }

        // 可打印 ASCII 字符（数字、标点、符号等）：直接返回其 Unicode 标量值。
        // 这保证中文模式下标点键能进入 Rime punctuator，而不是被系统直接输出英文标点。
        if let chars = chars, chars.count == 1 {
            let scalar = chars.unicodeScalars.first!
            if scalar.value >= 0x20 && scalar.value <= 0x7E {
                return Int32(scalar.value)
            }
        }

        // 特殊键映射
        switch keyCode {
        case 36: return Int32(XK_Return)      // 回车
        case 48: return Int32(XK_Tab)         // Tab
        case 49: return Int32(XK_space)       // 空格
        case 51: return Int32(XK_BackSpace)   // 退格
        case 53: return Int32(XK_Escape)      // Esc
        case 123: return Int32(XK_Left)       // 左箭头
        case 124: return Int32(XK_Right)      // 右箭头
        case 125: return Int32(XK_Down)       // 下箭头
        case 126: return Int32(XK_Up)         // 上箭头
        case 56: return Int32(XK_Shift_L)     // 左 Shift
        case 60: return Int32(XK_Shift_R)     // 右 Shift
        case 59: return Int32(XK_Control_L)   // 左 Control
        case 62: return Int32(XK_Control_R)   // 右 Control
        case 58: return Int32(XK_Option_L)    // 左 Option
        case 61: return Int32(XK_Option_R)    // 右 Option
        case 55: return Int32(XK_Super_L)     // 左 Command
        case 54: return Int32(XK_Super_R)     // 右 Command
        case 57: return Int32(XK_Caps_Lock)   // Caps Lock
        case 18: return Int32(XK_1)           // 数字键 1
        case 19: return Int32(XK_2)           // 数字键 2
        case 20: return Int32(XK_3)           // 数字键 3
        case 21: return Int32(XK_4)           // 数字键 4
        case 23: return Int32(XK_5)           // 数字键 5
        case 22: return Int32(XK_6)           // 数字键 6
        case 26: return Int32(XK_7)           // 数字键 7
        case 28: return Int32(XK_8)           // 数字键 8
        case 25: return Int32(XK_9)           // 数字键 9
        case 29: return Int32(XK_0)           // 数字键 0
        default: return 0
        }
    }

    /// 将 macOS 修饰键掩码转换为 Rime 修饰键掩码
    /// - Parameters:
    ///   - flags: NSEvent 修饰键标志的 rawValue
    ///   - keycode: 当前按键码（用于判断是否单独按下了修饰键）
    /// - Returns: Rime 修饰键掩码
    /// 注意：不传递 kLockMask（CapsLock）。CapsLock 的中英切换由 macOS 原生处理，
    /// 若传 kLockMask 给普通按键（如空格），Rime 会因修饰符不匹配而不选词。
    static func convertModifiers(_ flags: UInt, keycode: Int32 = 0) -> Int32 {
        var mask: Int32 = 0
        // 如果当前按下的就是 Shift 键本身，不要传递 shift modifier
        let isShiftKey = (keycode == Int32(XK_Shift_L) || keycode == Int32(XK_Shift_R))
        if !isShiftKey && flags & NSEvent.ModifierFlags.shift.rawValue != 0 {
            mask |= Int32(kShiftMask)
        }
        if flags & NSEvent.ModifierFlags.control.rawValue != 0 { mask |= Int32(kControlMask) }
        if flags & NSEvent.ModifierFlags.option.rawValue != 0 { mask |= Int32(kAltMask) }
        if flags & NSEvent.ModifierFlags.command.rawValue != 0 { mask |= Int32(kSuperMask) }
        // 不传递 CapsLock (kLockMask)：CapsLock 物理状态由 macOS 在字符层处理大小写，
        // Rime 的 Caps_Lock 已设为 noop，传 kLockMask 会导致空格等按键无法选词。
        return mask
    }

    /// 将 macOS 修饰键掩码转换为 Rime 修饰键掩码（flagsChanged 场景）
    /// 与 convertModifiers 不同：保留完整的当前 modifiers 状态（包含 shift），
    /// 因为 flagsChanged 需要把按下后的完整状态交给 Rime 的 ascii_composer 判断。
    static func convertModifiersForFlagsChanged(_ flags: UInt) -> Int32 {
        var mask: Int32 = 0
        if flags & NSEvent.ModifierFlags.shift.rawValue != 0 { mask |= Int32(kShiftMask) }
        if flags & NSEvent.ModifierFlags.control.rawValue != 0 { mask |= Int32(kControlMask) }
        if flags & NSEvent.ModifierFlags.option.rawValue != 0 { mask |= Int32(kAltMask) }
        if flags & NSEvent.ModifierFlags.command.rawValue != 0 { mask |= Int32(kSuperMask) }
        if flags & NSEvent.ModifierFlags.capsLock.rawValue != 0 { mask |= Int32(kLockMask) }
        return mask
    }

    // MARK: - 修饰键辅助（flagsChanged 用，对齐 Squirrel）

    /// Rime 按键释放标志位
    static let releaseMask: UInt32 = kReleaseMask

    /// Rime CapsLock 锁定掩码
    static let lockMask: UInt32 = kLockMask

    /// macOS 修饰键虚拟键码集合（左/右 Shift、Control、Option、Command、CapsLock）
    private static let modifierKeycodes: Set<UInt16> = [
        56, 60,   // Shift_L, Shift_R
        59, 62,   // Control_L, Control_R
        58, 61,   // Option_L, Option_R
        55, 54,   // Command_L, Command_R
        57,       // Caps_Lock
    ]

    /// 判断给定 keyCode 是否为修饰键
    static func isModifierKeycode(_ keyCode: UInt16) -> Bool {
        return modifierKeycodes.contains(keyCode)
    }

    /// 当 flagsChanged 事件的 keyCode 不可靠（如远程桌面传 0）时，
    /// 根据修饰键变化量推断对应的 macOS 虚拟键码
    static func inferModifierKeycode(from changes: NSEvent.ModifierFlags) -> UInt16? {
        if changes.contains(.shift) { return 56 }       // 默认左 Shift
        if changes.contains(.control) { return 59 }     // 默认左 Control
        if changes.contains(.option) { return 58 }      // 默认左 Option
        if changes.contains(.command) { return 55 }     // 默认左 Command
        if changes.contains(.capsLock) { return 57 }    // CapsLock
        return nil
    }

    // MARK: - 清理

    /// 终止 Rime 引擎，释放资源
    func finalize() {
        guard initialized else { return }
        api.pointee.finalize()
        initialized = false
    }

    deinit {
        finalize()
    }
}

// MARK: - X11 按键码常量

/// X11 按键码常量，librime 使用这些值作为按键码
private let XK_BackSpace: UInt32 = 0xFF08
private let XK_Tab: UInt32 = 0xFF09
private let XK_Return: UInt32 = 0xFF0D
private let XK_Escape: UInt32 = 0xFF1B
private let XK_space: UInt32 = 0x0020
private let XK_Left: UInt32 = 0xFF51
private let XK_Up: UInt32 = 0xFF52
private let XK_Right: UInt32 = 0xFF53
private let XK_Down: UInt32 = 0xFF54
private let XK_0: UInt32 = 0x0030
private let XK_1: UInt32 = 0x0031
private let XK_2: UInt32 = 0x0032
private let XK_3: UInt32 = 0x0033
private let XK_4: UInt32 = 0x0034
private let XK_5: UInt32 = 0x0035
private let XK_6: UInt32 = 0x0036
private let XK_7: UInt32 = 0x0037
private let XK_8: UInt32 = 0x0038
private let XK_9: UInt32 = 0x0039
private let XK_Shift_L: UInt32 = 0xFFE1
private let XK_Shift_R: UInt32 = 0xFFE2
private let XK_Control_L: UInt32 = 0xFFE3
private let XK_Control_R: UInt32 = 0xFFE4
private let XK_Option_L: UInt32 = 0xFE03
private let XK_Option_R: UInt32 = 0xFE04
private let XK_Super_L: UInt32 = 0xFFEB
private let XK_Super_R: UInt32 = 0xFFEC
private let XK_Caps_Lock: UInt32 = 0xFFE5

// MARK: - Rime 修饰键常量

/// Rime 修饰键掩码
private let kControlMask: UInt32 = 1 << 2
private let kAltMask: UInt32 = 1 << 3
private let kShiftMask: UInt32 = 1 << 0
private let kSuperMask: UInt32 = 1 << 6
private let kLockMask: UInt32 = 1 << 1

/// Rime 按键释放标志位（key release flag，librime 中为 1 << 30）
private let kReleaseMask: UInt32 = 1 << 30

import Foundation
import InputMethodKit
import CRime

// MARK: - Rime 会话管理

/// 管理输入法客户端与 Rime 会话的映射关系
///
/// 每个 IMK 客户端对应一个 RimeSessionId。这份映射曾经以客户端对象的指针地址做 key，
/// 但 IMK 客户端是远程代理对象：macOS 26/27 起，每次激活、每次 CapsLock 切源都可能
/// 换成一个全新的代理实例。于是 `activateServer` 与 `deactivateServer` 拿到的地址不一样，
/// 配对失败 → 会话既不回收也不复用得成，只能靠进程退出来清账。
///
/// 现在改为「稳定身份 + 兜底回收 + 容量上限」三层：
/// 1. `clientKey` 优先用客户端自报的稳定标识，不依赖代理对象地址；
/// 2. 客户端换代（身份对不上）时，激活新会话的动作会顺手回收上一条残留会话；
/// 3. 仍然限制同时存在的会话数，任何未预料到的身份漂移都不会让会话无限增长。
class RimeSessionManager {

    /// 同时保留的会话数上限。
    /// 一个控制器同一时刻只服务一个客户端，正常只会用到 1 条；
    /// 这里纯粹是兜底，防止身份漂移时静默泄漏。
    /// `internal` 以便回归测试直接引用这个上限。
    static let maxSessions = 4

    private struct Entry {
        let sessionId: RimeSessionId
        /// 单调递增的使用序号，用于淘汰最久未使用的会话
        var lastUsed: UInt64
    }

    /// Rime 引擎
    private let engine: RimeEngine

    /// 客户端标识到会话的映射
    private var sessions: [String: Entry] = [:]

    /// 最近一次被激活的客户端标识，用于回收「没等到 deactivate 就被换掉」的会话
    private var lastActiveKey: String?

    /// 单调递增的使用计数
    private var clock: UInt64 = 0

    /// 线程安全锁
    private let lock = NSLock()

    init(engine: RimeEngine) {
        self.engine = engine
    }

    /// 当前存活的会话数（诊断与回归测试用）
    var activeSessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.count
    }

    /// 获取或创建指定客户端的 Rime 会话
    /// - Parameter client: IMK 客户端对象
    /// - Returns: 会话 ID，如果创建失败则返回 0
    func sessionForClient(_ client: Any) -> RimeSessionId {
        let key = clientKey(client)
        lock.lock()
        defer { lock.unlock() }

        clock &+= 1

        // 同一客户端再次激活：复用已有会话
        if var entry = sessions[key], entry.sessionId != 0 {
            entry.lastUsed = clock
            sessions[key] = entry
            lastActiveKey = key
            return entry.sessionId
        }

        // 换了客户端，而上一个客户端的会话没等到 deactivate（快速切源、控制器复用）：
        // 这里兜底回收，否则它会永远留在字典里
        if let previousKey = lastActiveKey, previousKey != key,
           let stale = sessions.removeValue(forKey: previousKey) {
            engine.destroySession(stale.sessionId)
            debugLog("[Session] 回收未正常释放的会话 \(stale.sessionId)（上一个客户端=\(previousKey)）")
        }
        lastActiveKey = nil

        // 创建新会话
        let sessionId = engine.createSession()
        guard sessionId != 0 else { return 0 }
        sessions[key] = Entry(sessionId: sessionId, lastUsed: clock)
        lastActiveKey = key
        evictOverflow(keeping: key)
        return sessionId
    }

    /// 移除指定客户端的会话
    /// - Parameter client: IMK 客户端对象
    /// - Returns: 被销毁的会话 ID；没有匹配到会话时返回 0
    @discardableResult
    func removeSession(for client: Any) -> RimeSessionId {
        let key = clientKey(client)
        lock.lock()
        defer { lock.unlock() }

        guard let entry = sessions.removeValue(forKey: key) else { return 0 }
        engine.destroySession(entry.sessionId)
        if lastActiveKey == key {
            lastActiveKey = nil
        }
        return entry.sessionId
    }

    /// 会话是否仍然存活
    ///
    /// 控制器需要在 `deactivateServer` 里判断「我手上这条会话是不是已经被回收了」，
    /// 避免继续拿一个已销毁的 ID 去调 librime。
    func isAlive(_ sessionId: RimeSessionId) -> Bool {
        guard sessionId != 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.contains { $0.sessionId == sessionId }
    }

    /// 清理所有会话
    func removeAllSessions() {
        lock.lock()
        defer { lock.unlock() }

        for (_, entry) in sessions {
            engine.destroySession(entry.sessionId)
        }
        sessions.removeAll()
        lastActiveKey = nil
    }

    // MARK: - 私有方法

    /// 超出上限时淘汰最久未使用的会话（刚创建的那条不参与淘汰）
    /// - Parameter key: 需要保留的客户端标识
    private func evictOverflow(keeping key: String) {
        while sessions.count > Self.maxSessions,
              let victim = sessions
                .filter({ $0.key != key })
                .min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            sessions.removeValue(forKey: victim.key)
            engine.destroySession(victim.value.sessionId)
            debugLog("[Session] 会话数超限，淘汰 \(victim.value.sessionId)（客户端=\(victim.key)）")
            if lastActiveKey == victim.key {
                lastActiveKey = nil
            }
        }
    }

    /// 生成客户端的稳定标识
    ///
    /// 顺序很关键：对象地址最不稳定，只能当最后兜底。
    /// - Parameter client: 客户端对象
    /// - Returns: 标识字符串
    private func clientKey(_ client: Any) -> String {
        if let textInput = client as? IMKTextInput {
            // 客户端自报的稳定身份（同一个文本客户端跨激活保持一致）
            if let identifier = textInput.uniqueClientIdentifierString(), !identifier.isEmpty {
                return "id:\(identifier)"
            }
            // 退一步：至少同一 App 的激活与停用能配上对
            if let bundleID = textInput.bundleIdentifier(), !bundleID.isEmpty {
                return "bundle:\(bundleID)"
            }
        }
        if let obj = client as? NSObjectProtocol {
            return String(format: "ptr:%p", unsafeBitCast(obj, to: UInt.self))
        }
        return "desc:\(String(describing: client))"
    }
}

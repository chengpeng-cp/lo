import Foundation
import CRime

// MARK: - Rime 会话管理

/// 管理输入法客户端与 Rime 会话的映射关系
/// 每个 IMK 客户端对应一个 RimeSessionId
class RimeSessionManager {

    /// Rime 引擎
    private let engine: RimeEngine

    /// 客户端标识到会话 ID 的映射
    /// 使用 ObjectIdentifier 作为 key 不适用于 Any 类型，
    /// 因此使用客户端的描述字符串作为标识
    private var sessions: [String: RimeSessionId] = [:]

    /// 线程安全锁
    private let lock = NSLock()

    init(engine: RimeEngine) {
        self.engine = engine
    }

    /// 获取或创建指定客户端的 Rime 会话
    /// - Parameter client: IMK 客户端对象
    /// - Returns: 会话 ID，如果引擎未初始化则返回 0
    func sessionForClient(_ client: Any) -> RimeSessionId {
        let key = clientKey(client)
        lock.lock()
        defer { lock.unlock() }

        // 如果已有会话，直接返回
        if let sessionId = sessions[key], sessionId != 0 {
            return sessionId
        }

        // 创建新会话
        let sessionId = engine.createSession()
        if sessionId != 0 {
            sessions[key] = sessionId
        }
        return sessionId
    }

    /// 移除指定客户端的会话
    /// - Parameter client: IMK 客户端对象
    func removeSession(for client: Any) {
        let key = clientKey(client)
        lock.lock()
        defer { lock.unlock() }

        if let sessionId = sessions.removeValue(forKey: key) {
            engine.destroySession(sessionId)
        }
    }

    /// 清理所有会话
    func removeAllSessions() {
        lock.lock()
        defer { lock.unlock() }

        for (_, sessionId) in sessions {
            engine.destroySession(sessionId)
        }
        sessions.removeAll()
    }

    // MARK: - 私有方法

    /// 生成客户端的唯一标识
    /// - Parameter client: 客户端对象
    /// - Returns: 标识字符串
    private func clientKey(_ client: Any) -> String {
        // 使用对象的描述作为标识
        // 对于 NSObject 子类，description 通常是唯一的
        if let obj = client as? NSObjectProtocol {
            return String(format: "%p", unsafeBitCast(obj, to: UInt.self))
        }
        return String(describing: client)
    }
}

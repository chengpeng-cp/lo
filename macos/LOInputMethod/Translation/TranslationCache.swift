import Foundation

// MARK: - 翻译缓存

/// 翻译结果缓存，内存 + 文件持久化
/// 使用 LRU 策略，最多保留 1000 条记录
class TranslationCache {

    /// 单例
    static let shared = TranslationCache()

    /// 最大缓存条目数
    private let maxEntries = 1000

    /// 内存缓存，key 为原文，value 为翻译结果
    private var cache: [String: String] = [:]

    /// 访问顺序记录，用于 LRU 淘汰（最近访问的在末尾）
    private var accessOrder: [String] = []

    /// 线程安全锁
    private let lock = NSLock()

    /// 缓存文件路径
    private let cacheFilePath: String

    // 保证写入次序与 set/clear 次序一致，避免旧快照覆盖清空操作。
    private let persistenceQueue = DispatchQueue(label: "lo.translation-cache.persistence")
    private var persistenceGeneration: UInt64 = 0

    // MARK: - 初始化

    init(cacheFileURL: URL? = nil) {
        // 缓存文件位于用户数据目录
        let fileURL = cacheFileURL ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/LOInputMethod/translation_cache.json")
        let cacheDir = fileURL.deletingLastPathComponent().path
        cacheFilePath = fileURL.path

        // 确保目录存在
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDir) {
            try? fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        }

        // 从文件加载缓存
        loadFromFile()
    }

    // MARK: - 公开接口

    /// 获取缓存的翻译结果
    /// - Parameters:
    ///   - text: 原文
    ///   - targetLanguage: 目标语言代码
    /// - Returns: 翻译结果，如果没有缓存则返回 nil
    func get(text: String, targetLanguage: String, context: String = "") -> String? {
        lock.lock()
        defer { lock.unlock() }

        let key = cacheKey(text, targetLanguage: targetLanguage, context: context)
        guard let value = cache[key] else { return nil }

        // 更新访问顺序（移到末尾）
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return value
    }

    /// 设置翻译结果缓存
    /// - Parameters:
    ///   - text: 原文
    ///   - translation: 翻译结果
    ///   - targetLanguage: 目标语言代码
    func set(text: String, translation: String, targetLanguage: String, context: String = "") {
        guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let key = cacheKey(text, targetLanguage: targetLanguage, context: context)

        // 如果已存在，更新访问顺序
        if cache[key] != nil {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        cache[key] = translation
        accessOrder.append(key)

        // LRU 淘汰
        evictIfNeeded()

        // 异步持久化到文件
        saveToFileAsync()
    }

    /// 清除所有缓存
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
        saveToFileAsync()
    }

    // MARK: - 私有方法

    /// 版本化结构键：保留大小写，并隔离提供商、模型、模式与端点。
    private func cacheKey(_ text: String, targetLanguage: String, context: String) -> String {
        let fields = ["v2", context, targetLanguage, text.trimmingCharacters(in: .whitespacesAndNewlines)]
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return String(data: data, encoding: .utf8)!
    }

    /// LRU 淘汰超出限制的条目
    private func evictIfNeeded() {
        while cache.count > maxEntries, let oldestKey = accessOrder.first {
            cache.removeValue(forKey: oldestKey)
            accessOrder.removeFirst()
        }
    }

    /// 从文件加载缓存
    private func loadFromFile() {
        guard let data = FileManager.default.contents(atPath: cacheFilePath) else { return }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }

        cache = dict.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        accessOrder = Array(cache.keys)
        evictIfNeeded()
    }

    /// 异步保存缓存到文件
    private func saveToFileAsync() {
        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        let path = cacheFilePath

        persistenceQueue.async {
            self.lock.lock()
            guard self.persistenceGeneration == generation else {
                self.lock.unlock()
                return
            }
            let cacheCopy = self.cache
            self.lock.unlock()
            guard let data = try? JSONSerialization.data(
                withJSONObject: cacheCopy,
                options: [.sortedKeys]
            ) else { return }
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}

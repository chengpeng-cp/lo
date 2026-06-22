import Foundation

// MARK: - Rime 配置路径

/// Rime 引擎的路径配置
enum RimeConfig {

    /// 共享数据目录，从 Bundle 的 Resources/rime 获取
    static var sharedDataDir: String {
        Bundle.main.resourcePath.flatMap { $0 + "/rime" } ?? "/usr/share/rime-data"
    }

    /// 用户数据目录，位于 ~/Library/Rime
    static var userDir: String {
        let home = NSHomeDirectory()
        return home + "/Library/Rime"
    }

    /// 确保用户数据目录存在
    static func ensureUserDirExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: userDir) {
            try? fm.createDirectory(atPath: userDir, withIntermediateDirectories: true)
        }
    }
}

import Foundation
import LOMTCore

// MARK: - 本地模型存储

/// 管理 `~/Library/Application Support/LOInputMethod/models` 下的模型目录。
/// `.complete` 是「已安装」的唯一判据：只有下载与校验全部通过后才写入。
final class MTModelStore {

    static let shared = MTModelStore()

    private let fileManager = FileManager.default
    let rootDirectory: URL
    let downloadsDirectory: URL

    private let completionMarker = ".complete"

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let base = support.appendingPathComponent("LOInputMethod", isDirectory: true)
        rootDirectory = base.appendingPathComponent("models", isDirectory: true)
        downloadsDirectory = base.appendingPathComponent("downloads", isDirectory: true)
    }

    private func ensureDirectories() {
        for directory in [rootDirectory, downloadsDirectory] where !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func directory(for id: String) -> URL {
        ensureDirectories()
        return rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func isInstalled(_ id: String) -> Bool {
        let dir = directory(for: id)
        return fileManager.fileExists(atPath: dir.appendingPathComponent(completionMarker).path)
            && fileManager.fileExists(atPath: dir.appendingPathComponent("manifest.json").path)
    }

    func manifest(for id: String) -> MTModelManifest? {
        let url = directory(for: id).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MTModelManifest.self, from: data)
    }

    /// 已安装的轻量模型（按目录中的 manifest 读取，而不是仅依赖内置目录）
    func installedLightModels() -> [MTModelManifest] {
        MTModelCatalog.lightModels.filter { isInstalled($0.id) }
    }

    func installedBytes() -> Int64 {
        guard let ids = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path) else { return 0 }
        var total: Int64 = 0
        for id in ids where isInstalled(id) {
            let dir = rootDirectory.appendingPathComponent(id)
            let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
            while let url = enumerator?.nextObject() as? URL {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    func delete(_ id: String) throws {
        let dir = directory(for: id)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    /// 删除下载中的半成品
    func discardPartial(_ id: String) {
        let dir = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
        try? fileManager.removeItem(at: dir)
    }

    /// 查找覆盖指定方向、且已安装的模型
    func installedModel(forSource src: String, target: String) -> MTModelManifest? {
        let wanted = MTModelCatalog.normalized(target)
        for spec in MTModelCatalog.lightModels
        where spec.src == src && MTModelCatalog.normalized(spec.tgt) == wanted && isInstalled(spec.id) {
            return spec
        }
        return nil
    }

    func freeDiskSpace() -> Int64 {
        let values = try? rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

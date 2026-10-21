import Foundation
import Combine
import AppKit

// MARK: - 界面状态

enum UninstallPhase: Equatable {
    case scanning
    case ready
    case empty
    case uninstalling
    case finished
    case failed(String)
}

struct UninstallSummary {
    let removedCount: Int
    let freedBytes: Int64
    let remaining: [CleanItem]
    let warnings: [String]
}

// MARK: - 视图模型

/// 扫描与清理都交给 scripts/uninstall.sh 执行：
/// 脚本是唯一事实来源，App 只负责展示、确认与特权提权。
final class UninstallerViewModel: ObservableObject {

    @Published private(set) var phase: UninstallPhase = .scanning
    @Published private(set) var items: [CleanItem] = []
    @Published private(set) var statusText = "正在扫描语境输入法残留…"
    @Published private(set) var summary: UninstallSummary?
    /// 非致命提示，例如用户取消了管理员授权
    @Published private(set) var notice: String?

    /// 是否连 Rime 词库、用户词典一起清空
    @Published var purgeRime: Bool = true {
        didSet {
            guard oldValue != purgeRime else { return }
            if phase == .ready || phase == .empty {
                scan()
            }
        }
    }

    /// 卸载前把 Rime 与偏好设置备份到桌面
    @Published var backupBeforeUninstall: Bool = false

    /// 扫描是否在途。不能用 phase == .scanning 判断：
    /// 初始状态就是 .scanning，会让首次调用被自己拦住。
    private var scanInFlight = false

    private var isBusy: Bool {
        phase == .uninstalling || scanInFlight
    }

    var groupedItems: [(group: String, items: [CleanItem])] {
        var order: [String] = []
        var buckets: [String: [CleanItem]] = [:]
        for item in items {
            if buckets[item.group] == nil {
                order.append(item.group)
                buckets[item.group] = []
            }
            buckets[item.group]?.append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    var hasSystemItems: Bool {
        items.contains { $0.isSystemLevel }
    }

    // MARK: - 扫描

    func scan() {
        guard !isBusy else { return }
        scanInFlight = true
        notice = nil
        let purge = purgeRime
        phase = .scanning
        statusText = "正在扫描语境输入法残留…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                var args = ["--dry-run"]
                if purge { args.append("--purge") }
                let output = try UninstallRunner.runAsUser(arguments: args)
                var scanned = output.items
                // 原生读取输入源列表，避免依赖 python3 的可用性
                let leftover = self.pendingInputSourceEntryCount()
                if leftover > 0, !scanned.contains(where: { $0.group == "系统注册" }) {
                    scanned.append(
                        CleanItem(
                            group: "系统注册",
                            bytes: 0,
                            kind: .service,
                            path: "输入源启用列表（\(leftover) 条记录）"
                        )
                    )
                }
                DispatchQueue.main.async {
                    self.scanInFlight = false
                    self.items = scanned
                    self.summary = nil
                    self.phase = scanned.isEmpty ? .empty : .ready
                }
            } catch {
                DispatchQueue.main.async {
                    self.scanInFlight = false
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 清理

    func uninstall() {
        guard phase == .ready || phase == .empty, !isBusy else { return }

        let snapshot = items
        let purge = purgeRime
        let backup = backupBeforeUninstall && purge
        let needsPrivilege = snapshot.contains { $0.isSystemLevel }
        let desktopPath = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        // 用户态直接改写 CFPreferences，比让脚本调用 python3 更可靠
        let removedSourceEntries = removeInputSourceEntries()


        notice = nil
        phase = .uninstalling
        statusText = needsPrivilege
            ? "正在请求管理员授权，清理系统级安装…"
            : "正在清理用户数据与系统注册…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var warnings: [String] = []
            if removedSourceEntries > 0 {
                warnings.append("已从系统输入源启用列表移除 \(removedSourceEntries) 条旧记录")
            }
            do {
                if needsPrivilege {
                    let systemOutput = try UninstallRunner.runPrivileged(
                        arguments: ["--system-only", "--yes"]
                    )
                    warnings.append(contentsOf: systemOutput.warnings)
                }

                DispatchQueue.main.async {
                    self.statusText = "正在清理词库、设置、Keychain 与输入源注册…"
                }

                var args = ["--user-only", "--yes", "--skip-tis"]
                if purge { args.append("--purge") }
                if backup { args += ["--backup", desktopPath] }
                let userOutput = try UninstallRunner.runAsUser(arguments: args)
                warnings.append(contentsOf: userOutput.warnings)

                // 复检：用与扫描相同的口径再看一次
                var verifyArgs = ["--dry-run"]
                if purge { verifyArgs.append("--purge") }
                let verification = try UninstallRunner.runAsUser(arguments: verifyArgs)

                let remaining = verification.items
                let removed = max(0, snapshot.count - remaining.count)
                let freed = max(
                    0,
                    snapshot.reduce(0) { $0 + $1.bytes } - remaining.reduce(0) { $0 + $1.bytes }
                )

                DispatchQueue.main.async {
                    self.summary = UninstallSummary(
                        removedCount: removed,
                        freedBytes: freed,
                        remaining: remaining,
                        warnings: warnings
                    )
                    self.phase = .finished
                }
            } catch UninstallerError.privilegedCanceled {
                DispatchQueue.main.async {
                    self.phase = .ready
                    self.notice = "已取消管理员授权，未做任何修改。"
                }
            } catch {
                DispatchQueue.main.async {
                    self.scanInFlight = false
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 输入源列表（原生清理）

    private let bundleId = "com.lo.inputmethod.ime"

    private static let inputSourceDomains: [(domain: String, key: String)] = [
        ("com.apple.HIToolbox", "AppleEnabledInputSources"),
        ("com.apple.inputsources", "AppleEnabledThirdPartyInputSources")
    ]

    private func isLOEntry(_ entry: [String: Any]) -> Bool {
        let bundle = (entry["Bundle ID"] as? String)
            ?? (entry["BundleIdentifier"] as? String)
            ?? ""
        let mode = (entry["Input Mode"] as? String) ?? ""
        return bundle == bundleId
            || bundle.hasPrefix(bundleId + ".")
            || mode.hasPrefix(bundleId)
    }

    private func inputSourceEntries(domain: String, key: String) -> [[String: Any]] {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [[String: Any]] ?? []
    }

    /// 输入源启用列表中仍指向本输入法的记录数
    func pendingInputSourceEntryCount() -> Int {
        Self.inputSourceDomains.reduce(0) { total, pair in
            total + inputSourceEntries(domain: pair.domain, key: pair.key).filter(isLOEntry).count
        }
    }

    /// 从两个偏好域中删除残留记录；返回实际移除条数
    @discardableResult
    private func removeInputSourceEntries() -> Int {
        var removed = 0
        for pair in Self.inputSourceDomains {
            let entries = inputSourceEntries(domain: pair.domain, key: pair.key)
            let kept = entries.filter { !isLOEntry($0) }
            guard kept.count != entries.count else { continue }
            CFPreferencesSetAppValue(pair.key as CFString, kept as CFArray, pair.domain as CFString)
            _ = CFPreferencesAppSynchronize(pair.domain as CFString)
            let after = inputSourceEntries(domain: pair.domain, key: pair.key)
            removed += max(0, entries.count - after.filter(isLOEntry).count)
        }
        return removed
    }

    // MARK: - 其他动作

    func retry() {
        summary = nil
        scan()
    }

#if DEBUG
    /// 仅用于截图与 SwiftUI 预览：跳过异步扫描，直接注入扫描结果
    func applyPreview(items: [CleanItem]) {
        self.items = items
        self.summary = nil
        self.phase = items.isEmpty ? .empty : .ready
    }

    /// 仅用于截图与 SwiftUI 预览：注入完成页数据
    func applyPreviewSummary(removed: Int, freed: Int64, remaining: [CleanItem], warnings: [String]) {
        self.summary = UninstallSummary(
            removedCount: removed,
            freedBytes: freed,
            remaining: remaining,
            warnings: warnings
        )
        self.phase = .finished
    }
#endif

    func openInputSourcesSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}

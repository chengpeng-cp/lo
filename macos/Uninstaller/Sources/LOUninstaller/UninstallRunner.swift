import Foundation

// MARK: - 残留项模型

struct CleanItem: Identifiable, Hashable {
    enum Kind: String {
        case file
        case service
    }

    let group: String
    let bytes: Int64
    let kind: Kind
    let path: String

    var id: String { "\(group)|\(path)" }

    /// 把家目录缩写成 ~，清单更易读
    var displayPath: String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    var isSystemLevel: Bool {
        path.hasPrefix("/Library/")
    }
}

// MARK: - 脚本输出解析

struct ScriptOutput {
    var items: [CleanItem] = []
    var steps: [String] = []
    var warnings: [String] = []
    var errors: [String] = []
    var removed: [String] = []
    var result: (removed: Int, failed: Int, remaining: Int)?
    var completed = false

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    /// 解析 scripts/uninstall.sh 的 LO_ 制表符协议
    static func parse(_ text: String) -> ScriptOutput {
        var output = ScriptOutput()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard line.hasPrefix("LO_") else { continue }
            let fields = line.components(separatedBy: "\t")
            switch fields[0] {
            case "LO_ITEM" where fields.count >= 5:
                output.items.append(
                    CleanItem(
                        group: fields[1],
                        bytes: Int64(fields[2]) ?? 0,
                        kind: CleanItem.Kind(rawValue: fields[3]) ?? .file,
                        path: fields[4]
                    )
                )
            case "LO_STEP" where fields.count >= 2:
                output.steps.append(fields[1])
            case "LO_WARN" where fields.count >= 2:
                output.warnings.append(fields[1])
            case "LO_ERROR" where fields.count >= 2:
                output.errors.append(fields[1])
            case "LO_REMOVED" where fields.count >= 2:
                output.removed.append(fields[1])
            case "LO_RESULT" where fields.count >= 4:
                output.result = (
                    Int(fields[1]) ?? 0,
                    Int(fields[2]) ?? 0,
                    Int(fields[3]) ?? 0
                )
            case "LO_DONE":
                output.completed = true
            default:
                break
            }
        }
        return output
    }
}

// MARK: - 执行器

enum UninstallerError: LocalizedError {
    case scriptMissing
    case launchFailed(String)
    case privilegedCanceled
    case privilegedFailed(String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptMissing:
            return "卸载脚本缺失（uninstall.sh），请重新下载卸载工具。"
        case .launchFailed(let message):
            return "无法启动清理进程：\(message)"
        case .privilegedCanceled:
            return "已取消管理员授权，未做任何修改。"
        case .privilegedFailed(let message):
            return "系统级清理失败：\(message)"
        case .scriptFailed(let message):
            return message
        }
    }
}

enum UninstallRunner {
    /// 优先取 App 内置脚本；开发调试时可用环境变量指向源码目录里的脚本
    static func scriptURL() -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["LO_UNINSTALL_SCRIPT"],
           fm.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        if let bundled = Bundle.main.url(forResource: "uninstall", withExtension: "sh"),
           fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// 以当前用户身份执行（清理用户目录、偏好设置、Keychain、输入源注册）
    static func runAsUser(arguments: [String]) throws -> ScriptOutput {
        guard let script = scriptURL() else { throw UninstallerError.scriptMissing }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw UninstallerError.launchFailed(error.localizedDescription)
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var output = ScriptOutput.parse(String(decoding: outData, as: UTF8.self))
        let errText = String(decoding: errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !errText.isEmpty {
            output.errors.append(errText)
        }
        if process.terminationStatus != 0, output.result == nil {
            let message = output.errors.last ?? "清理脚本退出码 \(process.terminationStatus)"
            throw UninstallerError.scriptFailed(message)
        }
        return output
    }

    /// 以管理员权限执行系统级清理（停止进程、删除 /Library/Input Methods 中的 bundle）
    static func runPrivileged(arguments: [String]) throws -> ScriptOutput {
        guard let script = scriptURL() else { throw UninstallerError.scriptMissing }

        let command = "/bin/bash \(shellQuote(script.path)) " + arguments.map(shellQuote).joined(separator: " ")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        guard let appleScript = NSAppleScript(source: source) else {
            throw UninstallerError.privilegedFailed("无法创建管理员授权脚本")
        }
        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if number == -128 {
                throw UninstallerError.privilegedCanceled
            }
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "未知错误（代码 \(number)）"
            throw UninstallerError.privilegedFailed(message)
        }

        let text = result.stringValue ?? ""
        if !text.isEmpty, !text.contains("LO_DONE") {
            throw UninstallerError.privilegedFailed(text)
        }
        var output = ScriptOutput.parse(text)
        if text.isEmpty { output.completed = true }
        return output
    }
}

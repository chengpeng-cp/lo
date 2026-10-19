import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

// MARK: - 安装步骤

/// 安装器的状态机
enum InstallStep: Equatable {
    case welcome
    case installing
    case finished
    case failed(String)
}

// MARK: - 安装器视图模型

/// 负责执行系统级安装：以管理员权限将输入法拷贝到 /Library/Input Methods/ 并签名、注册、启动。
final class InstallerViewModel: ObservableObject {

    @Published var step: InstallStep = .welcome
    /// 安装过程中的状态文案
    @Published var statusText: String = "正在准备安装…"

    /// 系统级安装目录
    private let installDir = "/Library/Input Methods"
    private let appName = "LOInputMethod.app"
    private let bundleId = "com.lo.inputmethod.ime"

    /// 用户在授权对话框点取消时回传的标记
    private static let userCanceledMessage = "__USER_CANCELED__"

    /// 是否已安装旧版本（用于在欢迎页区分“安装”/“升级”文案）
    var isUpgrade: Bool {
        FileManager.default.fileExists(atPath: "\(installDir)/\(appName)")
    }

    // MARK: - 安装

    /// 启动安装流程
    func startInstall() {
        step = .installing
        statusText = "正在准备安装…"

        // 1. 定位内嵌的输入法 payload
        guard let payloadURL = Bundle.main.url(forResource: "LOInputMethod", withExtension: "app") else {
            step = .failed("安装包已损坏：未找到输入法主程序，请重新下载。")
            return
        }
        let payloadPath = payloadURL.path
        let targetPath = "\(installDir)/\(appName)"

        let userBundlePath = "\(NSHomeDirectory())/Library/Input Methods/\(appName)"

        // 2. 构造特权安装脚本（仅做需要 root 权限的操作：拷贝、签名、清理）
        //    关键：open / lsregister -f 不在此脚本内执行。
        //    特权脚本以 root 身份运行，open 会把 bundle 注册到 root 的
        //    LaunchServices 上下文，导致当前用户在输入法列表中只看到空白项
        //   （系统知道有输入法但读不到本地化名称）。这些操作改由 runPostInstall
        //    在普通用户上下文执行，与 make install && make restart 行为一致。
        let script = InstallerScripts.install(
            payload: payloadPath, target: targetPath, userBundle: userBundlePath
        )

        // 3. 写入临时脚本文件（无需权限）
        let tmpPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("lo-install-\(UUID().uuidString).sh")
        do {
            try script.write(toFile: tmpPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpPath)
        } catch {
            step = .failed("无法写入临时安装脚本：\(error.localizedDescription)")
            return
        }

        // 4. 后台执行特权脚本
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.runPrivileged(scriptPath: tmpPath) { errorMessage in
                try? FileManager.default.removeItem(atPath: tmpPath)
                DispatchQueue.main.async {
                    if let message = errorMessage {
                        // 用户在密码框点取消：静默回到欢迎页
                        if message == Self.userCanceledMessage {
                            self.step = .welcome
                        } else {
                            self.step = .failed(message)
                        }
                    } else {
                        // 特权操作成功，转至用户上下文执行后置注册
                        self.runPostInstall(targetPath: targetPath)
                    }
                }
            }
        }

        // 5. 脚本执行期间更新状态文案
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self, case .installing = self.step else { return }
            self.statusText = "正在安装语境输入法，请稍候…"
        }
    }

    // MARK: - 后置注册（用户上下文）

    /// 在普通用户上下文执行 LaunchServices 注册、刷新输入法菜单、启动驻留进程。
    /// 关键：open / lsregister 必须在用户会话中执行，不能在 root 特权脚本里执行，
    /// 否则 LaunchServices 会把 bundle 注册到 root 上下文，导致当前用户的输入法列表
    /// 出现空白项（系统知道有输入法但读不到本地化名称）。
    private func runPostInstall(targetPath: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "正在注册输入法…"
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 把后置操作写成脚本文件执行，避免 bash -c 中的引号嵌套解析问题
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
            let userBundlePath = "\(NSHomeDirectory())/Library/Input Methods/\(appName)"
            let script = """
            #!/bin/bash
            set -e
            # 先注销所有旧路径的 LaunchServices 注册（防止输入法列表出现重复项）
            \(InstallerScripts.shellQuote(lsregister)) -u \(InstallerScripts.shellQuote(targetPath)) 2>/dev/null || true
            \(InstallerScripts.shellQuote(lsregister)) -u \(InstallerScripts.shellQuote(userBundlePath)) 2>/dev/null || true
            # 强制注册新 bundle 到当前用户的 LaunchServices
            \(InstallerScripts.shellQuote(lsregister)) -f \(InstallerScripts.shellQuote(targetPath)) 2>&1
            """

            let postScriptPath = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("lo-postinstall-\(UUID().uuidString).sh")
            let logPath = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("lo-postinstall.log")
            do {
                try script.write(toFile: postScriptPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postScriptPath)
            } catch {
                // 写脚本失败，仍尝试在当前用户上下文显式注册并启动。
                self.registerInputSourceAndLaunch(targetPath: targetPath)
                return
            }

            // 执行后置脚本，捕获输出到日志
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = [postScriptPath]
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let logHandle = FileHandle(forWritingAtPath: logPath)
            defer { try? logHandle?.close() }
            if let logHandle = logHandle {
                logHandle.truncateFile(atOffset: 0)
                task.standardOutput = logHandle
                task.standardError = logHandle
            }
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                // Process 启动失败，用 NSWorkspace 后备
                try? FileManager.default.removeItem(atPath: postScriptPath)
                self.registerInputSourceAndLaunch(targetPath: targetPath)
                return
            }
            try? FileManager.default.removeItem(atPath: postScriptPath)

            guard task.terminationStatus == 0 else {
                DispatchQueue.main.async {
                    self.step = .failed("输入法文件已安装，但注册或启动失败。请重试安装，或查看日志：\(logPath)")
                }
                return
            }

            self.registerInputSourceAndLaunch(targetPath: targetPath)
        }
    }

    // MARK: - 特权执行

    /// 在普通用户会话中注册输入源，核对可见名称后再刷新菜单并启动。
    /// LaunchServices 注册 bundle 与 TIS 注册输入源是两步，安装器都显式完成。
    private func registerInputSourceAndLaunch(targetPath: String) {
        let url = URL(fileURLWithPath: targetPath)
        let status = TISRegisterInputSource(url as CFURL)
        guard status == noErr else {
            DispatchQueue.main.async {
                self.step = .failed("输入法文件已安装，但系统注册输入源失败（\(status)）。请重新安装，或重新登录后重试。")
            }
            return
        }

        guard let localizedName = localizedInputModeName() else {
            DispatchQueue.main.async {
                self.step = .failed("输入法文件已安装，但系统未读取到输入法名称。请重新登录后在系统设置中添加“语境输入法”。")
            }
            return
        }

        // 重新启动菜单代理，使刚注册的 source ID 和本地化名称立即刷新。
        let refresh = Process()
        refresh.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        refresh.arguments = ["TextInputMenuAgent"]
        do {
            try refresh.run()
            refresh.waitUntilExit()
        } catch {
            // 刷新失败不影响 source 注册与后续启动。
        }

        let opened = NSWorkspace.shared.open(url)
        if opened {
            NSLog("[LOInstaller] Registered input source: %@", localizedName)
            finishAfterLaunch(targetPath: targetPath)
        } else {
            DispatchQueue.main.async {
                self.step = .failed("输入法已注册并显示为“\(localizedName)”，但无法启动。请重新登录后在系统设置中启用输入法。")
            }
        }
    }

    /// 查找输入法唯一可见的模式 ID，并要求系统返回非空本地化名称。
    private func localizedInputModeName() -> String? {
        let modeID = "\(bundleId).pinyin"
        let filter = [kTISPropertyInputSourceID as String: modeID] as CFDictionary
        guard let unmanaged = TISCreateInputSourceList(filter, true) else { return nil }
        let sources = unmanaged.takeRetainedValue() as? [TISInputSource] ?? []
        for source in sources {
            guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
                continue
            }
            let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String
            if id == modeID, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return nil
    }

    /// A successful `open` only acknowledges a launch request. Catch immediate crashes.
    private func finishAfterLaunch(targetPath: String) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let targetURL = URL(fileURLWithPath: targetPath).standardizedFileURL
                let running = NSWorkspace.shared.runningApplications.contains {
                    !$0.isTerminated && $0.bundleIdentifier == self.bundleId &&
                    $0.bundleURL?.standardizedFileURL == targetURL
                }
                self.step = running ? .finished : .failed("输入法文件已安装，但启动后未保持运行。请重新登录后重试；若仍失败，请提交崩溃日志。")
            }
        }
    }

    // MARK: - 特权执行

    /// 通过 NSAppleScript 以管理员权限执行 shell 脚本
    /// - Parameters:
    ///   - scriptPath: 临时脚本文件路径
    ///   - completion: 成功返回 nil，失败返回错误信息（取消时返回 userCanceledMessage）
    private func runPrivileged(scriptPath: String, completion: @escaping (String?) -> Void) {
        // 转义路径中的反斜杠与双引号，保证 AppleScript 字符串安全
        let escaped = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptText = "do shell script \"/bin/bash \\\"\(escaped)\\\"\" with administrator privileges"

        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: appleScriptText) else {
            completion("无法创建管理员安装脚本。")
            return
        }
        let result = appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -128: 用户在授权对话框点了取消
            if number == -128 {
                completion(Self.userCanceledMessage)
            } else {
                let message = (error[NSAppleScript.errorMessage] as? String) ?? "未知错误（代码 \(number)）"
                completion(message)
            }
        } else if result.stringValue?.contains("LO_INSTALL_DONE") == true {
            completion(nil)
        } else {
            completion("安装没有返回完成标记，请重新下载安装包后重试。")
        }
    }

    // MARK: - 完成页动作

    /// 打开系统设置 → 键盘 → 输入法，引导用户添加输入法
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

import Foundation

@main
struct InstallerRegression {
    static func run(_ program: String, _ args: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lo-installer-regression-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func check(_ passed: Bool, _ title: String) {
            guard passed else { fatalError("FAIL: \(title)") }
            print("PASS: \(title)")
        }
        let hostile = "quote' double\" dollar$(touch \(root.path)/injected) `echo no`\nnext"
        let quoted = try run("/bin/bash", ["-c", "printf '%s' " + InstallerScripts.shellQuote(hostile)])
        check(quoted.0 == 0 && quoted.1 == hostile && !fm.fileExists(atPath: root.appendingPathComponent("injected").path), "shell paths cannot execute substitutions")

        let payload = root.appendingPathComponent("payload ' $(false).app")
        let target = root.appendingPathComponent("target ' $(false).app")
        let duplicate = root.appendingPathComponent("old-user.app")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try "old working version".write(to: target.appendingPathComponent("old-marker"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: duplicate, withIntermediateDirectories: true)
        func installScript(fault: Bool = false, backupCleanupFault: Bool = false) -> String {
            var script = InstallerScripts.install(payload: payload.path, target: target.path, userBundle: duplicate.path)
            // Exercise replacement without terminating any actual input-method process.
            script = script.replacingOccurrences(of: "/usr/bin/killall LOInputMethod", with: "/usr/bin/true")
            if fault {
                script = script.replacingOccurrences(of: "/usr/bin/codesign --verify --deep --strict \"$target\"", with: "/usr/bin/false")
            }
            if backupCleanupFault {
                // Simulate rm deleting part of an old bundle before a locked file fails.
                script = script.replacingOccurrences(of: "/bin/rm -rf \"$backup\"", with: "( /bin/rm -f \"$backup/old-marker\"; /usr/bin/false )")
            }
            return script
        }
        let scriptURL = root.appendingPathComponent("install.sh")
        try installScript().write(to: scriptURL, atomically: true, encoding: .utf8)
        let missing = try run("/bin/bash", [scriptURL.path])
        check(missing.0 != 0 && fm.fileExists(atPath: target.appendingPathComponent("old-marker").path) && fm.fileExists(atPath: duplicate.path), "missing payload preserves previous installation")

        try fm.createDirectory(at: payload.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/usr/bin/true", toPath: payload.appendingPathComponent("Contents/MacOS/TestApp").path)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.lo.regression.installer", "CFBundleExecutable": "TestApp", "CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: payload.appendingPathComponent("Contents/Info.plist"))
        let signing = try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", payload.path])
        check(signing.0 == 0, "signed disposable bundle prepared")
        try installScript(fault: true).write(to: scriptURL, atomically: true, encoding: .utf8)
        let rollback = try run("/bin/bash", [scriptURL.path])
        check(rollback.0 != 0 && fm.fileExists(atPath: target.appendingPathComponent("old-marker").path), "post-replacement failure rolls back previous installation")
        try installScript().write(to: scriptURL, atomically: true, encoding: .utf8)
        let success = try run("/bin/bash", [scriptURL.path])
        check(success.0 == 0 && success.1.contains("LO_INSTALL_DONE") && fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/TestApp").path) && !fm.fileExists(atPath: duplicate.path), "signed installation completes with safely quoted paths")
        check(try fm.contentsOfDirectory(atPath: root.path).filter { $0.contains(".backup-") || $0.contains(".install-") }.isEmpty, "transaction temporary bundles are removed")

        try "critical old file".write(to: target.appendingPathComponent("old-marker"), atomically: true, encoding: .utf8)
        try installScript(backupCleanupFault: true).write(to: scriptURL, atomically: true, encoding: .utf8)
        let partialCleanup = try run("/bin/bash", [scriptURL.path])
        let targetVerification = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
        check(partialCleanup.0 == 0 && partialCleanup.1.contains("LO_INSTALL_DONE") && partialCleanup.1.contains("LO_INSTALL_CLEANUP_WARNING") && targetVerification.0 == 0, "partial old-backup deletion preserves verified new installation and reports a warning")
    }
}

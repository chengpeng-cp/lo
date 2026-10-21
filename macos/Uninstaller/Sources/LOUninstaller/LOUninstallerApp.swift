import SwiftUI

// MARK: - 卸载工具入口

/// 语境输入法卸载工具：扫描残留 → 预览清单 → 一键彻底清理。
@main
struct LOUninstallerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

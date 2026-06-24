import SwiftUI

// MARK: - 安装器入口

/// 语境输入法安装器：引导用户一键安装到 /Library/Input Methods/
@main
struct LOInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 固定窗口尺寸，禁止缩放，保证企业级安装器一致的视觉
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

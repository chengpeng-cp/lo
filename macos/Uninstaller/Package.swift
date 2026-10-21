// swift-tools-version: 5.9

import PackageDescription

// MARK: - 语境输入法卸载工具 SPM 配置
// 独立可执行目标，不依赖 librime，仅用 SwiftUI/AppKit 实现。
// 真正的清理动作由 scripts/uninstall.sh 完成，App 负责扫描预览与调用。

let package = Package(
    name: "LOUninstaller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LOUninstaller",
            targets: ["LOUninstaller"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LOUninstaller",
            path: "Sources/LOUninstaller"
        )
    ]
)

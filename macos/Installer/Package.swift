// swift-tools-version: 5.9

import PackageDescription

// MARK: - 语境输入法安装器 SPM 配置
// 独立可执行目标，不依赖 librime，仅用 SwiftUI/AppKit 实现企业级安装引导。

let package = Package(
    name: "LOInstaller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LOInstaller",
            targets: ["LOInstaller"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LOInstaller",
            path: "Sources/LOInstaller"
        )
    ]
)

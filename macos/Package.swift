// swift-tools-version: 5.10

import PackageDescription

// MARK: - 语境输入法 SPM 配置

let package = Package(
    name: "LOInputMethod",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LOInputMethod",
            targets: ["LOInputMethod"]
        )
    ],
    dependencies: [],
    targets: [
        // 系统库目标：链接 librime
        .systemLibrary(
            name: "CRime",
            path: "CRime",
            pkgConfig: "rime",
            providers: [
                .brew(["librime"])
            ]
        ),
        .executableTarget(
            name: "LOInputMethod",
            dependencies: [
                .target(name: "CRime")
            ],
            path: "LOInputMethod",
            exclude: ["Info.plist", "Bridging-Header.h", "Resources/zh-Hans.lproj", "Resources/en.lproj", "Resources/AppIcon.icns", "Resources/InfoPlist.strings"],
            resources: [
                .copy("Resources/rime")
            ],
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-lrime"])
            ],
            // 显式指定 Swift 5 语言模式,避免 Xcode 16+ 默认启用严格并发检查
            // 导致 @MainActor 类在 Timer/Task 闭包中的捕获报错
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

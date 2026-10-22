// swift-tools-version: 5.9

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
        ),
        .executable(
            name: "LOSourceSwitcher",
            targets: ["LOSourceSwitcher"]
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
            exclude: ["Info.plist", "Bridging-Header.h", "Resources/zh-Hans.lproj", "Resources/en.lproj", "Resources/AppIcon.icns", "Resources/MenuIcon.tif", "Resources/InfoPlist.strings"],
            resources: [
                .copy("Resources/rime")
            ]
        ),
        // 输入源切换助手：必须以独立进程执行 TISSelectInputSource，
        // 输入法进程内选择自身会导致激活握手弹跳（详见 main.swift 注释）
        .executableTarget(
            name: "LOSourceSwitcher",
            path: "LOSourceSwitcher"
        )
    ]
)

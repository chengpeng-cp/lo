// swift-tools-version: 5.9

import PackageDescription
import Foundation

// MARK: - 语境输入法 SPM 配置

// 仓库根目录：用于定位本机 vendor 的 ONNX Runtime（不随仓库分发）
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let ortRoot = "\(packageRoot)/vendor/onnxruntime"

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
        ),
        .executable(
            name: "LOMTEngine",
            targets: ["LOMTEngine"]
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
        // 平台无关的本地翻译核心：清单、分词、协议常量
        .target(
            name: "LOMTCore",
            path: "LOMTCore"
        ),
        // ONNX Runtime C++ 桥接：仅暴露 C ABI，供 Swift 调用
        .target(
            name: "COrtBridge",
            path: "ORTBridge",
            cxxSettings: [
                .headerSearchPath("../vendor/onnxruntime/include"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(ortRoot)/lib",
                    "-lonnxruntime",
                    "-Xlinker", "-rpath", "-Xlinker", "\(ortRoot)/lib"
                ])
            ]
        ),
        // 本地翻译推理进程：独立于输入法主进程，崩溃不影响输入
        .executableTarget(
            name: "LOMTEngine",
            dependencies: [
                .target(name: "LOMTCore"),
                .target(name: "COrtBridge")
            ],
            path: "LOMTEngine",
            linkerSettings: [
                // 打包后从 App 的 Frameworks 目录加载 libonnxruntime
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(
            name: "LOInputMethod",
            dependencies: [
                .target(name: "CRime"),
                .target(name: "LOMTCore")
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

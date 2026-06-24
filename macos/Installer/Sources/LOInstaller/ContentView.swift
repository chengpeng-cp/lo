import SwiftUI
import AppKit

// MARK: - 主容器

struct ContentView: View {
    @StateObject private var viewModel = InstallerViewModel()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.gradientBackground().ignoresSafeArea()

            Group {
                switch viewModel.step {
                case .welcome:
                    WelcomeView(viewModel: viewModel)
                case .installing:
                    InstallingView(viewModel: viewModel)
                case .finished:
                    FinishedView(viewModel: viewModel)
                case .failed(let message):
                    FailedView(viewModel: viewModel, errorMessage: message)
                }
            }

            // 右上角自定义关闭按钮（安装进行中隐藏）
            if viewModel.step != .installing {
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("退出")
                .padding(14)
            }
        }
        .frame(width: 480, height: 640)
    }
}

// MARK: - 欢迎页

struct WelcomeView: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 48)

            IconBadge(
                systemName: "keyboard.fill",
                background: AnyShapeStyle(
                    LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.72)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                ),
                symbolColor: .white,
                size: 92
            )

            VStack(spacing: 6) {
                Text("语境输入法")
                    .font(.system(size: 25, weight: .bold))
                Text("版本 1.0.0")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
            }

            Text("原生 AI 输入法 · 实时翻译 · 中英混输\n安装后请在系统输入法中启用")
                .font(.system(size: 14))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            VStack(spacing: 10) {
                Button(action: { viewModel.startInstall() }) {
                    Text(viewModel.isUpgrade ? "升级" : "安装")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .controlSize(.large)

                Text("点击后将输入管理员密码以完成系统级安装")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 44)
        .frame(width: 480, height: 640)
    }
}

// MARK: - 安装中页

struct InstallingView: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .controlSize(.large)

            Text(viewModel.statusText)
                .font(.system(size: 15, weight: .medium))

            Text("请勿关闭窗口，安装过程中需要输入管理员密码")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(width: 480, height: 640)
    }
}

// MARK: - 完成页

struct FinishedView: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 48)

            IconBadge(
                systemName: "checkmark.circle.fill",
                background: AnyShapeStyle(Color.clear),
                symbolColor: Theme.success,
                size: 92
            )

            Text("安装成功")
                .font(.system(size: 23, weight: .bold))

            VStack(spacing: 6) {
                Text("语境输入法已安装到系统")
                    .font(.system(size: 14))
                Text("请在「系统设置 › 键盘 › 输入法」中添加「语境输入法」")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: { viewModel.openInputSourcesSettings() }) {
                    Text("打开系统设置添加输入法")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .controlSize(.large)

                Button(action: { NSApp.terminate(nil) }) {
                    Text("完成")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 44)
        .frame(width: 480, height: 640)
    }
}

// MARK: - 失败页

struct FailedView: View {
    @ObservedObject var viewModel: InstallerViewModel
    let errorMessage: String

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 48)

            IconBadge(
                systemName: "exclamationmark.triangle.fill",
                background: AnyShapeStyle(Color.clear),
                symbolColor: Theme.danger,
                size: 92
            )

            Text("安装失败")
                .font(.system(size: 23, weight: .bold))

            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineLimit(6)

            Spacer()

            VStack(spacing: 12) {
                Button(action: { viewModel.startInstall() }) {
                    Text("重试")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .controlSize(.large)

                Button(action: { NSApp.terminate(nil) }) {
                    Text("退出")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 44)
        .frame(width: 480, height: 640)
    }
}

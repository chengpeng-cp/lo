import SwiftUI
import AppKit

// MARK: - 格式化

enum Format {
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        value <= 0 ? "—" : bytesFormatter.string(fromByteCount: value)
    }
}

// MARK: - 主容器

struct ContentView: View {
    @StateObject private var viewModel = UninstallerViewModel()
    @State private var showConfirm = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.gradientBackground().ignoresSafeArea()

            Group {
                switch viewModel.phase {
                case .scanning:
                    ScanningView(statusText: viewModel.statusText)
                case .ready:
                    ReadyView(viewModel: viewModel, showConfirm: $showConfirm)
                case .empty:
                    EmptyView(viewModel: viewModel)
                case .uninstalling:
                    UninstallingView(statusText: viewModel.statusText)
                case .finished:
                    FinishedView(viewModel: viewModel)
                case .failed(let message):
                    FailedView(viewModel: viewModel, errorMessage: message)
                }
            }

            if viewModel.phase != .uninstalling && viewModel.phase != .scanning {
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
        .frame(width: 480, height: 700)
        .onAppear { viewModel.scan() }
        .alert("确认彻底卸载语境输入法？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) { viewModel.uninstall() }
        } message: {
            Text("将清理 \(viewModel.items.count) 项残留\(viewModel.purgeRime ? "，并删除 Rime 词库与用户词典" : "")。\n本地设置与 API Key 一并删除，操作无法撤销。")
        }
    }
}

// MARK: - 扫描中

struct ScanningView: View {
    let statusText: String

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ProgressView().scaleEffect(1.4).controlSize(.large)
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
            Spacer()
        }
        .frame(width: 480, height: 700)
    }
}

// MARK: - 待清理预览

struct ReadyView: View {
    @ObservedObject var viewModel: UninstallerViewModel
    @Binding var showConfirm: Bool

    var body: some View {
        VStack(spacing: 14) {
            header
            summaryBar
            if let notice = viewModel.notice {
                Text(notice)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            itemList
            options
            actions
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 480, height: 700)
    }

    private var header: some View {
        VStack(spacing: 6) {
            IconBadge(
                systemName: "trash.fill",
                background: AnyShapeStyle(
                    LinearGradient(colors: [Theme.danger, Theme.danger.opacity(0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                ),
                symbolColor: .white,
                size: 56
            )
            Text("语境输入法卸载工具")
                .font(.system(size: 19, weight: .bold))
            Text("清理应用本体、输入源注册、词库缓存与 API Key")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.secondaryText)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.warning)
            Text("发现 \(viewModel.items.count) 项残留")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("共 \(Format.bytes(viewModel.totalBytes))")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.66))
        )
    }

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(viewModel.groupedItems, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: Theme.icon(for: group.group))
                                .font(.system(size: 10, weight: .semibold))
                            Text(group.group)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("\(group.items.count)")
                                .font(.system(size: 9.5, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.06)))
                        }
                        .foregroundColor(Theme.secondaryText)

                        ForEach(group.items) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
    }

    private func itemRow(_ item: CleanItem) -> some View {
        HStack(spacing: 6) {
            Text(item.displayPath)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if item.kind == .service {
                Text("注册项")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
            } else {
                Text(Format.bytes(item.bytes))
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .padding(.leading, 2)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 7) {
            CompactToggle(
                title: "同时清空 Rime 词库与用户词典",
                subtitle: "~/Library/Rime：训练词频、部署缓存，旧缓存会干扰新版本",
                isOn: $viewModel.purgeRime
            )

            CompactToggle(
                title: "卸载前把词库与设置备份到桌面",
                isOn: $viewModel.backupBeforeUninstall,
                disabled: !viewModel.purgeRime
            )

            Text("卸载会删除本地设置与 API Key，无法撤销。检测到鼠须管等共用 Rime 数据时，只清理本输入法自己的文件。")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: { showConfirm = true }) {
                Text("彻底卸载")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.danger, pressedColor: Theme.dangerPressed))
            .disabled(viewModel.items.isEmpty)

            Button(action: { viewModel.scan() }) {
                Text("重新扫描")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 无残留

struct EmptyView: View {
    @ObservedObject var viewModel: UninstallerViewModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            IconBadge(
                systemName: "checkmark.seal.fill",
                background: AnyShapeStyle(Color.clear),
                symbolColor: Theme.success,
                size: 88
            )
            Text("未发现语境输入法残留")
                .font(.system(size: 21, weight: .bold))
            Text("系统里没有安装记录、输入源注册或词库缓存。\n可以直接安装新版本进行测试。")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
            VStack(spacing: 10) {
                Button(action: { viewModel.scan() }) {
                    Text("重新扫描")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                Button(action: { viewModel.openInputSourcesSettings() }) {
                    Text("打开键盘设置检查")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 40)
        .frame(width: 480, height: 700)
    }
}

// MARK: - 清理中

struct UninstallingView: View {
    let statusText: String

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ProgressView().scaleEffect(1.4).controlSize(.large)
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Text("请勿关闭窗口，系统级清理需要管理员授权")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.secondaryText)
            Spacer()
        }
        .frame(width: 480, height: 700)
    }
}

// MARK: - 完成

struct FinishedView: View {
    @ObservedObject var viewModel: UninstallerViewModel

    private var remainingCount: Int { viewModel.summary?.remaining.count ?? 0 }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 36)

            IconBadge(
                systemName: remainingCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                background: AnyShapeStyle(Color.clear),
                symbolColor: remainingCount == 0 ? Theme.success : Theme.warning,
                size: 82
            )

            Text(remainingCount == 0 ? "卸载完成" : "已清理，仍有残留")
                .font(.system(size: 22, weight: .bold))

            if let summary = viewModel.summary {
                Text("已清理 \(summary.removedCount) 项 · 释放 \(Format.bytes(summary.freedBytes))")
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.7)))

                if remainingCount > 0 {
                    Text("有 \(remainingCount) 项需要更高权限或重启后清理，可重新扫描查看。")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.warning)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                }

                if let warning = summary.warnings.first {
                    Text(warning)
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .lineLimit(3)
                }
            }

            if remainingCount == 0 {
                VStack(alignment: .leading, spacing: 5) {
                    checklistRow("程序副本与 LaunchServices 记录")
                    checklistRow("输入源启用列表与辅助功能授权")
                    if viewModel.purgeRime {
                        checklistRow("Rime 词库、用户词典与部署缓存")
                    }
                    checklistRow("偏好设置与 Keychain 中的 API Key")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 330, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
            }

            Text("建议注销并重新登录后再安装新版本，确保系统输入法列表完全刷新。")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 340)

            Spacer()

            VStack(spacing: 10) {
                Button(action: { viewModel.retry() }) {
                    Text("重新扫描验证")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))

                Button(action: { NSApp.terminate(nil) }) {
                    Text("完成")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 36)
        .frame(width: 480, height: 700)
    }

    private func checklistRow(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.success)
                .frame(width: 10)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - 失败

struct FailedView: View {
    @ObservedObject var viewModel: UninstallerViewModel
    let errorMessage: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            IconBadge(
                systemName: "exclamationmark.triangle.fill",
                background: AnyShapeStyle(Color.clear),
                symbolColor: Theme.danger,
                size: 88
            )
            Text("清理未完成")
                .font(.system(size: 22, weight: .bold))
            Text(errorMessage)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 340)
            Spacer()
            VStack(spacing: 10) {
                Button(action: { viewModel.retry() }) {
                    Text("重新扫描并重试")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                Button(action: { NSApp.terminate(nil) }) {
                    Text("退出")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 36)
        .frame(width: 480, height: 700)
    }
}

// MARK: - 紧凑开关

/// 用纯 SwiftUI 绘制的开关，避免系统 NSSwitch 在小尺寸下的对齐与主题差异。
struct CompactToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Button(action: { if !disabled { isOn.toggle() } }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Theme.accent : Color.black.opacity(0.16))
                        .frame(width: 34, height: 20)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .shadow(color: Color.black.opacity(0.15), radius: 1, y: 0.5)
                }
                .animation(.easeOut(duration: 0.16), value: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

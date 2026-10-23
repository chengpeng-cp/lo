import AppKit
import LOMTCore

// MARK: - 本地模型行

/// 设置页「本地模型」区域中的一行：名称 + 状态 + 操作按钮。
final class MTModelRowView: NSView {

    enum State {
        case notInstalled
        case downloading(done: Int64, total: Int64)
        case verifying
        case installed(bytes: Int64)
        case failed(String)
    }

    let manifest: MTModelManifest

    var onDownload: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?

    private let titleLabel: NSTextField
    private let statusLabel: NSTextField
    private let actionButton: NSButton
    private var state: State = .notInstalled

    init(manifest: MTModelManifest) {
        self.manifest = manifest
        titleLabel = NSTextField.loLabel(manifest.displayName,
                                         font: LODesign.Font.row,
                                         color: LODesign.Color.textPrimary)
        statusLabel = NSTextField.loLabel("", font: LODesign.Font.caption,
                                          color: LODesign.Color.textSecondary)
        actionButton = NSButton()
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: LODesign.Metric.labelWidth).isActive = true

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.font = NSFont.systemFont(ofSize: 11)
        actionButton.target = self
        actionButton.action = #selector(performAction)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let row = NSStackView(views: [titleLabel, statusLabel, actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: LODesign.Metric.rowHeight + 4)
        ])

        apply(.notInstalled)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    func apply(_ state: State) {
        self.state = state
        switch state {
        case .notInstalled:
            statusLabel.stringValue = "未安装 · \(Self.size(manifest.bytes))"
            statusLabel.textColor = LODesign.Color.textSecondary
            configure(title: "下载", enabled: true)

        case .downloading(let done, let total):
            let percent = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
            statusLabel.stringValue = "下载中 \(percent)% · \(Self.size(done)) / \(Self.size(total))"
            statusLabel.textColor = LODesign.Color.textSecondary
            configure(title: "取消", enabled: true)

        case .verifying:
            statusLabel.stringValue = "正在校验文件完整性…"
            statusLabel.textColor = LODesign.Color.textSecondary
            configure(title: "取消", enabled: true)

        case .installed(let bytes):
            statusLabel.stringValue = "已安装 · \(Self.size(bytes))"
            statusLabel.textColor = LODesign.Color.textSecondary
            configure(title: "删除", enabled: true)

        case .failed(let message):
            statusLabel.stringValue = message
            statusLabel.textColor = .systemRed
            configure(title: "重试", enabled: true)
        }
    }

    private func configure(title: String, enabled: Bool) {
        actionButton.title = title
        actionButton.isEnabled = enabled
    }

    @objc private func performAction() {
        switch state {
        case .notInstalled, .failed:
            onDownload?()
        case .downloading, .verifying:
            onCancel?()
        case .installed:
            onDelete?()
        }
    }

    private static func size(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1000 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

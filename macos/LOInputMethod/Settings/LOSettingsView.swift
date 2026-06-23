import AppKit

// MARK: - 通知

extension Notification.Name {
    /// 设置变更通知（保存设置后发出，输入法控制器据此更新悬浮窗配置）
    static let LOSettingsDidChange = Notification.Name("LOSettingsDidChange")
}

// MARK: - 设置页面视图

/// 语镜设置页面视图（精简版，只保留用户需要关心的设置项）
class LOSettingsView: NSView {

    // MARK: - 控件引用

    /// 翻译服务下拉框
    private var providerPopup: NSPopUpButton!

    /// 模型输入框（大模型提供商使用，用户手动输入模型名称）
    private var modelField: NSTextField!

    /// 模型行（含标签+输入框），免费方案时隐藏
    private var modelRow: NSView!

    /// 自定义 API 端点输入框（仅 custom 提供商显示）
    private var customBaseURLField: NSTextField!

    /// 自定义端点行
    private var customBaseURLRow: NSView!

    /// API 密钥输入框（使用普通 NSTextField，支持粘贴）
    private var apiKeyField: NSTextField!

    /// 验证按钮
    private var verifyButton: NSButton!

    /// API 密钥行（含标签+输入框+验证按钮），免费方案时隐藏
    private var apiKeyRow: NSView!

    /// 免费方案提示行（选择免费翻译时显示）
    private var freeHintRow: NSView!

    /// 未配置 API Key 的兜底提示行（LLM 提供商无 key 时显示）
    private var fallbackHintRow: NSView!

    /// 翻译模式下拉框
    private var modePopup: NSPopUpButton!

    /// 固定位置单选按钮
    private var fixedRadio: NSButton!

    /// 可拖动单选按钮
    private var movableRadio: NSButton!

    /// 跟随光标单选按钮
    private var followCursorRadio: NSButton!

    /// 自动消失数值输入框
    private var dismissField: NSTextField!

    /// 自动消失步进器（上下箭头）
    private var dismissStepper: NSStepper!

    /// 透明度数值输入框
    private var opacityField: NSTextField!

    /// 透明度步进器（上下箭头）
    private var opacityStepper: NSStepper!

    /// 段落断句时间数值输入框
    private var segmentPauseField: NSTextField!

    /// 段落断句时间步进器（上下箭头）
    private var segmentPauseStepper: NSStepper!

    /// 翻译防抖时间数值输入框
    private var debounceField: NSTextField!

    /// 翻译防抖时间步进器（上下箭头）
    private var debounceStepper: NSStepper!

    /// 当前设置
    private var settings = LOSettings.load()

    // MARK: - 布局常量

    private let margin: CGFloat = 20
    private let labelWidth: CGFloat = 90
    private let rowHeight: CGFloat = 24
    private let sectionSpacing: CGFloat = 16
    private let rowSpacing: CGFloat = 10

    /// 保存按钮引用（用于保存后反馈）
    private weak var saveButtonRef: NSButton?

    /// 数值行的配置：直接输入或点击上下箭头调整时，统一通过此结构同步 settings 与显示
    /// 使用 class（引用类型）以便在事件回调里更新 lastRawValue，无需重建字典条目
    private class NumberRowConfig {
        weak var field: NSTextField?
        weak var stepper: NSStepper?
        let minValue: Double
        let maxValue: Double
        /// 步进器每次增减的原始值（用于把累加结果四舍五入到步长倍数，消除浮点漂移）
        let step: Double
        /// 显示值 / settings 值的倍数（如透明度显示 85，settings 存 0.85，则 multiplier = 100）
        let multiplier: Double
        /// 值格式化串，如 "%.1f 秒" / "%.0f%%"
        let format: String
        /// 单位文本（与 format 末尾保持一致，独立显示在输入框后），如 "秒" / "%"
        let unit: String
        /// 数值改变时的回调，参数为换算后的 settings 原始值
        let onChange: (Double) -> Void

        /// 最近一次同步到 field/stepper 的原始值。
        /// 用于点击箭头时判断方向（上/下），避免 stepper 自身累加状态与 field 未提交编辑不一致。
        var lastRawValue: Double = 0

        init(field: NSTextField?,
             stepper: NSStepper?,
             minValue: Double,
             maxValue: Double,
             step: Double,
             multiplier: Double,
             format: String,
             unit: String,
             onChange: @escaping (Double) -> Void) {
            self.field = field
            self.stepper = stepper
            self.minValue = minValue
            self.maxValue = maxValue
            self.step = step
            self.multiplier = multiplier
            self.format = format
            self.unit = unit
            self.onChange = onChange
        }

        /// 把原始 settings 值格式化为输入框显示文本（不含 unit，unit 由独立标签展示）
        func displayString(forRawValue raw: Double) -> String {
            // format 形如 "%.1f 秒"，单位由独立 unit 标签展示，这里只取数值部分
            let valueString = String(format: format, raw * multiplier)
            return Self.stripTrailingUnit(from: valueString)
        }

        /// 从 "5.0 秒" 这类带单位的显示文本中剥离尾部单位，只保留数值部分
        private static func stripTrailingUnit(from string: String) -> String {
            var end = string.startIndex
            var seenDigit = false
            for i in string.indices {
                let c = string[i]
                if c.isNumber || c == "." || c == "-" {
                    end = string.index(after: i)
                    seenDigit = true
                } else if c == " " && !seenDigit {
                    // 前导空格跳过
                    continue
                } else {
                    break
                }
            }
            return String(string[..<end]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// 数值输入框与对应行配置的映射，便于直接输入或点击步进器时同步
    private var numberRowConfigs: [NSTextField: NumberRowConfig] = [:]

    /// 主垂直栈
    private let mainStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: - 键盘快捷键

    /// 输入法进程为 LSUIElement 后台 app，无主菜单 Edit 菜单，
    /// 导致 NSTextField 的 Cmd+A/C/V/X/Z 等标准编辑快捷键失效。
    /// 此处拦截 key equivalent，手动转发给当前聚焦的 field editor。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 仅处理 Cmd 组合键
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // 获取当前聚焦的 field editor
        guard let window = self.window,
              let fieldEditor = window.firstResponder as? NSTextView else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector?
        switch event.charactersIgnoringModifiers {
        case "a": action = NSSelectorFromString("selectAll:")
        case "c": action = NSSelectorFromString("copy:")
        case "v": action = NSSelectorFromString("paste:")
        case "x": action = NSSelectorFromString("cut:")
        default:  action = nil
        }

        guard let action = action else {
            return super.performKeyEquivalent(with: event)
        }

        // 尝试让 field editor 执行对应命令
        if fieldEditor.responds(to: action) {
            fieldEditor.perform(action, with: nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - 刷新设置

    func reloadSettings() {
        settings = LOSettings.load()
        updateControlsFromSettings()
    }

    // MARK: - UI 构建

    private func setupUI() {
        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
        ])
        translatesAutoresizingMaskIntoConstraints = false

        // === 翻译服务 ===
        mainStack.addArrangedSubview(makeSectionHeader("翻译服务"))
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeProviderRow())
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeModelRow())
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeCustomBaseURLRow())
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeAPIKeyRow())
        mainStack.addArrangedSubview(makeFreeHintRow())
        mainStack.addArrangedSubview(makeFallbackHintRow())

        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSeparator())

        // === 翻译模式 ===
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSectionHeader("翻译风格"))
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeModeRow())

        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSeparator())

        // === 翻译触发 ===
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSectionHeader("翻译触发"))
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeNumberRow(
            label: "段落断句：",
            field: &segmentPauseField,
            stepper: &segmentPauseStepper,
            minValue: 0.1, maxValue: 999999,
            step: 0.1,
            format: "%.1f 秒",
            unit: "秒",
            action: #selector(segmentPauseChanged),
            valueMultiplier: 1
        ))
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeNumberRow(
            label: "翻译防抖：",
            field: &debounceField,
            stepper: &debounceStepper,
            minValue: 0.1, maxValue: 999999,
            step: 0.1,
            format: "%.1f 秒",
            unit: "秒",
            action: #selector(debounceChanged),
            valueMultiplier: 1
        ))

        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSeparator())

        // === 悬浮窗设置 ===
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSectionHeader("翻译悬浮窗"))
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makePositionModeRow())
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeNumberRow(
            label: "自动消失：",
            field: &dismissField,
            stepper: &dismissStepper,
            minValue: 1, maxValue: 9999,
            step: 0.1,
            format: "%.1f 秒",
            unit: "秒",
            action: #selector(dismissChanged),
            valueMultiplier: 1
        ))
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeNumberRow(
            label: "透明度：",
            field: &opacityField,
            stepper: &opacityStepper,
            minValue: 0.1, maxValue: 1.0,
            step: 0.01,
            format: "%.0f%%",
            unit: "%",
            action: #selector(opacityChanged),
            valueMultiplier: 100
        ))

        // === 底部按钮 ===
        mainStack.addArrangedSubview(spacer(sectionSpacing + 4))
        mainStack.addArrangedSubview(makeBottomButtons())

        updateControlsFromSettings()
    }

    // MARK: - UI 辅助

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 20),
        ])
        return container
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func makeRow(label text: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)

        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        control.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6).isActive = true
        return row
    }

    private func makeProviderRow() -> NSView {
        providerPopup = NSPopUpButton()
        providerPopup.addItems(withTitles: TranslationProvider.allCases.map { $0.displayName })
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        return makeRow(label: "服务提供商：", control: providerPopup)
    }

    /// 构建模型输入行：标签 + 输入框（用户手动输入模型名称）
    private func makeModelRow() -> NSView {
        modelField = NSTextField()
        modelField.placeholderString = "模型名称"
        modelField.drawsBackground = true
        modelField.backgroundColor = NSColor.textBackgroundColor
        modelField.isBezeled = true
        modelField.bezelStyle = .roundedBezel
        modelField.target = self
        modelField.action = #selector(modelFieldChanged)
        modelField.translatesAutoresizingMaskIntoConstraints = false
        modelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        modelField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        let row = makeRow(label: "模型：", control: modelField)
        modelRow = row
        return row
    }

    /// 构建自定义 API 端点输入行（仅 custom 提供商显示）
    private func makeCustomBaseURLRow() -> NSView {
        customBaseURLField = NSTextField()
        customBaseURLField.placeholderString = "https://your-api-endpoint/v1/chat/completions"
        customBaseURLField.drawsBackground = true
        customBaseURLField.backgroundColor = NSColor.textBackgroundColor
        customBaseURLField.isBezeled = true
        customBaseURLField.bezelStyle = .roundedBezel
        customBaseURLField.translatesAutoresizingMaskIntoConstraints = false
        customBaseURLField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        customBaseURLField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        let row = makeRow(label: "API 端点：", control: customBaseURLField)
        customBaseURLRow = row
        return row
    }

    private func makeAPIKeyRow() -> NSView {
        // 使用普通 NSTextField 而非 NSSecureTextField，确保可以粘贴
        // （NSSecureTextField 在输入法进程的菜单/窗口中可能拦截 Cmd+V）
        apiKeyField = NSTextField()
        apiKeyField.placeholderString = "输入 API Key（可粘贴）"
        apiKeyField.drawsBackground = true
        apiKeyField.backgroundColor = NSColor.textBackgroundColor
        apiKeyField.isBezeled = true
        apiKeyField.bezelStyle = .roundedBezel

        verifyButton = NSButton()
        verifyButton.title = "验证"
        verifyButton.bezelStyle = .rounded
        verifyButton.target = self
        verifyButton.action = #selector(verifyAPIKey)
        verifyButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "API 密钥：")
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        apiKeyField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        verifyButton.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(apiKeyField)
        row.addArrangedSubview(verifyButton)
        apiKeyRow = row
        return row
    }

    /// 构建免费方案提示行（选择免费翻译引擎时显示）
    private func makeFreeHintRow() -> NSView {
        let label = NSTextField(labelWithString: "免费翻译，无需 API Key")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor

        let prefixLabel = NSTextField(labelWithString: "提示：")
        prefixLabel.alignment = .right
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        prefixLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        row.addArrangedSubview(prefixLabel)
        row.addArrangedSubview(label)

        freeHintRow = row
        return row
    }

    /// 构建兜底提示行（LLM 提供商未配置 API Key 时显示）
    private func makeFallbackHintRow() -> NSView {
        let label = NSTextField(labelWithString: "未配置 API Key，将自动使用必应免费翻译兜底")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.systemOrange

        let prefixLabel = NSTextField(labelWithString: "提示：")
        prefixLabel.alignment = .right
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        prefixLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        row.addArrangedSubview(prefixLabel)
        row.addArrangedSubview(label)

        fallbackHintRow = row
        return row
    }

    private func makeModeRow() -> NSView {
        modePopup = NSPopUpButton()
        modePopup.addItems(withTitles: TranslationMode.allCases.map { $0.displayName })
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        return makeRow(label: "翻译风格：", control: modePopup)
    }

    private func makePositionModeRow() -> NSView {
        fixedRadio = NSButton(radioButtonWithTitle: "固定位置", target: self, action: #selector(positionModeChanged))
        movableRadio = NSButton(radioButtonWithTitle: "可自由拖动", target: self, action: #selector(positionModeChanged))
        followCursorRadio = NSButton(radioButtonWithTitle: "跟随光标", target: self, action: #selector(positionModeChanged))

        let label = NSTextField(labelWithString: "位置模式：")
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let radios = NSStackView()
        radios.orientation = .horizontal
        radios.spacing = 16
        radios.addArrangedSubview(fixedRadio)
        radios.addArrangedSubview(movableRadio)
        radios.addArrangedSubview(followCursorRadio)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.addArrangedSubview(label)
        row.addArrangedSubview(radios)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// 构建数值调整行：label | 数值输入框 | 上下箭头(stepper) | 单位
    /// 不再使用长滑块，仅保留可输入的数值框 + 步进器 + 单位文本。
    private func makeNumberRow(
        label text: String,
        field: inout NSTextField!,
        stepper: inout NSStepper!,
        minValue: Double,
        maxValue: Double,
        step: Double,
        format: String,
        unit: String,
        action: Selector,
        valueMultiplier: Double = 1.0
    ) -> NSView {
        // 数值输入框（可手动输入）
        field = NSTextField()
        field.alignment = .right
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(numberFieldChanged(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.widthAnchor.constraint(equalToConstant: 55).isActive = true

        // 上下箭头步进器
        stepper = NSStepper()
        stepper.minValue = minValue
        stepper.maxValue = maxValue
        stepper.increment = step
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(numberStepperChanged(_:))
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.setContentHuggingPriority(.required, for: .horizontal)
        stepper.widthAnchor.constraint(equalToConstant: 19).isActive = true
        stepper.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        // 单位标签（输入框后）
        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.alignment = .left
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)
        unitLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 记录输入框对应的行配置，便于直接输入或点击步进器时同步
        let onChange: (Double) -> Void
        switch action {
        case #selector(dismissChanged):
            onChange = { [weak self] v in self?.settings.autoDismissInterval = v }
        case #selector(opacityChanged):
            onChange = { [weak self] v in self?.settings.overlayOpacity = v }
        case #selector(segmentPauseChanged):
            onChange = { [weak self] v in self?.settings.segmentPauseThreshold = v }
        case #selector(debounceChanged):
            onChange = { [weak self] v in self?.settings.translationDebounceInterval = v }
        default:
            onChange = { _ in }
        }
        numberRowConfigs[field] = NumberRowConfig(
            field: field,
            stepper: stepper,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            multiplier: valueMultiplier,
            format: format,
            unit: unit,
            onChange: onChange
        )

        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(stepper)
        row.addArrangedSubview(unitLabel)

        field.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        return row
    }

    private func makeBottomButtons() -> NSView {
        let saveButton = NSButton()
        saveButton.title = "保存"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        saveButtonRef = saveButton

        let resetButton = NSButton()
        resetButton.title = "恢复默认"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetSettings)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        let filler = NSView()
        filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(filler)
        row.addArrangedSubview(resetButton)
        row.addArrangedSubview(saveButton)
        return row
    }

    // MARK: - 控件值同步

    private func updateControlsFromSettings() {
        // 翻译服务
        let provider = TranslationProvider.from(settings.translationProvider)
        let providerIndex = TranslationProvider.allCases.firstIndex(of: provider) ?? 0
        providerPopup.selectItem(at: providerIndex)

        // 模型：直接使用用户保存的模型名，不再自动填充默认模型
        modelField.stringValue = settings.translationModel

        // 自定义端点
        customBaseURLField.stringValue = settings.customLLMBaseURL

        // API 密钥
        let currentProvider = settings.translationProvider
        apiKeyField.stringValue = settings.getAPIKey(provider: currentProvider) ?? ""

        // 根据提供商切换各行的显示
        updateProviderRowVisibility()

        // 翻译模式
        let modeIndex = TranslationMode.allCases.firstIndex(where: { $0.rawValue == settings.translationMode }) ?? 0
        modePopup.selectItem(at: modeIndex)

        // 位置模式
        let mode = settings.overlayPositionMode
        fixedRadio.state = (mode == "fixed") ? .on : .off
        movableRadio.state = (mode == "draggable") ? .on : .off
        followCursorRadio.state = (mode == "followCursor") ? .on : .off

        // 自动消失
        applyRawValue(settings.autoDismissInterval, to: dismissField, stepper: dismissStepper)

        // 透明度
        applyRawValue(settings.overlayOpacity, to: opacityField, stepper: opacityStepper)

        // 段落断句时间
        applyRawValue(settings.segmentPauseThreshold, to: segmentPauseField, stepper: segmentPauseStepper)

        // 翻译防抖时间
        applyRawValue(settings.translationDebounceInterval, to: debounceField, stepper: debounceStepper)
    }

    /// 把原始 settings 值同步到对应输入框（用 format 格式化显示）与 stepper
    private func applyRawValue(_ raw: Double, to field: NSTextField?, stepper: NSStepper?) {
        guard let field = field, let config = numberRowConfigs[field] else { return }
        field.stringValue = config.displayString(forRawValue: raw)
        stepper?.doubleValue = raw
        config.lastRawValue = raw
    }

    // MARK: - 控件事件

    @objc private func providerChanged() {
        let index = providerPopup.indexOfSelectedItem
        let provider = TranslationProvider.allCases[index]
        settings.translationProvider = provider.rawValue

        // 切换提供商时，加载该提供商上次保存的模型名（无则留空）
        let savedModel = LOSettings.loadModel(forProvider: provider.rawValue)
        settings.translationModel = savedModel
        modelField.stringValue = savedModel

        apiKeyField.stringValue = settings.getAPIKey(provider: settings.translationProvider) ?? ""
        updateProviderRowVisibility()
    }

    /// 模型输入框内容变化
    @objc private func modelFieldChanged() {
        settings.translationModel = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 根据当前翻译提供商切换模型行、自定义端点行、API Key 行与提示行的显示
    private func updateProviderRowVisibility() {
        let provider = TranslationProvider.from(settings.translationProvider)
        let isFree = provider.isFree
        let isCustom = provider == .custom

        // 模型行：仅 LLM 提供商显示
        modelRow.isHidden = isFree

        // 自定义端点行：仅 custom 提供商显示
        customBaseURLRow.isHidden = !isCustom

        // API Key 行：仅需要 API Key 的提供商显示
        apiKeyRow.isHidden = isFree

        // 免费提示行：仅免费翻译引擎显示
        freeHintRow.isHidden = !isFree

        // 兜底提示行：LLM 提供商且未配置 API Key 时显示
        if !isFree {
            let apiKey = settings.getAPIKey(provider: provider.rawValue) ?? ""
            fallbackHintRow.isHidden = !apiKey.isEmpty
        } else {
            fallbackHintRow.isHidden = true
        }
    }

    @objc private func modeChanged() {
        let idx = modePopup.indexOfSelectedItem
        settings.translationMode = TranslationMode.allCases[idx].rawValue
    }

    @objc private func verifyAPIKey() {
        // 先提交所有输入框的未保存编辑，确保验证使用的是用户当前输入的内容
        commitPendingEdits()

        let provider = TranslationProvider.from(settings.translationProvider)

        // 免费翻译引擎，直接测试连接
        if provider.isFree {
            verifyButton.isEnabled = false
            verifyButton.title = "测试中..."

            let mode = TranslationMode(rawValue: settings.translationMode) ?? .fluent
            let translator: TranslationServiceProtocol = BingTranslator()

            Task { [weak self] in
                do {
                    _ = try await translator.translate(text: "你好世界", mode: mode)
                    DispatchQueue.main.async {
                        self?.verifyButton.isEnabled = true
                        self?.verifyButton.title = "验证"
                        self?.showAlert(title: "连接成功", message: "\(provider.displayName) 接口可用")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.verifyButton.isEnabled = true
                        self?.verifyButton.title = "验证"
                        self?.showAlert(title: "连接失败", message: error.localizedDescription)
                    }
                }
            }
            return
        }

        // 大模型翻译：需要 API Key
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            showAlert(title: "验证失败", message: "请先输入 API 密钥")
            return
        }

        // 模型名称（直接从输入框读取，无需先保存）
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            showAlert(title: "验证失败", message: "请先输入模型名称")
            return
        }

        // 自定义提供商需要填写端点
        if provider == .custom {
            let baseURL = customBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseURL.isEmpty else {
                showAlert(title: "验证失败", message: "请先填写 API 端点")
                return
            }
            settings.customLLMBaseURL = baseURL
        }

        // 临时保存 API Key 以便验证（LLMTranslator 从 Keychain 读取）
        settings.setAPIKey(provider: provider.rawValue, key: apiKey)

        verifyButton.isEnabled = false
        verifyButton.title = "验证中..."

        let mode = TranslationMode(rawValue: settings.translationMode) ?? .fluent
        let translator = LLMTranslator(provider: provider, model: model)

        Task { [weak self] in
            do {
                _ = try await translator.translate(text: "你好世界", mode: mode)
                DispatchQueue.main.async {
                    self?.verifyButton.isEnabled = true
                    self?.verifyButton.title = "验证"
                    self?.showAlert(title: "验证成功", message: "API 密钥有效，模型 \(model) 可用")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.verifyButton.isEnabled = true
                    self?.verifyButton.title = "验证"
                    self?.showAlert(title: "验证失败", message: error.localizedDescription)
                }
            }
        }
    }

    /// 提交所有输入框中未保存的编辑（field editor 持有的文本）
    private func commitPendingEdits() {
        if let editor = apiKeyField.currentEditor() {
            apiKeyField.stringValue = editor.string
        }
        if let editor = modelField.currentEditor() {
            modelField.stringValue = editor.string
        }
        if let editor = customBaseURLField.currentEditor() {
            customBaseURLField.stringValue = editor.string
        }
        // 同步到 settings 内存对象
        settings.translationModel = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.customLLMBaseURL = customBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func positionModeChanged() {
        if fixedRadio.state == .on {
            settings.overlayPositionMode = "fixed"
        } else if followCursorRadio.state == .on {
            settings.overlayPositionMode = "followCursor"
        } else {
            settings.overlayPositionMode = "draggable"
        }
    }

    @objc private func dismissChanged() {
        // 实际同步逻辑在 numberFieldChanged / numberStepperChanged 中统一处理
        // 这里仅作为配置中的 action 标识（已通过 NumberRowConfig.onChange 回调写回）
    }

    @objc private func opacityChanged() {
        // 同上
    }

    @objc private func segmentPauseChanged() {
        // 同上
    }

    @objc private func debounceChanged() {
        // 同上
    }

    /// 数值输入框直接编辑后，按行配置 clamp、四舍五入到步长倍数，并同步 stepper 与 settings
    @objc private func numberFieldChanged(_ sender: NSTextField) {
        guard let config = numberRowConfigs[sender] else { return }
        var raw = sender.doubleValue / config.multiplier
        raw = snapToStep(raw, step: config.step)
        raw = clampRawValue(raw, minValue: config.minValue, maxValue: config.maxValue)
        // 用 format 重新格式化显示，消除浮点精度导致的多位小数
        sender.stringValue = config.displayString(forRawValue: raw)
        config.stepper?.doubleValue = raw
        config.lastRawValue = raw
        config.onChange(raw)
    }

    /// 点击上下箭头后，把步进器的新值四舍五入到步长倍数，再同步到输入框与 settings
    /// 关键：用户可能手动改了输入框但未按回车（field editor 持有未提交文本），
    /// 此时 stepper 的内部累加状态与 field 显示值不一致。这里以 field 当前显示值
    /// （先提交 field editor）为起点，按 stepper 的方向（新值 vs 上次值）决定增减。
    @objc private func numberStepperChanged(_ sender: NSStepper) {
        guard let config = numberRowConfigs.values.first(where: { $0.stepper === sender }),
              let field = config.field else { return }

        // 1. 若 field 正在编辑，先把 field editor 的未提交文本写回 field.stringValue
        if let editor = field.currentEditor() {
            field.stringValue = editor.string
        }

        // 2. 以 field 当前显示值作为调整起点（覆盖 stepper 自身的累加状态）
        var raw = field.doubleValue / config.multiplier

        // 3. 根据 stepper 新值与上次同步值的差，判断方向，从 field 当前值起增/减一个步长
        let stepperDelta = sender.doubleValue - config.lastRawValue
        if stepperDelta > 0 {
            raw = raw + config.step
        } else if stepperDelta < 0 {
            raw = raw - config.step
        }

        // 4. 四舍五入到步长倍数 + clamp
        raw = snapToStep(raw, step: config.step)
        raw = clampRawValue(raw, minValue: config.minValue, maxValue: config.maxValue)

        // 5. 同步 field / stepper / settings
        sender.doubleValue = raw
        field.stringValue = config.displayString(forRawValue: raw)
        config.lastRawValue = raw
        config.onChange(raw)
    }

    /// 将原始 settings 值限制在 [min, max] 区间
    private func clampRawValue(_ value: Double, minValue: Double, maxValue: Double) -> Double {
        return min(max(value, minValue), maxValue)
    }

    /// 把值四舍五入到最近的步长倍数，消除浮点累加漂移（如 0.1+0.1+0.1 -> 0.3）
    private func snapToStep(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    @objc private func saveSettings() {
        // 强制提交所有正在编辑的输入框，确保用户输入的最新值被保存
        commitPendingEdits()

        for (field, config) in numberRowConfigs {
            if let editor = field.currentEditor() {
                field.stringValue = editor.string
            }
            var raw = field.doubleValue / config.multiplier
            raw = snapToStep(raw, step: config.step)
            raw = clampRawValue(raw, minValue: config.minValue, maxValue: config.maxValue)
            field.stringValue = config.displayString(forRawValue: raw)
            config.stepper?.doubleValue = raw
            config.lastRawValue = raw
            config.onChange(raw)
        }

        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            settings.setAPIKey(provider: settings.translationProvider, key: apiKey)
        }
        settings.save()
        TranslationScheduler.shared.updateTranslator()
        NotificationCenter.default.post(name: .LOSettingsDidChange, object: nil)

        if let btn = saveButtonRef {
            btn.title = "已保存 ✓"
            btn.isEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak btn] in
                btn?.title = "保存"
                btn?.isEnabled = true
            }
        }
        debugLog("设置已保存")
    }

    @objc private func resetSettings() {
        settings = LOSettings()
        updateControlsFromSettings()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

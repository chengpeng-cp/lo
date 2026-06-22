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

    /// API 密钥输入框（使用普通 NSTextField，支持粘贴）
    private var apiKeyField: NSTextField!

    /// 验证按钮
    private var verifyButton: NSButton!

    /// 翻译模式下拉框
    private var modePopup: NSPopUpButton!

    /// 固定位置单选按钮
    private var fixedRadio: NSButton!

    /// 可拖动单选按钮
    private var movableRadio: NSButton!

    /// 自动消失滑块
    private var dismissSlider: NSSlider!

    /// 自动消失标签
    private var dismissLabel: NSTextField!

    /// 透明度滑块
    private var opacitySlider: NSSlider!

    /// 透明度标签
    private var opacityLabel: NSTextField!

    /// 段落断句时间滑块
    private var segmentPauseSlider: NSSlider!

    /// 段落断句时间标签
    private var segmentPauseLabel: NSTextField!

    /// 翻译防抖时间滑块
    private var debounceSlider: NSSlider!

    /// 翻译防抖时间标签
    private var debounceLabel: NSTextField!

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

    /// 滑块数值输入框与对应滑块的映射，用于直接输入数值时同步
    private var sliderTextFieldInfo: [NSTextField: (slider: NSSlider, multiplier: Double)] = [:]

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
        mainStack.addArrangedSubview(makeAPIKeyRow())

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
        mainStack.addArrangedSubview(makeSliderRow(
            label: "段落断句：",
            slider: &segmentPauseSlider,
            valueLabel: &segmentPauseLabel,
            minValue: 1, maxValue: 20,
            format: "%.1f 秒",
            action: #selector(segmentPauseSliderChanged)
        ))
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeSliderRow(
            label: "翻译防抖：",
            slider: &debounceSlider,
            valueLabel: &debounceLabel,
            minValue: 0.1, maxValue: 2.0,
            format: "%.1f 秒",
            action: #selector(debounceSliderChanged)
        ))

        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSeparator())

        // === 悬浮窗设置 ===
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makeSectionHeader("翻译悬浮窗"))
        mainStack.addArrangedSubview(spacer(sectionSpacing))
        mainStack.addArrangedSubview(makePositionModeRow())
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeSliderRow(
            label: "自动消失：",
            slider: &dismissSlider,
            valueLabel: &dismissLabel,
            minValue: 1, maxValue: 15,
            format: "%.1f 秒",
            action: #selector(dismissSliderChanged)
        ))
        mainStack.addArrangedSubview(spacer(rowSpacing))
        mainStack.addArrangedSubview(makeSliderRow(
            label: "透明度：",
            slider: &opacitySlider,
            valueLabel: &opacityLabel,
            minValue: 0.1, maxValue: 1.0,
            format: "%.0f%%",
            action: #selector(opacitySliderChanged),
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
        providerPopup.addItems(withTitles: ["DeepSeek", "Google Translate"])
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        return makeRow(label: "服务提供商：", control: providerPopup)
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

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.addArrangedSubview(label)
        row.addArrangedSubview(radios)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeSliderRow(
        label text: String,
        slider: inout NSSlider!,
        valueLabel: inout NSTextField!,
        minValue: Double,
        maxValue: Double,
        format: String,
        action: Selector,
        valueMultiplier: Double = 1.0
    ) -> NSView {
        slider = NSSlider()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.target = self
        slider.action = action
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        valueLabel = NSTextField()
        valueLabel.alignment = .right
        valueLabel.isEditable = true
        valueLabel.isSelectable = true
        valueLabel.drawsBackground = true
        valueLabel.backgroundColor = NSColor.textBackgroundColor
        valueLabel.bezelStyle = .roundedBezel
        valueLabel.target = self
        valueLabel.action = #selector(sliderTextFieldChanged(_:))
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: 55).isActive = true

        // 记录输入框与滑块的映射，便于直接输入时同步
        sliderTextFieldInfo[valueLabel] = (slider: slider, multiplier: valueMultiplier)

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
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)

        slider.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
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
        providerPopup.selectItem(at: settings.translationProvider == "google" ? 1 : 0)

        // API 密钥
        let currentProvider = settings.translationProvider
        apiKeyField.stringValue = settings.getAPIKey(provider: currentProvider) ?? ""

        // 翻译模式
        let modeIndex = TranslationMode.allCases.firstIndex(where: { $0.rawValue == settings.translationMode }) ?? 0
        modePopup.selectItem(at: modeIndex)

        // 位置模式
        fixedRadio.state = settings.overlayFixedPosition ? .on : .off
        movableRadio.state = settings.overlayFixedPosition ? .off : .on

        // 自动消失
        dismissSlider.doubleValue = settings.autoDismissInterval
        dismissLabel.stringValue = String(format: "%.1f 秒", settings.autoDismissInterval)

        // 透明度
        opacitySlider.doubleValue = settings.overlayOpacity
        opacityLabel.stringValue = String(format: "%.0f%%", settings.overlayOpacity * 100)

        // 段落断句时间
        segmentPauseSlider.doubleValue = settings.segmentPauseThreshold
        segmentPauseLabel.stringValue = String(format: "%.1f 秒", settings.segmentPauseThreshold)

        // 翻译防抖时间
        debounceSlider.doubleValue = settings.translationDebounceInterval
        debounceLabel.stringValue = String(format: "%.1f 秒", settings.translationDebounceInterval)
    }

    // MARK: - 控件事件

    @objc private func providerChanged() {
        let isGoogle = providerPopup.indexOfSelectedItem == 1
        settings.translationProvider = isGoogle ? "google" : "deepseek"
        apiKeyField.stringValue = settings.getAPIKey(provider: settings.translationProvider) ?? ""
    }

    @objc private func modeChanged() {
        let idx = modePopup.indexOfSelectedItem
        settings.translationMode = TranslationMode.allCases[idx].rawValue
    }

    @objc private func verifyAPIKey() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            showAlert(title: "验证失败", message: "请先输入 API 密钥")
            return
        }
        settings.setAPIKey(provider: settings.translationProvider, key: apiKey)

        verifyButton.isEnabled = false
        verifyButton.title = "验证中..."

        let provider = settings.translationProvider
        let mode = TranslationMode(rawValue: settings.translationMode) ?? .fluent
        let translator: TranslationServiceProtocol = provider == "google" ? GoogleTranslator() : DeepSeekTranslator()

        Task { [weak self] in
            do {
                _ = try await translator.translate(text: "你好世界", mode: mode)
                DispatchQueue.main.async {
                    self?.verifyButton.isEnabled = true
                    self?.verifyButton.title = "验证"
                    self?.showAlert(title: "验证成功", message: "API 密钥有效")
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

    @objc private func positionModeChanged() {
        settings.overlayFixedPosition = fixedRadio.state == .on
    }

    @objc private func dismissSliderChanged() {
        let value = dismissSlider.doubleValue
        settings.autoDismissInterval = value
        dismissLabel.stringValue = String(format: "%.1f 秒", value)
    }

    @objc private func opacitySliderChanged() {
        let value = opacitySlider.doubleValue
        settings.overlayOpacity = value
        opacityLabel.stringValue = String(format: "%.0f%%", value * 100)
    }

    @objc private func segmentPauseSliderChanged() {
        let value = segmentPauseSlider.doubleValue
        settings.segmentPauseThreshold = value
        segmentPauseLabel.stringValue = String(format: "%.1f 秒", value)
    }

    @objc private func debounceSliderChanged() {
        let value = debounceSlider.doubleValue
        settings.translationDebounceInterval = value
        debounceLabel.stringValue = String(format: "%.1f 秒", value)
    }

    /// 数值输入框直接编辑后，同步到对应滑块并触发滑块 action 以更新 settings
    @objc private func sliderTextFieldChanged(_ sender: NSTextField) {
        guard let info = sliderTextFieldInfo[sender] else { return }

        var value = sender.doubleValue / info.multiplier
        value = min(max(value, info.slider.minValue), info.slider.maxValue)
        info.slider.doubleValue = value

        // 触发滑块原有的 action，使 settings 和 label 格式化同步更新
        if let target = info.slider.target, let action = info.slider.action {
            NSApp.sendAction(action, to: target, from: info.slider)
        }
    }

    @objc private func saveSettings() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            settings.setAPIKey(provider: settings.translationProvider, key: apiKey)
        }
        settings.save()
        TranslationScheduler.shared.updateTranslator(provider: settings.translationProvider)
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

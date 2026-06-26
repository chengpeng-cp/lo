import AppKit

// MARK: - 通知

extension Notification.Name {
    /// 设置变更通知（保存设置后发出，输入法控制器据此更新悬浮窗配置）
    static let LOSettingsDidChange = Notification.Name("LOSettingsDidChange")
}

// MARK: - 设置页面视图

/// 语境设置页面视图（左侧 tab 导航 + 右侧内容区，类似系统/微信输入法设置）
class LOSettingsView: NSView {

    // MARK: - Tab 定义

    private enum SettingsTab: Int, CaseIterable {
        case translation = 0
        case overlay = 1
        case shortcuts = 2
        case about = 3

        var title: String {
            switch self {
            case .translation: return "翻译"
            case .overlay: return "悬浮窗"
            case .shortcuts: return "快捷键"
            case .about: return "关于"
            }
        }

        var iconName: String {
            switch self {
            case .translation: return "globe"
            case .overlay: return "rectangle.dashed"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }

    // MARK: - 控件引用

    /// 左侧 tab 按钮
    private var tabButtons: [NSButton] = []

    /// 右侧滚动视图
    private var contentScrollView: NSScrollView!

    /// documentView 容器（固定不变，内部子视图随 tab 切换替换）
    private var contentHostView: NSView!

    /// 当前 tab 内容视图相对于 contentHostView 的约束（切换 tab 时动态替换）
    private var currentContentConstraints: [NSLayoutConstraint] = []

    /// 各 tab 内容视图缓存
    private var tabContentViews: [SettingsTab: NSView] = [:]

    /// 翻译设置内容视图
    private var translationContentView: NSView!

    /// 关于页面内容视图
    private var aboutContentView: NSView!

    /// 悬浮窗设置内容视图
    private var overlayContentView: NSView!

    /// 快捷键说明内容视图
    private var shortcutsContentView: NSView!

    /// 当前选中的 tab
    private var currentTab: SettingsTab = .translation

    /// 翻译功能开关
    private var translationEnabledCheckbox: NSButton!

    /// 翻译相关区域的所有视图（开关关闭时统一隐藏）
    private var translationSectionViews: [NSView] = []

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

    /// 兜底提示行（LLM 提供商无 key 时显示）
    private var fallbackHintRow: NSView!

    /// 目标语言下拉框
    private var targetLanguagePopup: NSPopUpButton!

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

    /// 段落间隔数值输入框
    private var segmentPauseField: NSTextField!

    /// 段落间隔步进器（上下箭头）
    private var segmentPauseStepper: NSStepper!

    /// 翻译间隔数值输入框
    private var debounceField: NSTextField!

    /// 翻译间隔步进器（上下箭头）
    private var debounceStepper: NSStepper!

    /// 背景颜色选择器
    private var backgroundColorWell: NSColorWell!

    /// 待翻译文字颜色选择器
    private var originalTextColorWell: NSColorWell!

    /// 翻译文字颜色选择器
    private var translationTextColorWell: NSColorWell!

    /// 悬浮窗主题下拉框
    private var overlayThemePopup: NSPopUpButton!

    /// 点击穿透复选框
    private var clickThroughCheckbox: NSButton!

    /// 悬浮窗最大宽度输入框
    private var overlayMaxWidthField: NSTextField!
    private var overlayMaxWidthStepper: NSStepper!

    /// 悬浮窗最大高度输入框
    private var overlayMaxHeightField: NSTextField!
    private var overlayMaxHeightStepper: NSStepper!

    /// 原文字体大小输入框
    private var originalFontSizeField: NSTextField!
    private var originalFontSizeStepper: NSStepper!

    /// 翻译字体大小输入框
    private var translationFontSizeField: NSTextField!
    private var translationFontSizeStepper: NSStepper!

    /// 显示原文标签复选框
    private var showOriginalLabelCheckbox: NSButton!

    /// 显示翻译标签复选框
    private var showTranslationLabelCheckbox: NSButton!

    // MARK: - 当前设置

    private var settings = LOSettings.load()

    // MARK: - 布局常量

    private let sidebarWidth: CGFloat = 170
    private let margin: CGFloat = 24
    private let labelWidth: CGFloat = 100
    private let rowHeight: CGFloat = 24
    private let sectionSpacing: CGFloat = 20
    private let rowSpacing: CGFloat = 10

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

    /// 翻译设置主垂直栈
    private let translationStack: NSStackView = {
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
        registerTextFieldNotifications()
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    private func registerTextFieldNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textFieldDidEndEditing(_:)),
            name: NSTextField.textDidEndEditingNotification,
            object: nil
        )
    }

    @objc private func textFieldDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        if textField === modelField {
            settings.translationModel = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if textField === customBaseURLField {
            settings.customLLMBaseURL = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        persistSettings()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        // 整体使用 Auto Layout：左侧 sidebar + 右侧滚动内容区
        let sidebar = makeSidebar()
        addSubview(sidebar)

        contentScrollView = NSScrollView()
        contentScrollView.hasVerticalScroller = true
        contentScrollView.borderType = .noBorder
        contentScrollView.autohidesScrollers = true
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentScrollView)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            contentScrollView.topAnchor.constraint(equalTo: topAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        translatesAutoresizingMaskIntoConstraints = false

        // 构建 tab 内容视图
        translationContentView = makeTranslationContent()
        overlayContentView = makeOverlayContent()
        shortcutsContentView = makeShortcutsContent()
        aboutContentView = makeAboutContent()

        // 缓存所有 tab 视图，通过替换 contentHostView 子视图切换 tab
        tabContentViews = [
            .translation: translationContentView,
            .overlay: overlayContentView,
            .shortcuts: shortcutsContentView,
            .about: aboutContentView,
        ]

        // 使用固定的 host view 作为 scrollView 的 documentView
        contentHostView = NSView()
        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.documentView = contentHostView

        let clipView = contentScrollView.contentView
        NSLayoutConstraint.activate([
            contentHostView.topAnchor.constraint(equalTo: clipView.topAnchor),
            contentHostView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            contentHostView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
            // documentView 至少与可见区等高，避免内容较少时被鼠标滚轮随意滚动
            contentHostView.heightAnchor.constraint(greaterThanOrEqualTo: clipView.heightAnchor),
        ])

        // 默认选中「翻译」tab
        switchTab(to: .translation)

        updateControlsFromSettings()
    }

    // MARK: - Sidebar

    private func makeSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.sidebarBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        // Tab 按钮
        for tab in SettingsTab.allCases {
            let button = makeTabButton(tab: tab)
            tabButtons.append(button)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
        ])

        return sidebar
    }

    private func makeTabButton(tab: SettingsTab) -> NSButton {
        let button = NSButton()
        button.setButtonType(.momentaryLight)
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
        button.title = tab.title
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.tag = tab.rawValue
        button.target = self
        button.action = #selector(tabButtonClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.contentTintColor = NSColor.labelColor
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6

        // 让图片和文字更贴近左侧
        button.imageHugsTitle = true
        return button
    }

    @objc private func tabButtonClicked(_ sender: NSButton) {
        guard let tab = SettingsTab(rawValue: sender.tag) else { return }
        switchTab(to: tab)
    }

    private func switchTab(to tab: SettingsTab) {
        currentTab = tab

        // 更新按钮选中样式
        for button in tabButtons {
            let selected = (button.tag == tab.rawValue)
            button.wantsLayer = true
            button.layer?.backgroundColor = selected ? NSColor.selectedTabBackgroundColor.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? NSColor.selectedTabTextColor : NSColor.labelColor
        }

        // 移除旧内容视图，添加新内容视图到 host view
        guard let contentView = tabContentViews[tab] else { return }
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(contentView)

        // 切换 tab 时重建内容视图约束：
        // - 关于页内容较少，垂直居中显示（偏下），且固定不被滚动
        // - 其他页内容从顶部开始排列，内容超出时可滚动
        NSLayoutConstraint.deactivate(currentContentConstraints)
        currentContentConstraints = [
            contentView.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
        ]

        if tab == .about {
            // 关于页：垂直居中，并限制不超出可见区域
            currentContentConstraints.append(contentView.centerYAnchor.constraint(equalTo: contentHostView.centerYAnchor))
            currentContentConstraints.append(contentView.topAnchor.constraint(greaterThanOrEqualTo: contentHostView.topAnchor, constant: margin))
            currentContentConstraints.append(contentView.bottomAnchor.constraint(lessThanOrEqualTo: contentHostView.bottomAnchor, constant: -margin))
        } else {
            // 其他页：顶底对齐，内容多时自然滚动
            currentContentConstraints.append(contentView.topAnchor.constraint(equalTo: contentHostView.topAnchor))
            currentContentConstraints.append(contentView.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor))
        }

        NSLayoutConstraint.activate(currentContentConstraints)

        // 滚动到顶部
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.contentScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        }
    }

    // MARK: - 翻译设置内容

    private func makeTranslationContent() -> NSView {
        translationStack.addArrangedSubview(makeTranslationToggleRow())
        translationStack.addArrangedSubview(spacer(sectionSpacing))
        translationStack.addArrangedSubview(makeSeparator())

        // 以下为翻译相关设置区域，开关关闭时统一隐藏
        translationSectionViews = []

        // === 翻译服务 ===
        translationSectionViews.append(makeSectionHeader("翻译服务"))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeProviderRow())
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(rowSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeModelRow())
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(rowSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeCustomBaseURLRow())
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(rowSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeAPIKeyRow())
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeFallbackHintRow())
        translationStack.addArrangedSubview(translationSectionViews.last!)

        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeSeparator())
        translationStack.addArrangedSubview(translationSectionViews.last!)

        // === 翻译语言 ===
        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeSectionHeader("翻译语言"))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeTargetLanguageRow())
        translationStack.addArrangedSubview(translationSectionViews.last!)

        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeSeparator())
        translationStack.addArrangedSubview(translationSectionViews.last!)

        // === 翻译触发 ===
        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeSectionHeader("翻译触发"))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(sectionSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeNumberRow(
            label: "段落间隔：",
            field: &segmentPauseField,
            stepper: &segmentPauseStepper,
            minValue: 0.1, maxValue: 999999,
            step: 0.1,
            format: "%.1f 秒",
            unit: "秒",
            action: #selector(segmentPauseChanged),
            valueMultiplier: 1
        ))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeDescriptionLabel("停顿超过此时间后，下次输入将开启新段落"))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(spacer(rowSpacing))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeNumberRow(
            label: "翻译间隔：",
            field: &debounceField,
            stepper: &debounceStepper,
            minValue: 0.1, maxValue: 999999,
            step: 0.1,
            format: "%.1f 秒",
            unit: "秒",
            action: #selector(debounceChanged),
            valueMultiplier: 1
        ))
        translationStack.addArrangedSubview(translationSectionViews.last!)
        translationSectionViews.append(makeDescriptionLabel("停止输入后等待此时间再触发翻译"))
        translationStack.addArrangedSubview(translationSectionViews.last!)

        // === 恢复默认按钮 ===
        translationStack.addArrangedSubview(spacer(sectionSpacing + 4))
        translationStack.addArrangedSubview(makeResetButtonRow())

        return wrapContent(translationStack)
    }

    // MARK: - 悬浮窗设置内容

    /// 悬浮窗设置主垂直栈
    private let overlayStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private func makeOverlayContent() -> NSView {
        // === 外观主题 ===
        overlayStack.addArrangedSubview(makeSectionHeader("外观主题"))
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeThemeRow())
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeColorRow(
            label: "背景颜色：",
            well: &backgroundColorWell,
            action: #selector(backgroundColorChanged)
        ))
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeColorRow(
            label: "原文颜色：",
            well: &originalTextColorWell,
            action: #selector(originalTextColorChanged)
        ))
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeColorRow(
            label: "译文颜色：",
            well: &translationTextColorWell,
            action: #selector(translationTextColorChanged)
        ))

        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeSeparator())

        // === 窗口行为 ===
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeSectionHeader("窗口行为"))
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makePositionModeRow())
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeClickThroughRow())
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeNumberRow(
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
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeNumberRow(
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

        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeSeparator())

        // === 尺寸与字体 ===
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeSectionHeader("尺寸与字体"))
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeNumberRow(
            label: "最大宽度：",
            field: &overlayMaxWidthField,
            stepper: &overlayMaxWidthStepper,
            minValue: 200, maxValue: 800,
            step: 10,
            format: "%.0f",
            unit: "pt",
            action: #selector(overlayMaxWidthChanged),
            valueMultiplier: 1
        ))
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeNumberRow(
            label: "最大高度：",
            field: &overlayMaxHeightField,
            stepper: &overlayMaxHeightStepper,
            minValue: 80, maxValue: 600,
            step: 10,
            format: "%.0f",
            unit: "pt",
            action: #selector(overlayMaxHeightChanged),
            valueMultiplier: 1
        ))
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeNumberRow(
            label: "原文字号：",
            field: &originalFontSizeField,
            stepper: &originalFontSizeStepper,
            minValue: 8, maxValue: 32,
            step: 1,
            format: "%.0f",
            unit: "pt",
            action: #selector(originalFontSizeChanged),
            valueMultiplier: 1
        ))
        overlayStack.addArrangedSubview(spacer(rowSpacing))
        overlayStack.addArrangedSubview(makeNumberRow(
            label: "译文字号：",
            field: &translationFontSizeField,
            stepper: &translationFontSizeStepper,
            minValue: 8, maxValue: 32,
            step: 1,
            format: "%.0f",
            unit: "pt",
            action: #selector(translationFontSizeChanged),
            valueMultiplier: 1
        ))

        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeSeparator())

        // === 标签显示 ===
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeSectionHeader("标签显示"))
        overlayStack.addArrangedSubview(spacer(sectionSpacing))
        overlayStack.addArrangedSubview(makeLabelVisibilityRow())

        return wrapContent(overlayStack)
    }

    // MARK: - 悬浮窗设置控件构建

    /// 构建主题下拉框行
    private func makeThemeRow() -> NSView {
        overlayThemePopup = NSPopUpButton()
        overlayThemePopup.addItems(withTitles: ["深色模式", "浅色模式", "跟随系统"])
        overlayThemePopup.target = self
        overlayThemePopup.action = #selector(overlayThemeChanged)
        return makeRow(label: "主题：", control: overlayThemePopup)
    }

    /// 构建穿透模式复选框行（带缩进，与其他设置项的控件列对齐）
    private func makeClickThroughRow() -> NSView {
        clickThroughCheckbox = NSButton(checkboxWithTitle: "穿透模式（鼠标可穿透悬浮窗点击后方内容）",
                                         target: self, action: #selector(clickThroughChanged))
        clickThroughCheckbox.font = NSFont.systemFont(ofSize: 13)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: labelWidth + 6).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(clickThroughCheckbox)
        return row
    }

    /// 构建标签显隐复选框行（带缩进，与其他设置项的控件列对齐）
    private func makeLabelVisibilityRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        showOriginalLabelCheckbox = NSButton(checkboxWithTitle: "显示「原文」标签",
                                              target: self, action: #selector(showOriginalLabelChanged))
        showOriginalLabelCheckbox.font = NSFont.systemFont(ofSize: 13)

        showTranslationLabelCheckbox = NSButton(checkboxWithTitle: "显示「翻译」标签",
                                                 target: self, action: #selector(showTranslationLabelChanged))
        showTranslationLabelCheckbox.font = NSFont.systemFont(ofSize: 13)

        stack.addArrangedSubview(showOriginalLabelCheckbox)
        stack.addArrangedSubview(showTranslationLabelCheckbox)

        // 添加缩进，与其他设置项的控件列对齐
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: labelWidth + 6).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(stack)
        return row
    }

    // MARK: - 快捷键说明内容

    private func makeShortcutsContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeSectionHeader("快捷键说明"))
        stack.addArrangedSubview(spacer(sectionSpacing))

        // 快捷键列表
        let shortcuts: [(name: String, key: String, desc: String)] = [
            ("打开语境设置", "⌘ ,", "在输入法菜单中打开设置窗口"),
            ("快捷复制翻译", "⌃ ⌘ ,", "复制最近一次翻译结果到剪贴板"),
        ]

        for shortcut in shortcuts {
            stack.addArrangedSubview(makeShortcutRow(name: shortcut.name, key: shortcut.key, desc: shortcut.desc))
            stack.addArrangedSubview(spacer(rowSpacing))
        }

        stack.addArrangedSubview(spacer(sectionSpacing))
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(spacer(sectionSpacing))

        // 说明文字
        let hint = NSTextField(labelWithString: "提示：快捷键仅在输入法激活状态下生效。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = NSColor.secondaryLabelColor
        stack.addArrangedSubview(hint)

        return wrapContent(stack)
    }

    /// 构建单个快捷键说明行：名称 | 快捷键标签 | 说明
    private func makeShortcutRow(name: String, key: String, desc: String) -> NSView {
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        // 快捷键样式：带圆角背景的标签
        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        keyLabel.textColor = NSColor.labelColor
        keyLabel.alignment = .center
        keyLabel.wantsLayer = true
        keyLabel.layer?.cornerRadius = 4
        keyLabel.layer?.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 1.0).cgColor
        keyLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true
        keyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        let keyPadding = 8
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)

        // 用 wrapper 给 keyLabel 加内边距
        let keyWrapper = NSView()
        keyWrapper.translatesAutoresizingMaskIntoConstraints = false
        keyWrapper.addSubview(keyLabel)
        NSLayoutConstraint.activate([
            keyLabel.topAnchor.constraint(equalTo: keyWrapper.topAnchor, constant: 2),
            keyLabel.bottomAnchor.constraint(equalTo: keyWrapper.bottomAnchor, constant: -2),
            keyLabel.leadingAnchor.constraint(equalTo: keyWrapper.leadingAnchor, constant: CGFloat(keyPadding)),
            keyLabel.trailingAnchor.constraint(equalTo: keyWrapper.trailingAnchor, constant: -CGFloat(keyPadding)),
        ])

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(keyWrapper)
        row.addArrangedSubview(descLabel)

        return row
    }

    // MARK: - 关于页面内容

    private func makeAboutContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let nameLabel = NSTextField(labelWithString: "语境输入法")
        nameLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.alignment = .center

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "版本 \(version)")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = NSColor.secondaryLabelColor
        versionLabel.alignment = .center

        stack.addArrangedSubview(spacer(60))
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(versionLabel)

        // 联系我们按钮
        stack.addArrangedSubview(spacer(24))
        let contactButton = NSButton()
        contactButton.title = "联系我们"
        contactButton.bezelStyle = .rounded
        contactButton.target = self
        contactButton.action = #selector(openContactWebsite)
        contactButton.font = NSFont.systemFont(ofSize: 12)
        contactButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(contactButton)

        let container = wrapContent(stack)
        return container
    }

    /// 打开联系我们网址
    @objc private func openContactWebsite() {
        if let url = URL(string: "https://www.chengjinxi.com") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 将内容 stack 包裹在一个容器中，并添加边距约束
    private func wrapContent(_ stack: NSStackView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
        ])
        return container
    }

    // MARK: - UI 辅助

    /// 构建翻译功能开关行
    private func makeTranslationToggleRow() -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "启用翻译", target: self, action: #selector(translationEnabledChanged))
        checkbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        translationEnabledCheckbox = checkbox
        return checkbox
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 22),
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

    /// 构建兜底提示行（LLM 提供商未配置 API Key 时显示）
    private func makeFallbackHintRow() -> NSView {
        let label = NSTextField(labelWithString: "未配置 API Key，将自动使用语境免费翻译兜底")
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

    /// 构建目标语言下拉框行
    private func makeTargetLanguageRow() -> NSView {
        targetLanguagePopup = NSPopUpButton()
        targetLanguagePopup.addItems(withTitles: TargetLanguage.allCases.map { $0.displayName })
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(targetLanguageChanged)
        return makeRow(label: "目标语言：", control: targetLanguagePopup)
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

    /// 构建设置项说明文字（小号灰色字体，缩进对齐控件位置）
    private func makeDescriptionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: labelWidth + 6).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(label)
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
        case #selector(overlayMaxWidthChanged):
            onChange = { [weak self] v in self?.settings.overlayMaxWidth = v }
        case #selector(overlayMaxHeightChanged):
            onChange = { [weak self] v in self?.settings.overlayMaxHeight = v }
        case #selector(originalFontSizeChanged):
            onChange = { [weak self] v in self?.settings.overlayOriginalFontSize = v }
        case #selector(translationFontSizeChanged):
            onChange = { [weak self] v in self?.settings.overlayTranslationFontSize = v }
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

    /// 构建颜色选择行：label | NSColorWell
    private func makeColorRow(
        label text: String,
        well: inout NSColorWell!,
        action: Selector
    ) -> NSView {
        well = NSColorWell()
        well.target = self
        well.action = action
        well.translatesAutoresizingMaskIntoConstraints = false
        well.setContentHuggingPriority(.required, for: .horizontal)
        well.setContentCompressionResistancePriority(.required, for: .horizontal)
        well.widthAnchor.constraint(equalToConstant: 45).isActive = true
        well.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        return makeRow(label: text, control: well)
    }

    // MARK: - 控件值同步

    private func updateControlsFromSettings() {
        // 翻译开关
        translationEnabledCheckbox.state = settings.translationEnabled ? .on : .off

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

        // 目标语言
        let langIndex = TargetLanguage.allCases.firstIndex(where: { $0.rawValue == settings.targetLanguage }) ?? 0
        targetLanguagePopup.selectItem(at: langIndex)

        // 位置模式
        let mode = settings.overlayPositionMode
        fixedRadio.state = (mode == "fixed") ? .on : .off
        movableRadio.state = (mode == "draggable") ? .on : .off
        followCursorRadio.state = (mode == "followCursor") ? .on : .off

        // 自动消失
        applyRawValue(settings.autoDismissInterval, to: dismissField, stepper: dismissStepper)

        // 透明度
        applyRawValue(settings.overlayOpacity, to: opacityField, stepper: opacityStepper)

        // 颜色
        backgroundColorWell.color = NSColor(hex: settings.overlayBackgroundColor) ?? NSColor(white: 0.12, alpha: 1.0)
        originalTextColorWell.color = NSColor(hex: settings.overlayOriginalTextColor) ?? NSColor(white: 0.6, alpha: 1.0)
        translationTextColorWell.color = NSColor(hex: settings.overlayTranslationTextColor) ?? NSColor.white

        // 段落间隔时间
        applyRawValue(settings.segmentPauseThreshold, to: segmentPauseField, stepper: segmentPauseStepper)

        // 翻译间隔时间
        applyRawValue(settings.translationDebounceInterval, to: debounceField, stepper: debounceStepper)

        // === 悬浮窗设置 ===
        // 主题
        let themeIndex: Int
        switch settings.overlayTheme {
        case "light": themeIndex = 1
        case "auto": themeIndex = 2
        default: themeIndex = 0
        }
        overlayThemePopup.selectItem(at: themeIndex)

        // 点击穿透
        clickThroughCheckbox.state = settings.overlayClickThrough ? .on : .off

        // 最大宽度/高度
        applyRawValue(settings.overlayMaxWidth, to: overlayMaxWidthField, stepper: overlayMaxWidthStepper)
        applyRawValue(settings.overlayMaxHeight, to: overlayMaxHeightField, stepper: overlayMaxHeightStepper)

        // 字体大小
        applyRawValue(settings.overlayOriginalFontSize, to: originalFontSizeField, stepper: originalFontSizeStepper)
        applyRawValue(settings.overlayTranslationFontSize, to: translationFontSizeField, stepper: translationFontSizeStepper)

        // 标签显隐
        showOriginalLabelCheckbox.state = settings.overlayShowOriginalLabel ? .on : .off
        showTranslationLabelCheckbox.state = settings.overlayShowTranslationLabel ? .on : .off
    }

    /// 把原始 settings 值同步到对应输入框（用 format 格式化显示）与 stepper
    private func applyRawValue(_ raw: Double, to field: NSTextField?, stepper: NSStepper?) {
        guard let field = field, let config = numberRowConfigs[field] else { return }
        field.stringValue = config.displayString(forRawValue: raw)
        stepper?.doubleValue = raw
        config.lastRawValue = raw
    }

    // MARK: - 控件事件

    // MARK: 翻译设置事件

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
        persistSettings()
    }

    /// 模型输入框内容变化
    @objc private func modelFieldChanged() {
        settings.translationModel = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        persistSettings()
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

        // 兜底提示行：LLM 提供商且未配置 API Key 时显示
        if !isFree {
            let apiKey = settings.getAPIKey(provider: provider.rawValue) ?? ""
            fallbackHintRow.isHidden = !apiKey.isEmpty
        } else {
            fallbackHintRow.isHidden = true
        }
    }

    /// 翻译开关切换
    @objc private func translationEnabledChanged() {
        settings.translationEnabled = (translationEnabledCheckbox.state == .on)
        persistSettings()
    }

    @objc private func targetLanguageChanged() {
        let idx = targetLanguagePopup.indexOfSelectedItem
        settings.targetLanguage = TargetLanguage.allCases[idx].rawValue
        persistSettings()
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
            let targetLang = TargetLanguage(rawValue: settings.targetLanguage) ?? .english
            let translator: TranslationServiceProtocol = BingTranslator()

            Task { [weak self] in
                do {
                    _ = try await translator.translate(text: "你好世界", mode: mode, targetLanguage: targetLang)
                    DispatchQueue.main.async {
                        self?.verifyButton.isEnabled = true
                        self?.verifyButton.title = "验证"
                        self?.persistSettings()
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
        let targetLang = TargetLanguage(rawValue: settings.targetLanguage) ?? .english
        let translator = LLMTranslator(provider: provider, model: model)

        Task { [weak self] in
            do {
                _ = try await translator.translate(text: "你好世界", mode: mode, targetLanguage: targetLang)
                DispatchQueue.main.async {
                    self?.verifyButton.isEnabled = true
                    self?.verifyButton.title = "验证"
                    self?.persistSettings()
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
        persistSettings()
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

    @objc private func overlayMaxWidthChanged() {
        // 同上
    }

    @objc private func overlayMaxHeightChanged() {
        // 同上
    }

    @objc private func originalFontSizeChanged() {
        // 同上
    }

    @objc private func translationFontSizeChanged() {
        // 同上
    }

    @objc private func backgroundColorChanged() {
        settings.overlayBackgroundColor = backgroundColorWell.color.hexString
        persistSettings()
    }

    @objc private func originalTextColorChanged() {
        settings.overlayOriginalTextColor = originalTextColorWell.color.hexString
        persistSettings()
    }

    @objc private func translationTextColorChanged() {
        settings.overlayTranslationTextColor = translationTextColorWell.color.hexString
        persistSettings()
    }

    @objc private func overlayThemeChanged() {
        let index = overlayThemePopup.indexOfSelectedItem
        let theme: String
        switch index {
        case 1: theme = "light"
        case 2: theme = "auto"
        default: theme = "dark"
        }
        settings.overlayTheme = theme

        // 切换主题时，更新颜色设置为主题预设
        let preset = LOSettings.themeColors(for: theme)
        settings.overlayBackgroundColor = preset.bg
        settings.overlayOriginalTextColor = preset.original
        settings.overlayTranslationTextColor = preset.translation

        // 同步颜色选择器 UI
        backgroundColorWell.color = NSColor(hex: preset.bg) ?? NSColor(white: 0.12, alpha: 1.0)
        originalTextColorWell.color = NSColor(hex: preset.original) ?? NSColor(white: 0.6, alpha: 1.0)
        translationTextColorWell.color = NSColor(hex: preset.translation) ?? NSColor.white

        persistSettings()
    }

    @objc private func clickThroughChanged() {
        settings.overlayClickThrough = (clickThroughCheckbox.state == .on)
        persistSettings()
    }

    @objc private func showOriginalLabelChanged() {
        settings.overlayShowOriginalLabel = (showOriginalLabelCheckbox.state == .on)
        persistSettings()
    }

    @objc private func showTranslationLabelChanged() {
        settings.overlayShowTranslationLabel = (showTranslationLabelCheckbox.state == .on)
        persistSettings()
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
        persistSettings()
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
        persistSettings()
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

    /// 构建恢复默认按钮行（右对齐）
    private func makeResetButtonRow() -> NSView {
        let resetButton = NSButton()
        resetButton.title = "恢复默认"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetSettings)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        let filler = NSView()
        filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(filler)
        row.addArrangedSubview(resetButton)
        return row
    }

    /// 自动保存设置。所有控件变化后都应调用此方法。
    private func persistSettings() {
        commitPendingEdits()

        // 同步所有数值输入框（防止用户未按回车就切换焦点）
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
        if apiKey.isEmpty {
            // 用户清空了 API Key，删除 Keychain 中的旧密钥
            settings.deleteAPIKey(provider: settings.translationProvider)
        } else {
            settings.setAPIKey(provider: settings.translationProvider, key: apiKey)
        }

        settings.save()
        TranslationScheduler.shared.updateTranslator()
        NotificationCenter.default.post(name: .LOSettingsDidChange, object: nil)
        debugLog("设置已自动保存")
    }

    /// 提交所有未保存的编辑并保存设置（窗口关闭时调用）
    func commitAndSave() {
        persistSettings()
    }

    @objc private func resetSettings() {
        settings = LOSettings()
        updateControlsFromSettings()
        persistSettings()
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

// MARK: - 颜色扩展

private extension NSColor {
    /// 侧边栏背景色
    static var sidebarBackgroundColor: NSColor {
        if #available(macOS 10.14, *) {
            return NSColor(name: nil) { appearance in
                return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedWhite: 0.15, alpha: 1.0)
                    : NSColor(calibratedWhite: 0.96, alpha: 1.0)
            }
        }
        return NSColor(calibratedWhite: 0.96, alpha: 1.0)
    }

    /// 选中 tab 背景色
    static var selectedTabBackgroundColor: NSColor {
        if #available(macOS 10.14, *) {
            return NSColor(name: nil) { appearance in
                return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedWhite: 0.28, alpha: 1.0)
                    : NSColor(calibratedWhite: 0.90, alpha: 1.0)
            }
        }
        return NSColor(calibratedWhite: 0.90, alpha: 1.0)
    }

    /// 选中 tab 文字颜色
    static var selectedTabTextColor: NSColor {
        return NSColor.labelColor
    }
}

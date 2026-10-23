import AppKit
import LOMTCore

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

    /// 语音播报开关
    private var speechEnabledCheckbox: NSButton!

    /// 悬浮窗显示开关
    private var overlayEnabledCheckbox: NSButton!

    /// 翻译引擎下拉框（在线 / 本地轻量）
    private var mtEngineModePopup: NSPopUpButton!

    /// 引擎说明文字（随选择变化）
    private var mtEngineDetailLabel: NSTextField!

    /// 本地不可用时是否回退在线
    private var mtFallbackCheckbox: NSButton!

    /// 语言包概况（已安装数量、占用体积）
    private var mtPackSummaryLabel: NSTextField!

    /// 语言包列表容器（按安装状态动态重建）
    private var mtPackListStack: NSStackView!

    /// 语言包提示（未覆盖当前目标语言等）
    private var mtPackHintLabel: NSTextField!

    /// 「语言包」整个区块的视图（仅本地轻量模式显示）
    private var mtPackSectionViews: [NSView] = []

    /// 语言包行（按 manifest id 索引）
    private var mtModelRows: [String: MTModelRowView] = [:]

    /// 正在下载的模型 id，避免重复触发
    private var mtDownloading: Set<String> = []

    /// 语音播报语速下拉框
    private var speechRatePopup: NSPopUpButton!

    /// 语速可选值（AVSpeechUtterance.rate，0.5 为系统默认）
    private static let speechRateOptions: [(title: String, value: Double)] = [
        ("慢", 0.4), ("正常", 0.5), ("快", 0.6)
    ]

    /// 目标语言下拉框
    private var targetLanguagePopup: NSPopUpButton!

    /// 目标语言可选项（语言代码，随当前引擎生成）
    private var targetLanguageCodes: [String] = []

    /// 目标语言能力说明（当前引擎支持多少种语言）
    private var targetCapabilityLabel: NSTextField!

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
        // 整体使用 Auto Layout：左侧毛玻璃侧边栏 + 右侧卡片式滚动内容区
        let sidebar = makeSidebar()
        addSubview(sidebar)

        contentScrollView = NSScrollView()
        contentScrollView.hasVerticalScroller = true
        contentScrollView.borderType = .noBorder
        contentScrollView.autohidesScrollers = true
        contentScrollView.drawsBackground = true
        contentScrollView.backgroundColor = LODesign.Color.content
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentScrollView)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: LODesign.Metric.sidebarWidth),

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
        // 毛玻璃材质侧边栏，与系统设置一致
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .followsWindowActiveState
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        // Tab 按钮
        for tab in SettingsTab.allCases {
            let button = makeTabButton(tab: tab)
            tabButtons.append(button)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let inset = LODesign.Metric.sidebarInset
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: inset + 8),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -inset),
        ])

        return sidebar
    }

    private func makeTabButton(tab: SettingsTab) -> NSButton {
        let button = NSButton()
        button.setButtonType(.momentaryChange)
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
        button.title = tab.title
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.tag = tab.rawValue
        button.target = self
        button.action = #selector(tabButtonClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: LODesign.Metric.sidebarItemHeight).isActive = true
        button.contentTintColor = LODesign.Color.textSecondary
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.imageHugsTitle = true
        return button
    }

    @objc private func tabButtonClicked(_ sender: NSButton) {
        guard let tab = SettingsTab(rawValue: sender.tag) else { return }
        switchTab(to: tab)
    }

    private func switchTab(to tab: SettingsTab) {
        currentTab = tab

        // 更新按钮选中样式：选中项用半透明胶囊，文字提亮
        for button in tabButtons {
            let selected = (button.tag == tab.rawValue)
            button.wantsLayer = true
            button.layer?.backgroundColor = selected
                ? LODesign.Color.sidebarSelection.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = selected ? LODesign.Color.textPrimary : LODesign.Color.textSecondary
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
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makePageHeader("翻译", subtitle: "翻译、悬浮窗与语音播报相互独立，可任意组合"))
        stack.addArrangedSubview(spacer(LODesign.Metric.cardGap))

        appendSection("功能开关", rows: [makeFeatureToggleRows()], to: stack, isFirst: true)

        appendSection("翻译引擎", rows: [
            makeEngineModeRow(),
            makeEngineDetailLabel(),
            makeFallbackRow()
        ], to: stack)

        appendSection("翻译语言", rows: [
            makeTargetLanguageRow(),
            makeTargetCapabilityLabel()
        ], to: stack)

        mtPackSectionViews = appendSection("本地模型", rows: makeLanguagePackRows(), to: stack)

        appendSection("语音播报", rows: [
            makeDescriptionLabel("使用系统语音离线朗读，无需额外配置；关闭翻译时朗读原文"),
            makeSpeechRateRow()
        ], to: stack)

        appendSection("翻译触发", rows: [
            makeNumberRow(
                label: "段落间隔：",
                field: &segmentPauseField,
                stepper: &segmentPauseStepper,
                minValue: 0.1, maxValue: 999999,
                step: 0.1,
                format: "%.1f 秒",
                unit: "秒",
                action: #selector(segmentPauseChanged),
                valueMultiplier: 1
            ),
            makeDescriptionLabel("停顿超过此时间后，下次输入将开启新段落"),
            makeNumberRow(
                label: "翻译间隔：",
                field: &debounceField,
                stepper: &debounceStepper,
                minValue: 0.1, maxValue: 999999,
                step: 0.1,
                format: "%.1f 秒",
                unit: "秒",
                action: #selector(debounceChanged),
                valueMultiplier: 1
            ),
            makeDescriptionLabel("停止输入后等待此时间再触发翻译")
        ], to: stack)

        stack.addArrangedSubview(spacer(LODesign.Metric.cardGap))
        stack.addArrangedSubview(makeResetButtonRow())

        return wrapContent(stack)
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
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makePageHeader("悬浮窗", subtitle: "调整翻译浮窗的外观、行为与字号"))
        stack.addArrangedSubview(spacer(LODesign.Metric.cardGap))

        appendSection("外观", rows: [
            makeThemeRow(),
            makeColorRow(label: "背景颜色：", well: &backgroundColorWell,
                         action: #selector(backgroundColorChanged)),
            makeColorRow(label: "原文颜色：", well: &originalTextColorWell,
                         action: #selector(originalTextColorChanged)),
            makeColorRow(label: "译文颜色：", well: &translationTextColorWell,
                         action: #selector(translationTextColorChanged))
        ], to: stack, isFirst: true)

        appendSection("窗口行为", rows: [
            makePositionModeRow(),
            makeClickThroughRow(),
            makeNumberRow(label: "自动消失：", field: &dismissField, stepper: &dismissStepper,
                          minValue: 1, maxValue: 9999, step: 0.1, format: "%.1f 秒", unit: "秒",
                          action: #selector(dismissChanged), valueMultiplier: 1),
            makeNumberRow(label: "透明度：", field: &opacityField, stepper: &opacityStepper,
                          minValue: 0.1, maxValue: 1.0, step: 0.01, format: "%.0f%%", unit: "%",
                          action: #selector(opacityChanged), valueMultiplier: 100)
        ], to: stack)

        appendSection("尺寸与字体", rows: [
            makeNumberRow(label: "最大宽度：", field: &overlayMaxWidthField, stepper: &overlayMaxWidthStepper,
                          minValue: 200, maxValue: 800, step: 10, format: "%.0f", unit: "pt",
                          action: #selector(overlayMaxWidthChanged), valueMultiplier: 1),
            makeNumberRow(label: "最大高度：", field: &overlayMaxHeightField, stepper: &overlayMaxHeightStepper,
                          minValue: 80, maxValue: 600, step: 10, format: "%.0f", unit: "pt",
                          action: #selector(overlayMaxHeightChanged), valueMultiplier: 1),
            makeNumberRow(label: "原文字号：", field: &originalFontSizeField, stepper: &originalFontSizeStepper,
                          minValue: 8, maxValue: 32, step: 1, format: "%.0f", unit: "pt",
                          action: #selector(originalFontSizeChanged), valueMultiplier: 1),
            makeNumberRow(label: "译文字号：", field: &translationFontSizeField, stepper: &translationFontSizeStepper,
                          minValue: 8, maxValue: 32, step: 1, format: "%.0f", unit: "pt",
                          action: #selector(translationFontSizeChanged), valueMultiplier: 1)
        ], to: stack)

        return wrapContent(stack)
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

    /// 构建穿透模式复选框行
    private func makeClickThroughRow() -> NSView {
        clickThroughCheckbox = NSButton(checkboxWithTitle: "穿透模式（鼠标可穿透悬浮窗点击后方内容）",
                                         target: self, action: #selector(clickThroughChanged))
        clickThroughCheckbox.font = NSFont.systemFont(ofSize: 13)
        return clickThroughCheckbox
    }

    /// 构建标签显隐复选框行（带缩进，与其他设置项的控件列对齐）
    // MARK: - 快捷键说明内容

    private func makeShortcutsContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makePageHeader("快捷键", subtitle: "输入法激活时可用"))
        stack.addArrangedSubview(spacer(LODesign.Metric.cardGap))

        let shortcuts: [(name: String, key: String, desc: String)] = [
            ("打开语境设置", "⌘ ,", "在输入法菜单中打开设置窗口"),
            ("快捷复制翻译", "⌃ ⌘ ,", "复制最近一次翻译结果到剪贴板"),
        ]

        appendSection("快捷键说明", rows: shortcuts.map {
            makeShortcutRow(name: $0.name, key: $0.key, desc: $0.desc)
        }, to: stack, isFirst: true)

        stack.addArrangedSubview(spacer(LODesign.Metric.cardGap))
        stack.addArrangedSubview(makeDescriptionLabel("提示：快捷键仅在输入法激活状态下生效。"))

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

    /// 将内容 stack 包裹在一个容器中，并添加边距约束。
    /// 底部只用「大于等于」而不是等号：内容不足一屏时让内容贴顶排列，
    /// 避免 NSStackView 被拉伸导致行间距异常、最后一行被滚动区裁掉。
    private func wrapContent(_ stack: NSStackView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        let inset = LODesign.Metric.contentMargin
        let bottomInset = LODesign.Metric.contentBottomInset
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            container.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor, constant: bottomInset),
        ])
        return container
    }

    // MARK: - 卡片式布局辅助

    /// 页面标题区：主标题 + 一句说明
    private func makePageHeader(_ title: String, subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField.loLabel(title, font: LODesign.Font.pageTitle, color: LODesign.Color.textPrimary)
        let subtitleLabel = NSTextField.loLabel(subtitle, font: LODesign.Font.caption, color: LODesign.Color.textSecondary)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }

    /// 圆角卡片：把若干行包成一组，形成系统设置那样的分组
    private func makeCard(_ rows: [NSView]) -> NSView {
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = LODesign.Metric.rowGap
        inner.translatesAutoresizingMaskIntoConstraints = false

        for row in rows {
            inner.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = LODesign.Color.card.cgColor
        card.layer?.cornerRadius = LODesign.Metric.cardCorner
        card.layer?.borderWidth = 1
        card.layer?.borderColor = LODesign.Color.border.cgColor
        card.addSubview(inner)

        let pad = LODesign.Metric.cardPadding
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: pad),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -pad),
        ])
        return card
    }

    /// 把「区块标题 + 卡片」组装好，直接加进页面 stack
    /// - Returns: 该区块的所有视图，便于按条件整体显示/隐藏
    @discardableResult
    private func appendSection(_ title: String, rows: [NSView], to stack: NSStackView, isFirst: Bool = false) -> [NSView] {
        var views: [NSView] = []
        if !isFirst {
            let gap = spacer(LODesign.Metric.cardGap)
            stack.addArrangedSubview(gap)
            views.append(gap)
        }
        let header = makeSectionHeader(title)
        stack.addArrangedSubview(header)
        views.append(header)
        let sub = spacer(6)
        stack.addArrangedSubview(sub)
        views.append(sub)

        // 卡片撑满内容宽度，各分组左右边界保持对齐
        let card = makeCard(rows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        views.append(card)
        return views
    }

    private func setSectionViews(_ views: [NSView], visible: Bool) {
        views.forEach { $0.isHidden = !visible }
    }

    // MARK: - UI 辅助

    /// 功能开关组：翻译、悬浮窗、播报相互独立，可任意组合
    private func makeFeatureToggleRows() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        translationEnabledCheckbox = NSButton(
            checkboxWithTitle: "启用翻译（使用免费的语境翻译）",
            target: self, action: #selector(translationEnabledChanged))
        translationEnabledCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        overlayEnabledCheckbox = NSButton(
            checkboxWithTitle: "显示悬浮窗（关闭翻译时只显示原文）",
            target: self, action: #selector(overlayEnabledChanged))
        overlayEnabledCheckbox.font = NSFont.systemFont(ofSize: 13)

        speechEnabledCheckbox = NSButton(
            checkboxWithTitle: "语音播报（关闭翻译时朗读原文）",
            target: self, action: #selector(speechEnabledChanged))
        speechEnabledCheckbox.font = NSFont.systemFont(ofSize: 13)

        stack.addArrangedSubview(translationEnabledCheckbox)
        stack.addArrangedSubview(overlayEnabledCheckbox)
        stack.addArrangedSubview(speechEnabledCheckbox)
        return stack
    }

    /// 语音播报语速
    private func makeSpeechRateRow() -> NSView {
        speechRatePopup = NSPopUpButton()
        speechRatePopup.addItems(withTitles: Self.speechRateOptions.map { $0.title })
        speechRatePopup.target = self
        speechRatePopup.action = #selector(speechRateChanged)
        return makeRow(label: "语速：", control: speechRatePopup)
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        // 卡片分组小标题：小号、次级颜色、轻微字距
        let attributed = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: LODesign.Color.textTertiary,
                .kern: 0.5
            ]
        )
        let label = NSTextField(labelWithAttributedString: attributed)
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 16),
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
        let label = NSTextField.loLabel(text, font: LODesign.Font.row, color: LODesign.Color.textPrimary)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        // 中间填充，把控件推到行尾（与系统设置的表单一致）
        let filler = NSView()
        filler.translatesAutoresizingMaskIntoConstraints = false
        filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filler.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(label)
        row.addArrangedSubview(filler)
        row.addArrangedSubview(control)

        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        return row
    }

    /// 构建目标语言下拉框行（选项由当前引擎决定，见 rebuildTargetLanguageMenu）
    private func makeTargetLanguageRow() -> NSView {
        targetLanguagePopup = NSPopUpButton()
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(targetLanguageChanged)
        return makeRow(label: "目标语言：", control: targetLanguagePopup)
    }

    private func makeTargetCapabilityLabel() -> NSView {
        targetCapabilityLabel = NSTextField.loLabel("", font: LODesign.Font.caption,
                                                    color: LODesign.Color.textSecondary)
        targetCapabilityLabel.maximumNumberOfLines = 0
        targetCapabilityLabel.lineBreakMode = .byWordWrapping
        targetCapabilityLabel.cell?.wraps = true
        return targetCapabilityLabel
    }

    /// 按引擎能力重建目标语言列表：不支持当前语言时自动切到默认值
    private func rebuildTargetLanguageMenu(for mode: MTEngineMode) {
        guard let popup = targetLanguagePopup else { return }
        let codes = MTLanguageCatalog.codes(for: mode)
        targetLanguageCodes = codes

        popup.removeAllItems()
        popup.addItems(withTitles: codes.map { MTLanguageCatalog.displayName(for: $0) })

        let selected: String
        if codes.contains(settings.targetLanguage) {
            selected = settings.targetLanguage
        } else {
            selected = MTLanguageCatalog.defaultCode(for: mode)
            settings.targetLanguage = selected
            settings.save()
        }
        popup.selectItem(at: codes.firstIndex(of: selected) ?? 0)
        popup.isEnabled = codes.count > 1
        targetCapabilityLabel?.stringValue = MTLanguageCatalog.capabilityText(for: mode, count: codes.count)
    }

    // MARK: - 翻译引擎与本地模型

    private func makeEngineModeRow() -> NSView {
        mtEngineModePopup = NSPopUpButton()
        mtEngineModePopup.addItems(withTitles: MTEngineMode.allCases.map { $0.displayName })
        mtEngineModePopup.target = self
        mtEngineModePopup.action = #selector(mtEngineModeChanged)
        return makeRow(label: "翻译引擎：", control: mtEngineModePopup)
    }

    private func makeEngineDetailLabel() -> NSView {
        mtEngineDetailLabel = NSTextField.loLabel("", font: LODesign.Font.caption,
                                                  color: LODesign.Color.textSecondary)
        mtEngineDetailLabel.maximumNumberOfLines = 0
        mtEngineDetailLabel.lineBreakMode = .byWordWrapping
        mtEngineDetailLabel.cell?.wraps = true
        return mtEngineDetailLabel
    }

    private func makeFallbackRow() -> NSView {
        mtFallbackCheckbox = NSButton(checkboxWithTitle: "本地模型不可用时自动使用在线翻译",
                                      target: self, action: #selector(mtFallbackChanged))
        mtFallbackCheckbox.font = NSFont.systemFont(ofSize: 13)
        return mtFallbackCheckbox
    }

    private func makeLanguagePackRows() -> [NSView] {
        mtPackSummaryLabel = NSTextField.loLabel("", font: LODesign.Font.caption,
                                                 color: LODesign.Color.textSecondary)

        mtPackListStack = NSStackView()
        mtPackListStack.orientation = .vertical
        mtPackListStack.alignment = .leading
        mtPackListStack.spacing = LODesign.Metric.rowGap
        mtPackListStack.translatesAutoresizingMaskIntoConstraints = false

        mtPackHintLabel = NSTextField.loLabel("", font: LODesign.Font.caption,
                                              color: LODesign.Color.textSecondary)
        mtPackHintLabel.maximumNumberOfLines = 0
        mtPackHintLabel.lineBreakMode = .byWordWrapping
        mtPackHintLabel.cell?.wraps = true

        return [mtPackSummaryLabel, mtPackListStack, mtPackHintLabel]
    }

    /// 当前目标语言需要的语言包（按执行顺序，中→英 在前）
    private func manifestsForCurrentMode() -> [MTModelManifest] {
        guard MTEngineMode.from(settings.mtEngineMode) == .light else { return [] }
        return MTModelCatalog.packs(forTarget: settings.targetLanguage)
    }

    /// 重建当前目标语言所需的语言包列表
    private func rebuildPackRows() {
        guard let stack = mtPackListStack else { return }
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        mtModelRows.removeAll()

        let store = MTModelStore.shared
        let manifests = manifestsForCurrentMode()
        for manifest in manifests {
            let row = MTModelRowView(manifest: manifest,
                                     labelWidth: manifests.count > 1 ? 150 : 190)
            row.onDownload = { [weak self] in self?.startDownload(manifest) }
            row.onCancel = { [weak self] in self?.cancelDownload(manifest) }
            row.onDelete = { [weak self] in self?.deleteModel(manifest) }
            mtModelRows[manifest.id] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if store.isInstalled(manifest.id) {
                row.apply(.installed(bytes: manifest.bytes))
            } else {
                row.apply(.notInstalled)
            }
        }
    }

    private func applyPackStates() {
        let store = MTModelStore.shared
        for (id, row) in mtModelRows where !mtDownloading.contains(id) {
            row.apply(store.isInstalled(id) ? .installed(bytes: row.manifest.bytes) : .notInstalled)
        }
    }

    @objc private func mtEngineModeChanged() {
        let index = mtEngineModePopup.indexOfSelectedItem
        guard MTEngineMode.allCases.indices.contains(index) else { return }
        settings.mtEngineMode = MTEngineMode.allCases[index].rawValue
        MTEngineClient.shared.resetCircuitBreaker()
        // 目标语言能力随引擎变化，先重建列表再刷新状态
        rebuildTargetLanguageMenu(for: MTEngineMode.allCases[index])
        updateMTStatus()
        persistSettings()
    }

    @objc private func mtFallbackChanged() {
        settings.mtFallbackOnline = (mtFallbackCheckbox.state == .on)
        persistSettings()
        updateMTStatus()
    }

    /// 刷新引擎说明、模型区块与安装状态
    private func updateMTStatus() {
        let mode = MTEngineMode.from(settings.mtEngineMode)
        mtEngineDetailLabel?.stringValue = mode.detail
        mtFallbackCheckbox?.state = settings.mtFallbackOnline ? .on : .off
        mtFallbackCheckbox?.isHidden = mode == .online

        setSectionViews(mtPackSectionViews, visible: mode.isLocal)
        guard mode.isLocal else { return }

        let store = MTModelStore.shared
        if mtDownloading.isEmpty {
            rebuildPackRows()
        } else {
            applyPackStates()
        }

        let fallback = settings.mtFallbackOnline
        let route = manifestsForCurrentMode()
        let installed = route.filter { store.isInstalled($0.id) }
        let missing = route.filter { !store.isInstalled($0.id) }
        let usedBytes = installed.reduce(Int64(0)) { $0 + $1.bytes }
        let hint: String

        switch mode {
        case .online:
            return

        case .light:
            if route.isEmpty {
                mtPackSummaryLabel?.stringValue = "当前目标语言不支持本地翻译"
            } else if route.count == 1 {
                mtPackSummaryLabel?.stringValue = installed.isEmpty
                    ? "\(route[0].displayName) · 约 \(Self.sizeText(route[0].bytes))"
                    : "已安装 · 占用 \(Self.sizeText(usedBytes))"
            } else {
                mtPackSummaryLabel?.stringValue = missing.isEmpty
                    ? "已就绪 · 占用 \(Self.sizeText(usedBytes))（2 个语言包）"
                    : "该方向需要 2 个语言包 · 已安装 \(installed.count)/2"
            }

            if route.isEmpty {
                hint = "当前目标语言暂不支持本地轻量翻译，\(fallback ? "将使用在线翻译" : "本地翻译会提示不支持")。"
            } else if !missing.isEmpty {
                let names = missing.map { $0.displayName }.joined(separator: "、")
                hint = "还需要下载：\(names)。\(fallback ? "下载前暂用在线翻译。" : "未下载时会提示缺少语言包。")"
            } else if route.count > 1 {
                hint = "中文文本会先翻译为英文，再翻译为目标语言；两个语言包会同时驻留内存。"
            } else {
                hint = ""
            }
        }

        mtPackHintLabel?.stringValue = hint
        mtPackHintLabel?.textColor = hint.isEmpty ? LODesign.Color.textSecondary : .systemOrange
    }

    private static func sizeText(_ bytes: Int64) -> String {
        MTModelCatalog.sizeText(bytes)
    }

    private func startDownload(_ manifest: MTModelManifest) {
        guard !mtDownloading.contains(manifest.id) else { return }
        mtDownloading.insert(manifest.id)
        mtModelRows[manifest.id]?.apply(.downloading(done: 0, total: manifest.bytes))

        Task { @MainActor in
            do {
                try await MTDownloader.shared.download(manifest) { [weak self] done, total in
                    self?.mtModelRows[manifest.id]?.apply(.downloading(done: done, total: total))
                }
                mtDownloading.remove(manifest.id)
                MTEngineClient.shared.resetCircuitBreaker()
                updateMTStatus()
                debugLog("[MT] 模型安装完成 \(manifest.id)")
            } catch {
                mtDownloading.remove(manifest.id)
                if case MTDownloader.DownloadError.cancelled = error {
                    mtModelRows[manifest.id]?.apply(.notInstalled)
                } else {
                    mtModelRows[manifest.id]?.apply(.failed(error.localizedDescription))
                }
                debugLog("[MT] 模型下载失败 \(manifest.id)：\(error.localizedDescription)")
            }
        }
    }

    private func cancelDownload(_ manifest: MTModelManifest) {
        MTDownloader.shared.cancel()
        mtDownloading.remove(manifest.id)
        MTModelStore.shared.discardPartial(manifest.id)
        updateMTStatus()
    }

    private func deleteModel(_ manifest: MTModelManifest) {
        let alert = NSAlert()
        alert.messageText = "删除本地模型？"
        alert.informativeText = "删除后该方向将回退到在线翻译，需要时可重新下载（\(manifest.displayName)）。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? MTModelStore.shared.delete(manifest.id)
        if MTEngineClient.shared.currentModelID == manifest.id {
            Task { await MTEngineClient.shared.unload() }
        }
        updateMTStatus()
    }

    private func makePositionModeRow() -> NSView {
        fixedRadio = NSButton(radioButtonWithTitle: "固定位置", target: self, action: #selector(positionModeChanged))
        movableRadio = NSButton(radioButtonWithTitle: "可自由拖动", target: self, action: #selector(positionModeChanged))
        followCursorRadio = NSButton(radioButtonWithTitle: "跟随光标", target: self, action: #selector(positionModeChanged))

        let label = NSTextField.loLabel("位置模式：", font: LODesign.Font.row, color: LODesign.Color.textPrimary)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let radios = NSStackView()
        radios.orientation = .horizontal
        radios.spacing = 14
        radios.translatesAutoresizingMaskIntoConstraints = false
        radios.setContentHuggingPriority(.required, for: .horizontal)
        radios.addArrangedSubview(fixedRadio)
        radios.addArrangedSubview(movableRadio)
        radios.addArrangedSubview(followCursorRadio)

        let filler = NSView()
        filler.translatesAutoresizingMaskIntoConstraints = false
        filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filler.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(label)
        row.addArrangedSubview(filler)
        row.addArrangedSubview(radios)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// 构建设置项说明文字（小号灰色字体，缩进对齐控件位置）
    private func makeDescriptionLabel(_ text: String) -> NSView {
        let label = NSTextField.loLabel(text, font: LODesign.Font.caption, color: LODesign.Color.textSecondary)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        return label
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

        let label = NSTextField.loLabel(text, font: LODesign.Font.row, color: LODesign.Color.textPrimary)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        let filler = NSView()
        filler.translatesAutoresizingMaskIntoConstraints = false
        filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filler.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(label)
        row.addArrangedSubview(filler)
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

        // 翻译引擎与本地模型（目标语言列表由引擎能力决定）
        let engineMode = MTEngineMode.from(settings.mtEngineMode)
        mtEngineModePopup?.selectItem(at: MTEngineMode.allCases.firstIndex(of: engineMode) ?? 0)
        rebuildTargetLanguageMenu(for: engineMode)
        updateMTStatus()

        // 语音播报
        speechEnabledCheckbox.state = settings.speechEnabled ? .on : .off
        let rateIndex = Self.speechRateOptions.firstIndex { abs($0.value - settings.speechRate) < 0.01 } ?? 1
        speechRatePopup.selectItem(at: rateIndex)

        // 悬浮窗
        overlayEnabledCheckbox.state = settings.overlayEnabled ? .on : .off

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

    /// 翻译开关切换
    @objc private func translationEnabledChanged() {
        settings.translationEnabled = (translationEnabledCheckbox.state == .on)
        persistSettings()
    }

    /// 悬浮窗开关切换（独立于翻译）
    @objc private func overlayEnabledChanged() {
        settings.overlayEnabled = (overlayEnabledCheckbox.state == .on)
        persistSettings()
    }

    @objc private func speechEnabledChanged() {
        settings.speechEnabled = (speechEnabledCheckbox.state == .on)
        persistSettings()
    }

    @objc private func speechRateChanged() {
        let idx = speechRatePopup.indexOfSelectedItem
        guard Self.speechRateOptions.indices.contains(idx) else { return }
        settings.speechRate = Self.speechRateOptions[idx].value
        persistSettings()
    }

    @objc private func targetLanguageChanged() {
        let idx = targetLanguagePopup.indexOfSelectedItem
        guard targetLanguageCodes.indices.contains(idx) else { return }
        settings.targetLanguage = targetLanguageCodes[idx]
        persistSettings()
        updateMTStatus()
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
}

// MARK: - 颜色扩展

import Foundation

// MARK: - 翻译调度器

/// 翻译调度器，负责段落管理、长停顿断句、防抖翻译和缓存
@MainActor
class TranslationScheduler {

    /// 单例
    static let shared = TranslationScheduler()

    /// 翻译服务实例
    private var translator: TranslationServiceProtocol

    /// 翻译缓存
    private let cache = TranslationCache.shared

    /// 设置
    private var settings: LOSettings {
        return LOSettings.load()
    }

    // MARK: - 段落与计时器

    /// 短防抖定时器：连续快速提交时，只翻译最后一次
    private var debounceTimer: Timer?

    /// 段落超时定时器：长时间无新输入时，清空当前段落
    private var segmentTimeoutTimer: Timer?

    /// 当前段落缓冲
    private var currentSegment: String = ""

    /// 上次提交时间，用于判断长停顿
    private var lastCommitTime: Date = Date.distantPast

    /// 线程安全锁
    private let lock = NSLock()

    // MARK: - 回调

    /// 防抖期间静默更新原文（用于显示正在输入的原文）
    var onOriginalUpdate: ((String) -> Void)?

    /// 翻译开始（用于显示加载状态）
    var onTranslationStart: ((String) -> Void)?

    /// 翻译完成（原文, 译文）
    var onTranslationReady: ((String, String) -> Void)?

    // MARK: - 初始化

    private init() {
        // 默认使用 DeepSeek 翻译器
        self.translator = DeepSeekTranslator()
    }

    // MARK: - 公开接口

    /// 提交待翻译文本
    /// 会先判断是否需要开启新段落，然后启动防抖计时
    /// - Parameter text: 用户提交的文本
    func commit(text: String) {
        lock.lock()

        let isSegmentEmpty = currentSegment.isEmpty
        // 空段落且文本无需翻译时直接跳过；非空段落则允许追加（如标点）
        guard !isSegmentEmpty || shouldTranslate(text) else {
            lock.unlock()
            return
        }

        let now = Date()
        // 长停顿超过阈值，开启新段落
        if now.timeIntervalSince(lastCommitTime) > settings.segmentPauseThreshold {
            currentSegment = ""
        }

        // 追加到当前段落（中文输入候选词之间不应插入空格）
        if currentSegment.isEmpty {
            currentSegment = text
        } else {
            currentSegment += text
        }
        lastCommitTime = now

        let segmentToUpdate = currentSegment
        lock.unlock()

        // 通知原文更新
        onOriginalUpdate?(segmentToUpdate)

        // 重置短防抖与段落超时计时器
        resetDebounceTimer()
        resetSegmentTimeoutTimer()
    }

    /// 重置调度器状态（如切换输入法时调用）
    func reset() {
        lock.lock()
        currentSegment = ""
        lastCommitTime = Date.distantPast
        lock.unlock()

        debounceTimer?.invalidate()
        debounceTimer = nil
        segmentTimeoutTimer?.invalidate()
        segmentTimeoutTimer = nil
    }

    /// 更新翻译服务（切换翻译提供商时调用）
    func updateTranslator(provider: String) {
        switch provider {
        case "google":
            translator = GoogleTranslator()
        default:
            translator = DeepSeekTranslator()
        }
    }

    // MARK: - 文本过滤

    /// 判断文本是否需要翻译
    /// 过滤空文本、纯标点；允许中文或数字进入翻译
    private func shouldTranslate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空文本不翻译
        guard !trimmed.isEmpty else { return false }

        // 纯标点不翻译
        let punctuationSet = CharacterSet.punctuationCharacters
            .union(CharacterSet.whitespacesAndNewlines)
        let withoutPunctuation = trimmed.unicodeScalars.filter { !punctuationSet.contains($0) }
        guard !withoutPunctuation.isEmpty else { return false }

        // 必须包含中文字符或数字才翻译
        let hasChineseOrDigit = trimmed.unicodeScalars.contains { scalar in
            // CJK 统一汉字范围
            (0x4E00...0x9FFF).contains(scalar.value) ||
            // CJK 扩展 A
            (0x3400...0x4DBF).contains(scalar.value) ||
            // CJK 兼容汉字
            (0xF900...0xFAFF).contains(scalar.value) ||
            // 阿拉伯数字
            CharacterSet.decimalDigits.contains(scalar)
        }
        guard hasChineseOrDigit else { return false }

        return true
    }

    // MARK: - 计时器

    /// 重置短防抖定时器
    private func resetDebounceTimer() {
        debounceTimer?.invalidate()

        let debounceInterval = settings.translationDebounceInterval

        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.executeTranslation()
            }
        }
    }

    /// 重置段落超时定时器
    private func resetSegmentTimeoutTimer() {
        segmentTimeoutTimer?.invalidate()

        let segmentPauseThreshold = settings.segmentPauseThreshold

        segmentTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: segmentPauseThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endSegment()
            }
        }
    }

    /// 结束当前段落：清空缓冲，下次提交将开启新段落
    private func endSegment() {
        lock.lock()
        currentSegment = ""
        lastCommitTime = Date.distantPast
        lock.unlock()
    }

    // MARK: - 翻译执行

    /// 执行翻译
    private func executeTranslation() {
        lock.lock()
        let text = currentSegment
        lock.unlock()

        // 取消短防抖定时器
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard !text.isEmpty else { return }

        // 检查缓存
        if let cached = cache.get(text: text) {
            onTranslationReady?(text, cached)
            return
        }

        // 通知翻译开始
        onTranslationStart?(text)

        // 获取当前翻译模式
        let mode = TranslationMode(rawValue: settings.translationMode) ?? .fluent

        // 异步执行翻译
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await self.translator.translate(text: text, mode: mode)
                // 缓存结果
                self.cache.set(text: text, translation: result)
                // 回调主线程
                DispatchQueue.main.async {
                    self.onTranslationReady?(text, result)
                }
            } catch {
                // 翻译失败，静默处理（不弹窗打断用户）
                print("[TranslationScheduler] 翻译失败：\(error.localizedDescription)")
            }
        }
    }
}

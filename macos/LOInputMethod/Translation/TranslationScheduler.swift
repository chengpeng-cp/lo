import Foundation

// MARK: - 翻译调度器

/// 翻译调度器，负责段落管理、长停顿断句、防抖翻译和缓存
@MainActor
class TranslationScheduler {

    /// 单例
    /// init 保持为空，实际翻译器延迟到首次主线程访问时创建，
    /// 避免输入法控制器（非 @MainActor）引用 shared 时触发并发检查警告。
    nonisolated static let shared = TranslationScheduler()

    /// 翻译服务实例（延迟初始化，确保在主线程上创建）
    private lazy var translator: TranslationServiceProtocol = Self.createTranslator(for: LOSettings.load())

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

    /// 当前进行中的翻译任务，发起新翻译前取消旧任务，避免竞态
    private var currentTranslationTask: Task<Void, Never>?

    // MARK: - 回调

    /// 防抖期间静默更新原文（用于显示正在输入的原文）
    var onOriginalUpdate: ((String) -> Void)?

    /// 翻译开始（用于显示加载状态）
    var onTranslationStart: ((String) -> Void)?

    /// 翻译完成（原文, 译文）
    var onTranslationReady: ((String, String) -> Void)?

    /// 流式翻译增量（原文, 累积译文）：大模型边生成边更新悬浮窗，降低首字延迟
    /// 仅在启用流式翻译且引擎支持时触发；免费引擎一次性回调全量
    var onTranslationDelta: ((String, String) -> Void)?

    /// 翻译失败（原文, 错误信息）
    var onTranslationFailed: ((String, String) -> Void)?

    // MARK: - 初始化

    nonisolated private init() {
        // 保持为空：翻译器通过 lazy var 延迟到主线程首次访问时创建，
        // 避免 init 被 nonisolated(unsafe) shared 引用时触发 main actor 检查。
    }

    // MARK: - 公开接口

    /// 通知调度器用户正在输入（按键、组合输入中）。
    /// 用于刷新「段落超时」判定基准：用户输入拼音时并无 commit 事件产生，
    /// 但这段时间用户并未真的停顿，不应触发段落断句，否则前面已 commit 的数字/字母会被丢弃。
    /// - Parameter text: 当前组合输入的预编辑文本（可为空，仅表示有按键活动）
    func noteTyping(preedit: String = "") {
        // 翻译功能关闭时，不执行任何翻译逻辑
        guard settings.translationEnabled else { return }

        lock.lock()
        // 仅刷新时间基准与段落超时定时器，不改变 currentSegment
        lastCommitTime = Date()
        lock.unlock()

        // 重置段落超时定时器，避免输入拼音中途段落被截断
        resetSegmentTimeoutTimer()

        // 若用户已开始组合输入新内容，也重置短防抖定时器，确保最终翻译在输入停止后触发
        resetDebounceTimer()
    }

    /// 提交待翻译文本
    /// 会先判断是否需要开启新段落，然后启动防抖计时
    /// - Parameter text: 用户提交的文本
    func commit(text: String) {
        // 翻译功能关闭时，不执行任何翻译逻辑
        guard settings.translationEnabled else { return }

        lock.lock()

        let isSegmentEmpty = currentSegment.isEmpty
        // 空段落且文本无需翻译时直接跳过；非空段落则允许追加（如标点）
        guard !isSegmentEmpty || shouldTranslate(text) else {
            debugLog("[Scheduler] commit 跳过（无需翻译）: '\(text)'")
            lock.unlock()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastCommitTime)
        // 长停顿超过阈值，开启新段落
        if !isSegmentEmpty && elapsed > settings.segmentPauseThreshold {
            debugLog("[Scheduler] 段落超时重置: elapsed=\(elapsed)s threshold=\(settings.segmentPauseThreshold)s 旧段落='\(currentSegment)'")
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

        debugLog("[Scheduler] commit: '\(text)' → 段落='\(segmentToUpdate)'")

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

    /// 更新翻译服务（切换翻译提供商或模型时调用）
    func updateTranslator() {
        let settings = LOSettings.load()
        translator = Self.createTranslator(for: settings)
        // 预热连接：提前与当前翻译端点建立 TCP+TLS，后续请求可复用，减少首次翻译握手延迟
        Self.warmupConnection(for: settings)
    }

    /// 预热翻译端点连接
    /// 判断实际会使用的引擎：LLM 配置完整则预热 LLM 端点，否则预热 Bing 兜底端点
    private static func warmupConnection(for settings: LOSettings) {
        let provider = TranslationProvider.from(settings.translationProvider)
        let hasAPIKey = !(settings.getAPIKey(provider: provider.rawValue) ?? "").isEmpty
        let useLLM = !provider.isFree && hasAPIKey && !settings.translationModel.isEmpty

        let url: URL?
        if useLLM {
            if provider == .custom {
                url = URL(string: settings.customLLMBaseURL)
            } else {
                url = URL(string: provider.baseURL)
            }
        } else {
            // 免费引擎（Bing）预热 token 端点
            url = URL(string: "https://edge.microsoft.com/translate/auth")
        }
        guard let url = url else { return }
        TranslationNetwork.warmup(url: url)
    }

    // MARK: - 翻译器工厂

    /// 根据设置创建翻译器
    /// - LLM 提供商未配置 API Key 时，自动回退到必应免费翻译
    private static func createTranslator(for settings: LOSettings) -> TranslationServiceProtocol {
        let provider = TranslationProvider.from(settings.translationProvider)

        // 免费翻译引擎
        if provider == .bing {
            return BingTranslator()
        }

        // 大模型翻译：检查 API Key
        let apiKey = settings.getAPIKey(provider: provider.rawValue) ?? ""
        if apiKey.isEmpty {
            debugLog("[Scheduler] \(provider.rawValue) 未配置 API Key，回退到语境免费翻译")
            return BingTranslator()
        }

        // 检查模型名是否已配置
        let model = settings.translationModel
        if model.isEmpty {
            debugLog("[Scheduler] \(provider.rawValue) 未配置模型名，回退到必应免费翻译")
            return BingTranslator()
        }

        return LLMTranslator(provider: provider, model: model)
    }

    // MARK: - 文本过滤

    /// 判断文本是否需要翻译
    /// 过滤空文本、纯标点；包含非 ASCII 字符（中文、日文、韩文、西里尔文等）或数字才翻译。
    /// 纯 ASCII 英文不翻译（避免 ASCII 模式下输入英文触发无意义翻译）。
    private func shouldTranslate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空文本不翻译
        guard !trimmed.isEmpty else { return false }

        // 纯标点不翻译
        let punctuationSet = CharacterSet.punctuationCharacters
            .union(CharacterSet.whitespacesAndNewlines)
        let withoutPunctuation = trimmed.unicodeScalars.filter { !punctuationSet.contains($0) }
        guard !withoutPunctuation.isEmpty else { return false }

        // 包含非 ASCII 字符或数字才翻译
        let hasTranslatableChar = trimmed.unicodeScalars.contains { scalar in
            CharacterSet.decimalDigits.contains(scalar) || scalar.value > 0x7E
        }
        guard hasTranslatableChar else { return false }

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
            MainActor.assumeIsolated {
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

        debugLog("[Scheduler] 触发翻译: '\(text)' (长度=\(text.count))")

        // 获取当前翻译模式与目标语言
        let mode = TranslationMode(rawValue: settings.translationMode) ?? .fluent
        let targetLang = TargetLanguage(rawValue: settings.targetLanguage) ?? .english

        // 检查缓存
        if let cached = cache.get(text: text, targetLanguage: targetLang.rawValue) {
            debugLog("[Scheduler] 命中缓存")
            onTranslationReady?(text, cached)
            return
        }

        // 通知翻译开始
        onTranslationStart?(text)

        // 取消进行中的旧翻译任务，避免旧结果/错误覆盖当前状态
        currentTranslationTask?.cancel()

        // 大模型翻译默认走流式（边生成边显示），语境等传统机器翻译一次性返回
        let provider = TranslationProvider.from(settings.translationProvider)
        let useStream = !provider.isFree

        // 异步执行翻译
        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                let result: String
                if useStream {
                    // 流式：每个增量片段累积后回调 UI 实时更新悬浮窗
                    var accumulated = ""
                    result = try await self.translator.translateStream(
                        text: text,
                        mode: mode,
                        targetLanguage: targetLang
                    ) { [weak self] delta in
                        accumulated += delta
                        let snapshot = accumulated
                        DispatchQueue.main.async {
                            self?.onTranslationDelta?(text, snapshot)
                        }
                    }
                } else {
                    result = try await self.translator.translate(text: text, mode: mode, targetLanguage: targetLang)
                }

                // 任务被取消时不再回调（用户已输入新内容，旧结果无意义）
                if Task.isCancelled {
                    debugLog("[Scheduler] 翻译已取消（旧任务）: '\(text)'")
                    return
                }
                debugLog("[Scheduler] 翻译完成: '\(text)' → '\(result)'")
                // 缓存结果
                self.cache.set(text: text, translation: result, targetLanguage: targetLang.rawValue)
                // 回调主线程
                DispatchQueue.main.async {
                    self.onTranslationReady?(text, result)
                }
            } catch {
                // 任务被取消（包括 URLSession 取消错误）时不回调
                if Task.isCancelled {
                    debugLog("[Scheduler] 翻译已取消（旧任务，错误阶段）: '\(text)'")
                    return
                }
                // 翻译失败，通知 UI 更新（避免悬浮窗一直卡在 loading 状态）
                let errorMsg = error.localizedDescription
                debugLog("[Scheduler] 翻译失败: '\(text)' 错误: \(errorMsg)")
                print("[TranslationScheduler] 翻译失败：\(errorMsg)")
                DispatchQueue.main.async {
                    self.onTranslationFailed?(text, errorMsg)
                }
            }
        }
        currentTranslationTask = task
    }
}

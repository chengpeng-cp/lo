#include "TranslationScheduler.h"
#include "BingTranslator.h"
#include "LLMTranslator.h"
#include "TranslationCache.h"
#include "../core/Globals.h"
#include "../settings/Settings.h"
#include <thread>
#include <cwctype>

// ============================================================================
// 构造 / 析构
// ============================================================================

LOTranslationScheduler& LOTranslationScheduler::Shared() {
    static LOTranslationScheduler instance;
    return instance;
}

LOTranslationScheduler::LOTranslationScheduler() {
    InitializeCriticalSection(&m_cs);
    m_translator = CreateTranslator();
}

LOTranslationScheduler::~LOTranslationScheduler() {
    EnterCriticalSection(&m_cs);
    m_destroying = true;
    LeaveCriticalSection(&m_cs);

    // 非阻塞关闭定时器；回调会检测 m_destroying 后提前返回
    if (m_debounceTimer) {
        DeleteTimerQueueTimer(nullptr, m_debounceTimer, nullptr);
        m_debounceTimer = nullptr;
    }
    if (m_segmentTimer) {
        DeleteTimerQueueTimer(nullptr, m_segmentTimer, nullptr);
        m_segmentTimer = nullptr;
    }
    DeleteCriticalSection(&m_cs);
}

// ============================================================================
// 设置辅助
// ============================================================================

static LOTranslationMode ParseMode(const std::wstring& s) {
    if (s == L"native") return LOTranslationMode::Native;
    if (s == L"literal") return LOTranslationMode::Literal;
    return LOTranslationMode::Fluent;
}

// 是否为翻译失败标记（翻译器返回的错误信息以 "[翻译失败" 开头）
static bool IsFailureResult(const std::wstring& result) {
    if (result.empty()) return true;
    static const std::wstring kPrefix = L"[翻译失败";
    return result.size() >= kPrefix.size() &&
           result.compare(0, kPrefix.size(), kPrefix) == 0;
}

// ============================================================================
// 过滤：是否需要翻译
// ============================================================================

bool LOTranslationScheduler::ShouldTranslate(const std::wstring& text) {
    if (text.empty()) return false;

    bool hasNonAscii = false;
    int meaningful = 0; // 非标点/空白的字符数
    for (wchar_t c : text) {
        if (c >= 128) {
            hasNonAscii = true;
            ++meaningful;
        } else if (iswpunct(c) || iswspace(c)) {
            // 标点与空白不计入
        } else {
            ++meaningful;
        }
    }
    if (meaningful == 0) return false; // 纯标点/空白
    return hasNonAscii;                // 仅当包含非 ASCII 字符时翻译
}

// ============================================================================
// 工厂：创建翻译器
// ============================================================================

std::shared_ptr<LOTranslationService> LOTranslationScheduler::CreateTranslator() {
    const LOSettings& s = LOSettingsGet();
    if (!s.translationEnabled) {
        return nullptr;
    }

    const LOProviderConfig* cfg = LOFindProviderConfig(s.translationProvider);
    bool isFree = cfg && cfg->isFree;

    if (isFree || s.translationProvider == L"bing") {
        return std::make_shared<LOBingTranslator>();
    }

    // LLM 提供商
    auto llm = std::make_shared<LOLLMTranslator>(s.translationProvider, s.translationModel);
    if (llm->IsConfigured()) {
        return llm;
    }

    // 缺少 API 密钥或模型，回退到 Bing
    LOLog(L"[Scheduler] LLM 提供商 %s 未配置（密钥/模型），回退到 Bing\r\n", s.translationProvider.c_str());
    return std::make_shared<LOBingTranslator>();
}

void LOTranslationScheduler::UpdateTranslator() {
    EnterCriticalSection(&m_cs);
    m_translator = CreateTranslator();
    LeaveCriticalSection(&m_cs);
}

// ============================================================================
// 定时器管理
// ============================================================================

void LOTranslationScheduler::ResetDebounceTimer() {
    EnterCriticalSection(&m_cs);
    if (m_destroying) { LeaveCriticalSection(&m_cs); return; }

    if (m_debounceTimer) {
        DeleteTimerQueueTimer(nullptr, m_debounceTimer, nullptr);
        m_debounceTimer = nullptr;
    }
    DWORD ms = (DWORD)(LOSettingsGet().translationDebounceInterval * 1000.0);
    if (ms == 0) ms = 1;
    CreateTimerQueueTimer(&m_debounceTimer, nullptr, OnDebounceTimer, this,
                          ms, 0, WT_EXECUTEONLYONCE);
    LeaveCriticalSection(&m_cs);
}

void LOTranslationScheduler::ResetSegmentTimer() {
    EnterCriticalSection(&m_cs);
    if (m_destroying) { LeaveCriticalSection(&m_cs); return; }

    if (m_segmentTimer) {
        DeleteTimerQueueTimer(nullptr, m_segmentTimer, nullptr);
        m_segmentTimer = nullptr;
    }
    DWORD ms = (DWORD)(LOSettingsGet().segmentPauseThreshold * 1000.0);
    if (ms == 0) ms = 1;
    CreateTimerQueueTimer(&m_segmentTimer, nullptr, OnSegmentTimer, this,
                          ms, 0, WT_EXECUTEONLYONCE);
    LeaveCriticalSection(&m_cs);
}

void LOTranslationScheduler::CloseDebounceTimer() {
    EnterCriticalSection(&m_cs);
    if (m_debounceTimer) {
        DeleteTimerQueueTimer(nullptr, m_debounceTimer, nullptr);
        m_debounceTimer = nullptr;
    }
    LeaveCriticalSection(&m_cs);
}

void LOTranslationScheduler::CloseSegmentTimer() {
    EnterCriticalSection(&m_cs);
    if (m_segmentTimer) {
        DeleteTimerQueueTimer(nullptr, m_segmentTimer, nullptr);
        m_segmentTimer = nullptr;
    }
    LeaveCriticalSection(&m_cs);
}

// ============================================================================
// 定时器回调
// ============================================================================

void CALLBACK LOTranslationScheduler::OnDebounceTimer(void* ctx, BOOLEAN) {
    LOTranslationScheduler* self = static_cast<LOTranslationScheduler*>(ctx);
    if (self) self->FireDebounce();
}

void CALLBACK LOTranslationScheduler::OnSegmentTimer(void* ctx, BOOLEAN) {
    LOTranslationScheduler* self = static_cast<LOTranslationScheduler*>(ctx);
    if (self) self->FireSegmentTimeout();
}

// ============================================================================
// 防抖触发
// ============================================================================

void LOTranslationScheduler::FireDebounce() {
    EnterCriticalSection(&m_cs);
    if (m_destroying) { LeaveCriticalSection(&m_cs); return; }

    std::wstring segment = m_currentSegment;
    // 避免重复派发相同段落
    if (!segment.empty() && segment == m_lastDispatched) {
        LeaveCriticalSection(&m_cs);
        return;
    }
    m_lastDispatched = segment;

    ++m_taskId;
    uint64_t taskId = m_taskId;
    auto translator = m_translator;
    LeaveCriticalSection(&m_cs);

    if (segment.empty() || !translator) return;

    // 读取设置
    const LOSettings& s = LOSettingsGet();
    std::wstring targetLang = s.targetLanguage;
    LOTranslationMode mode = ParseMode(s.translationMode);

    LOLog(L"[Scheduler] 派发翻译任务 #%llu，段落长度=%zu\r\n",
          (unsigned long long)taskId, segment.size());

    // 启动工作线程
    std::thread(&LOTranslationScheduler::WorkerMain, this,
                segment, targetLang, mode, taskId, translator).detach();
}

// ============================================================================
// 段落超时
// ============================================================================

void LOTranslationScheduler::FireSegmentTimeout() {
    EnterCriticalSection(&m_cs);
    if (m_destroying) { LeaveCriticalSection(&m_cs); return; }
    std::wstring oldSegment = m_currentSegment;
    m_currentSegment.clear();
    m_lastDispatched.clear();
    // 使进行中的任务失效
    ++m_taskId;
    LeaveCriticalSection(&m_cs);

    if (!oldSegment.empty() && onOriginalUpdate) {
        onOriginalUpdate(L"");  // 通知 UI 清空原文
    }
    LOLog(L"[Scheduler] 段落超时，已清空\r\n");
}

// ============================================================================
// 公共方法
// ============================================================================

void LOTranslationScheduler::NoteTyping(const std::wstring& /*preedit*/) {
    // 用户正在输入预编辑文本：仅刷新段落超时定时器
    ResetSegmentTimer();
}

void LOTranslationScheduler::Commit(const std::wstring& text) {
    if (m_destroying) return;

    EnterCriticalSection(&m_cs);
    if (m_currentSegment.empty()) {
        m_currentSegment = text;
    } else {
        m_currentSegment += text;
    }
    std::wstring segment = m_currentSegment;
    LeaveCriticalSection(&m_cs);

    if (onOriginalUpdate) onOriginalUpdate(segment);

    ResetDebounceTimer();
    ResetSegmentTimer();
}

void LOTranslationScheduler::Reset() {
    CloseDebounceTimer();
    CloseSegmentTimer();

    EnterCriticalSection(&m_cs);
    m_currentSegment.clear();
    m_lastDispatched.clear();
    ++m_taskId;  // 使进行中的任务失效
    LeaveCriticalSection(&m_cs);
}

// ============================================================================
// 工作线程
// ============================================================================

void LOTranslationScheduler::WorkerMain(std::wstring segment,
                                         std::wstring targetLang,
                                         LOTranslationMode mode,
                                         uint64_t taskId,
                                         std::shared_ptr<LOTranslationService> translator) {
    // 过滤
    if (!ShouldTranslate(segment)) {
        return;
    }

    // 检查是否过期
    auto isStale = [&]() -> bool {
        EnterCriticalSection(&m_cs);
        bool stale = (m_destroying || m_taskId != taskId);
        LeaveCriticalSection(&m_cs);
        return stale;
    };

    if (isStale()) return;

    // 缓存命中检查
    std::wstring cached = LOTranslationCache::Shared().Get(segment, targetLang);
    if (!cached.empty() && !IsFailureResult(cached)) {
        if (isStale()) return;
        if (onTranslationStart) onTranslationStart(segment);
        if (onTranslationReady) onTranslationReady(segment, cached);
        LOLog(L"[Scheduler] 命中缓存，任务 #%llu\r\n", (unsigned long long)taskId);
        return;
    }

    if (isStale()) return;
    if (onTranslationStart) onTranslationStart(segment);

    std::wstring result;

    if (translator->SupportsStream()) {
        result = translator->TranslateStream(segment, mode, targetLang,
            [&](const std::wstring& delta) {
                if (isStale()) return;
                if (onTranslationDelta) onTranslationDelta(segment, delta);
            });
    } else {
        result = translator->Translate(segment, mode, targetLang);
    }

    if (isStale()) return;

    if (IsFailureResult(result)) {
        if (onTranslationFailed) {
            onTranslationFailed(segment, result.empty() ? L"翻译失败：未获得结果" : result);
        }
        LOLog(L"[Scheduler] 翻译失败，任务 #%llu\r\n", (unsigned long long)taskId);
        return;
    }

    // 写入缓存
    LOTranslationCache::Shared().Set(segment, result, targetLang);

    // 最终结果（流式已通过 onTranslationDelta 推送累计内容，仍发送一次 Ready 以标识完成）
    if (onTranslationReady) onTranslationReady(segment, result);
    LOLog(L"[Scheduler] 翻译完成，任务 #%llu，结果长度=%zu\r\n",
          (unsigned long long)taskId, result.size());
}

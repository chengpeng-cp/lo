#pragma once

#include "../core/Globals.h"
#include "TranslationService.h"
#include <windows.h>
#include <string>
#include <functional>
#include <memory>
#include <cstdint>

// ============================================================================
// 翻译调度器
//   - 累积已上屏文本到当前段落
//   - 防抖定时器（translationDebounceInterval）：用户停止上屏后触发翻译
//   - 段落定时器（segmentPauseThreshold）：用户无任何输入超时后清空段落
//   - 工作线程异步执行翻译，通过序号丢弃过期结果
//   - 工厂按设置创建 Bing（免费）或 LLM 翻译器
//   - 回调在工作线程触发，UI 层负责 marshal 到 UI 线程
// ============================================================================

class LOTranslationScheduler {
public:
    static LOTranslationScheduler& Shared();

    // --- 回调 ---
    std::function<void(const std::wstring&)> onOriginalUpdate;       // 原文更新（段落变化）
    std::function<void(const std::wstring&)> onTranslationStart;     // 翻译开始（原文）
    std::function<void(const std::wstring&, const std::wstring&)> onTranslationDelta;  // 流式增量（原文, 累计译文）
    std::function<void(const std::wstring&, const std::wstring&)> onTranslationReady;  // 翻译完成（原文, 译文）
    std::function<void(const std::wstring&, const std::wstring&)> onTranslationFailed;  // 翻译失败（原文, 错误）

    // 用户正在输入预编辑文本（刷新段落超时）
    void NoteTyping(const std::wstring& preedit);

    // 上屏文本：追加到当前段落，并启动/重置防抖定时器
    void Commit(const std::wstring& text);

    // 清空状态（段落、定时器）
    void Reset();

    // 根据当前设置重建翻译器
    void UpdateTranslator();

private:
    LOTranslationScheduler();
    ~LOTranslationScheduler();
    LOTranslationScheduler(const LOTranslationScheduler&) = delete;
    LOTranslationScheduler& operator=(const LOTranslationScheduler&) = delete;

    // 定时器回调（静态，转发到实例）
    static void CALLBACK OnDebounceTimer(void* ctx, BOOLEAN /*timerOrWait*/);
    static void CALLBACK OnSegmentTimer(void* ctx, BOOLEAN /*timerOrWait*/);

    // 防抖触发：快照段落并启动工作线程
    void FireDebounce();
    // 段落超时：清空段落
    void FireSegmentTimeout();
    // 工作线程入口
    void WorkerMain(std::wstring segment, std::wstring targetLang,
                    LOTranslationMode mode, uint64_t taskId,
                    std::shared_ptr<LOTranslationService> translator);

    // 创建翻译器（工厂）
    std::shared_ptr<LOTranslationService> CreateTranslator();

    // 重置防抖定时器
    void ResetDebounceTimer();
    // 重置段落定时器
    void ResetSegmentTimer();
    // 关闭并清理定时器句柄
    void CloseDebounceTimer();
    void CloseSegmentTimer();

    // 是否需要翻译（过滤空文本、纯标点、纯 ASCII）
    static bool ShouldTranslate(const std::wstring& text);

    // 锁保护的成员
    CRITICAL_SECTION m_cs;
    std::wstring m_currentSegment;          // 当前累积段落
    std::wstring m_lastDispatched;          // 上次已派发的段落（避免重复派发）
    uint64_t m_taskId = 0;                  // 当前任务序号
    std::shared_ptr<LOTranslationService> m_translator;

    // 定时器句柄
    HANDLE m_debounceTimer = nullptr;
    HANDLE m_segmentTimer = nullptr;
    bool m_destroying = false;
};

#pragma once

#include "../core/Globals.h"
#include "../settings/Settings.h"
#include <functional>
#include <string>
#include <mutex>
#include <atomic>

// ============================================================================
// LOTranslationOverlay - 翻译结果悬浮窗
//
// 显示原文 + 译文，支持加载/结果/错误三种状态、自动消失（淡出）、
// 三种定位模式（fixed / draggable / followCursor）、点击穿透（仅复制按钮可点）、
// 译文超长滚动。使用 UpdateLayeredWindow 逐像素 alpha，GDI 渲染到 32 位 DIB。
//
// 线程模型：Shared() 单例。窗口在构造时于 UI 线程创建——务必在 UI 线程
// 首次访问 Shared()（例如 TextService::Activate 中调用一次）以保证窗口
// 绑定到 UI 线程。Show*/Hide/Update*/UpdateConfig 等公共方法可在任意线程
// 调用，内部通过加锁 + PostMessage 转发到 UI 线程执行。
// ============================================================================

class LOTranslationOverlay {
public:
    static LOTranslationOverlay& Shared();
    ~LOTranslationOverlay();

    LOTranslationOverlay(const LOTranslationOverlay&) = delete;
    LOTranslationOverlay& operator=(const LOTranslationOverlay&) = delete;

    // --- 显示状态 ---
    void ShowLoading(const std::wstring& originalText);
    void Show(const std::wstring& original, const std::wstring& translation);
    void ShowError(const std::wstring& original, const std::wstring& error);

    // 无闪烁更新原文（不重启动画，仅重绘）
    void SilentUpdateOriginal(const std::wstring& text);

    // 流式更新译文（在 ShowLoading 后持续追加/替换）
    void UpdateTranslation(const std::wstring& text);

    void Hide();

    // 复制最近一次译文到剪贴板，成功返回 true
    bool CopyLastTranslation();

    // 重新加载设置并应用
    void UpdateConfig();

    // 提供 followCursor 模式下的光标区域（屏幕坐标）
    void SetCursorPositionProvider(std::function<RECT()> provider);

private:
    LOTranslationOverlay();

    // --- 窗口过程 ---
    static LRESULT CALLBACK WndProcStatic(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
    LRESULT WndProc(UINT msg, WPARAM wp, LPARAM lp);

    void EnsureRegistered();
    void CreateWindowInternal();

    // --- 渲染（UI 线程）---
    void Render();
    void ComputeLayout();   // 测量并计算各区域矩形与窗口尺寸
    void ComputePosition(); // 依据定位模式计算窗口位置

    // 从设置读取配置快照（UI 线程）
    void ApplyConfig();

    // --- 计时器 ---
    void ArmDismissTimer();
    void StopDismissTimer();
    void StartFadeOut();
    void StopFadeTimer();
    void OnDismissTick();
    void OnFadeTick();

    // --- 复制 / 拖拽 / 滚动 ---
    bool IsOverCopyButton(POINT clientPt) const;
    void StartDrag(POINT screenPt);
    void UpdateDrag(POINT screenPt);
    void EndDrag();

    // --- 消息处理（UI 线程）---
    void HandleShowLoading();
    void HandleShow();
    void HandleShowError();
    void HandleSilentUpdateOriginal();
    void HandleUpdateTranslation();

    HWND m_hwnd = nullptr;

    // --- GDI 缓存 ---
    HDC     m_hdcMem = nullptr;
    HBITMAP m_hbmp = nullptr;
    HBITMAP m_hbmpOld = nullptr;
    void*   m_bits = nullptr;
    int     m_bmpW = 0;
    int     m_bmpH = 0;

    // --- 状态（UI 线程）---
    enum class State { Hidden, Loading, Result, Error };
    State m_state = State::Hidden;
    std::wstring m_original;
    std::wstring m_translation;
    std::wstring m_errorText;
    std::wstring m_lastTranslation;  // 供复制使用

    // --- 布局（UI 线程）---
    int m_windowW = 0;
    int m_windowH = 0;
    RECT m_origRect    = {};   // 原文绘制区
    RECT m_transRect   = {};   // 译文可见区
    int  m_transFullH   = 0;    // 译文完整高度
    int  m_transScroll  = 0;   // 译文滚动偏移
    int  m_maxTransScroll = 0;
    RECT m_copyBtnRect = {};   // 复制按钮区（客户坐标）

    // --- 配置快照（UI 线程）---
    COLORREF m_bgColor        = RGB(30, 30, 30);
    COLORREF m_origColor      = RGB(0x99, 0x99, 0x99);
    COLORREF m_transColor     = RGB(255, 255, 255);
    COLORREF m_labelColor     = RGB(120, 120, 120);
    double   m_opacity        = 0.85;
    std::wstring m_posMode    = L"draggable";
    bool     m_clickThrough   = false;
    bool     m_showOrigLabel  = true;
    bool     m_showTransLabel = true;
    int      m_maxWidth       = 360;
    int      m_maxHeight      = 200;
    int      m_origFontSize   = 14;
    int      m_transFontSize  = 14;
    double   m_dismissInterval = 5.0;

    // --- 计时器 ---
    UINT_PTR m_dismissTimer = 0;
    UINT_PTR m_fadeTimer    = 0;
    double   m_fadeAlpha    = 1.0;   // 淡出进度 1=完全显示

    // --- 拖拽 ---
    bool  m_dragging  = false;
    POINT m_dragOffset = {};

    // --- 光标位置提供者 ---
    std::function<RECT()> m_cursorProvider;

    // --- 跨线程待处理数据 ---
    std::mutex m_dataMutex;
    std::wstring m_pendingOriginal;
    std::wstring m_pendingTranslation;
    std::wstring m_pendingError;

    bool m_classRegistered = false;
};

// 计时器 ID
constexpr UINT_PTR kDismissTimerId = 9001;
constexpr UINT_PTR kFadeTimerId    = 9002;

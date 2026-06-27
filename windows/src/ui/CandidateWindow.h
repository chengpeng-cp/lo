#pragma once

#include "../core/Globals.h"
#include <msctf.h>
#include <functional>
#include <vector>
#include <mutex>
#include <atomic>

// ============================================================================
// LOCandidateWindow - 候选词浮动窗口
//
// 水平排列的编号候选词（1.候选词 2.候选词 ...），无边框、圆角、半透明深色背景。
// 使用 UpdateLayeredWindow 实现逐像素 alpha 混合，GDI 渲染到 32 位 DIB。
//
// 线程模型：构造函数在 UI 线程创建窗口；Show/Hide/SetHighlight 可在任意线程
// 调用，内部通过 PostMessage 转发到窗口所在 UI 线程执行。NavigateByArrow
// 假定在 UI 线程调用（按键处理在 UI 线程）。
// ============================================================================

class LOCandidateWindow {
public:
    LOCandidateWindow();
    ~LOCandidateWindow();

    LOCandidateWindow(const LOCandidateWindow&) = delete;
    LOCandidateWindow& operator=(const LOCandidateWindow&) = delete;

    // 在光标附近显示候选词列表（pContext 用于定位光标，可为 nullptr）
    void Show(const std::vector<LOCandidate>& candidates, ITfContext* pContext);

    // 隐藏窗口
    void Hide();

    // 当前是否可见
    bool IsVisible() const { return m_visible.load(); }

    // 当前高亮索引（无高亮返回 -1）
    int GetSelectedIndex() const { return m_selectedIndex.load(); }

    // 设置高亮候选
    void SetHighlight(int index);

    // 方向键导航。forward=true 下一个，false 上一个；
    // 到达边界时触发翻页回调并返回 true。
    bool NavigateByArrow(bool forward);

    // --- 回调 ---
    std::function<void(int)>  onCandidateSelected;  // 选中某候选（index）
    std::function<void(bool)> onPageChange;         // backward=true 上一页

private:
    // 窗口过程
    static LRESULT CALLBACK WndProcStatic(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
    LRESULT WndProc(UINT msg, WPARAM wp, LPARAM lp);

    void EnsureRegistered();
    void CreateWindowInternal();

    // 渲染（UI 线程）
    void Render();
    void UpdateLayout();   // 测量候选词并计算各项矩形
    void PositionNearCursor(ITfContext* pContext);

    // 点击命中测试（x 为窗口坐标）
    int HitTestCandidate(int x) const;

    // 消息处理（UI 线程）
    void HandleShow();
    void HandleHide();
    void HandleSetHighlight(int index);

    HWND m_hwnd = nullptr;

    std::atomic<bool> m_visible{false};
    std::atomic<int>  m_selectedIndex{-1};

    // 候选词与布局（仅 UI 线程访问）
    std::vector<LOCandidate> m_candidates;

    struct ItemRect { int x = 0; int width = 0; };
    std::vector<ItemRect> m_itemRects;
    int m_contentWidth = 0;
    int m_contentHeight = 0;
    int m_windowWidth = 0;
    int m_windowHeight = 0;

    // GDI 资源（缓存）
    HDC     m_hdcMem = nullptr;
    HBITMAP m_hbmp = nullptr;
    HBITMAP m_hbmpOld = nullptr;
    void*   m_bits = nullptr;
    int     m_bmpW = 0;
    int     m_bmpH = 0;

    // 跨线程待处理数据
    std::mutex m_dataMutex;
    std::vector<LOCandidate> m_pendingCandidates;
    ITfContext* m_pendingContext = nullptr;  // 不 AddRef，仅作定位提示
    int m_pendingHighlight = 0;

    bool m_classRegistered = false;
};

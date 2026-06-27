#include "CandidateWindow.h"
#include "DPIUtils.h"
#include <windowsx.h>
#include <algorithm>
#include <cmath>

// 自定义消息（跨线程转发）
namespace {
    const UINT kMsgShow         = WM_USER + 1;
    const UINT kMsgHide         = WM_USER + 2;
    const UINT kMsgSetHighlight = WM_USER + 3;

    const wchar_t* kClassName = L"LOCandidateWindowClass";

    // 视觉常量（逻辑像素，96 DPI 基准；渲染时按 DPI 缩放）
    const int    kPadding          = 8;     // 内边距
    const int    kItemInnerGap     = 4;     // 序号与文本间距
    const int    kSeparatorGap     = 6;    // 分隔线两侧间距
    const int    kIndexFontSize    = 13;   // 序号字号
    const int    kTextFontSize     = 16;   // 候选词字号
    const int    kCornerRadius     = 6;    // 圆角半径
    const int    kUnderlineHeight  = 2;     // 高亮下划线高度
    const int    kCursorOffsetY    = 4;    // 距光标的垂直偏移

    const double kBgOpacity = 0.95;        // 背景不透明度

    const COLORREF kBgColor        = RGB(38, 38, 38);
    const COLORREF kTextColor      = RGB(255, 255, 255);
    const COLORREF kIndexColor     = RGB(150, 150, 150);
    const COLORREF kHighlightColor = RGB(0, 120, 215);   // 蓝色下划线
    const COLORREF kSeparatorColor = RGB(90, 90, 90);   // 半透明分隔线（相对暗背景）
}

// ============================================================================
// 构造 / 析构
// ============================================================================

LOCandidateWindow::LOCandidateWindow() {
    EnsureRegistered();
    CreateWindowInternal();
}

LOCandidateWindow::~LOCandidateWindow() {
    if (m_hwnd) {
        DestroyWindow(m_hwnd);
        m_hwnd = nullptr;
    }
    if (m_hbmpOld && m_hdcMem) {
        SelectObject(m_hdcMem, m_hbmpOld);
    }
    if (m_hbmp) DeleteObject(m_hbmp);
    if (m_hdcMem) DeleteDC(m_hdcMem);
}

// ============================================================================
// 窗口类注册与创建
// ============================================================================

void LOCandidateWindow::EnsureRegistered() {
    if (m_classRegistered) return;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &LOCandidateWindow::WndProcStatic;
    wc.hInstance = g_hInstance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;

    ATOM atom = RegisterClassExW(&wc);
    if (atom || GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
        m_classRegistered = true;
    }
}

void LOCandidateWindow::CreateWindowInternal() {
    DWORD exStyle = WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE;
    DWORD style = WS_POPUP;

    m_hwnd = CreateWindowExW(exStyle, kClassName, L"", style,
        CW_USEDEFAULT, CW_USEDEFAULT, 0, 0,
        nullptr, nullptr, g_hInstance, this);
    // CreateWindowEx 在 WM_NCCREATE 之前将 lpParam 传给 CREATESTRUCT，
    // WndProcStatic 在 WM_NCCREATE 时通过 SetWindowLongPtr(GWLP_USERDATA) 记录 this。
}

// ============================================================================
// 窗口过程
// ============================================================================

LRESULT CALLBACK LOCandidateWindow::WndProcStatic(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    LOCandidateWindow* self = nullptr;

    if (msg == WM_NCCREATE) {
        auto cs = reinterpret_cast<CREATESTRUCT*>(lp);
        self = reinterpret_cast<LOCandidateWindow*>(cs->lpCreateParams);
        SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    } else {
        self = reinterpret_cast<LOCandidateWindow*>(
            GetWindowLongPtr(hwnd, GWLP_USERDATA));
    }

    if (self) {
        return self->WndProc(msg, wp, lp);
    }
    return DefWindowProc(hwnd, msg, wp, lp);
}

LRESULT LOCandidateWindow::WndProc(UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case kMsgShow:
        HandleShow();
        return 0;
    case kMsgHide:
        HandleHide();
        return 0;
    case kMsgSetHighlight:
        HandleSetHighlight((int)wp);
        return 0;
    case WM_LBUTTONDOWN: {
        int x = GET_X_LPARAM(lp);
        int idx = HitTestCandidate(x);
        if (idx >= 0) {
            m_selectedIndex = idx;
            if (onCandidateSelected) onCandidateSelected(idx);
        }
        return 0;
    }
    case WM_DESTROY:
        // GDI 资源由析构函数释放，这里不置空以免跳过释放
        return 0;
    default:
        return DefWindowProc(m_hwnd, msg, wp, lp);
    }
}

// ============================================================================
// 公共方法
// ============================================================================

void LOCandidateWindow::Show(const std::vector<LOCandidate>& candidates, ITfContext* pContext) {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_pendingCandidates = candidates;
        m_pendingContext = pContext;
        m_pendingHighlight = 0;
    }
    if (m_hwnd) PostMessage(m_hwnd, kMsgShow, 0, 0);
}

void LOCandidateWindow::Hide() {
    if (m_hwnd) PostMessage(m_hwnd, kMsgHide, 0, 0);
}

void LOCandidateWindow::SetHighlight(int index) {
    if (m_hwnd) PostMessage(m_hwnd, kMsgSetHighlight, (WPARAM)index, 0);
}

bool LOCandidateWindow::NavigateByArrow(bool forward) {
    // 假定在 UI 线程调用（按键处理在 UI 线程）
    if (m_candidates.empty()) return false;

    int count = static_cast<int>(m_candidates.size());
    int cur = m_selectedIndex.load();
    if (cur < 0 || cur >= count) cur = 0;

    if (forward) {
        if (cur + 1 >= count) {
            // 触发下一页（backward=false）
            if (onPageChange) onPageChange(false);
            return true;
        }
        cur++;
    } else {
        if (cur - 1 < 0) {
            // 触发上一页（backward=true）
            if (onPageChange) onPageChange(true);
            return true;
        }
        cur--;
    }

    m_selectedIndex = cur;
    Render();
    return false;
}

// ============================================================================
// 消息处理（UI 线程）
// ============================================================================

void LOCandidateWindow::HandleShow() {
    ITfContext* ctxForPosition = nullptr;
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_candidates = std::move(m_pendingCandidates);
        m_pendingCandidates.clear();
        ctxForPosition = m_pendingContext;  // 仅作定位提示，不持有引用
    }
    if (m_candidates.empty()) {
        HandleHide();
        return;
    }

    int highlight = m_pendingHighlight;
    if (highlight < 0) highlight = 0;
    if (highlight >= (int)m_candidates.size()) highlight = (int)m_candidates.size() - 1;
    m_selectedIndex = highlight;

    UpdateLayout();
    PositionNearCursor(ctxForPosition);
    Render();

    if (!m_visible.load()) {
        ShowWindow(m_hwnd, SW_SHOWNOACTIVATE);
        m_visible = true;
    }
}

void LOCandidateWindow::HandleHide() {
    if (m_visible.load()) {
        ShowWindow(m_hwnd, SW_HIDE);
        m_visible = false;
    }
}

void LOCandidateWindow::HandleSetHighlight(int index) {
    if (index < 0) index = 0;
    if (index >= (int)m_candidates.size()) index = (int)m_candidates.size() - 1;
    m_selectedIndex = index;
    if (m_visible.load()) Render();
}

// ============================================================================
// 布局：测量候选词，计算每项的 x 范围与窗口尺寸
// ============================================================================

void LOCandidateWindow::UpdateLayout() {
    m_itemRects.clear();
    m_contentWidth = 0;
    m_contentHeight = 0;

    if (m_candidates.empty()) return;

    HDC hdcScreen = GetDC(nullptr);
    if (!hdcScreen) return;

    int idxSize = ScaleY(m_hwnd, kIndexFontSize);
    int txtSize = ScaleY(m_hwnd, kTextFontSize);

    HFONT hIdxFont = CreateFontW(-idxSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT hTxtFont = CreateFontW(-txtSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");

    HGDIOBJ oldFont = SelectObject(hdcScreen, hTxtFont);

    int innerGap = ScaleX(m_hwnd, kItemInnerGap);
    int sepGap = ScaleX(m_hwnd, kSeparatorGap);

    int textH = 0, idxH = 0;
    int x = 0;

    for (size_t i = 0; i < m_candidates.size(); i++) {
        // 序号 "N."
        std::wstring idxStr = std::to_wstring(i + 1) + L".";

        SIZE idxSz = {0, 0};
        SelectObject(hdcScreen, hIdxFont);
        GetTextExtentPoint32W(hdcScreen, idxStr.c_str(), (int)idxStr.size(), &idxSz);

        SIZE txtSz = {0, 0};
        SelectObject(hdcScreen, hTxtFont);
        GetTextExtentPoint32W(hdcScreen, m_candidates[i].text.c_str(),
            (int)m_candidates[i].text.size(), &txtSz);

        int itemW = idxSz.cx + innerGap + txtSz.cx;

        m_itemRects.push_back({x, itemW});
        x += itemW;

        if (i + 1 < m_candidates.size()) {
            // 项间留出分隔线空间
            x += sepGap + 1 + sepGap;  // 分隔线 1px + 两侧间距
        }

        if (idxSz.cy > idxH) idxH = idxSz.cy;
        if (txtSz.cy > textH) textH = txtSz.cy;
    }

    m_contentWidth = x;
    m_contentHeight = (textH > idxH ? textH : idxH);

    int pad = ScaleX(m_hwnd, kPadding);
    int underline = ScaleY(m_hwnd, kUnderlineHeight);

    m_windowWidth = m_contentWidth + pad * 2;
    m_windowHeight = m_contentHeight + pad * 2 + underline;

    SelectObject(hdcScreen, oldFont);
    DeleteObject(hIdxFont);
    DeleteObject(hTxtFont);
    ReleaseDC(nullptr, hdcScreen);
}

// ============================================================================
// 定位：靠近光标
// ============================================================================

void LOCandidateWindow::PositionNearCursor(ITfContext* pContext) {
    POINT pt = {0, 0};
    bool got = false;
    HWND hTarget = nullptr;

    // 优先通过 ITfContext::GetActiveView 获取上下文窗口
    if (pContext) {
        ITfContextView* view = nullptr;
        if (SUCCEEDED(pContext->GetActiveView(&view)) && view) {
            view->GetWnd(&hTarget);
            view->Release();
        }
    }

    // 尝试 GetCaretPos（拥有插入符的聚焦控件更准确，回退到文档窗口）
    if (!got) {
        POINT cp = {0, 0};
        HWND hCaret = GetFocus();
        if (!hCaret) hCaret = hTarget;
        if (hCaret && GetCaretPos(&cp) && (cp.x != 0 || cp.y != 0)) {
            pt = cp;
            ClientToScreen(hCaret, &pt);
            got = true;
        }
    }

    // 回退：当前鼠标位置
    if (!got) {
        GetCursorPos(&pt);
    }

    int offY = ScaleY(m_hwnd, kCursorOffsetY);
    int x = pt.x;
    int y = pt.y + offY;

    // 限制在显示器工作区内
    MONITORINFO mi = {sizeof(mi)};
    HMONITOR hMon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
    if (GetMonitorInfoW(hMon, &mi)) {
        if (x + m_windowWidth > mi.rcWork.right) {
            x = mi.rcWork.right - m_windowWidth;
        }
        if (x < mi.rcWork.left) x = mi.rcWork.left;
        if (y + m_windowHeight > mi.rcWork.bottom) {
            // 放到光标上方
            y = pt.y - offY - m_windowHeight;
        }
        if (y < mi.rcWork.top) y = mi.rcWork.top;
    }

    SetWindowPos(m_hwnd, nullptr, x, y, 0, 0,
        SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER);
}

// ============================================================================
// 命中测试
// ============================================================================

int LOCandidateWindow::HitTestCandidate(int x) const {
    int pad = ScaleX(m_hwnd, kPadding);
    int relX = x - pad;
    if (relX < 0 || relX > m_contentWidth) return -1;

    for (size_t i = 0; i < m_itemRects.size(); i++) {
        if (relX >= m_itemRects[i].x &&
            relX < m_itemRects[i].x + m_itemRects[i].width) {
            return (int)i;
        }
    }
    return -1;
}

// ============================================================================
// 渲染
// ============================================================================

namespace {
    // 计算像素 (px,py) 在圆角矩形 [0,W)x[0,H) 内的覆盖度（0..1）
    double CornerCoverage(int px, int py, int W, int H, int r) {
        if (r <= 0) return 1.0;
        double cx = 0.0, cy = 0.0;
        bool inCorner = false;

        if (px < r && py < r) { cx = r; cy = r; inCorner = true; }
        else if (px >= W - r && py < r) { cx = W - r; cy = r; inCorner = true; }
        else if (px < r && py >= H - r) { cx = r; cy = H - r; inCorner = true; }
        else if (px >= W - r && py >= H - r) { cx = W - r; cy = H - r; inCorner = true; }

        if (!inCorner) return 1.0;

        double dx = (px + 0.5) - cx;
        double dy = (py + 0.5) - cy;
        double d = sqrt(dx * dx + dy * dy);
        double cov = (double)r + 0.5 - d;
        if (cov < 0.0) cov = 0.0;
        if (cov > 1.0) cov = 1.0;
        return cov;
    }
}

void LOCandidateWindow::Render() {
    if (!m_hwnd || m_windowWidth <= 0 || m_windowHeight <= 0) return;

    // 按需（重新）创建 DIB
    if (!m_hdcMem) {
        m_hdcMem = CreateCompatibleDC(nullptr);
    }
    if (m_bmpW != m_windowWidth || m_bmpH != m_windowHeight || !m_hbmp) {
        if (m_hbmpOld && m_hdcMem) {
            SelectObject(m_hdcMem, m_hbmpOld);
            m_hbmpOld = nullptr;
        }
        if (m_hbmp) { DeleteObject(m_hbmp); m_hbmp = nullptr; }

        BITMAPINFO bmi = {};
        bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = m_windowWidth;
        bmi.bmiHeader.biHeight = -m_windowHeight;  // top-down
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        m_hbmp = CreateDIBSection(nullptr, &bmi, DIB_RGB_COLORS, &m_bits, nullptr, 0);
        if (m_hbmp && m_hdcMem) {
            m_hbmpOld = (HBITMAP)SelectObject(m_hdcMem, m_hbmp);
        }
        m_bmpW = m_windowWidth;
        m_bmpH = m_windowHeight;
    }

    if (!m_hdcMem || !m_hbmp) return;

    // --- 1. 用不透明背景色填充整个 DIB（alpha=255，便于 GDI 文本抗锯齿混合）---
    {
        BYTE* p = (BYTE*)m_bits;
        BYTE b = GetBValue(kBgColor);
        BYTE g = GetGValue(kBgColor);
        BYTE r = GetRValue(kBgColor);
        int total = m_windowWidth * m_windowHeight;
        for (int i = 0; i < total; i++) {
            p[i * 4 + 0] = b;
            p[i * 4 + 1] = g;
            p[i * 4 + 2] = r;
            p[i * 4 + 3] = 255;
        }
    }

    // --- 2. GDI 绘制文本、分隔线、高亮下划线（全部不透明，alpha 保持 255）---
    int pad = ScaleX(m_hwnd, kPadding);
    int idxSize = ScaleY(m_hwnd, kIndexFontSize);
    int txtSize = ScaleY(m_hwnd, kTextFontSize);
    int innerGap = ScaleX(m_hwnd, kItemInnerGap);
    int sepGap = ScaleX(m_hwnd, kSeparatorGap);
    int underline = ScaleY(m_hwnd, kUnderlineHeight);

    HFONT hIdxFont = CreateFontW(-idxSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT hTxtFont = CreateFontW(-txtSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");

    SetBkMode(m_hdcMem, TRANSPARENT);

    int selected = m_selectedIndex.load();
    int textBottom = pad + m_contentHeight;

    // 高亮下划线（在文本下方）
    if (selected >= 0 && selected < (int)m_itemRects.size()) {
        HBRUSH hbr = CreateSolidBrush(kHighlightColor);
        RECT ur;
        ur.left = pad + m_itemRects[selected].x;
        ur.right = ur.left + m_itemRects[selected].width;
        ur.top = textBottom + 1;
        ur.bottom = ur.top + underline;
        FillRect(m_hdcMem, &ur, hbr);
        DeleteObject(hbr);
    }

    // 分隔线（项之间）
    HBRUSH hSep = CreateSolidBrush(kSeparatorColor);
    for (size_t i = 0; i + 1 < m_itemRects.size(); i++) {
        int itemEnd = pad + m_itemRects[i].x + m_itemRects[i].width;
        int sepX = itemEnd + sepGap;
        RECT sr;
        sr.left = sepX;
        sr.right = sepX + 1;
        sr.top = pad + 2;
        sr.bottom = pad + m_contentHeight - 2;
        FillRect(m_hdcMem, &sr, hSep);
    }
    DeleteObject(hSep);

    // 候选项文本
    for (size_t i = 0; i < m_candidates.size(); i++) {
        std::wstring idxStr = std::to_wstring(i + 1) + L".";

        // 序号
        SelectObject(m_hdcMem, hIdxFont);
        SetTextColor(m_hdcMem, kIndexColor);
        SIZE idxSz = {0, 0};
        GetTextExtentPoint32W(m_hdcMem, idxStr.c_str(), (int)idxStr.size(), &idxSz);
        int idxY = pad + (m_contentHeight - idxSz.cy) / 2;
        RECT idxRect;
        idxRect.left = pad + m_itemRects[i].x;
        idxRect.right = idxRect.left + idxSz.cx;
        idxRect.top = idxY;
        idxRect.bottom = idxY + idxSz.cy;
        DrawTextW(m_hdcMem, idxStr.c_str(), (int)idxStr.size(), &idxRect,
            DT_LEFT | DT_SINGLELINE | DT_VCENTER);

        // 候选词
        SelectObject(m_hdcMem, hTxtFont);
        SetTextColor(m_hdcMem, kTextColor);
        RECT txtRect;
        txtRect.left = pad + m_itemRects[i].x + idxSz.cx + innerGap;
        txtRect.right = txtRect.left + (m_itemRects[i].width - idxSz.cx - innerGap);
        txtRect.top = pad;
        txtRect.bottom = pad + m_contentHeight;
        DrawTextW(m_hdcMem, m_candidates[i].text.c_str(),
            (int)m_candidates[i].text.size(), &txtRect,
            DT_LEFT | DT_SINGLELINE | DT_VCENTER);
    }

    DeleteObject(hIdxFont);
    DeleteObject(hTxtFont);

    // --- 3. 后处理：应用圆角覆盖度 + 整体不透明度，并做预乘 alpha ---
    {
        BYTE* p = (BYTE*)m_bits;
        int W = m_windowWidth;
        int H = m_windowHeight;
        int r = ScaleX(m_hwnd, kCornerRadius);
        if (r > W / 2) r = W / 2;
        if (r > H / 2) r = H / 2;
        int bgAlpha = (int)(kBgOpacity * 255.0 + 0.5);

        for (int y = 0; y < H; y++) {
            for (int x = 0; x < W; x++) {
                double cov = CornerCoverage(x, y, W, H, r);
                int a = (int)(cov * bgAlpha + 0.5);
                BYTE* px = p + (y * W + x) * 4;
                // 预乘 alpha
                px[0] = (BYTE)((int)px[0] * a / 255);
                px[1] = (BYTE)((int)px[1] * a / 255);
                px[2] = (BYTE)((int)px[2] * a / 255);
                px[3] = (BYTE)a;
            }
        }
    }

    // --- 4. UpdateLayeredWindow 提交 ---
    POINT ptZero = {0, 0};
    SIZE sz = {m_windowWidth, m_windowHeight};
    BLENDFUNCTION bf = {};
    bf.BlendOp = AC_SRC_OVER;
    bf.SourceConstantAlpha = 255;
    bf.AlphaFormat = AC_SRC_ALPHA;

    UpdateLayeredWindow(m_hwnd, nullptr, nullptr, &sz,
        m_hdcMem, &ptZero, 0, &bf, ULW_ALPHA);
}

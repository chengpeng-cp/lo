#include "TranslationOverlay.h"
#include "ColorUtils.h"
#include "DPIUtils.h"
#include <windowsx.h>
#include <algorithm>
#include <cmath>

// 自定义消息（跨线程转发）
namespace {
    const wchar_t* kClassName = L"LOTranslationOverlayClass";

    const UINT kMsgShowLoading          = WM_USER + 10;
    const UINT kMsgShow                 = WM_USER + 11;
    const UINT kMsgShowError            = WM_USER + 12;
    const UINT kMsgSilentUpdateOriginal = WM_USER + 13;
    const UINT kMsgUpdateTranslation    = WM_USER + 14;
    const UINT kMsgHide                = WM_USER + 15;
    const UINT kMsgUpdateConfig         = WM_USER + 16;

    // 布局常量（逻辑像素，96 DPI 基准）
    const int    kPadding        = 16;
    const int    kLabelFontSize  = 11;
    const int    kDividerGap     = 8;
    const int    kLabelGap       = 4;
    const int    kCornerRadius   = 12;
    const int    kMinWidth       = 220;
    const int    kCopyBtnSize    = 18;
    const int    kCopyBtnMargin  = 6;
    const int    kFadeStepMs     = 15;
    const double kFadeStep       = 0.06;   // 约 300ms 淡出
}

// ============================================================================
// 圆角覆盖度计算（与 CandidateWindow 一致）
// ============================================================================
static double CornerCoverage(int px, int py, int W, int H, int r) {
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

// ============================================================================
// 单例
// ============================================================================
LOTranslationOverlay& LOTranslationOverlay::Shared() {
    static LOTranslationOverlay s_instance;
    return s_instance;
}

// ============================================================================
// 构造 / 析构
// ============================================================================
LOTranslationOverlay::LOTranslationOverlay() {
    EnsureRegistered();
    CreateWindowInternal();
    // 拉取一次配置快照（构造在 UI 线程，直接读取）
    ApplyConfig();
}

LOTranslationOverlay::~LOTranslationOverlay() {
    StopDismissTimer();
    StopFadeTimer();
    if (m_hwnd) {
        DestroyWindow(m_hwnd);
        m_hwnd = nullptr;
    }
    if (m_hbmpOld && m_hdcMem) SelectObject(m_hdcMem, m_hbmpOld);
    if (m_hbmp) DeleteObject(m_hbmp);
    if (m_hdcMem) DeleteDC(m_hdcMem);
}

void LOTranslationOverlay::EnsureRegistered() {
    if (m_classRegistered) return;
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &LOTranslationOverlay::WndProcStatic;
    wc.hInstance = g_hInstance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    ATOM atom = RegisterClassExW(&wc);
    if (atom || GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
        m_classRegistered = true;
    }
}

void LOTranslationOverlay::CreateWindowInternal() {
    DWORD exStyle = WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE;
    DWORD style = WS_POPUP;
    m_hwnd = CreateWindowExW(exStyle, kClassName, L"", style,
        CW_USEDEFAULT, CW_USEDEFAULT, 0, 0,
        nullptr, nullptr, g_hInstance, this);
}

// ============================================================================
// 窗口过程
// ============================================================================
LRESULT CALLBACK LOTranslationOverlay::WndProcStatic(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    LOTranslationOverlay* self = nullptr;
    if (msg == WM_NCCREATE) {
        auto cs = reinterpret_cast<CREATESTRUCT*>(lp);
        self = reinterpret_cast<LOTranslationOverlay*>(cs->lpCreateParams);
        SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    } else {
        self = reinterpret_cast<LOTranslationOverlay*>(
            GetWindowLongPtr(hwnd, GWLP_USERDATA));
    }
    if (self) return self->WndProc(msg, wp, lp);
    return DefWindowProc(hwnd, msg, wp, lp);
}

LRESULT LOTranslationOverlay::WndProc(UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case kMsgShowLoading:           HandleShowLoading(); return 0;
    case kMsgShow:                  HandleShow(); return 0;
    case kMsgShowError:             HandleShowError(); return 0;
    case kMsgSilentUpdateOriginal:  HandleSilentUpdateOriginal(); return 0;
    case kMsgUpdateTranslation:    HandleUpdateTranslation(); return 0;
    case kMsgHide: {
            // 已在 UI 线程，同步隐藏
            StopDismissTimer();
            StopFadeTimer();
            m_fadeAlpha = 1.0;
            if (m_state != State::Hidden) {
                ShowWindow(m_hwnd, SW_HIDE);
                m_state = State::Hidden;
            }
            return 0;
        }
    case kMsgUpdateConfig: {
            ApplyConfig();
            if (m_state != State::Hidden) { ComputeLayout(); ComputePosition(); Render(); }
            return 0;
        }

    case WM_TIMER:
        if (wp == kDismissTimerId) { OnDismissTick(); return 0; }
        if (wp == kFadeTimerId)    { OnFadeTick(); return 0; }
        return 0;

    case WM_NCHITTEST: {
        POINT pt = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
        POINT client = pt;
        ScreenToClient(m_hwnd, &client);
        if (IsOverCopyButton(client)) return HTCLIENT;
        if (m_clickThrough) return HTTRANSPARENT;
        return HTCLIENT;
    }

    case WM_LBUTTONDOWN: {
        POINT pt = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
        if (IsOverCopyButton(pt)) {
            CopyLastTranslation();
            return 0;
        }
        if (m_clickThrough) return 0;
        // 开始拖拽（仅 draggable 模式）
        if (m_posMode == L"draggable") {
            POINT screen = pt;
            ClientToScreen(m_hwnd, &screen);
            StartDrag(screen);
        }
        return 0;
    }
    case WM_MOUSEMOVE: {
        if (m_dragging) {
            POINT screen = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            ClientToScreen(m_hwnd, &screen);
            UpdateDrag(screen);
        }
        return 0;
    }
    case WM_LBUTTONUP: {
        if (m_dragging) EndDrag();
        return 0;
    }
    case WM_MOUSEWHEEL: {
        // 滚动译文
        int delta = GET_WHEEL_DELTA_WPARAM(wp);
        int step = WHEEL_DELTA;
        int lines = delta / step;
        int newVal = m_transScroll - lines * 18;
        if (newVal < 0) newVal = 0;
        if (newVal > m_maxTransScroll) newVal = m_maxTransScroll;
        if (newVal != m_transScroll) {
            m_transScroll = newVal;
            Render();
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
// 公共方法（可跨线程调用，加锁 + PostMessage）
// ============================================================================
void LOTranslationOverlay::ShowLoading(const std::wstring& originalText) {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_pendingOriginal = originalText;
    }
    if (m_hwnd) PostMessage(m_hwnd, kMsgShowLoading, 0, 0);
}

void LOTranslationOverlay::Show(const std::wstring& original, const std::wstring& translation) {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_pendingOriginal = original;
        m_pendingTranslation = translation;
    }
    if (m_hwnd) PostMessage(m_hwnd, kMsgShow, 0, 0);
}

void LOTranslationOverlay::ShowError(const std::wstring& original, const std::wstring& error) {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_pendingOriginal = original;
        m_pendingError = error;
    }
    if (m_hwnd) PostMessage(m_hwnd, kMsgShowError, 0, 0);
}

void LOTranslationOverlay::SilentUpdateOriginal(const std::wstring& text) {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_pendingOriginal = text;
    }
    if (m_hwnd) PostMessage(m_hwnd, kMsgSilentUpdateOriginal, 0, 0);
}

void LOTranslationOverlay::UpdateTranslation(const std::wstring& text) {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_pendingTranslation = text;
    }
    if (m_hwnd) PostMessage(m_hwnd, kMsgUpdateTranslation, 0, 0);
}

void LOTranslationOverlay::Hide() {
    if (m_hwnd) PostMessage(m_hwnd, kMsgHide, 0, 0);
}

void LOTranslationOverlay::UpdateConfig() {
    // 跨线程安全：发消息到 UI 线程执行
    if (m_hwnd) PostMessage(m_hwnd, kMsgUpdateConfig, 0, 0);
}

void LOTranslationOverlay::ApplyConfig() {
    const LOSettings& s = LOSettingsGet();
    m_bgColor   = HexToColor(s.overlayBackgroundColor);
    m_origColor = HexToColor(s.overlayOriginalTextColor);
    m_transColor = HexToColor(s.overlayTranslationTextColor);
    m_labelColor = Blend(m_origColor, m_bgColor, 0.55);
    m_opacity    = s.overlayOpacity;
    m_posMode    = s.overlayPositionMode;
    m_clickThrough = s.overlayClickThrough;
    m_showOrigLabel  = s.overlayShowOriginalLabel;
    m_showTransLabel = s.overlayShowTranslationLabel;
    m_maxWidth   = (int)s.overlayMaxWidth;
    m_maxHeight  = (int)s.overlayMaxHeight;
    m_origFontSize  = (int)s.overlayOriginalFontSize;
    m_transFontSize = (int)s.overlayTranslationFontSize;
    m_dismissInterval = s.autoDismissInterval;
}

void LOTranslationOverlay::SetCursorPositionProvider(std::function<RECT()> provider) {
    // 简单赋值；调用方应确保线程安全
    m_cursorProvider = provider;
}

// ============================================================================
// 消息处理（UI 线程）
// ============================================================================
void LOTranslationOverlay::HandleShowLoading() {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_original = m_pendingOriginal;
        m_pendingOriginal.clear();
    }
    m_translation.clear();
    m_errorText.clear();
    m_lastTranslation.clear();
    m_state = State::Loading;
    m_fadeAlpha = 1.0;
    StopFadeTimer();
    // 加载态不自动消失，等待结果
    StopDismissTimer();

    ComputeLayout();
    ComputePosition();
    Render();
    ShowWindow(m_hwnd, SW_SHOWNOACTIVATE);
}

void LOTranslationOverlay::HandleShow() {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_original = m_pendingOriginal;
        m_translation = m_pendingTranslation;
        m_pendingOriginal.clear();
        m_pendingTranslation.clear();
    }
    m_errorText.clear();
    m_lastTranslation = m_translation;
    m_transScroll = 0;
    m_state = State::Result;
    m_fadeAlpha = 1.0;
    StopFadeTimer();
    ArmDismissTimer();

    ComputeLayout();
    ComputePosition();
    Render();
    ShowWindow(m_hwnd, SW_SHOWNOACTIVATE);
}

void LOTranslationOverlay::HandleShowError() {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_original = m_pendingOriginal;
        m_errorText = m_pendingError;
        m_pendingOriginal.clear();
        m_pendingError.clear();
    }
    m_translation.clear();
    m_lastTranslation = m_errorText;
    m_transScroll = 0;
    m_state = State::Error;
    m_fadeAlpha = 1.0;
    StopFadeTimer();
    ArmDismissTimer();

    ComputeLayout();
    ComputePosition();
    Render();
    ShowWindow(m_hwnd, SW_SHOWNOACTIVATE);
}

void LOTranslationOverlay::HandleSilentUpdateOriginal() {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_original = m_pendingOriginal;
        m_pendingOriginal.clear();
    }
    if (m_state != State::Hidden) {
        ComputeLayout();
        Render();
    }
}

void LOTranslationOverlay::HandleUpdateTranslation() {
    {
        std::lock_guard<std::mutex> lock(m_dataMutex);
        m_translation = m_pendingTranslation;
        m_pendingTranslation.clear();
    }
    m_lastTranslation = m_translation;
    if (m_state == State::Loading) {
        m_state = State::Result;
        m_transScroll = 0;
        ArmDismissTimer();
    } else if (m_state == State::Result) {
        // 流式更新：重置消失计时，保持滚动顶在合理位置
        ArmDismissTimer();
    }
    if (m_state != State::Hidden) {
        ComputeLayout();
        Render();
    }
}

// ============================================================================
// 命中 / 拖拽
// ============================================================================
bool LOTranslationOverlay::IsOverCopyButton(POINT clientPt) const {
    return PtInRect(&m_copyBtnRect, clientPt) != 0;
}

void LOTranslationOverlay::StartDrag(POINT screenPt) {
    RECT rc; GetWindowRect(m_hwnd, &rc);
    m_dragOffset.x = screenPt.x - rc.left;
    m_dragOffset.y = screenPt.y - rc.top;
    m_dragging = true;
    SetCapture(m_hwnd);
}

void LOTranslationOverlay::UpdateDrag(POINT screenPt) {
    int x = screenPt.x - m_dragOffset.x;
    int y = screenPt.y - m_dragOffset.y;
    SetWindowPos(m_hwnd, nullptr, x, y, 0, 0,
        SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER);
}

void LOTranslationOverlay::EndDrag() {
    m_dragging = false;
    ReleaseCapture();
    // 持久化位置
    RECT rc; GetWindowRect(m_hwnd, &rc);
    LOSettings& s = LOSettingsGet();
    s.overlayPosition.x = rc.left;
    s.overlayPosition.y = rc.top;
    s.Save();
}

// ============================================================================
// 计时器
// ============================================================================
void LOTranslationOverlay::ArmDismissTimer() {
    StopFadeTimer();
    m_fadeAlpha = 1.0;
    StopDismissTimer();
    if (m_dismissInterval <= 0) return;  // 0 表示不自动消失
    UINT ms = (UINT)(m_dismissInterval * 1000.0 + 0.5);
    if (ms < 200) ms = 200;
    m_dismissTimer = SetTimer(m_hwnd, kDismissTimerId, ms, nullptr);
}

void LOTranslationOverlay::StopDismissTimer() {
    if (m_dismissTimer) {
        KillTimer(m_hwnd, kDismissTimerId);
        m_dismissTimer = 0;
    }
}

void LOTranslationOverlay::StartFadeOut() {
    StopDismissTimer();
    m_fadeTimer = SetTimer(m_hwnd, kFadeTimerId, kFadeStepMs, nullptr);
}

void LOTranslationOverlay::StopFadeTimer() {
    if (m_fadeTimer) {
        KillTimer(m_hwnd, kFadeTimerId);
        m_fadeTimer = 0;
    }
}

void LOTranslationOverlay::OnDismissTick() {
    StopDismissTimer();
    if (m_state == State::Hidden) return;
    StartFadeOut();
}

void LOTranslationOverlay::OnFadeTick() {
    m_fadeAlpha -= kFadeStep;
    if (m_fadeAlpha <= 0.0) {
        m_fadeAlpha = 0.0;
        StopFadeTimer();
        ShowWindow(m_hwnd, SW_HIDE);
        m_state = State::Hidden;
        m_fadeAlpha = 1.0;
        return;
    }
    Render();
}

// ============================================================================
// 复制到剪贴板
// ============================================================================
bool LOTranslationOverlay::CopyLastTranslation() {
    if (m_lastTranslation.empty()) return false;
    if (!OpenClipboard(m_hwnd)) return false;
    EmptyClipboard();
    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, (m_lastTranslation.size() + 1) * sizeof(wchar_t));
    if (!hMem) { CloseClipboard(); return false; }
    wchar_t* p = (wchar_t*)GlobalLock(hMem);
    if (p) {
        memcpy(p, m_lastTranslation.c_str(), (m_lastTranslation.size() + 1) * sizeof(wchar_t));
        GlobalUnlock(hMem);
        SetClipboardData(CF_UNICODETEXT, hMem);
    } else {
        GlobalFree(hMem);
    }
    CloseClipboard();
    // 复制后重新计时
    if (m_state == State::Result || m_state == State::Error) ArmDismissTimer();
    return true;
}

// ============================================================================
// 布局
// ============================================================================
void LOTranslationOverlay::ComputeLayout() {
    int pad = ScaleX(m_hwnd, kPadding);
    int maxW = ScaleX(m_hwnd, m_maxWidth);
    int maxH = ScaleY(m_hwnd, m_maxHeight);
    int labelSize = ScaleY(m_hwnd, kLabelFontSize);
    int origSize = ScaleY(m_hwnd, m_origFontSize);
    int transSize = ScaleY(m_hwnd, m_transFontSize);
    int dividerGap = ScaleY(m_hwnd, kDividerGap);
    int labelGap = ScaleY(m_hwnd, kLabelGap);
    int btnSize = ScaleX(m_hwnd, kCopyBtnSize);
    int btnMargin = ScaleX(m_hwnd, kCopyBtnMargin);
    int minW = ScaleX(m_hwnd, kMinWidth);

    HDC hdcScreen = GetDC(nullptr);
    if (!hdcScreen) return;

    HFONT hLabelFont = CreateFontW(-labelSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT hOrigFont = CreateFontW(-origSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
    HFONT hTransFont = CreateFontW(-transSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");

    // 用临时 DC 测量
    HDC mdc = CreateCompatibleDC(hdcScreen);

    auto measureHeight = [&](HFONT font, const std::wstring& text, int availW) -> int {
        if (text.empty()) return 0;
        HGDIOBJ old = SelectObject(mdc, font);
        RECT rc = {0, 0, availW, 0};
        DrawTextW(mdc, text.c_str(), (int)text.size(), &rc,
            DT_WORDBREAK | DT_CALCRECT | DT_EDITCONTROL);
        SelectObject(mdc, old);
        return rc.bottom - rc.top;
    };

    // 先以 maxW 估算内容宽度
    int availW = maxW - pad * 2;
    if (availW < 50) availW = 50;

    std::wstring origText = m_original;
    std::wstring transText = (m_state == State::Error) ? m_errorText : m_translation;
    if (m_state == State::Loading) transText = L"正在翻译…";

    int origH = measureHeight(hOrigFont, origText, availW);
    int transH = measureHeight(hTransFont, transText, availW);

    // 测量内容自然宽度（不换行）
    auto naturalWidth = [&](HFONT font, const std::wstring& text) -> int {
        if (text.empty()) return 0;
        HGDIOBJ old = SelectObject(mdc, font);
        SIZE sz = {0, 0};
        GetTextExtentPoint32W(mdc, text.c_str(), (int)text.size(), &sz);
        SelectObject(mdc, old);
        return sz.cx;
    };
    int origNatW = naturalWidth(hOrigFont, origText);
    int transNatW = naturalWidth(hTransFont, transText);

    int contentNatW = origNatW > transNatW ? origNatW : transNatW;
    int width = contentNatW + pad * 2;
    if (width < minW) width = minW;
    if (width > maxW) width = maxW;

    // 以最终可用宽度重新测量高度
    int finalAvailW = width - pad * 2;
    if (finalAvailW < 50) finalAvailW = 50;
    origH = measureHeight(hOrigFont, origText, finalAvailW);
    transH = measureHeight(hTransFont, transText, finalAvailW);

    // 标签高度
    int labelH = 0;
    {
        HGDIOBJ old = SelectObject(mdc, hLabelFont);
        RECT rc = {0, 0, finalAvailW, 0};
        DrawTextW(mdc, L"原文", -1, &rc, DT_CALCRECT | DT_SINGLELINE);
        labelH = rc.bottom - rc.top;
        SelectObject(mdc, old);
    }

    // 计算各段高度
    int y = pad;
    if (m_showOrigLabel) {
        y += labelH + labelGap;
    }
    int origTop = y;
    y += origH;
    y += dividerGap;          // 分隔线上下
    y += 1;                   // 分隔线
    y += dividerGap;
    int transTop = y;
    if (m_showTransLabel) {
        y += labelH + labelGap;
    }

    // 译文可见区受 maxHeight 限制
    int copyArea = btnSize + btnMargin;
    int reservedBottom = pad + copyArea;
    int heightCap = maxH;
    int transAreaMax = (heightCap - (transTop + reservedBottom));
    if (transAreaMax < 40) transAreaMax = 40;

    int transAreaH = transH < transAreaMax ? transH : transAreaMax;
    m_transFullH = transH;
    m_maxTransScroll = transH > transAreaH ? (transH - transAreaH) : 0;
    if (m_transScroll > m_maxTransScroll) m_transScroll = m_maxTransScroll;
    if (m_transScroll < 0) m_transScroll = 0;

    y += transAreaH;
    int height = y + reservedBottom;

    m_windowW = width;
    m_windowH = height;

    // 记录绘制矩形
    m_origRect.left = pad;
    m_origRect.right = pad + finalAvailW;
    m_origRect.top = origTop;
    m_origRect.bottom = origTop + origH;

    m_transRect.left = pad;
    m_transRect.right = pad + finalAvailW;
    m_transRect.top = (m_showTransLabel ? transTop + labelH + labelGap : transTop);
    m_transRect.bottom = m_transRect.top + transAreaH;

    m_copyBtnRect.left = width - pad - btnSize + btnMargin;
    m_copyBtnRect.right = m_copyBtnRect.left + btnSize;
    m_copyBtnRect.top = height - pad - btnSize + btnMargin;
    m_copyBtnRect.bottom = m_copyBtnRect.top + btnSize;

    DeleteDC(mdc);
    DeleteObject(hLabelFont);
    DeleteObject(hOrigFont);
    DeleteObject(hTransFont);
    ReleaseDC(nullptr, hdcScreen);
}

// ============================================================================
// 定位
// ============================================================================
void LOTranslationOverlay::ComputePosition() {
    if (m_windowW <= 0 || m_windowH <= 0) return;

    MONITORINFO mi = {sizeof(mi)};
    HMONITOR hMon = MonitorFromWindow(m_hwnd, MONITOR_DEFAULTTONEAREST);
    GetMonitorInfoW(hMon, &mi);
    RECT work = mi.rcWork;

    int x = 0, y = 0;

    if (m_posMode == L"fixed") {
        int margin = ScaleX(m_hwnd, 16);
        x = work.right - m_windowW - margin;
        y = (work.top + work.bottom) / 2 - m_windowH / 2;
    } else if (m_posMode == L"followCursor") {
        RECT r = {};
        bool have = false;
        if (m_cursorProvider) {
            r = m_cursorProvider();
            have = (r.right > r.left || r.bottom > r.top);
        }
        POINT anchor;
        if (have) {
            anchor.x = r.left;
            anchor.y = r.bottom + 2;
        } else {
            GetCursorPos(&anchor);
            anchor.y += 4;
        }
        x = anchor.x;
        y = anchor.y;
    } else {
        // draggable：使用保存的位置，否则默认右侧居中
        const LOPosition& sp = LOSettingsGet().overlayPosition;
        if (sp.x != 0 || sp.y != 0) {
            x = sp.x;
            y = sp.y;
        } else {
            int margin = ScaleX(m_hwnd, 16);
            x = work.right - m_windowW - margin;
            y = (work.top + work.bottom) / 2 - m_windowH / 2;
        }
    }

    // 限制在工作区内
    if (x + m_windowW > work.right) x = work.right - m_windowW;
    if (x < work.left) x = work.left;
    if (y + m_windowH > work.bottom) y = work.bottom - m_windowH;
    if (y < work.top) y = work.top;

    SetWindowPos(m_hwnd, nullptr, x, y, 0, 0,
        SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER);
}

// ============================================================================
// 渲染
// ============================================================================
void LOTranslationOverlay::Render() {
    if (!m_hwnd || m_windowW <= 0 || m_windowH <= 0) return;

    if (!m_hdcMem) m_hdcMem = CreateCompatibleDC(nullptr);
    if (m_bmpW != m_windowW || m_bmpH != m_windowH || !m_hbmp) {
        if (m_hbmpOld && m_hdcMem) { SelectObject(m_hdcMem, m_hbmpOld); m_hbmpOld = nullptr; }
        if (m_hbmp) { DeleteObject(m_hbmp); m_hbmp = nullptr; }
        BITMAPINFO bmi = {};
        bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = m_windowW;
        bmi.bmiHeader.biHeight = -m_windowH;
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;
        m_hbmp = CreateDIBSection(nullptr, &bmi, DIB_RGB_COLORS, &m_bits, nullptr, 0);
        if (m_hbmp && m_hdcMem) m_hbmpOld = (HBITMAP)SelectObject(m_hdcMem, m_hbmp);
        m_bmpW = m_windowW;
        m_bmpH = m_windowH;
    }
    if (!m_hdcMem || !m_hbmp) return;

    int pad = ScaleX(m_hwnd, kPadding);
    int labelSize = ScaleY(m_hwnd, kLabelFontSize);
    int origSize = ScaleY(m_hwnd, m_origFontSize);
    int transSize = ScaleY(m_hwnd, m_transFontSize);
    int dividerGap = ScaleY(m_hwnd, kDividerGap);
    int labelGap = ScaleY(m_hwnd, kLabelGap);
    int btnSize = ScaleX(m_hwnd, kCopyBtnSize);

    // --- 1. 用背景色不透明填充整个 DIB ---
    {
        BYTE* p = (BYTE*)m_bits;
        BYTE b = GetBValue(m_bgColor);
        BYTE g = GetGValue(m_bgColor);
        BYTE r = GetRValue(m_bgColor);
        int total = m_windowW * m_windowH;
        for (int i = 0; i < total; i++) {
            p[i * 4 + 0] = b; p[i * 4 + 1] = g; p[i * 4 + 2] = r; p[i * 4 + 3] = 255;
        }
    }

    // --- 2. GDI 绘制内容 ---
    SetBkMode(m_hdcMem, TRANSPARENT);

    HFONT hLabelFont = CreateFontW(-labelSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT hOrigFont = CreateFontW(-origSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
    HFONT hTransFont = CreateFontW(-transSize, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");

    int y = pad;
    int labelH = 0;
    {
        SelectObject(m_hdcMem, hLabelFont);
        TEXTMETRICW tm; GetTextMetricsW(m_hdcMem, &tm);
        labelH = tm.tmHeight;
    }

    // 原文标签
    if (m_showOrigLabel) {
        SelectObject(m_hdcMem, hLabelFont);
        SetTextColor(m_hdcMem, m_labelColor);
        RECT rl = {pad, y, m_windowW - pad, y + labelH};
        DrawTextW(m_hdcMem, L"原文", -1, &rl, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);
        y += labelH + labelGap;
    }
    // 原文
    {
        SelectObject(m_hdcMem, hOrigFont);
        SetTextColor(m_hdcMem, m_origColor);
        DrawTextW(m_hdcMem, m_original.c_str(), (int)m_original.size(),
            &m_origRect, DT_WORDBREAK | DT_EDITCONTROL);
    }

    // 分隔线
    int divY = m_origRect.bottom + dividerGap;
    {
        HBRUSH hbr = CreateSolidBrush(Blend(m_bgColor, RGB(255,255,255), 0.15));
        RECT dr = {pad, divY, m_windowW - pad, divY + 1};
        FillRect(m_hdcMem, &dr, hbr);
        DeleteObject(hbr);
    }

    // 译文标签
    if (m_showTransLabel) {
        SelectObject(m_hdcMem, hLabelFont);
        SetTextColor(m_hdcMem, m_labelColor);
        RECT tl = {pad, divY + 1 + dividerGap, m_windowW - pad, divY + 1 + dividerGap + labelH};
        DrawTextW(m_hdcMem, L"翻译", -1, &tl, DT_LEFT | DT_SINGLELINE);
    }

    // 译文（带滚动裁剪）
    {
        std::wstring transText = (m_state == State::Error) ? m_errorText : m_translation;
        if (m_state == State::Loading) transText = L"正在翻译…";

        SelectObject(m_hdcMem, hTransFont);
        SetTextColor(m_hdcMem, (m_state == State::Error) ? RGB(255, 140, 140) : m_transColor);

        // 裁剪到译文可见区，避免滚动时溢出到上方区域
        HRGN clip = CreateRectRgn(m_transRect.left, m_transRect.top,
            m_transRect.right, m_transRect.bottom);
        SelectClipRgn(m_hdcMem, clip);
        DeleteObject(clip);

        RECT tr = m_transRect;
        tr.top -= m_transScroll;
        tr.bottom = tr.top + m_transFullH;
        DrawTextW(m_hdcMem, transText.c_str(), (int)transText.size(),
            &tr, DT_WORDBREAK | DT_EDITCONTROL | DT_LEFT | DT_TOP);

        // 恢复裁剪（内存 DC 此前无裁剪区）
        SelectClipRgn(m_hdcMem, nullptr);
    }

    // 复制按钮（两叠加圆角矩形图标）
    {
        int bx = m_copyBtnRect.left;
        int by = m_copyBtnRect.top;
        int s = btnSize;
        COLORREF iconCol = Blend(m_transColor, m_bgColor, 0.6);
        HPEN hpen = CreatePen(PS_SOLID, 1, iconCol);
        HGDIOBJ oldPen = SelectObject(m_hdcMem, hpen);
        HBRUSH hbr = (HBRUSH)GetStockObject(NULL_BRUSH);
        HGDIOBJ oldBr = SelectObject(m_hdcMem, hbr);

        RECT back = {bx, by + 3, bx + s - 4, by + s};
        RECT front = {bx + 3, by, bx + s - 1, by + s - 3};
        RoundRect(m_hdcMem, back.left, back.top, back.right, back.bottom, 2, 2);
        RoundRect(m_hdcMem, front.left, front.top, front.right, front.bottom, 2, 2);

        SelectObject(m_hdcMem, oldPen);
        SelectObject(m_hdcMem, oldBr);
        DeleteObject(hpen);
    }

    DeleteObject(hLabelFont);
    DeleteObject(hOrigFont);
    DeleteObject(hTransFont);

    // --- 3. 后处理：圆角覆盖度 + 不透明度 × 淡出，并预乘 alpha ---
    {
        BYTE* p = (BYTE*)m_bits;
        int W = m_windowW, H = m_windowH;
        int r = ScaleX(m_hwnd, kCornerRadius);
        if (r > W / 2) r = W / 2;
        if (r > H / 2) r = H / 2;
        double overall = m_opacity * m_fadeAlpha;
        if (overall < 0.0) overall = 0.0;
        if (overall > 1.0) overall = 1.0;
        int baseAlpha = (int)(overall * 255.0 + 0.5);

        for (int yy = 0; yy < H; yy++) {
            for (int xx = 0; xx < W; xx++) {
                double cov = CornerCoverage(xx, yy, W, H, r);
                int a = (int)(cov * baseAlpha + 0.5);
                BYTE* px = p + (yy * W + xx) * 4;
                px[0] = (BYTE)((int)px[0] * a / 255);
                px[1] = (BYTE)((int)px[1] * a / 255);
                px[2] = (BYTE)((int)px[2] * a / 255);
                px[3] = (BYTE)a;
            }
        }
    }

    // --- 4. UpdateLayeredWindow ---
    POINT ptZero = {0, 0};
    SIZE sz = {m_windowW, m_windowH};
    BLENDFUNCTION bf = {};
    bf.BlendOp = AC_SRC_OVER;
    bf.SourceConstantAlpha = 255;
    bf.AlphaFormat = AC_SRC_ALPHA;
    UpdateLayeredWindow(m_hwnd, nullptr, nullptr, &sz,
        m_hdcMem, &ptZero, 0, &bf, ULW_ALPHA);
}

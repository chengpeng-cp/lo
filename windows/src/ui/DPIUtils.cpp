#include "DPIUtils.h"

// Windows 10 1607+ 提供 GetDpiForWindow；在较旧 SDK 上手动声明以保持兼容
typedef UINT(WINAPI* PFN_GetDpiForWindow)(HWND hwnd);

// 动态解析 GetDpiForWindow，避免在旧版 Windows 上链接失败
static UINT SafeGetDpiForWindow(HWND hwnd) {
    if (hwnd) {
        HMODULE hUser = GetModuleHandleW(L"user32.dll");
        if (hUser) {
            auto pFn = (PFN_GetDpiForWindow)GetProcAddress(hUser, "GetDpiForWindow");
            if (pFn) {
                return pFn(hwnd);
            }
        }
    }
    // 回退：使用屏幕 DC 的 LOGPIXELSX
    HDC hScreen = GetDC(nullptr);
    UINT dpi = 96;
    if (hScreen) {
        int logX = GetDeviceCaps(hScreen, LOGPIXELSX);
        if (logX > 0) dpi = (UINT)logX;
        ReleaseDC(nullptr, hScreen);
    }
    return dpi;
}

// 回退路径：获取垂直方向 DPI
static UINT SafeGetDpiForWindowY(HWND hwnd) {
    if (hwnd) {
        HMODULE hUser = GetModuleHandleW(L"user32.dll");
        if (hUser) {
            auto pFn = (PFN_GetDpiForWindow)GetProcAddress(hUser, "GetDpiForWindow");
            if (pFn) {
                return pFn(hwnd);
            }
        }
    }
    HDC hScreen = GetDC(nullptr);
    UINT dpi = 96;
    if (hScreen) {
        int logY = GetDeviceCaps(hScreen, LOGPIXELSY);
        if (logY > 0) dpi = (UINT)logY;
        ReleaseDC(nullptr, hScreen);
    }
    return dpi;
}

double GetDPIRatio(HWND hwnd) {
    UINT dpi = SafeGetDpiForWindow(hwnd);
    return (double)dpi / 96.0;
}

int ScaleX(HWND hwnd, int value) {
    if (value == 0) return 0;
    UINT dpi = SafeGetDpiForWindow(hwnd);
    return MulDiv(value, dpi, 96);
}

int ScaleY(HWND hwnd, int value) {
    if (value == 0) return 0;
    UINT dpi = SafeGetDpiForWindowY(hwnd);
    return MulDiv(value, dpi, 96);
}

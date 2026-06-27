#pragma once

#include <windows.h>

// ============================================================================
// DPI 缩放工具
// 在高 DPI 屏幕上将逻辑像素值缩放为物理像素值
// 优先使用 Windows 10+ 的 GetDpiForWindow，回退到 GetDeviceCaps(LOGPIXELSX/Y)
// ============================================================================

// 按水平方向 DPI 缩放一个数值（hwnd 可为 nullptr，此时回退到屏幕 DC）
int ScaleX(HWND hwnd, int value);

// 按垂直方向 DPI 缩放一个数值
int ScaleY(HWND hwnd, int value);

// 获取 DPI 缩放因子（1.0 表示 96 DPI）
double GetDPIRatio(HWND hwnd);

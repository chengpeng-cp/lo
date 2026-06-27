#pragma once

#include <windows.h>
#include <string>

// ============================================================================
// 颜色工具函数
// 提供 COLORREF 与十六进制字符串之间的转换、RGB 分量提取及颜色混合
// ============================================================================

// 将 "RRGGBB" 或 "#RRGGBB" 解析为 COLORREF
// 解析失败时返回黑色 RGB(0,0,0)
COLORREF HexToColor(const std::wstring& hex);

// 将 COLORREF 转换为 "RRGGBB" 字符串（不含 # 前缀）
std::wstring ColorToHex(COLORREF color);

// 由 RGB 分量构造 COLORREF（自动 clamp 到 [0,255]）
COLORREF MakeColor(int r, int g, int b);

// 提取 COLORREF 的 RGB 分量
void ColorToRGB(COLORREF color, int& r, int& g, int& b);

// Alpha 混合：alpha=0 完全使用 bg，alpha=1 完全使用 fg
// alpha 会被 clamp 到 [0.0, 1.0]
COLORREF Blend(COLORREF fg, COLORREF bg, double alpha);

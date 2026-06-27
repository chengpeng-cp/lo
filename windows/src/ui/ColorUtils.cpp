#include "ColorUtils.h"
#include <cwctype>
#include <algorithm>

// 十六进制字符转数值（小写/大写均支持），非法字符返回 -1
static int HexDigitToInt(wchar_t c) {
    if (c >= L'0' && c <= L'9') return c - L'0';
    if (c >= L'a' && c <= L'f') return 10 + (c - L'a');
    if (c >= L'A' && c <= L'F') return 10 + (c - L'A');
    return -1;
}

COLORREF HexToColor(const std::wstring& hex) {
    std::wstring s = hex;
    // 去除前后空白
    while (!s.empty() && std::iswspace(s.front())) s.erase(s.begin());
    while (!s.empty() && std::iswspace(s.back())) s.pop_back();

    // 去除可选的 '#' 前缀
    if (!s.empty() && (s.front() == L'#' || s.front() == L'＃')) {
        s.erase(s.begin());
    }

    if (s.size() < 6) return RGB(0, 0, 0);

    int r = HexDigitToInt(s[0]);
    int g = HexDigitToInt(s[2]);
    int b = HexDigitToInt(s[4]);
    int r2 = HexDigitToInt(s[1]);
    int g2 = HexDigitToInt(s[3]);
    int b2 = HexDigitToInt(s[5]);

    if (r < 0 || g < 0 || b < 0 || r2 < 0 || g2 < 0 || b2 < 0) {
        return RGB(0, 0, 0);
    }

    return RGB(r * 16 + r2, g * 16 + g2, b * 16 + b2);
}

std::wstring ColorToHex(COLORREF color) {
    const wchar_t* digits = L"0123456789ABCDEF";
    wchar_t buf[7];
    int r = GetRValue(color);
    int g = GetGValue(color);
    int b = GetBValue(color);
    buf[0] = digits[(r >> 4) & 0xF];
    buf[1] = digits[r & 0xF];
    buf[2] = digits[(g >> 4) & 0xF];
    buf[3] = digits[g & 0xF];
    buf[4] = digits[(b >> 4) & 0xF];
    buf[5] = digits[b & 0xF];
    buf[6] = L'\0';
    return std::wstring(buf, 6);
}

COLORREF MakeColor(int r, int g, int b) {
    r = (r < 0) ? 0 : (r > 255 ? 255 : r);
    g = (g < 0) ? 0 : (g > 255 ? 255 : g);
    b = (b < 0) ? 0 : (b > 255 ? 255 : b);
    return RGB((BYTE)r, (BYTE)g, (BYTE)b);
}

void ColorToRGB(COLORREF color, int& r, int& g, int& b) {
    r = GetRValue(color);
    g = GetGValue(color);
    b = GetBValue(color);
}

COLORREF Blend(COLORREF fg, COLORREF bg, double alpha) {
    if (alpha < 0.0) alpha = 0.0;
    if (alpha > 1.0) alpha = 1.0;

    int fr = GetRValue(fg);
    int fg_ = GetGValue(fg);
    int fb = GetBValue(fg);

    int br = GetRValue(bg);
    int bg_ = GetGValue(bg);
    int bb = GetBValue(bg);

    int r = (int)(fr * alpha + br * (1.0 - alpha) + 0.5);
    int g = (int)(fg_ * alpha + bg_ * (1.0 - alpha) + 0.5);
    int b = (int)(fb * alpha + bb * (1.0 - alpha) + 0.5);

    return MakeColor(r, g, b);
}

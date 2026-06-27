#pragma once

#include "Globals.h"
#include <string>

// ============================================================================
// 设置数据模型 - 注册表持久化（普通设置）+ DPAPI（API密钥）
// ============================================================================

struct LOPosition {
    int x = 0;
    int y = 0;
};

struct LOSettings {
    // --- 翻译 ---
    bool translationEnabled = true;
    std::wstring translationProvider = L"bing";  // bing/deepseek/glm/qwen/kimi/minimax/openai/volcengine/custom
    std::wstring translationModel;               // 当前提供商模型名
    std::wstring customLLMBaseURL;               // 自定义端点
    std::wstring translationMode = L"fluent";    // fluent/native/literal
    std::wstring targetLanguage = L"en";         // 目标语言代码

    // --- 悬浮窗 ---
    std::wstring overlayPositionMode = L"draggable"; // fixed/draggable/followCursor
    LOPosition overlayPosition;
    double autoDismissInterval = 5.0;
    double overlayOpacity = 0.85;
    std::wstring overlayBackgroundColor = L"1E1E1E";
    std::wstring overlayOriginalTextColor = L"999999";
    std::wstring overlayTranslationTextColor = L"FFFFFF";
    std::wstring overlayTheme = L"dark";
    bool overlayClickThrough = false;
    double overlayMaxWidth = 360;
    double overlayMaxHeight = 200;
    double overlayOriginalFontSize = 14;
    double overlayTranslationFontSize = 14;
    bool overlayShowOriginalLabel = true;
    bool overlayShowTranslationLabel = true;

    // --- 翻译调度 ---
    double segmentPauseThreshold = 5.0;
    double translationDebounceInterval = 0.5;

    // --- 输入 ---
    std::wstring defaultInputMode = L"chinese"; // chinese/english

    // --- 加载/保存 ---
    static LOSettings Load();
    void Save() const;

    // --- API 密钥（DPAPI 加密存储）---
    std::wstring GetAPIKey(const std::wstring& provider) const;
    void SetAPIKey(const std::wstring& provider, const std::wstring& key) const;
    void DeleteAPIKey(const std::wstring& provider) const;

    // --- 模型名（按提供商分别存储）---
    static std::wstring LoadModel(const std::wstring& provider);

    // --- 主题预设颜色 ---
    struct ThemeColors { std::wstring bg, original, translation; };
    static ThemeColors DarkThemeColors();
    static ThemeColors LightThemeColors();
    static ThemeColors ThemeColorsFor(const std::wstring& theme);
};

// 全局单例访问（线程安全）
LOSettings& LOSettingsGet();

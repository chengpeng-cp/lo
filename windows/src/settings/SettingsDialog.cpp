// ============================================================================
// LOSettingsDialog - 设置对话框实现
//
// 使用 CreateWindowExW + 自定义窗口类实现模态对话框（非 DialogBox 资源模板），
// 所有子控件在 WM_CREATE 中动态创建。使用 IsDialogMessage 处理 Tab/Enter/Escape。
// ============================================================================

#include "../settings/Settings.h"
#include "../settings/SettingsDialog.h"
#include "../core/Globals.h"
#include "../ui/DPIUtils.h"
#include "../ui/ColorUtils.h"
#include "../ui/TranslationOverlay.h"
#include "../translation/TranslationScheduler.h"

#include <commctrl.h>
#include <commdlg.h>
#include <windowsx.h>
#include <vector>
#include <string>
#include <map>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "comdlg32.lib")

namespace {

// ============================================================================
// 布局常量（逻辑像素，96 DPI 基准，运行时按 DPI 缩放）
// ============================================================================
constexpr int kWindowW = 580;
constexpr int kWindowH = 480;

constexpr int kMargin      = 8;
constexpr int kTabX        = 8;
constexpr int kTabY        = 8;
constexpr int kTabW       = 564;
constexpr int kTabH       = 420;

constexpr int kContentX   = 20;   // tab 内容区左边界
constexpr int kLeftColX   = 20;   // 左列 x
constexpr int kRightColX  = 300;  // 右列 x
constexpr int kColWidth   = 260;  // 列宽
constexpr int kLabelH     = 16;   // 标签高度
constexpr int kCtrlH      = 22;   // 控件高度
constexpr int kComboDropH = 300;  // 下拉框展开高度
constexpr int kLabelGap   = 2;    // 标签到控件的垂直间距
constexpr int kRowGap     = 12;   // 行间空白（标签底到下一标签顶）

constexpr int kButtonW    = 80;
constexpr int kButtonH    = 24;
constexpr int kButtonY    = 440;

constexpr int kEditShort  = 100;  // 短编辑框宽度（数值输入）
constexpr int kColorEditW = 80;   // 颜色编辑框宽度
constexpr int kColorBtnW  = 40;   // 颜色选择按钮宽度
constexpr int kSliderW    = 200;  // 滑块宽度

// ============================================================================
// 控件 ID
// ============================================================================
enum ControlId {
    IDC_TAB = 100,

    // 翻译
    IDC_TRANSLATION_ENABLED,
    IDC_PROVIDER_LBL, IDC_PROVIDER,
    IDC_APIKEY_LBL, IDC_APIKEY,
    IDC_MODEL_LBL, IDC_MODEL,
    IDC_ENDPOINT_LBL, IDC_ENDPOINT,
    IDC_MODE_LBL, IDC_MODE,
    IDC_TARGETLANG_LBL, IDC_TARGETLANG,
    IDC_SEGMENT_PAUSE_LBL, IDC_SEGMENT_PAUSE,
    IDC_DEBOUNCE_LBL, IDC_DEBOUNCE,

    // 悬浮窗
    IDC_POSITION_LBL, IDC_POSITION,
    IDC_THEME_LBL, IDC_THEME,
    IDC_CLICK_THROUGH,
    IDC_SHOW_ORIG_LABEL,
    IDC_SHOW_TRANS_LABEL,
    IDC_OPACITY_LBL, IDC_OPACITY, IDC_OPACITY_VAL,
    IDC_BG_COLOR_LBL, IDC_BG_COLOR, IDC_BG_PICKER,
    IDC_ORIG_COLOR_LBL, IDC_ORIG_COLOR, IDC_ORIG_PICKER,
    IDC_TRANS_COLOR_LBL, IDC_TRANS_COLOR, IDC_TRANS_PICKER,
    IDC_MAX_WIDTH_LBL, IDC_MAX_WIDTH,
    IDC_MAX_HEIGHT_LBL, IDC_MAX_HEIGHT,
    IDC_ORIG_FONT_LBL, IDC_ORIG_FONT,
    IDC_TRANS_FONT_LBL, IDC_TRANS_FONT,
    IDC_DISMISS_LBL, IDC_DISMISS,
    IDC_INPUT_MODE_LBL, IDC_INPUT_MODE,

    // 关于
    IDC_ABOUT_NAME,
    IDC_ABOUT_VERSION,
    IDC_ABOUT_DESC,
    IDC_ABOUT_INFO,

    // 底部按钮（OK/Cancel 使用标准 ID 以支持 Enter/Escape）
    IDC_BTN_APPLY = 200,
};

// ============================================================================
// 提供商 / 下拉项定义
// ============================================================================
struct ComboEntry { const wchar_t* code; const wchar_t* label; };

const ComboEntry kProviders[] = {
    { L"bing",       L"语境翻译（免费）" },
    { L"deepseek",   L"DeepSeek（深度求索）" },
    { L"glm",        L"GLM（智谱）" },
    { L"qwen",       L"Qwen（通义千问）" },
    { L"kimi",       L"Kimi（月之暗面）" },
    { L"minimax",    L"MiniMax" },
    { L"openai",     L"OpenAI" },
    { L"volcengine", L"火山引擎（豆包）" },
    { L"custom",     L"自定义（OpenAI兼容）" },
};
constexpr int kProviderCount = (int)(sizeof(kProviders) / sizeof(kProviders[0]));

const ComboEntry kModes[] = {
    { L"fluent",  L"自然翻译" },
    { L"native",  L"母语级表达" },
    { L"literal", L"直译" },
};

const ComboEntry kPositions[] = {
    { L"fixed",        L"固定右侧" },
    { L"draggable",    L"可拖动" },
    { L"followCursor", L"跟随光标" },
};

const ComboEntry kThemes[] = {
    { L"dark", L"深色" },
    { L"light", L"浅色" },
    { L"auto", L"跟随系统" },
};

const ComboEntry kInputModes[] = {
    { L"chinese", L"中文" },
    { L"english", L"英文" },
};

const wchar_t* kClassName = L"LOSettingsDialogClass";

// ============================================================================
// 对话框状态
// ============================================================================
struct DialogState {
    HWND hwnd = nullptr;
    HWND tabCtrl = nullptr;
    HFONT hFont = nullptr;
    HFONT hFontTitle = nullptr;

    // 翻译
    HWND chkTranslationEnabled;
    HWND lblProvider, cmbProvider;
    HWND lblApiKey, edtApiKey;
    HWND lblModel, edtModel;
    HWND lblEndpoint, edtEndpoint;
    HWND lblMode, cmbMode;
    HWND lblTargetLang, cmbTargetLang;
    HWND lblSegmentPause, edtSegmentPause;
    HWND lblDebounce, edtDebounce;

    // 悬浮窗
    HWND lblPosition, cmbPosition;
    HWND lblTheme, cmbTheme;
    HWND chkClickThrough;
    HWND chkShowOrigLabel, chkShowTransLabel;
    HWND lblOpacity, sldOpacity, lblOpacityVal;
    HWND lblBgColor, edtBgColor, btnBgPicker;
    HWND lblOrigColor, edtOrigColor, btnOrigPicker;
    HWND lblTransColor, edtTransColor, btnTransPicker;
    HWND lblMaxWidth, edtMaxWidth;
    HWND lblMaxHeight, edtMaxHeight;
    HWND lblOrigFont, edtOrigFont;
    HWND lblTransFont, edtTransFont;
    HWND lblDismiss, edtDismiss;
    HWND lblInputMode, cmbInputMode;

    // 关于
    HWND lblAppName, lblVersion, lblDesc, lblInfo;

    // 底部按钮
    HWND btnOK, btnCancel, btnApply;

    // 控件分组（tab 切换时显示/隐藏）
    std::vector<HWND> tab1;
    std::vector<HWND> tab2;
    std::vector<HWND> tab3;

    int currentTab = 0;

    // 临时存储各 provider 的 API 密钥与模型名（按 provider 索引）
    std::map<std::wstring, std::wstring> apiKeys;
    std::map<std::wstring, std::wstring> models;
    std::wstring currentProvider;

    // 颜色选择器的自定义颜色
    COLORREF customColors[16] = {};
};

// ============================================================================
// 小工具
// ============================================================================
int CbFindIndexByCode(HWND combo, const wchar_t* code, const ComboEntry* entries, int count) {
    if (!code) return 0;
    for (int i = 0; i < count; ++i) {
        if (wcscmp(entries[i].code, code) == 0) return i;
    }
    return 0;  // 默认第一项
}

std::wstring CbGetCodeByIndex(const ComboEntry* entries, int count, int index) {
    if (index < 0 || index >= count) return entries[0].code;
    return entries[index].code;
}

std::wstring GetEditText(HWND edit) {
    int len = GetWindowTextLengthW(edit);
    if (len <= 0) return L"";
    std::wstring buf(len + 1, L'\0');
    GetWindowTextW(edit, &buf[0], len + 1);
    buf.resize(len);
    return buf;
}

void SetEditText(HWND edit, const std::wstring& text) {
    SetWindowTextW(edit, text.c_str());
}

// 格式化 double 为简洁字符串（1 位小数，去掉无意义尾零）
std::wstring FormatDouble(double v) {
    wchar_t buf[32];
    swprintf_s(buf, L"%.1f", v);
    return buf;
}

// 直接写注册表中某 provider 的模型名（绕过 LOSettings::Save 只写当前 provider 的限制）
void SaveModelForProvider(const std::wstring& provider, const std::wstring& model) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, LO_REG_ROOT, 0, nullptr, 0,
            KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
        return;
    }
    std::wstring name = L"translationModel_" + provider;
    if (model.empty()) {
        RegDeleteValueW(hKey, name.c_str());
    } else {
        RegSetValueExW(hKey, name.c_str(), 0, REG_SZ,
            (const BYTE*)model.c_str(),
            (DWORD)((model.size() + 1) * sizeof(wchar_t)));
    }
    RegCloseKey(hKey);
}

// ============================================================================
// 控件创建辅助
// ============================================================================
HWND CreateCtrl(HWND parent, const wchar_t* cls, DWORD style, DWORD exStyle,
                 int x, int y, int w, int h, int id, HFONT font) {
    HWND hwnd = CreateWindowExW(exStyle, cls, L"", style | WS_CHILD,
                             x, y, w, h, parent, (HMENU)(INT_PTR)id, g_hInstance, nullptr);
    if (hwnd && font) SendMessageW(hwnd, WM_SETFONT, (WPARAM)font, TRUE);
    return hwnd;
}

HWND CreateLabel(HWND parent, const wchar_t* text, int x, int y, int w, int h, HFONT font) {
    HWND hwnd = CreateCtrl(parent, WC_STATICW, SS_LEFT, 0, x, y, w, h, 0, font);
    if (hwnd) SetWindowTextW(hwnd, text);
    return hwnd;
}

HWND CreateCheckbox(HWND parent, const wchar_t* text, int x, int y, int w, int h,
                    int id, HFONT font) {
    HWND hwnd = CreateCtrl(parent, WC_BUTTONW, BS_AUTOCHECKBOX | WS_TABSTOP, 0,
                        x, y, w, h, id, font);
    if (hwnd) SetWindowTextW(hwnd, text);
    return hwnd;
}

HWND CreateEdit(HWND parent, DWORD style, int x, int y, int w, int h, int id, HFONT font) {
    return CreateCtrl(parent, WC_EDITW, style | WS_TABSTOP | ES_AUTOHSCROLL,
                      WS_EX_CLIENTEDGE, x, y, w, h, id, font);
}

HWND CreateCombo(HWND parent, int x, int y, int w, int h, int id, HFONT font) {
    return CreateCtrl(parent, WC_COMBOBOXW, CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL,
                      0, x, y, w, h, id, font);
}

HWND CreateButton(HWND parent, const wchar_t* text, DWORD style, int x, int y,
                  int w, int h, int id, HFONT font) {
    HWND hwnd = CreateCtrl(parent, WC_BUTTONW, style | WS_TABSTOP, 0, x, y, w, h, id, font);
    if (hwnd) SetWindowTextW(hwnd, text);
    return hwnd;
}

HWND CreateSlider(HWND parent, int x, int y, int w, int h, int id, HFONT font) {
    HWND hwnd = CreateCtrl(parent, TRACKBAR_CLASSW, TBS_HORZ | TBS_AUTOTICKS, 0,
                        x, y, w, h, id, font);
    return hwnd;
}

void FillCombo(HWND combo, const ComboEntry* entries, int count) {
    for (int i = 0; i < count; ++i) {
        ComboBox_AddString(combo, entries[i].label);
    }
}

// ============================================================================
// 控件可见性
// ============================================================================

// 根据「启用翻译」复选框与当前 provider，调整翻译相关控件可见性
void UpdateTranslationControlsVisibility(DialogState* s) {
    BOOL enabled = Button_GetCheck(s->chkTranslationEnabled) == BST_CHECKED;
    int sel = ComboBox_GetCurSel(s->cmbProvider);
    std::wstring provider = (sel >= 0 && sel < kProviderCount)
                            ? std::wstring(kProviders[sel].code) : L"bing";
    bool isFree = (provider == L"bing");
    bool isCustom = (provider == L"custom");

    // 需要隐藏/禁用的控件集合
    auto setVisibility = [](HWND h, BOOL show) {
        EnableWindow(h, show);
        ShowWindow(h, show ? SW_SHOW : SW_HIDE);
    };

    // provider 下拉始终可见但不可用
    setVisibility(s->cmbProvider, enabled);
    EnableWindow(s->lblProvider, enabled);
    ShowWindow(s->lblProvider, enabled ? SW_SHOW : SW_HIDE);

    // API key / model / endpoint：免费时隐藏；非免费时显示 key+model；custom 时也显示 endpoint
    BOOL showKey = enabled && !isFree;
    setVisibility(s->edtApiKey, showKey);
    EnableWindow(s->lblApiKey, showKey);
    ShowWindow(s->lblApiKey, showKey ? SW_SHOW : SW_HIDE);

    BOOL showModel = enabled && !isFree;
    setVisibility(s->edtModel, showModel);
    EnableWindow(s->lblModel, showModel);
    ShowWindow(s->lblModel, showModel ? SW_SHOW : SW_HIDE);

    BOOL showEndpoint = enabled && isCustom;
    setVisibility(s->edtEndpoint, showEndpoint);
    EnableWindow(s->lblEndpoint, showEndpoint);
    ShowWindow(s->lblEndpoint, showEndpoint ? SW_SHOW : SW_HIDE);

    // 其余翻译控件
    auto setVis = [&](HWND h) {
        EnableWindow(h, enabled);
        ShowWindow(h, enabled ? SW_SHOW : SW_HIDE);
    };
    setVis(s->lblMode);     setVis(s->cmbMode);
    setVis(s->lblTargetLang); setVis(s->cmbTargetLang);
    setVis(s->lblSegmentPause); setVis(s->edtSegmentPause);
    setVis(s->lblDebounce); setVis(s->edtDebounce);
}

// ============================================================================
// Tab 切换
// ============================================================================
void ShowTab(DialogState* s, int tab) {
    auto showList = [](std::vector<HWND>& list, BOOL show) {
        for (HWND h : list) ShowWindow(h, show ? SW_SHOW : SW_HIDE);
    };
    showList(s->tab1, FALSE);
    showList(s->tab2, FALSE);
    showList(s->tab3, FALSE);

    switch (tab) {
        case 0: showList(s->tab1, TRUE); break;
        case 1: showList(s->tab2, TRUE); break;
        case 2: showList(s->tab3, TRUE); break;
    }
    s->currentTab = tab;
}

// ============================================================================
// Provider 切换：保存旧 provider 的 key/model，加载新 provider 的
// ============================================================================
void OnProviderChanged(DialogState* s) {
    int sel = ComboBox_GetCurSel(s->cmbProvider);
    if (sel < 0 || sel >= kProviderCount) return;
    std::wstring newProvider = kProviders[sel].code;

    // 保存当前 provider 的 key/model 到临时 map
    if (!s->currentProvider.empty()) {
        s->apiKeys[s->currentProvider] = GetEditText(s->edtApiKey);
        s->models[s->currentProvider] = GetEditText(s->edtModel);
    }

    // 加载新 provider 的 key/model
    auto itKey = s->apiKeys.find(newProvider);
    if (itKey != s->apiKeys.end()) {
        SetEditText(s->edtApiKey, itKey->second);
    } else {
        SetEditText(s->edtApiKey, LOSettingsGet().GetAPIKey(newProvider));
    }
    auto itModel = s->models.find(newProvider);
    if (itModel != s->models.end()) {
        SetEditText(s->edtModel, itModel->second);
    } else {
        SetEditText(s->edtModel, LOSettings::LoadModel(newProvider));
    }

    s->currentProvider = newProvider;
    UpdateTranslationControlsVisibility(s);
}

// ============================================================================
// 从 LOSettings 加载到控件
// ============================================================================
void LoadSettingsToControls(DialogState* s) {
    LOSettings& cfg = LOSettingsGet();

    // 预加载所有 provider 的 key/model 到临时 map
    s->apiKeys.clear();
    s->models.clear();
    for (int i = 0; i < kProviderCount; ++i) {
        std::wstring p = kProviders[i].code;
        s->apiKeys[p] = cfg.GetAPIKey(p);
        s->models[p] = LOSettings::LoadModel(p);
    }
    s->currentProvider = cfg.translationProvider;

    // 翻译
    Button_SetCheck(s->chkTranslationEnabled,
                    cfg.translationEnabled ? BST_CHECKED : BST_UNCHECKED);

    int provIdx = CbFindIndexByCode(s->cmbProvider, cfg.translationProvider.c_str(),
                                    kProviders, kProviderCount);
    ComboBox_SetCurSel(s->cmbProvider, provIdx);

    // 显示当前 provider 的 key/model
    SetEditText(s->edtApiKey, s->apiKeys[cfg.translationProvider]);
    SetEditText(s->edtModel, s->models[cfg.translationProvider]);
    SetEditText(s->edtEndpoint, cfg.customLLMBaseURL);

    int modeIdx = CbFindIndexByCode(s->cmbMode, cfg.translationMode.c_str(),
                                    kModes, (int)(sizeof(kModes)/sizeof(kModes[0])));
    ComboBox_SetCurSel(s->cmbMode, modeIdx);

    // 目标语言
    const auto& langs = LOGetTargetLanguages();
    int langSel = 0;
    for (int i = 0; i < (int)langs.size(); ++i) {
        if (langs[i].code == cfg.targetLanguage) { langSel = i; break; }
    }
    ComboBox_SetCurSel(s->cmbTargetLang, langSel);

    SetEditText(s->edtSegmentPause, FormatDouble(cfg.segmentPauseThreshold));
    SetEditText(s->edtDebounce, FormatDouble(cfg.translationDebounceInterval));

    // 悬浮窗
    ComboBox_SetCurSel(s->cmbPosition,
        CbFindIndexByCode(s->cmbPosition, cfg.overlayPositionMode.c_str(),
                          kPositions, (int)(sizeof(kPositions)/sizeof(kPositions[0]))));
    ComboBox_SetCurSel(s->cmbTheme,
        CbFindIndexByCode(s->cmbTheme, cfg.overlayTheme.c_str(),
                          kThemes, (int)(sizeof(kThemes)/sizeof(kThemes[0]))));
    Button_SetCheck(s->chkClickThrough,
                    cfg.overlayClickThrough ? BST_CHECKED : BST_UNCHECKED);
    Button_SetCheck(s->chkShowOrigLabel,
                    cfg.overlayShowOriginalLabel ? BST_CHECKED : BST_UNCHECKED);
    Button_SetCheck(s->chkShowTransLabel,
                    cfg.overlayShowTranslationLabel ? BST_CHECKED : BST_UNCHECKED);

    int opacity = (int)(cfg.overlayOpacity * 100.0 + 0.5);
    if (opacity < 0) opacity = 0;
    if (opacity > 100) opacity = 100;
    SendMessageW(s->sldOpacity, TBM_SETPOS, TRUE, opacity);
    wchar_t buf[16]; swprintf_s(buf, L"%d%%", opacity);
    SetWindowTextW(s->lblOpacityVal, buf);

    SetEditText(s->edtBgColor, cfg.overlayBackgroundColor);
    SetEditText(s->edtOrigColor, cfg.overlayOriginalTextColor);
    SetEditText(s->edtTransColor, cfg.overlayTranslationTextColor);

    SetEditText(s->edtMaxWidth, FormatDouble(cfg.overlayMaxWidth));
    SetEditText(s->edtMaxHeight, FormatDouble(cfg.overlayMaxHeight));
    SetEditText(s->edtOrigFont, FormatDouble(cfg.overlayOriginalFontSize));
    SetEditText(s->edtTransFont, FormatDouble(cfg.overlayTranslationFontSize));
    SetEditText(s->edtDismiss, FormatDouble(cfg.autoDismissInterval));

    ComboBox_SetCurSel(s->cmbInputMode,
        CbFindIndexByCode(s->cmbInputMode, cfg.defaultInputMode.c_str(),
                          kInputModes, (int)(sizeof(kInputModes)/sizeof(kInputModes[0]))));

    UpdateTranslationControlsVisibility(s);
}

// ============================================================================
// 从控件读取并保存到 LOSettings
// ============================================================================
bool SaveControlsToSettings(DialogState* s) {
    LOSettings& cfg = LOSettingsGet();

    // 翻译
    cfg.translationEnabled = Button_GetCheck(s->chkTranslationEnabled) == BST_CHECKED;

    int provSel = ComboBox_GetCurSel(s->cmbProvider);
    std::wstring newProvider = CbGetCodeByIndex(kProviders, kProviderCount, provSel);

    // 保存当前 provider 的 key/model 到临时 map
    if (!s->currentProvider.empty()) {
        s->apiKeys[s->currentProvider] = GetEditText(s->edtApiKey);
        s->models[s->currentProvider] = GetEditText(s->edtModel);
    }

    cfg.translationProvider = newProvider;
    cfg.customLLMBaseURL = GetEditText(s->edtEndpoint);
    cfg.translationModel = s->models[newProvider];

    int modeSel = ComboBox_GetCurSel(s->cmbMode);
    cfg.translationMode = CbGetCodeByIndex(kModes, (int)(sizeof(kModes)/sizeof(kModes[0])), modeSel);

    int langSel = ComboBox_GetCurSel(s->cmbTargetLang);
    const auto& langs = LOGetTargetLanguages();
    if (langSel >= 0 && langSel < (int)langs.size()) {
        cfg.targetLanguage = langs[langSel].code;
    }

    try { cfg.segmentPauseThreshold = std::stod(GetEditText(s->edtSegmentPause)); } catch (...) {}
    try { cfg.translationDebounceInterval = std::stod(GetEditText(s->edtDebounce)); } catch (...) {}

    // 悬浮窗
    int posSel = ComboBox_GetCurSel(s->cmbPosition);
    cfg.overlayPositionMode = CbGetCodeByIndex(kPositions, (int)(sizeof(kPositions)/sizeof(kPositions[0])), posSel);

    int themeSel = ComboBox_GetCurSel(s->cmbTheme);
    cfg.overlayTheme = CbGetCodeByIndex(kThemes, (int)(sizeof(kThemes)/sizeof(kThemes[0])), themeSel);

    cfg.overlayClickThrough = Button_GetCheck(s->chkClickThrough) == BST_CHECKED;
    cfg.overlayShowOriginalLabel = Button_GetCheck(s->chkShowOrigLabel) == BST_CHECKED;
    cfg.overlayShowTranslationLabel = Button_GetCheck(s->chkShowTransLabel) == BST_CHECKED;

    int opacity = (int)SendMessageW(s->sldOpacity, TBM_GETPOS, 0, 0);
    cfg.overlayOpacity = (double)opacity / 100.0;

    // 校验颜色为合法 6 位 hex
    auto validHex = [](const std::wstring& s) -> bool {
        if (s.size() != 6) return false;
        for (wchar_t c : s) {
            if (!((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') || (c >= L'A' && c <= L'F')))
                return false;
        }
        return true;
    };
    auto getHex = [&](HWND edit) -> std::wstring {
        std::wstring v = GetEditText(edit);
        // 去掉可能的前缀 #
        if (!v.empty() && v[0] == L'#') v = v.substr(1);
        if (validHex(v)) return v;
        return L"000000";  // 回退为黑色
    };
    cfg.overlayBackgroundColor = getHex(s->edtBgColor);
    cfg.overlayOriginalTextColor = getHex(s->edtOrigColor);
    cfg.overlayTranslationTextColor = getHex(s->edtTransColor);

    try { cfg.overlayMaxWidth = std::stod(GetEditText(s->edtMaxWidth)); } catch (...) {}
    try { cfg.overlayMaxHeight = std::stod(GetEditText(s->edtMaxHeight)); } catch (...) {}
    try { cfg.overlayOriginalFontSize = std::stod(GetEditText(s->edtOrigFont)); } catch (...) {}
    try { cfg.overlayTranslationFontSize = std::stod(GetEditText(s->edtTransFont)); } catch (...) {}
    try { cfg.autoDismissInterval = std::stod(GetEditText(s->edtDismiss)); } catch (...) {}

    int inputSel = ComboBox_GetCurSel(s->cmbInputMode);
    cfg.defaultInputMode = CbGetCodeByIndex(kInputModes, (int)(sizeof(kInputModes)/sizeof(kInputModes[0])), inputSel);

    // 持久化到注册表
    cfg.Save();

    // 持久化各 provider 的 API 密钥与模型名
    for (int i = 0; i < kProviderCount; ++i) {
        std::wstring p = kProviders[i].code;
        auto itKey = s->apiKeys.find(p);
        if (itKey != s->apiKeys.end()) {
            cfg.SetAPIKey(p, itKey->second);
        }
        auto itModel = s->models.find(p);
        if (itModel != s->models.end()) {
            SaveModelForProvider(p, itModel->second);
        }
    }

    // 通知运行时组件刷新
    LOTranslationOverlay::Shared().UpdateConfig();
    LOTranslationScheduler::Shared().UpdateTranslator();

    LOLog(L"SettingsDialog: settings saved and applied (provider=%s, targetLang=%s)",
          cfg.translationProvider.c_str(), cfg.targetLanguage.c_str());
    return true;
}

// ============================================================================
// 颜色选择器
// ============================================================================
void OpenColorPicker(HWND edit, DialogState* s) {
    std::wstring hex = GetEditText(edit);
    if (!hex.empty() && hex[0] == L'#') hex = hex.substr(1);
    COLORREF initial = HexToColor(hex);

    CHOOSECOLORW cc = {};
    cc.lStructSize = sizeof(cc);
    cc.hwndOwner = s->hwnd;
    cc.lpCustColors = s->customColors;
    cc.rgbResult = initial;
    cc.Flags = CC_FULLOPEN | CC_RGBINIT;
    if (ChooseColorW(&cc)) {
        SetEditText(edit, ColorToHex(cc.rgbResult));
    }
}

// ============================================================================
// 创建所有控件
// ============================================================================
void CreateControls(DialogState* s, HWND hwnd) {
    // DPI 缩放辅助
    auto SX = [hwnd](int v) { return ScaleX(hwnd, v); };
    auto SY = [hwnd](int v) { return ScaleY(hwnd, v); };

    // Tab Control
    s->tabCtrl = CreateCtrl(hwnd, WC_TABCONTROLW, WS_VISIBLE | WS_TABSTOP, 0,
                            SX(kTabX), SY(kTabY), SX(kTabW), SY(kTabH), IDC_TAB, s->hFont);

    TCITEMW ti = {};
    ti.mask = TCIF_TEXT;
    ti.pszText = (LPWSTR)L"翻译";
    TabCtrl_InsertItem(s->tabCtrl, 0, &ti);
    ti.pszText = (LPWSTR)L"悬浮窗";
    TabCtrl_InsertItem(s->tabCtrl, 1, &ti);
    ti.pszText = (LPWSTR)L"关于";
    TabCtrl_InsertItem(s->tabCtrl, 2, &ti);

    // --- Tab 1: 翻译 ---
    int y = 52;
    s->chkTranslationEnabled = CreateCheckbox(hwnd, L"启用翻译",
        SX(kLeftColX), SY(y), SX(200), SY(kCtrlH), IDC_TRANSLATION_ENABLED, s->hFont);
    s->tab1.push_back(s->chkTranslationEnabled);

    y = 84;
    s->lblProvider = CreateLabel(hwnd, L"翻译服务",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->cmbProvider = CreateCombo(hwnd,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kComboDropH),
        IDC_PROVIDER, s->hFont);
    FillCombo(s->cmbProvider, kProviders, kProviderCount);
    s->tab1.push_back(s->lblProvider); s->tab1.push_back(s->cmbProvider);

    y = 136;
    s->lblApiKey = CreateLabel(hwnd, L"API 密钥",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtApiKey = CreateEdit(hwnd, ES_PASSWORD,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kCtrlH),
        IDC_APIKEY, s->hFont);
    s->tab1.push_back(s->lblApiKey); s->tab1.push_back(s->edtApiKey);

    y = 188;
    s->lblModel = CreateLabel(hwnd, L"模型名称",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtModel = CreateEdit(hwnd, 0,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kCtrlH),
        IDC_MODEL, s->hFont);
    s->tab1.push_back(s->lblModel); s->tab1.push_back(s->edtModel);

    y = 240;
    s->lblEndpoint = CreateLabel(hwnd, L"API 端点",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtEndpoint = CreateEdit(hwnd, 0,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kCtrlH),
        IDC_ENDPOINT, s->hFont);
    s->tab1.push_back(s->lblEndpoint); s->tab1.push_back(s->edtEndpoint);

    // 右列
    y = 84;
    s->lblMode = CreateLabel(hwnd, L"翻译模式",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->cmbMode = CreateCombo(hwnd,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kComboDropH),
        IDC_MODE, s->hFont);
    FillCombo(s->cmbMode, kModes, (int)(sizeof(kModes)/sizeof(kModes[0])));
    s->tab1.push_back(s->lblMode); s->tab1.push_back(s->cmbMode);

    y = 136;
    s->lblTargetLang = CreateLabel(hwnd, L"目标语言",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->cmbTargetLang = CreateCombo(hwnd,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kComboDropH),
        IDC_TARGETLANG, s->hFont);
    {
        const auto& langs = LOGetTargetLanguages();
        for (const auto& l : langs) {
            ComboBox_AddString(s->cmbTargetLang, l.displayName.c_str());
        }
    }
    s->tab1.push_back(s->lblTargetLang); s->tab1.push_back(s->cmbTargetLang);

    y = 188;
    s->lblSegmentPause = CreateLabel(hwnd, L"段落间隔(秒)",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtSegmentPause = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_SEGMENT_PAUSE, s->hFont);
    s->tab1.push_back(s->lblSegmentPause); s->tab1.push_back(s->edtSegmentPause);

    y = 240;
    s->lblDebounce = CreateLabel(hwnd, L"翻译间隔(秒)",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtDebounce = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_DEBOUNCE, s->hFont);
    s->tab1.push_back(s->lblDebounce); s->tab1.push_back(s->edtDebounce);

    // --- Tab 2: 悬浮窗 ---
    y = 52;
    s->lblPosition = CreateLabel(hwnd, L"位置模式",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->cmbPosition = CreateCombo(hwnd,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kComboDropH),
        IDC_POSITION, s->hFont);
    FillCombo(s->cmbPosition, kPositions, (int)(sizeof(kPositions)/sizeof(kPositions[0])));
    s->tab2.push_back(s->lblPosition); s->tab2.push_back(s->cmbPosition);

    y = 104;
    s->lblTheme = CreateLabel(hwnd, L"主题",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->cmbTheme = CreateCombo(hwnd,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kComboDropH),
        IDC_THEME, s->hFont);
    FillCombo(s->cmbTheme, kThemes, (int)(sizeof(kThemes)/sizeof(kThemes[0])));
    s->tab2.push_back(s->lblTheme); s->tab2.push_back(s->cmbTheme);

    y = 156;
    s->chkClickThrough = CreateCheckbox(hwnd, L"点击穿透",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kCtrlH), IDC_CLICK_THROUGH, s->hFont);
    s->tab2.push_back(s->chkClickThrough);

    y = 180;
    s->chkShowOrigLabel = CreateCheckbox(hwnd, L"显示原文标签",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kCtrlH), IDC_SHOW_ORIG_LABEL, s->hFont);
    s->tab2.push_back(s->chkShowOrigLabel);

    y = 204;
    s->chkShowTransLabel = CreateCheckbox(hwnd, L"显示翻译标签",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kCtrlH), IDC_SHOW_TRANS_LABEL, s->hFont);
    s->tab2.push_back(s->chkShowTransLabel);

    y = 236;
    s->lblInputMode = CreateLabel(hwnd, L"默认输入模式",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->cmbInputMode = CreateCombo(hwnd,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kColWidth), SY(kComboDropH),
        IDC_INPUT_MODE, s->hFont);
    FillCombo(s->cmbInputMode, kInputModes, (int)(sizeof(kInputModes)/sizeof(kInputModes[0])));
    s->tab2.push_back(s->lblInputMode); s->tab2.push_back(s->cmbInputMode);

    y = 288;
    s->lblOpacity = CreateLabel(hwnd, L"透明度",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->sldOpacity = CreateSlider(hwnd,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kSliderW), SY(kCtrlH),
        IDC_OPACITY, s->hFont);
    SendMessageW(s->sldOpacity, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
    SendMessageW(s->sldOpacity, TBM_SETTICFREQ, 10, 0);
    s->lblOpacityVal = CreateLabel(hwnd, L"85%",
        SX(kLeftColX + kSliderW + 8), SY(y + kLabelH + kLabelGap + 2),
        SX(40), SY(kLabelH), s->hFont);
    s->tab2.push_back(s->lblOpacity); s->tab2.push_back(s->sldOpacity);
    s->tab2.push_back(s->lblOpacityVal);

    y = 340;
    s->lblDismiss = CreateLabel(hwnd, L"自动消失时间(秒)（0=不消失）",
        SX(kLeftColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtDismiss = CreateEdit(hwnd, 0,
        SX(kLeftColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_DISMISS, s->hFont);
    s->tab2.push_back(s->lblDismiss); s->tab2.push_back(s->edtDismiss);

    // 右列：颜色 + 尺寸
    y = 52;
    s->lblBgColor = CreateLabel(hwnd, L"背景颜色",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtBgColor = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kColorEditW), SY(kCtrlH),
        IDC_BG_COLOR, s->hFont);
    Edit_LimitText(s->edtBgColor, 6);
    s->btnBgPicker = CreateButton(hwnd, L"...", 0,
        SX(kRightColX + kColorEditW + 4), SY(y + kLabelH + kLabelGap - 1),
        SX(kColorBtnW), SY(kCtrlH), IDC_BG_PICKER, s->hFont);
    s->tab2.push_back(s->lblBgColor); s->tab2.push_back(s->edtBgColor);
    s->tab2.push_back(s->btnBgPicker);

    y = 104;
    s->lblOrigColor = CreateLabel(hwnd, L"待翻译文字颜色",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtOrigColor = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kColorEditW), SY(kCtrlH),
        IDC_ORIG_COLOR, s->hFont);
    Edit_LimitText(s->edtOrigColor, 6);
    s->btnOrigPicker = CreateButton(hwnd, L"...", 0,
        SX(kRightColX + kColorEditW + 4), SY(y + kLabelH + kLabelGap - 1),
        SX(kColorBtnW), SY(kCtrlH), IDC_ORIG_PICKER, s->hFont);
    s->tab2.push_back(s->lblOrigColor); s->tab2.push_back(s->edtOrigColor);
    s->tab2.push_back(s->btnOrigPicker);

    y = 156;
    s->lblTransColor = CreateLabel(hwnd, L"翻译文字颜色",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtTransColor = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kColorEditW), SY(kCtrlH),
        IDC_TRANS_COLOR, s->hFont);
    Edit_LimitText(s->edtTransColor, 6);
    s->btnTransPicker = CreateButton(hwnd, L"...", 0,
        SX(kRightColX + kColorEditW + 4), SY(y + kLabelH + kLabelGap - 1),
        SX(kColorBtnW), SY(kCtrlH), IDC_TRANS_PICKER, s->hFont);
    s->tab2.push_back(s->lblTransColor); s->tab2.push_back(s->edtTransColor);
    s->tab2.push_back(s->btnTransPicker);

    y = 208;
    s->lblMaxWidth = CreateLabel(hwnd, L"最大宽度",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtMaxWidth = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_MAX_WIDTH, s->hFont);
    s->tab2.push_back(s->lblMaxWidth); s->tab2.push_back(s->edtMaxWidth);

    y = 260;
    s->lblMaxHeight = CreateLabel(hwnd, L"最大高度",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtMaxHeight = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_MAX_HEIGHT, s->hFont);
    s->tab2.push_back(s->lblMaxHeight); s->tab2.push_back(s->edtMaxHeight);

    y = 312;
    s->lblOrigFont = CreateLabel(hwnd, L"原文字体大小",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtOrigFont = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_ORIG_FONT, s->hFont);
    s->tab2.push_back(s->lblOrigFont); s->tab2.push_back(s->edtOrigFont);

    y = 364;
    s->lblTransFont = CreateLabel(hwnd, L"翻译字体大小",
        SX(kRightColX), SY(y), SX(kColWidth), SY(kLabelH), s->hFont);
    s->edtTransFont = CreateEdit(hwnd, 0,
        SX(kRightColX), SY(y + kLabelH + kLabelGap), SX(kEditShort), SY(kCtrlH),
        IDC_TRANS_FONT, s->hFont);
    s->tab2.push_back(s->lblTransFont); s->tab2.push_back(s->edtTransFont);

    // --- Tab 3: 关于 ---
    s->lblAppName = CreateCtrl(hwnd, WC_STATICW, SS_CENTER, 0,
        SX(40), SY(80), SX(kWindowW - 80), SY(40), IDC_ABOUT_NAME, s->hFontTitle);
    SetWindowTextW(s->lblAppName, LO_APP_NAME);
    s->tab3.push_back(s->lblAppName);

    s->lblVersion = CreateCtrl(hwnd, WC_STATICW, SS_CENTER, 0,
        SX(40), SY(130), SX(kWindowW - 80), SY(kCtrlH), IDC_ABOUT_VERSION, s->hFont);
    SetWindowTextW(s->lblVersion, L"版本：" LO_VERSION);
    s->tab3.push_back(s->lblVersion);

    s->lblDesc = CreateCtrl(hwnd, WC_STATICW, SS_CENTER, 0,
        SX(40), SY(180), SX(kWindowW - 80), SY(kCtrlH), IDC_ABOUT_DESC, s->hFont);
    SetWindowTextW(s->lblDesc, L"边写边翻译，日常沟通场景融入外语环境");
    s->tab3.push_back(s->lblDesc);

    s->lblInfo = CreateCtrl(hwnd, WC_STATICW, SS_CENTER, 0,
        SX(40), SY(260), SX(kWindowW - 80), SY(kCtrlH), IDC_ABOUT_INFO, s->hFont);
    SetWindowTextW(s->lblInfo, L"基于 TSF 框架的 Windows 输入法");
    s->tab3.push_back(s->lblInfo);

    // --- 底部按钮（右对齐：OK, Cancel, Apply）---
    int btnX = kWindowW - kMargin - kButtonW;
    s->btnApply = CreateButton(hwnd, L"应用", 0,
        SX(btnX), SY(kButtonY), SX(kButtonW), SY(kButtonH), IDC_BTN_APPLY, s->hFont);
    btnX -= (kButtonW + 4);
    s->btnCancel = CreateButton(hwnd, L"取消", 0,
        SX(btnX), SY(kButtonY), SX(kButtonW), SY(kButtonH), IDCANCEL, s->hFont);
    btnX -= (kButtonW + 4);
    s->btnOK = CreateButton(hwnd, L"确定", BS_DEFPUSHBUTTON,
        SX(btnX), SY(kButtonY), SX(kButtonW), SY(kButtonH), IDOK, s->hFont);

    // 初始显示第一个 tab
    ShowTab(s, 0);
}

// ============================================================================
// 窗口过程
// ============================================================================
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    DialogState* s = (DialogState*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

    // WM_CREATE 之前 s 为 nullptr，交由默认处理
    if (!s && msg != WM_CREATE) {
        return DefWindowProcW(hwnd, msg, wp, lp);
    }

    switch (msg) {
        case WM_CREATE: {
            auto cs = (CREATESTRUCTW*)lp;
            s = (DialogState*)cs->lpCreateParams;
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)s);
            s->hwnd = hwnd;

            // 创建字体（按窗口 DPI 缩放）
            double ratio = GetDPIRatio(hwnd);
            int dpi = (int)(ratio * 96.0 + 0.5);
            s->hFont = CreateFontW(-MulDiv(9, dpi, 72),
                0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            if (!s->hFont) {
                s->hFont = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
            }
            s->hFontTitle = CreateFontW(-MulDiv(18, dpi, 72), 0, 0, 0, FW_BOLD,
                FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            if (!s->hFontTitle) {
                s->hFontTitle = s->hFont;
            }

            CreateControls(s, hwnd);
            LoadSettingsToControls(s);
            return 0;
        }

        case WM_NOTIFY: {
            auto nmh = (NMHDR*)lp;
            if (nmh->hwndFrom == s->tabCtrl && nmh->code == TCN_SELCHANGE) {
                int sel = TabCtrl_GetCurSel(s->tabCtrl);
                ShowTab(s, sel);
            }
            return 0;
        }

        case WM_COMMAND: {
            WORD id = LOWORD(wp);
            WORD code = HIWORD(wp);

            switch (id) {
                case IDOK:
                    if (SaveControlsToSettings(s)) {
                        DestroyWindow(hwnd);
                    }
                    return TRUE;

                case IDCANCEL:
                    DestroyWindow(hwnd);
                    return TRUE;

                case IDC_BTN_APPLY:
                    SaveControlsToSettings(s);
                    return TRUE;

                case IDC_TRANSLATION_ENABLED:
                    if (code == BN_CLICKED) {
                        UpdateTranslationControlsVisibility(s);
                    }
                    return TRUE;

                case IDC_PROVIDER:
                    if (code == CBN_SELCHANGE) {
                        OnProviderChanged(s);
                    }
                    return TRUE;

                case IDC_BG_PICKER:
                    if (code == BN_CLICKED) OpenColorPicker(s->edtBgColor, s);
                    return TRUE;
                case IDC_ORIG_PICKER:
                    if (code == BN_CLICKED) OpenColorPicker(s->edtOrigColor, s);
                    return TRUE;
                case IDC_TRANS_PICKER:
                    if (code == BN_CLICKED) OpenColorPicker(s->edtTransColor, s);
                    return TRUE;
            }
            return FALSE;
        }

        case WM_HSCROLL: {
            if ((HWND)lp == s->sldOpacity) {
                int val = (int)SendMessageW(s->sldOpacity, TBM_GETPOS, 0, 0);
                wchar_t buf[16];
                swprintf_s(buf, L"%d%%", val);
                SetWindowTextW(s->lblOpacityVal, buf);
            }
            return 0;
        }

        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;

        case WM_NCDESTROY:
            if (s) {
                if (s->hFont) DeleteObject(s->hFont);
                if (s->hFontTitle && s->hFontTitle != s->hFont) DeleteObject(s->hFontTitle);
            }
            PostQuitMessage(0);
            return 0;

        case WM_CTLCOLORDLG:
            return (LRESULT)GetSysColorBrush(COLOR_BTNFACE);

        case WM_CTLCOLORSTATIC: {
            HDC hdc = (HDC)wp;
            SetBkMode(hdc, TRANSPARENT);
            return (LRESULT)GetSysColorBrush(COLOR_BTNFACE);
        }
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

} // namespace

// ============================================================================
// LOSettingsDialog::Show
// ============================================================================
void LOSettingsDialog::Show() {
    // 初始化通用控件
    INITCOMMONCONTROLSEX icc = {};
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_TAB_CLASSES | ICC_BAR_CLASSES | ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&icc);

    // 注册窗口类
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof(wc);
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = WndProc;
        wc.hInstance = g_hInstance;
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
        wc.lpszClassName = kClassName;
        if (RegisterClassExW(&wc) || GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
            registered = true;
        }
    }
    if (!registered) {
        LOLog(L"SettingsDialog: failed to register window class");
        return;
    }

    // 计算窗口尺寸（含标题栏与边框）。使用已 DPI 缩放的客户区尺寸 +
    // AdjustWindowRectEx（非 DPI 感知版本，但客户区已按 DPI 缩放，差异可忽略）
    RECT rc = { 0, 0, ScaleX(nullptr, kWindowW), ScaleY(nullptr, kWindowH) };
    AdjustWindowRectEx(&rc, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE, 0);
    int winW = rc.right - rc.left;
    int winH = rc.bottom - rc.top;

    // 居中到屏幕工作区
    RECT workArea;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &workArea, 0);
    int x = workArea.left + ((workArea.right - workArea.left) - winW) / 2;
    int y = workArea.top + ((workArea.bottom - workArea.top) - winH) / 2;

    // 创建窗口
    DialogState state;
    HWND hwnd = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        LO_APP_NAME L" 设置",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        x, y, winW, winH,
        nullptr, nullptr, g_hInstance, &state);
    if (!hwnd) {
        LOLog(L"SettingsDialog: CreateWindowEx failed, err=%u", GetLastError());
        return;
    }

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    // 模态消息循环
    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(hwnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    LOLog(L"SettingsDialog: closed");
}

#pragma once

#include <windows.h>

// ============================================================================
// LOSettingsDialog - 设置对话框
//
// 提供模态设置对话框，包含「翻译」「悬浮窗」「关于」三个标签页。
// 使用 Win32 通用控件（Tab Control、ComboBox、Edit、Trackbar 等）构建。
// 通过 LOSettings 全局单例加载/保存设置，保存后通知悬浮窗与翻译调度器刷新。
// ============================================================================
class LOSettingsDialog {
public:
    // 打开设置对话框（模态）。
    // 通常在独立线程中调用（见 LOTextService::OpenSettings），避免阻塞 TSF。
    static void Show();
};

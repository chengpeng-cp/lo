#pragma once

#include "Globals.h"
#include <msctf.h>
#include <atomic>
#include <memory>

class LORimeEngine;
class LORimeSessionManager;
class LOCandidateWindow;
class LOTranslationOverlay;
class LOTranslationScheduler;

// ============================================================================
// TextService - TSF 输入法文本服务
// 实现 ITfTextInputProcessorEx + ITfKeyEventSink + ITfCompositionSink
// ============================================================================

class LOTextService :
    public ITfTextInputProcessorEx,
    public ITfKeyEventSink,
    public ITfCompositionSink,
    public ITfThreadFocusSink,
    public ITfActiveLanguageProfileNotifySink
{
public:
    LOTextService();
    ~LOTextService();

    // --- IUnknown ---
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // --- ITfTextInputProcessorEx ---
    STDMETHODIMP Activate(ITfThreadMgr* pThreadMgr, TfClientId tfClientId) override;
    STDMETHODIMP Deactivate() override;
    STDMETHODIMP ActivateEx(ITfThreadMgr* pThreadMgr, TfClientId tfClientId, DWORD dwFlags) override;

    // --- ITfKeyEventSink ---
    STDMETHODIMP OnSetFocus(BOOL fForeground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) override;
    STDMETHODIMP OnKeyUp(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext* pContext, REFGUID rguid, BOOL* pfEaten) override;

    // --- ITfCompositionSink ---
    STDMETHODIMP OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) override;

    // --- ITfThreadFocusSink ---
    STDMETHODIMP OnSetThreadFocus() override;
    STDMETHODIMP OnKillThreadFocus() override;

    // --- ITfActiveLanguageProfileNotifySink ---
    STDMETHODIMP OnActivated(REFCLSID clsid, REFGUID guidProfile, BOOL fActivated) override;

    // --- 公共方法 ---
    void OpenSettings();
    void CommitPreedit();

    ITfThreadMgr* GetThreadMgr() const { return m_threadMgr; }
    TfClientId GetClientId() const { return m_clientId; }

private:
    // --- 初始化 ---
    HRESULT InitKeyEventSink();
    HRESULT InitThreadFocusSink();
    HRESULT InitActiveLanguageProfileSink();
    HRESULT InitDisplayAttributeProvider();
    void CleanupSinks();

    // --- 按键处理 ---
    bool HandleKeyDown(ITfContext* pContext, WPARAM wParam, LPARAM lParam);
    bool ShouldEatKey(WPARAM wParam, LPARAM lParam);

    // --- 编辑上下文 ---
    HRESULT BeginComposition(ITfContext* pContext);
    HRESULT EndComposition(ITfContext* pContext);
    HRESULT UpdateComposition(ITfContext* pContext, const std::wstring& preedit);
    HRESULT CommitText(ITfContext* pContext, const std::wstring& text);

    // --- 候选词 ---
    void ShowCandidates(ITfContext* pContext);
    void HideCandidates();
    void OnCandidateSelected(int index);
    void OnPageChange(bool backward);

    // --- 翻译 ---
    void OnCommitText(const std::wstring& text);

    // --- 引用计数 ---
    std::atomic<LONG> m_refCount;

    // --- TSF ---
    ITfThreadMgr* m_threadMgr;
    TfClientId m_clientId;
    DWORD m_keyEventSinkCookie;
    DWORD m_threadFocusSinkCookie;
    DWORD m_activeLangProfileCookie;
    ITfComposition* m_composition;
    TfEditCookie m_editCookie;

    // --- 引擎 ---
    std::shared_ptr<LORimeEngine> m_rimeEngine;
    std::unique_ptr<LORimeSessionManager> m_sessionManager;
    std::unique_ptr<LOCandidateWindow> m_candidateWindow;
    std::unique_ptr<LOTranslationOverlay> m_translationOverlay;
    std::unique_ptr<LOTranslationScheduler> m_translationScheduler;

    // --- 当前上下文 ---
    ITfContext* m_currentContext;
    bool m_isComposing;

    // --- 设置 ---
    void ApplySettings();
};

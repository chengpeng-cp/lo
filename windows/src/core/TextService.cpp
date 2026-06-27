#include "TextService.h"
#include "../rime/RimeEngine.h"
#include "../rime/RimeSessionManager.h"
#include "../ui/CandidateWindow.h"
#include "../ui/TranslationOverlay.h"
#include "../translation/TranslationScheduler.h"
#include "../settings/Settings.h"
#include "../settings/SettingsDialog.h"

#include <msctf.h>
#include <richedit.h>
#include <chrono>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")
#pragma comment(lib, "msctf.lib")

// ============================================================================
// 构造/析构
// ============================================================================

LOTextService::LOTextService()
    : m_refCount(1)
    , m_threadMgr(nullptr)
    , m_clientId(0)
    , m_keyEventSinkCookie(TF_INVALID_COOKIE)
    , m_threadFocusSinkCookie(TF_INVALID_COOKIE)
    , m_activeLangProfileCookie(TF_INVALID_COOKIE)
    , m_composition(nullptr)
    , m_editCookie(0)
    , m_currentContext(nullptr)
    , m_isComposing(false)
{
    LOLog(L"LOTextService 构造");
}

LOTextService::~LOTextService() {
    LOLog(L"LOTextService 析构");
}

// ============================================================================
// IUnknown
// ============================================================================

STDMETHODIMP LOTextService::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;

    if (IsEqualIID(riid, IID_IUnknown) ||
        IsEqualIID(riid, IID_ITfTextInputProcessor) ||
        IsEqualIID(riid, IID_ITfTextInputProcessorEx)) {
        *ppv = static_cast<ITfTextInputProcessorEx*>(this);
    } else if (IsEqualIID(riid, IID_ITfKeyEventSink)) {
        *ppv = static_cast<ITfKeyEventSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfCompositionSink)) {
        *ppv = static_cast<ITfCompositionSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfThreadFocusSink)) {
        *ppv = static_cast<ITfThreadFocusSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfActiveLanguageProfileNotifySink)) {
        *ppv = static_cast<ITfActiveLanguageProfileNotifySink*>(this);
    } else {
        return E_NOINTERFACE;
    }

    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) LOTextService::AddRef() {
    return InterlockedIncrement(&m_refCount);
}

STDMETHODIMP_(ULONG) LOTextService::Release() {
    LONG count = InterlockedDecrement(&m_refCount);
    if (count == 0) {
        delete this;
    }
    return count;
}

// ============================================================================
// ITfTextInputProcessor / ITfTextInputProcessorEx
// ============================================================================

STDMETHODIMP LOTextService::Activate(ITfThreadMgr* pThreadMgr, TfClientId tfClientId) {
    return ActivateEx(pThreadMgr, tfClientId, 0);
}

STDMETHODIMP LOTextService::Deactivate() {
    LOLog(L"Deactivate 开始");

    CleanupSinks();

    // 清理引擎
    if (m_candidateWindow) {
        m_candidateWindow->Hide();
    }
    if (m_translationOverlay) {
        m_translationOverlay->Hide();
    }
    if (m_translationScheduler) {
        m_translationScheduler->Reset();
    }
    if (m_sessionManager && m_rimeEngine) {
        m_sessionManager->RemoveAllSessions();
    }

    // 结束组合
    if (m_composition) {
        m_composition->Release();
        m_composition = nullptr;
    }

    m_candidateWindow.reset();
    // 单例不释放,仅断开引用
    m_translationOverlay = nullptr;
    m_translationScheduler = nullptr;
    m_sessionManager.reset();

    if (m_rimeEngine) {
        m_rimeEngine->Finalize();
        m_rimeEngine.reset();
    }

    m_threadMgr = nullptr;
    m_clientId = 0;

    LOLog(L"Deactivate 完成");
    return S_OK;
}

STDMETHODIMP LOTextService::ActivateEx(ITfThreadMgr* pThreadMgr, TfClientId tfClientId, DWORD dwFlags) {
    LOLog(L"ActivateEx 开始");

    m_threadMgr = pThreadMgr;
    m_clientId = tfClientId;

    // 1. 初始化 Rime 引擎
    m_rimeEngine = std::make_shared<LORimeEngine>();
    if (!m_rimeEngine->Initialize()) {
        LOLog(L"ActivateEx: Rime 引擎初始化失败");
        // 继续执行，即使 Rime 失败，也注册键盘事件接收按键
    }

    m_sessionManager = std::make_unique<LORimeSessionManager>(m_rimeEngine);

    // 2. 创建候选词窗口
    m_candidateWindow = std::make_unique<LOCandidateWindow>();
    m_candidateWindow->onCandidateSelected = [this](int index) {
        OnCandidateSelected(index);
    };
    m_candidateWindow->onPageChange = [this](bool backward) {
        OnPageChange(backward);
    };

    // 3. 创建翻译悬浮窗（单例，触发首次访问以绑定到 UI 线程）
    m_translationOverlay = &LOTranslationOverlay::Shared();
    m_translationOverlay->UpdateConfig();

    // 4. 创建翻译调度器并连接回调
    m_translationScheduler = &LOTranslationScheduler::Shared();
    m_translationScheduler->onOriginalUpdate = [](const std::wstring& text) {
        LOTranslationOverlay::Shared().SilentUpdateOriginal(text);
    };
    m_translationScheduler->onTranslationStart = [](const std::wstring& text) {
        LOTranslationOverlay::Shared().ShowLoading(text);
    };
    m_translationScheduler->onTranslationDelta = [](const std::wstring& /*original*/, const std::wstring& translation) {
        LOTranslationOverlay::Shared().UpdateTranslation(translation);
    };
    m_translationScheduler->onTranslationReady = [](const std::wstring& original, const std::wstring& translation) {
        LOTranslationOverlay::Shared().Show(original, translation);
    };
    m_translationScheduler->onTranslationFailed = [](const std::wstring& original, const std::wstring& error) {
        LOTranslationOverlay::Shared().ShowError(original, error);
    };
    m_translationScheduler->UpdateTranslator();

    // 5. 注册键盘事件接收器
    HRESULT hr = InitKeyEventSink();
    if (FAILED(hr)) {
        LOLog(L"ActivateEx: InitKeyEventSink 失败: 0x%08X", hr);
    }

    // 6. 注册线程焦点接收器
    hr = InitThreadFocusSink();
    if (FAILED(hr)) {
        LOLog(L"ActivateEx: InitThreadFocusSink 失败: 0x%08X", hr);
    }

    // 7. 注册活跃语言配置文件接收器
    hr = InitActiveLanguageProfileSink();
    if (FAILED(hr)) {
        LOLog(L"ActivateEx: InitActiveLanguageProfileSink 失败: 0x%08X", hr);
    }

    ApplySettings();
    LOLog(L"ActivateEx 完成");
    return S_OK;
}

// ============================================================================
// 键盘事件接收器初始化
// ============================================================================

HRESULT LOTextService::InitKeyEventSink() {
    ITfKeystrokeMgr* pKeystrokeMgr = nullptr;
    HRESULT hr = m_threadMgr->QueryInterface(IID_ITfKeystrokeMgr, (void**)&pKeystrokeMgr);
    if (FAILED(hr) || !pKeystrokeMgr) return hr;

    hr = pKeystrokeMgr->AdviseKeyEventSink(m_clientId, this, TRUE);
    pKeystrokeMgr->Release();
    return hr;
}

HRESULT LOTextService::InitThreadFocusSink() {
    ITfSource* pSource = nullptr;
    HRESULT hr = m_threadMgr->QueryInterface(IID_ITfSource, (void**)&pSource);
    if (FAILED(hr) || !pSource) return hr;

    hr = pSource->AdviseSink(IID_ITfThreadFocusSink, static_cast<ITfThreadFocusSink*>(this), &m_threadFocusSinkCookie);
    pSource->Release();
    return hr;
}

HRESULT LOTextService::InitActiveLanguageProfileSink() {
    ITfSource* pSource = nullptr;
    HRESULT hr = m_threadMgr->QueryInterface(IID_ITfSource, (void**)&pSource);
    if (FAILED(hr) || !pSource) return hr;

    hr = pSource->AdviseSink(IID_ITfActiveLanguageProfileNotifySink, static_cast<ITfActiveLanguageProfileNotifySink*>(this), &m_activeLangProfileCookie);
    pSource->Release();
    return hr;
}

void LOTextService::CleanupSinks() {
    // 键盘事件接收器
    if (m_threadMgr) {
        ITfKeystrokeMgr* pKeystrokeMgr = nullptr;
        if (SUCCEEDED(m_threadMgr->QueryInterface(IID_ITfKeystrokeMgr, (void**)&pKeystrokeMgr)) && pKeystrokeMgr) {
            pKeystrokeMgr->UnadviseKeyEventSink(m_clientId);
            pKeystrokeMgr->Release();
        }

        ITfSource* pSource = nullptr;
        if (SUCCEEDED(m_threadMgr->QueryInterface(IID_ITfSource, (void**)&pSource)) && pSource) {
            if (m_threadFocusSinkCookie != TF_INVALID_COOKIE) {
                pSource->UnadviseSink(m_threadFocusSinkCookie);
                m_threadFocusSinkCookie = TF_INVALID_COOKIE;
            }
            if (m_activeLangProfileCookie != TF_INVALID_COOKIE) {
                pSource->UnadviseSink(m_activeLangProfileCookie);
                m_activeLangProfileCookie = TF_INVALID_COOKIE;
            }
            pSource->Release();
        }
    }
    m_keyEventSinkCookie = TF_INVALID_COOKIE;
}

// ============================================================================
// ITfKeyEventSink
// ============================================================================

STDMETHODIMP LOTextService::OnSetFocus(BOOL fForeground) {
    return S_OK;
}

STDMETHODIMP LOTextService::OnTestKeyDown(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = ShouldEatKey(wParam, lParam) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP LOTextService::OnTestKeyUp(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;
    return S_OK;
}

STDMETHODIMP LOTextService::OnKeyDown(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = HandleKeyDown(pContext, wParam, lParam) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP LOTextService::OnKeyUp(ITfContext* pContext, WPARAM wParam, LPARAM lParam, BOOL* pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;
    return S_OK;
}

STDMETHODIMP LOTextService::OnPreservedKey(ITfContext* pContext, REFGUID rguid, BOOL* pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;
    return S_OK;
}

// ============================================================================
// 按键处理逻辑
// ============================================================================

bool LOTextService::ShouldEatKey(WPARAM wParam, LPARAM lParam) {
    if (!m_rimeEngine) return false;

    // Ctrl+逗号快捷复制翻译内容
    if (GetKeyState(VK_CONTROL) & 0x8000 && GetKeyState(VK_MENU) & 0x8000) {
        if (wParam == VK_OEM_COMMA || wParam == 'B' || wParam == 'N') {
            return true;
        }
    }

    // Command 组合键放行（Windows 上是 Win 键）
    if (GetKeyState(VK_LWIN) & 0x8000 || GetKeyState(VK_RWIN) & 0x8000) {
        return false;
    }

    // Ctrl 组合键放行（让应用处理复制粘贴等）
    if (GetKeyState(VK_CONTROL) & 0x8000) {
        return false;
    }

    // 字母、数字、标点、空格、退格等
    if ((wParam >= 'A' && wParam <= 'Z') ||
        (wParam >= '0' && wParam <= '9') ||
        wParam == VK_SPACE || wParam == VK_BACK ||
        wParam == VK_RETURN || wParam == VK_ESCAPE ||
        wParam == VK_TAB ||
        wParam >= VK_OEM_1 && wParam <= VK_OEM_102) {
        return true;
    }

    // 方向键
    if (wParam == VK_LEFT || wParam == VK_RIGHT ||
        wParam == VK_UP || wParam == VK_DOWN) {
        return true;
    }

    return false;
}

bool LOTextService::HandleKeyDown(ITfContext* pContext, WPARAM wParam, LPARAM lParam) {
    if (!m_rimeEngine || !m_sessionManager) return false;

    m_currentContext = pContext;

    // 获取当前线程 ID 作为客户端标识
    DWORD clientId = GetCurrentThreadId();
    RimeSessionId session = m_sessionManager->GetSession(clientId);
    if (session == 0) return false;

    // Ctrl+Alt+逗号：快捷复制翻译内容
    if ((GetKeyState(VK_CONTROL) & 0x8000) && (GetKeyState(VK_MENU) & 0x8000)) {
        if (wParam == VK_OEM_COMMA || wParam == 'B' || wParam == 'N') {
            if (LOTranslationOverlay::Shared().CopyLastTranslation()) {
                // 若正在组合输入，先清除
                if (m_rimeEngine->IsComposing(session)) {
                    m_rimeEngine->ClearComposition(session);
                    UpdateComposition(pContext, L"");
                }
                return true;
            }
        }
    }

    // Ctrl 组合键放行
    if (GetKeyState(VK_CONTROL) & 0x8000) {
        if (m_rimeEngine->IsComposing(session)) {
            m_rimeEngine->ClearComposition(session);
            UpdateComposition(pContext, L"");
            HideCandidates();
        }
        return false;
    }

    // 获取按键字符（用于字母键判断）
    wchar_t ch = 0;
    BYTE keyboardState[256];
    GetKeyboardState(keyboardState);
    ToUnicode((UINT)wParam, (UINT)lParam, keyboardState, &ch, 1, 0);

    // 候选词窗口可见时，方向键导航
    if (m_candidateWindow && m_candidateWindow->IsVisible() &&
        m_rimeEngine->IsComposing(session)) {
        switch (wParam) {
        case VK_RIGHT:
            m_candidateWindow->NavigateByArrow(true);
            return true;
        case VK_LEFT:
            m_candidateWindow->NavigateByArrow(false);
            return true;
        case VK_DOWN:
            OnPageChange(false);
            return true;
        case VK_UP:
            OnPageChange(true);
            return true;
        }
    }

    // 空格选词
    if (wParam == VK_SPACE &&
        m_candidateWindow && m_candidateWindow->IsVisible() &&
        m_rimeEngine->IsComposing(session)) {
        OnCandidateSelected(m_candidateWindow->GetSelectedIndex());
        return true;
    }

    // 转换按键码和修饰键
    int keycode = LORimeEngine::ConvertKeyCode(wParam, ch);
    if (keycode == 0) return false;

    // 组装修饰键标志
    DWORD modFlags = 0;
    if (GetKeyState(VK_SHIFT) & 0x8000) modFlags |= LO_MOD_SHIFT;
    if (GetKeyState(VK_CONTROL) & 0x8000) modFlags |= LO_MOD_CONTROL;
    if (GetKeyState(VK_MENU) & 0x8000) modFlags |= LO_MOD_ALT;
    if (GetKeyState(VK_LWIN) & 0x8000 || GetKeyState(VK_RWIN) & 0x8000) modFlags |= LO_MOD_SUPER;
    if (GetKeyState(VK_CAPITAL) & 0x0001) modFlags |= LO_MOD_CAPSLOCK;

    int modifiers = LORimeEngine::ConvertModifiers(modFlags, keycode);

    // 交给 Rime 处理
    bool handled = m_rimeEngine->ProcessKey(keycode, modifiers, session);

    // 通知翻译调度器用户正在输入
    if (m_rimeEngine->IsComposing(session)) {
        std::wstring preedit = m_rimeEngine->GetPreedit(session);
        m_translationScheduler->NoteTyping(preedit);
    }

    // 检查提交文本
    std::wstring commitText = m_rimeEngine->GetCommit(session);
    if (!commitText.empty()) {
        // 提交文本到客户端
        CommitText(pContext, commitText);
        // 交给翻译调度器
        OnCommitText(commitText);
    } else if (!handled) {
        // Rime 未处理：可打印 ASCII 字符直接交给翻译调度器
        if (ch != 0 && ch >= 0x20 && ch <= 0x7E &&
            !m_rimeEngine->IsComposing(session)) {
            std::wstring chars(1, ch);
            OnCommitText(chars);
        }
    }

    // 更新 UI
    if (m_rimeEngine->IsComposing(session)) {
        std::wstring preedit = m_rimeEngine->GetPreedit(session);
        UpdateComposition(pContext, preedit);
        ShowCandidates(pContext);
    } else {
        EndComposition(pContext);
        HideCandidates();
    }

    return handled;
}

// ============================================================================
// 组合编辑
// ============================================================================

HRESULT LOTextService::BeginComposition(ITfContext* pContext) {
    if (m_composition) return S_OK;

    ITfContextComposition* pContextComposition = nullptr;
    HRESULT hr = pContext->QueryInterface(IID_ITfContextComposition, (void**)&pContextComposition);
    if (FAILED(hr) || !pContextComposition) return hr;

    ITfRange* pRange = nullptr;
    TF_SELECTION selection;
    ULONG fetched = 0;
    if (SUCCEEDED(pContext->GetSelection(m_editCookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) && fetched > 0) {
        pRange = selection.range;
    }

    if (pRange) pRange->AddRef();

    hr = pContextComposition->StartComposition(m_editCookie, pRange, this, &m_composition);
    pContextComposition->Release();

    if (pRange) pRange->Release();
    m_isComposing = true;
    return hr;
}

HRESULT LOTextService::EndComposition(ITfContext* pContext) {
    if (!m_composition) {
        m_isComposing = false;
        return S_OK;
    }

    m_composition->EndComposition(m_editCookie);
    m_composition->Release();
    m_composition = nullptr;
    m_isComposing = false;
    return S_OK;
}

HRESULT LOTextService::UpdateComposition(ITfContext* pContext, const std::wstring& preedit) {
    if (!pContext) return E_POINTER;

    // 获取编辑会话
    ITfEditSession* pEditSession = nullptr;
    // 简化：直接在当前 edit cookie 上操作
    // 实际 TSF 需要通过 RequestEditSession，但为简化起见，
    // 这里使用直接写入方式（在 key event 回调的上下文中可行）

    if (preedit.empty()) {
        EndComposition(pContext);
        return S_OK;
    }

    // 开始组合
    if (!m_composition) {
        // 获取编辑 cookie
        ITfDocumentMgr* pDocMgr = nullptr;
        if (SUCCEEDED(pContext->GetDocumentMgr(&pDocMgr)) && pDocMgr) {
            ITfContext* pTopContext = nullptr;
            if (SUCCEEDED(pDocMgr->GetTop(&pTopContext)) && pTopContext) {
                // 使用 ITfContext::RequestEditSession 获取 edit cookie
                pTopContext->Release();
            }
            pDocMgr->Release();
        }
        // 简化处理：设置 marked text
        BeginComposition(pContext);
    }

    if (m_composition) {
        // 获取组合范围并设置文本
        ITfRange* pRange = nullptr;
        if (SUCCEEDED(m_composition->GetRange(&pRange)) && pRange) {
            // 设置预编辑文本
            BSTR bstrText = SysAllocStringLen(preedit.c_str(), (UINT)preedit.length());
            if (bstrText) {
                pRange->SetText(m_editCookie, TF_ST_CORRECTION, bstrText, (LONG)preedit.length());
                SysFreeString(bstrText);
            }
            pRange->Release();
        }
    }

    return S_OK;
}

HRESULT LOTextService::CommitText(ITfContext* pContext, const std::wstring& text) {
    if (!pContext || text.empty()) return E_INVALIDARG;

    // 结束组合（如果有）
    if (m_composition) {
        // 替换组合文本为提交文本
        ITfRange* pRange = nullptr;
        if (SUCCEEDED(m_composition->GetRange(&pRange)) && pRange) {
            BSTR bstrText = SysAllocStringLen(text.c_str(), (UINT)text.length());
            if (bstrText) {
                pRange->SetText(m_editCookie, 0, bstrText, (LONG)text.length());
                SysFreeString(bstrText);
            }
            pRange->Release();
        }
        m_composition->EndComposition(m_editCookie);
        m_composition->Release();
        m_composition = nullptr;
        m_isComposing = false;
    } else {
        // 无组合：在当前光标位置插入文本
        TF_SELECTION selection;
        ULONG fetched = 0;
        if (SUCCEEDED(pContext->GetSelection(m_editCookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) && fetched > 0) {
            BSTR bstrText = SysAllocStringLen(text.c_str(), (UINT)text.length());
            if (bstrText) {
                selection.range->SetText(m_editCookie, 0, bstrText, (LONG)text.length());
                SysFreeString(bstrText);
            }
            selection.range->Release();
        }
    }

    return S_OK;
}

// ============================================================================
// ITfCompositionSink
// ============================================================================

STDMETHODIMP LOTextService::OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) {
    LOLog(L"OnCompositionTerminated");
    if (m_composition) {
        m_composition->Release();
        m_composition = nullptr;
    }
    m_isComposing = false;
    HideCandidates();
    return S_OK;
}

// ============================================================================
// ITfThreadFocusSink
// ============================================================================

STDMETHODIMP LOTextService::OnSetThreadFocus() {
    return S_OK;
}

STDMETHODIMP LOTextService::OnKillThreadFocus() {
    // 线程失去焦点时隐藏 UI
    if (m_candidateWindow) m_candidateWindow->Hide();
    return S_OK;
}

// ============================================================================
// ITfActiveLanguageProfileNotifySink
// ============================================================================

STDMETHODIMP LOTextService::OnActivated(REFCLSID clsid, REFGUID guidProfile, BOOL fActivated) {
    if (fActivated) {
        LOLog(L"OnActivated: 输入法被激活");
        ApplySettings();
    } else {
        LOLog(L"OnActivated: 输入法被停用");
    }
    return S_OK;
}

// ============================================================================
// 候选词交互
// ============================================================================

void LOTextService::ShowCandidates(ITfContext* pContext) {
    if (!m_rimeEngine || !m_candidateWindow) return;

    DWORD clientId = GetCurrentThreadId();
    RimeSessionId session = m_sessionManager->GetSession(clientId);
    if (session == 0) return;

    auto candidates = m_rimeEngine->GetCandidates(session, 10);
    if (candidates.empty()) {
        HideCandidates();
    } else {
        m_candidateWindow->Show(candidates, pContext);
    }
}

void LOTextService::HideCandidates() {
    if (m_candidateWindow) {
        m_candidateWindow->Hide();
    }
}

void LOTextService::OnCandidateSelected(int index) {
    if (!m_rimeEngine || !m_sessionManager) return;

    DWORD clientId = GetCurrentThreadId();
    RimeSessionId session = m_sessionManager->GetSession(clientId);
    if (session == 0) return;

    m_rimeEngine->SelectCandidateOnCurrentPage(index, session);

    // 检查提交文本
    std::wstring commitText = m_rimeEngine->GetCommit(session);
    if (!commitText.empty() && m_currentContext) {
        CommitText(m_currentContext, commitText);
        OnCommitText(commitText);
    }

    // 更新 UI
    if (m_rimeEngine->IsComposing(session)) {
        std::wstring preedit = m_rimeEngine->GetPreedit(session);
        UpdateComposition(m_currentContext, preedit);
        ShowCandidates(m_currentContext);
    } else {
        EndComposition(m_currentContext);
        HideCandidates();
    }
}

void LOTextService::OnPageChange(bool backward) {
    if (!m_rimeEngine || !m_sessionManager) return;

    DWORD clientId = GetCurrentThreadId();
    RimeSessionId session = m_sessionManager->GetSession(clientId);
    if (session == 0) return;

    m_rimeEngine->ChangePage(backward, session);
    ShowCandidates(m_currentContext);
}

// ============================================================================
// 翻译
// ============================================================================

void LOTextService::OnCommitText(const std::wstring& text) {
    if (m_translationScheduler) {
        m_translationScheduler->Commit(text);
    }
}

// ============================================================================
// 设置
// ============================================================================

void LOTextService::ApplySettings() {
    // 重新加载设置
    LOSettings& s = LOSettingsGet();
    s = LOSettings::Load();

    // 更新悬浮窗配置
    if (m_translationOverlay) {
        m_translationOverlay->UpdateConfig();
    }

    // 更新翻译器
    if (m_translationScheduler) {
        m_translationScheduler->UpdateTranslator();
    }

    LOLog(L"ApplySettings: provider=%s, targetLang=%s, translationEnabled=%d",
        s.translationProvider.c_str(), s.targetLanguage.c_str(), s.translationEnabled);
}

void LOTextService::OpenSettings() {
    // 打开设置对话框
    if (m_threadMgr) {
        // 在独立线程中打开设置对话框，避免阻塞 TSF
        std::thread([]() {
            LOSettingsDialog::Show();
        }).detach();
    }
}

void LOTextService::CommitPreedit() {
    if (!m_rimeEngine || !m_sessionManager || !m_currentContext) return;

    DWORD clientId = GetCurrentThreadId();
    RimeSessionId session = m_sessionManager->GetSession(clientId);
    if (session == 0) return;

    if (m_rimeEngine->IsComposing(session)) {
        std::wstring rawInput = m_rimeEngine->GetRawInput(session);
        if (!rawInput.empty()) {
            CommitText(m_currentContext, rawInput);
        }
        m_rimeEngine->ClearComposition(session);
        EndComposition(m_currentContext);
        HideCandidates();
    }
}

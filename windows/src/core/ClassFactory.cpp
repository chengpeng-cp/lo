#include "ClassFactory.h"
#include "TextService.h"

// ============================================================================
// LOClassFactory 实现
// ============================================================================

STDMETHODIMP LOClassFactory::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;

    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) {
        *ppv = static_cast<IClassFactory*>(this);
    } else {
        return E_NOINTERFACE;
    }

    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) LOClassFactory::AddRef() {
    return InterlockedIncrement(&m_refCount);
}

STDMETHODIMP_(ULONG) LOClassFactory::Release() {
    LONG count = InterlockedDecrement(&m_refCount);
    if (count == 0) {
        delete this;
    }
    return count;
}

STDMETHODIMP LOClassFactory::CreateInstance(IUnknown* pUnkOuter, REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;

    if (pUnkOuter != nullptr) {
        return CLASS_E_NOAGGREGATION;
    }

    LOTextService* pService = new (std::nothrow) LOTextService();
    if (!pService) {
        return E_OUTOFMEMORY;
    }

    HRESULT hr = pService->QueryInterface(riid, ppv);
    pService->Release();
    return hr;
}

STDMETHODIMP LOClassFactory::LockServer(BOOL fLock) {
    if (fLock) {
        InterlockedIncrement(&g_serverLockCount);
    } else {
        InterlockedDecrement(&g_serverLockCount);
    }
    return S_OK;
}

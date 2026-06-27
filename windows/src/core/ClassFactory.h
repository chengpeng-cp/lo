#pragma once

#include "Globals.h"
#include <unknwn.h>

// ============================================================================
// COM ClassFactory - 创建 LOTextService 实例
// ============================================================================

class LOClassFactory : public IClassFactory
{
public:
    LOClassFactory() : m_refCount(1) {}
    ~LOClassFactory() {}

    // --- IUnknown ---
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // --- IClassFactory ---
    STDMETHODIMP CreateInstance(IUnknown* pUnkOuter, REFIID riid, void** ppv) override;
    STDMETHODIMP LockServer(BOOL fLock) override;

private:
    LONG m_refCount;
};

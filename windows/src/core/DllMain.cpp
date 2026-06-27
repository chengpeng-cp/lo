#include "Globals.h"
#include "ClassFactory.h"
#include <msctf.h>

// ============================================================================
// DLL 全局状态
// ============================================================================

LONG g_serverLockCount = 0;
LONG g_classFactoryRefCount = 0;
HINSTANCE g_hInstance = nullptr;

// ============================================================================
// DLL 入口
// ============================================================================

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    switch (reason) {
    case DLL_PROCESS_ATTACH:
        g_hInstance = hModule;
        DisableThreadLibraryCalls(hModule);
        break;
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}

// ============================================================================
// COM 导出函数
// ============================================================================

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;

    if (!IsEqualCLSID(rclsid, CLSID_LOTextService)) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }

    LOClassFactory* pFactory = new (std::nothrow) LOClassFactory();
    if (!pFactory) {
        return E_OUTOFMEMORY;
    }

    HRESULT hr = pFactory->QueryInterface(riid, ppv);
    pFactory->Release();
    return hr;
}

STDAPI DllCanUnloadNow() {
    return (g_serverLockCount == 0 && g_classFactoryRefCount == 0) ? S_OK : S_FALSE;
}

// ============================================================================
// COM 注册/注销
// ============================================================================

STDAPI DllRegisterServer() {
    return RegisterServer();
}

STDAPI DllUnregisterServer() {
    return UnregisterServer();
}

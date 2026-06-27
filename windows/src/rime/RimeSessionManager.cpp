#include "RimeSessionManager.h"

// ============================================================================
// 构造 / 析构
// ============================================================================

LORimeSessionManager::LORimeSessionManager(LORimeEngine* engine)
    : m_engine(engine) {
    InitializeCriticalSection(&m_cs);
}

LORimeSessionManager::~LORimeSessionManager() {
    RemoveAllSessions();
    DeleteCriticalSection(&m_cs);
}

// ============================================================================
// 会话管理
// ============================================================================

RimeSessionId LORimeSessionManager::GetSession(DWORD clientId) {
    EnterCriticalSection(&m_cs);

    RimeSessionId id = 0;
    auto it = m_sessions.find(clientId);
    if (it != m_sessions.end()) {
        id = it->second;
    } else if (m_engine) {
        id = m_engine->CreateSession();
        if (id != 0) {
            m_sessions[clientId] = id;
        }
    }

    LeaveCriticalSection(&m_cs);
    return id;
}

void LORimeSessionManager::RemoveSession(DWORD clientId) {
    EnterCriticalSection(&m_cs);

    auto it = m_sessions.find(clientId);
    if (it != m_sessions.end()) {
        if (m_engine) {
            m_engine->DestroySession(it->second);
        }
        m_sessions.erase(it);
    }

    LeaveCriticalSection(&m_cs);
}

void LORimeSessionManager::RemoveAllSessions() {
    EnterCriticalSection(&m_cs);

    if (m_engine) {
        for (auto& pair : m_sessions) {
            m_engine->DestroySession(pair.second);
        }
    }
    m_sessions.clear();

    LeaveCriticalSection(&m_cs);
}

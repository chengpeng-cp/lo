#pragma once

// ============================================================================
// 语境输入法 Windows 版 - Rime 会话管理器
// 将客户端标识（线程 ID）映射到 RimeSessionId，线程安全
// ============================================================================

#include <windows.h>
#include <unordered_map>

#include "RimeEngine.h"

class LORimeSessionManager {
public:
    explicit LORimeSessionManager(LORimeEngine* engine);
    ~LORimeSessionManager();

    // 禁止拷贝
    LORimeSessionManager(const LORimeSessionManager&) = delete;
    LORimeSessionManager& operator=(const LORimeSessionManager&) = delete;

    // 获取或创建指定客户端的会话，返回 0 表示失败
    RimeSessionId GetSession(DWORD clientId);
    // 移除并销毁指定客户端的会话
    void RemoveSession(DWORD clientId);
    // 移除并销毁所有会话
    void RemoveAllSessions();

private:
    LORimeEngine* m_engine;
    std::unordered_map<DWORD, RimeSessionId> m_sessions;
    CRITICAL_SECTION m_cs;
};

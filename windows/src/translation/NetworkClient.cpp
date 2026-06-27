#include "NetworkClient.h"
#include "../core/Globals.h"
#include <winhttp.h>

// 30 秒超时
static const int kTimeoutMs = 30000;

// ============================================================================
// 构造 / 析构
// ============================================================================

LONetworkClient& LONetworkClient::Shared() {
    static LONetworkClient instance;
    return instance;
}

LONetworkClient::LONetworkClient() : m_session(nullptr) {
    m_session = WinHttpOpen(L"LOInputMethod/1.0",
                            WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (m_session) {
        WinHttpSetTimeouts(m_session,
                           kTimeoutMs,  // 解析超时
                           kTimeoutMs,  // 连接超时
                           kTimeoutMs,  // 发送超时
                           kTimeoutMs); // 接收超时
    }
}

LONetworkClient::~LONetworkClient() {
    if (m_session) {
        WinHttpCloseHandle(m_session);
        m_session = nullptr;
    }
}

// ============================================================================
// URL 解析
// ============================================================================

bool LONetworkClient::CrackUrl(const std::wstring& url, UrlParts& parts) {
    URL_COMPONENTS uc = {};
    uc.dwStructSize = sizeof(uc);

    wchar_t schemeBuf[16] = {};
    wchar_t hostBuf[256] = {};
    wchar_t pathBuf[2048] = {};

    uc.lpszScheme = schemeBuf;
    uc.dwSchemeLength = _countof(schemeBuf);
    uc.lpszHostName = hostBuf;
    uc.dwHostNameLength = _countof(hostBuf);
    uc.lpszUrlPath = pathBuf;
    uc.dwUrlPathLength = _countof(pathBuf);
    // 不解析用户名/密码/额外信息

    if (!WinHttpCrackUrl(url.c_str(), (DWORD)url.size(), 0, &uc)) {
        LOLog(L"[Net] WinHttpCrackUrl 失败，url=%s，错误码=%lu\r\n", url.c_str(), GetLastError());
        return false;
    }

    parts.scheme = (uc.lpszScheme && uc.dwSchemeLength) ? std::wstring(uc.lpszScheme, uc.dwSchemeLength) : L"https";
    parts.host = (uc.lpszHostName && uc.dwHostNameLength) ? std::wstring(uc.lpszHostName, uc.dwHostNameLength) : L"";
    parts.port = uc.nPort;
    parts.path = (uc.lpszUrlPath && uc.dwUrlPathLength) ? std::wstring(uc.lpszUrlPath, uc.dwUrlPathLength) : L"/";
    if (parts.path.empty()) parts.path = L"/";
    parts.isHttps = (uc.nScheme == INTERNET_SCHEME_HTTPS);
    return true;
}

// ============================================================================
// 公共接口
// ============================================================================

bool LONetworkClient::Request(const std::wstring& url,
                              const std::string& body,
                              const std::vector<std::pair<std::string, std::string>>& headers,
                              bool isPost,
                              std::string& responseOut) {
    responseOut.clear();
    UrlParts parts;
    if (!CrackUrl(url, parts)) return false;
    return DoRequest(parts, body, headers, isPost, false, nullptr, responseOut);
}

bool LONetworkClient::RequestStream(const std::wstring& url,
                                    const std::string& body,
                                    const std::vector<std::pair<std::string, std::string>>& headers,
                                    std::function<bool(const std::string&)> onLine) {
    std::string dummy;
    UrlParts parts;
    if (!CrackUrl(url, parts)) return false;
    return DoRequest(parts, body, headers, true, true, onLine, dummy);
}

// ============================================================================
// 通用请求执行
// ============================================================================

bool LONetworkClient::DoRequest(const UrlParts& parts,
                                 const std::string& body,
                                 const std::vector<std::pair<std::string, std::string>>& headers,
                                 bool isPost,
                                 bool stream,
                                 std::function<bool(const std::string&)> onLine,
                                 std::string& responseOut) {
    responseOut.clear();
    if (!m_session) {
        LOLog(L"[Net] session 未初始化\r\n");
        return false;
    }

    HINTERNET hConnect = WinHttpConnect(m_session, parts.host.c_str(), parts.port, 0);
    if (!hConnect) {
        LOLog(L"[Net] WinHttpConnect 失败，host=%s，错误码=%lu\r\n", parts.host.c_str(), GetLastError());
        return false;
    }

    DWORD flags = WINHTTP_FLAG_REFRESH;
    if (parts.isHttps) flags |= WINHTTP_FLAG_SECURE;

    HINTERNET hRequest = WinHttpOpenRequest(hConnect,
                                            isPost ? L"POST" : L"GET",
                                            parts.path.c_str(),
                                            nullptr, WINHTTP_NO_REFERER,
                                            WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hRequest) {
        LOLog(L"[Net] WinHttpOpenRequest 失败，错误码=%lu\r\n", GetLastError());
        WinHttpCloseHandle(hConnect);
        return false;
    }

    // 添加请求头
    for (const auto& h : headers) {
        std::wstring headerLine = LOUtf8ToWide(h.first) + L": " + LOUtf8ToWide(h.second) + L"\r\n";
        WinHttpAddRequestHeaders(hRequest, headerLine.c_str(), (DWORD)-1,
                                 WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
    }

    // 发送请求
    const void* bodyPtr = body.empty() ? WINHTTP_NO_REQUEST_DATA : body.data();
    DWORD bodyLen = body.empty() ? 0 : (DWORD)body.size();
    if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            const_cast<void*>(bodyPtr), bodyLen, bodyLen, 0)) {
        LOLog(L"[Net] WinHttpSendRequest 失败，错误码=%lu\r\n", GetLastError());
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        return false;
    }

    if (!WinHttpReceiveResponse(hRequest, nullptr)) {
        LOLog(L"[Net] WinHttpReceiveResponse 失败，错误码=%lu\r\n", GetLastError());
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        return false;
    }

    // 检查状态码
    DWORD statusCode = 0;
    DWORD statusSize = sizeof(statusCode);
    WinHttpQueryHeaders(hRequest,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusSize, WINHTTP_NO_HEADER_INDEX);
    if (statusCode < 200 || statusCode >= 300) {
        LOLog(L"[Net] HTTP 状态码异常=%lu\r\n", statusCode);
        // 仍读取响应体用于错误诊断
    }

    // 读取响应数据
    bool ok = true;
    std::string lineBuf;  // 用于 SSE 行缓冲

    while (true) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &avail)) {
            LOLog(L"[Net] WinHttpQueryDataAvailable 失败，错误码=%lu\r\n", GetLastError());
            ok = false;
            break;
        }
        if (avail == 0) break;  // 读取完毕

        std::vector<char> chunk(avail);
        DWORD read = 0;
        if (!WinHttpReadData(hRequest, chunk.data(), avail, &read)) {
            LOLog(L"[Net] WinHttpReadData 失败，错误码=%lu\r\n", GetLastError());
            ok = false;
            break;
        }
        if (read == 0) break;

        if (stream) {
            // SSE：按行切分，以 \n 为分隔
            for (DWORD i = 0; i < read; ++i) {
                char c = chunk[i];
                if (c == '\n') {
                    // 去掉行尾 \r
                    if (!lineBuf.empty() && lineBuf.back() == '\r') lineBuf.pop_back();
                    // 检查是否为 "data:" 行
                    if (lineBuf.size() >= 5 &&
                        (lineBuf[0] == 'd' || lineBuf[0] == 'D') &&
                        (lineBuf[1] == 'a' || lineBuf[1] == 'A') &&
                        (lineBuf[2] == 't' || lineBuf[2] == 'T') &&
                        (lineBuf[3] == 'a' || lineBuf[3] == 'A') &&
                        lineBuf[4] == ':') {
                        // 提取冒号后的内容，跳过可选空格
                        size_t start = 5;
                        while (start < lineBuf.size() && (lineBuf[start] == ' ' || lineBuf[start] == '\t')) ++start;
                        std::string data(lineBuf.begin() + start, lineBuf.end());
                        if (onLine && !onLine(data)) {
                            ok = true; // 客户端主动中止
                            lineBuf.clear();
                            goto done;
                        }
                    }
                    lineBuf.clear();
                } else {
                    lineBuf.push_back(c);
                }
            }
        } else {
            responseOut.append(chunk.data(), read);
        }
    }

    // 处理流式模式下最后未换行的行
    if (stream && ok && !lineBuf.empty()) {
        if (!lineBuf.empty() && lineBuf.back() == '\r') lineBuf.pop_back();
        if (lineBuf.size() >= 5 &&
            (lineBuf[0] == 'd' || lineBuf[0] == 'D') &&
            (lineBuf[1] == 'a' || lineBuf[1] == 'A') &&
            (lineBuf[2] == 't' || lineBuf[2] == 'T') &&
            (lineBuf[3] == 'a' || lineBuf[3] == 'A') &&
            lineBuf[4] == ':') {
            size_t start = 5;
            while (start < lineBuf.size() && (lineBuf[start] == ' ' || lineBuf[start] == '\t')) ++start;
            std::string data(lineBuf.begin() + start, lineBuf.end());
            if (onLine) onLine(data);
        }
    }

done:
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    return ok;
}

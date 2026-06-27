#pragma once

#include <windows.h>
#include <winhttp.h>
#include <string>
#include <vector>
#include <functional>
#include <utility>

#pragma comment(lib, "winhttp.lib")

// ============================================================================
// 基于 WinHTTP 的 HTTP 客户端
// 提供 同步请求 与 SSE 流式请求 两种模式
// ============================================================================

class LONetworkClient {
public:
    static LONetworkClient& Shared();

    // 同步 HTTP 请求
    //   url        : 完整 URL，例如 https://api.example.com/path?query=1
    //   body       : 请求体（GET 时传空字符串）
    //   headers    : 请求头列表 (name, value)，name/value 均为 UTF-8 字符串
    //   isPost     : true=POST，false=GET
    //   responseOut: 接收响应体（UTF-8 编码）
    //   返回值     : 成功与否
    bool Request(const std::wstring& url,
                 const std::string& body,
                 const std::vector<std::pair<std::string, std::string>>& headers,
                 bool isPost,
                 std::string& responseOut);

    // SSE 流式请求（POST）
    //   对每个 "data:" 行调用 onLine，传入去掉 "data: " 前缀后的内容
    //   onLine 返回 false 表示中止接收
    //   返回值: 成功与否
    bool RequestStream(const std::wstring& url,
                       const std::string& body,
                       const std::vector<std::pair<std::string, std::string>>& headers,
                       std::function<bool(const std::string&)> onLine);

private:
    LONetworkClient();
    ~LONetworkClient();
    LONetworkClient(const LONetworkClient&) = delete;
    LONetworkClient& operator=(const LONetworkClient&) = delete;

    struct UrlParts {
        std::wstring scheme;
        std::wstring host;
        INTERNET_PORT port = 0;
        std::wstring path;   // 含 query
        bool isHttps = true;
    };

    bool CrackUrl(const std::wstring& url, UrlParts& parts);

    // 通用请求执行：stream=true 时按 SSE 行回调，否则收集完整响应
    bool DoRequest(const UrlParts& parts,
                   const std::string& body,
                   const std::vector<std::pair<std::string, std::string>>& headers,
                   bool isPost,
                   bool stream,
                   std::function<bool(const std::string&)> onLine,
                   std::string& responseOut);

    HINTERNET m_session;
};

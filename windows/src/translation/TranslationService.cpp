#include "TranslationService.h"
#include "../core/Globals.h"

// ============================================================================
// LOJsonValue 辅助方法
// ============================================================================

const LOJsonValue* LOJsonValue::Find(const std::wstring& key) const {
    if (type != Object) return nullptr;
    for (const auto& kv : objVal) {
        if (kv.first == key) return &kv.second;
    }
    return nullptr;
}

const LOJsonValue* LOJsonValue::At(size_t i) const {
    if (type != Array) return nullptr;
    if (i >= arrVal.size()) return nullptr;
    return &arrVal[i];
}

// ============================================================================
// 提供商配置
// ============================================================================

const std::vector<LOProviderConfig>& LOGetProviderConfigs() {
    static const std::vector<LOProviderConfig> configs = {
        { L"bing",       L"Bing 翻译（免费）",                       L"",                                                         true,  false },
        { L"deepseek",   L"DeepSeek",                                L"https://api.deepseek.com/v1/chat/completions",             false, true  },
        { L"glm",        L"智谱 GLM",                                L"https://open.bigmodel.cn/api/paas/v4/chat/completions",    false, true  },
        { L"qwen",       L"通义千问 Qwen",                           L"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", false, true },
        { L"kimi",       L"Kimi（月之暗面）",                        L"https://api.moonshot.cn/v1/chat/completions",               false, true  },
        { L"minimax",    L"MiniMax",                                 L"https://api.minimax.chat/v1/text/chatcompletion_v2",        false, true  },
        { L"openai",     L"OpenAI",                                  L"https://api.openai.com/v1/chat/completions",               false, true  },
        { L"volcengine", L"火山引擎（豆包）",                        L"https://ark.cn-beijing.volces.com/api/v3/chat/completions", false, true },
        { L"custom",     L"自定义",                                  L"",                                                         false, true  },
    };
    return configs;
}

const LOProviderConfig* LOFindProviderConfig(const std::wstring& id) {
    for (const auto& c : LOGetProviderConfigs()) {
        if (c.id == id) return &c;
    }
    return nullptr;
}

// ============================================================================
// JSON 字符串转义
// ============================================================================

std::wstring LOEscapeJsonString(const std::wstring& s) {
    std::wstring out;
    out.reserve(s.size() + 8);
    for (wchar_t c : s) {
        switch (c) {
            case L'"':  out += L"\\\""; break;
            case L'\\': out += L"\\\\"; break;
            case L'\b': out += L"\\b"; break;
            case L'\f': out += L"\\f"; break;
            case L'\n': out += L"\\n"; break;
            case L'\r': out += L"\\r"; break;
            case L'\t': out += L"\\t"; break;
            default:
                if (c < 0x20) {
                    wchar_t buf[8];
                    swprintf_s(buf, L"\\u%04x", (unsigned)c);
                    out += buf;
                } else {
                    out += c;
                }
                break;
        }
    }
    return out;
}

// ============================================================================
// 最小 JSON 解析器（递归下降）
// ============================================================================

namespace {

struct JsonParser {
    const char* p;     // 当前指针
    const char* end;    // 结尾

    JsonParser(const char* s, size_t n) : p(s), end(s + n) {}

    void SkipWs() {
        while (p < end) {
            char c = *p;
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { ++p; }
            else break;
        }
    }

    bool ParseValue(LOJsonValue& out) {
        SkipWs();
        if (p >= end) return false;
        char c = *p;
        if (c == '{') return ParseObject(out);
        if (c == '[') return ParseArray(out);
        if (c == '"') { out.type = LOJsonValue::String; return ParseString(out.strVal); }
        if (c == 't' || c == 'f') return ParseBool(out);
        if (c == 'n') return ParseNull(out);
        return ParseNumber(out);
    }

    bool ParseObject(LOJsonValue& out) {
        out.type = LOJsonValue::Object;
        ++p; // 跳过 '{'
        SkipWs();
        if (p < end && *p == '}') { ++p; return true; }
        while (p < end) {
            SkipWs();
            if (p >= end || *p != '"') return false;
            std::wstring key;
            if (!ParseString(key)) return false;
            SkipWs();
            if (p >= end || *p != ':') return false;
            ++p;
            LOJsonValue val;
            if (!ParseValue(val)) return false;
            out.objVal.emplace_back(std::move(key), std::move(val));
            SkipWs();
            if (p >= end) return false;
            if (*p == ',') { ++p; continue; }
            if (*p == '}') { ++p; return true; }
            return false;
        }
        return false;
    }

    bool ParseArray(LOJsonValue& out) {
        out.type = LOJsonValue::Array;
        ++p; // 跳过 '['
        SkipWs();
        if (p < end && *p == ']') { ++p; return true; }
        while (p < end) {
            LOJsonValue val;
            if (!ParseValue(val)) return false;
            out.arrVal.push_back(std::move(val));
            SkipWs();
            if (p >= end) return false;
            if (*p == ',') { ++p; continue; }
            if (*p == ']') { ++p; return true; }
            return false;
        }
        return false;
    }

    bool ParseString(std::wstring& out) {
        out.clear();
        ++p; // 跳过开头的 '"'
        while (p < end) {
            unsigned char c = (unsigned char)*p;
            if (c == '"') { ++p; return true; }
            if (c == '\\') {
                ++p;
                if (p >= end) return false;
                char e = *p++;
                switch (e) {
                    case '"':  out += L'"'; break;
                    case '\\': out += L'\\'; break;
                    case '/':  out += L'/'; break;
                    case 'b':  out += L'\b'; break;
                    case 'f':  out += L'\f'; break;
                    case 'n':  out += L'\n'; break;
                    case 'r':  out += L'\r'; break;
                    case 't':  out += L'\t'; break;
                    case 'u': {
                        if (p + 4 > end) return false;
                        unsigned code = 0;
                        for (int i = 0; i < 4; ++i) {
                            char h = *p++;
                            code <<= 4;
                            if (h >= '0' && h <= '9') code |= (h - '0');
                            else if (h >= 'a' && h <= 'f') code |= (h - 'a' + 10);
                            else if (h >= 'A' && h <= 'F') code |= (h - 'A' + 10);
                            else return false;
                        }
                        // 处理代理对
                        if (code >= 0xD800 && code <= 0xDBFF && p + 6 <= end && *p == '\\' && *(p + 1) == 'u') {
                            p += 2;
                            unsigned low = 0;
                            for (int i = 0; i < 4; ++i) {
                                char h = *p++;
                                low <<= 4;
                                if (h >= '0' && h <= '9') low |= (h - '0');
                                else if (h >= 'a' && h <= 'f') low |= (h - 'a' + 10);
                                else if (h >= 'A' && h <= 'F') low |= (h - 'A' + 10);
                                else { return false; }
                            }
                            unsigned full = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                            out += (wchar_t)full;
                        } else {
                            out += (wchar_t)code;
                        }
                        break;
                    }
                    default: return false;
                }
            } else {
                // UTF-8 多字节处理
                if (c < 0x80) {
                    out += (wchar_t)c;
                    ++p;
                } else {
                    int extra = 0;
                    wchar_t ch = 0;
                    if ((c & 0xE0) == 0xC0) { extra = 1; ch = c & 0x1F; }
                    else if ((c & 0xF0) == 0xE0) { extra = 2; ch = c & 0x0F; }
                    else if ((c & 0xF8) == 0xF0) { extra = 3; ch = c & 0x07; }
                    else { ++p; continue; } // 非法字节，跳过
                    ++p;
                    if (p + extra > end) return false;
                    for (int i = 0; i < extra; ++i) {
                        unsigned char b = (unsigned char)*p++;
                        if ((b & 0xC0) != 0x80) return false;
                        ch = (ch << 6) | (b & 0x3F);
                    }
                    out += ch;
                }
            }
        }
        return false;
    }

    bool ParseNumber(LOJsonValue& out) {
        out.type = LOJsonValue::Number;
        const char* start = p;
        if (p < end && (*p == '-' || *p == '+')) ++p;
        while (p < end && ((*p >= '0' && *p <= '9') || *p == '.' || *p == 'e' || *p == 'E' || *p == '+' || *p == '-')) ++p;
        if (p == start) return false;
        std::string numStr(start, p);
        try { out.numVal = std::stod(numStr); } catch (...) { return false; }
        return true;
    }

    bool ParseBool(LOJsonValue& out) {
        out.type = LOJsonValue::Bool;
        if (end - p >= 4 && p[0] == 't' && p[1] == 'r' && p[2] == 'u' && p[3] == 'e') {
            out.boolVal = true; p += 4; return true;
        }
        if (end - p >= 5 && p[0] == 'f' && p[1] == 'a' && p[2] == 'l' && p[3] == 's' && p[4] == 'e') {
            out.boolVal = false; p += 5; return true;
        }
        return false;
    }

    bool ParseNull(LOJsonValue& out) {
        out.type = LOJsonValue::Null;
        if (end - p >= 4 && p[0] == 'n' && p[1] == 'u' && p[2] == 'l' && p[3] == 'l') {
            p += 4; return true;
        }
        return false;
    }
};

} // namespace

bool LOParseJson(const std::string& utf8, LOJsonValue& out) {
    if (utf8.empty()) return false;
    JsonParser parser(utf8.data(), utf8.size());
    if (!parser.ParseValue(out)) return false;
    parser.SkipWs();
    return parser.p == parser.end;
}

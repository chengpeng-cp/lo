#include "RimeEngine.h"

#include <shlobj.h>
#include <cstring>
#include <utility>

// ============================================================================
// 局部工具
// ============================================================================

namespace {

// 等价于 RIME_STRUCT_INIT 宏：清零结构体并设置 data_size 字段
// data_size = sizeof(T) - sizeof(data_size) （data_size 为结构体首字段，int 类型）
template <typename T>
void RimeStructInit(T& s) {
    std::memset(&s, 0, sizeof(T));
    s.data_size = sizeof(T) - sizeof(s.data_size);
}

} // namespace

// ============================================================================
// 构造 / 析构
// ============================================================================

LORimeEngine::LORimeEngine()
    : m_api(nullptr)
    , m_initialized(false) {
}

LORimeEngine::~LORimeEngine() {
    Finalize();
}

// ============================================================================
// 初始化
// ============================================================================

bool LORimeEngine::Initialize() {
    if (m_initialized) return true;

    m_api = rime_get_api();
    if (!m_api) {
        LOLog(L"[Rime] rime_get_api() 失败，无法获取 librime API");
        return false;
    }

    // 共享数据目录：DLL 同级目录下的 rime 子目录
    m_sharedDataDir = GetModuleDir() + L"\\rime";
    // 用户数据目录：%LOCALAPPDATA%\LOInputMethod\rime
    m_userDir = GetUserDataDir();
    EnsureUserDirExists();

    // 将宽字符路径转为 UTF-8 供 Rime 使用（librime 接收 char* UTF-8 字符串）
    std::string sharedDataDirUtf8 = LOWideToUtf8(m_sharedDataDir);
    std::string userDirUtf8 = LOWideToUtf8(m_userDir);
    std::string distNameUtf8 = LOWideToUtf8(L"语境输入法");
    std::string distCodeNameUtf8 = "lo";
    std::string distVersionUtf8 = "1.0.0";
    std::string appNameUtf8 = "rime.lo";

    RimeTraits traits;
    RimeStructInit(traits);
    traits.shared_data_dir = sharedDataDirUtf8.c_str();
    traits.user_data_dir = userDirUtf8.c_str();
    traits.distribution_name = distNameUtf8.c_str();
    traits.distribution_code_name = distCodeNameUtf8.c_str();
    traits.distribution_version = distVersionUtf8.c_str();
    traits.app_name = appNameUtf8.c_str();

    // 先 setup 再 initialize（与 macOS 版本保持一致）
    m_api->setup(&traits);
    m_api->initialize(&traits);

    // 同步等待部署完成，确保 schema 已加载
    if (m_api->start_maintenance(1)) {
        m_api->join_maintenance_thread();
    }

    m_initialized = true;
    LOLog(L"[Rime] 初始化完成，shared=%s user=%s", m_sharedDataDir.c_str(), m_userDir.c_str());
    return true;
}

void LORimeEngine::Finalize() {
    if (!m_initialized) return;
    if (m_api) {
        m_api->finalize();
    }
    m_initialized = false;
    LOLog(L"[Rime] 已释放");
}

// ============================================================================
// 会话管理
// ============================================================================

RimeSessionId LORimeEngine::CreateSession() {
    if (!m_api) return 0;
    return m_api->create_session();
}

void LORimeEngine::DestroySession(RimeSessionId id) {
    if (!m_api || !id) return;
    m_api->destroy_session(id);
}

// ============================================================================
// 按键处理
// ============================================================================

bool LORimeEngine::ProcessKey(int keycode, int modifiers, RimeSessionId session) {
    if (!m_api || !session) return false;
    return m_api->process_key(session, keycode, modifiers) != 0;
}

// ============================================================================
// 输出获取
// ============================================================================

std::wstring LORimeEngine::GetCommit(RimeSessionId session) {
    if (!m_api || !session) return L"";
    RimeCommit commit;
    RimeStructInit(commit);
    if (!m_api->get_commit(session, &commit)) return L"";
    std::wstring result = commit.text ? LOUtf8ToWide(commit.text) : L"";
    m_api->free_commit(&commit);
    return result;
}

std::vector<LOCandidate> LORimeEngine::GetCandidates(RimeSessionId session, int count) {
    std::vector<LOCandidate> result;
    if (!m_api || !session) return result;

    RimeContext ctx;
    RimeStructInit(ctx);
    if (!m_api->get_context(session, &ctx)) return result;

    int num = ctx.menu.num_candidates;
    if (num > count) num = count;
    if (ctx.menu.candidates) {
        for (int i = 0; i < num; i++) {
            LOCandidate c;
            c.text = ctx.menu.candidates[i].text
                ? LOUtf8ToWide(ctx.menu.candidates[i].text) : L"";
            c.comment = ctx.menu.candidates[i].comment
                ? LOUtf8ToWide(ctx.menu.candidates[i].comment) : L"";
            result.push_back(std::move(c));
        }
    }
    m_api->free_context(&ctx);
    return result;
}

std::wstring LORimeEngine::GetPreedit(RimeSessionId session) {
    if (!m_api || !session) return L"";
    RimeContext ctx;
    RimeStructInit(ctx);
    if (!m_api->get_context(session, &ctx)) return L"";
    std::wstring result = ctx.composition.preedit
        ? LOUtf8ToWide(ctx.composition.preedit) : L"";
    m_api->free_context(&ctx);
    return result;
}

std::wstring LORimeEngine::GetRawInput(RimeSessionId session) {
    if (!m_api || !session) return L"";
    const char* raw = m_api->get_input(session);
    if (!raw) return L"";
    return LOUtf8ToWide(raw);
}

// ============================================================================
// 状态查询
// ============================================================================

bool LORimeEngine::IsComposing(RimeSessionId session) {
    if (!m_api || !session) return false;
    RimeStatus status;
    RimeStructInit(status);
    if (!m_api->get_status(session, &status)) return false;
    bool result = status.is_composing != 0;
    m_api->free_status(&status);
    return result;
}

bool LORimeEngine::IsAsciiMode(RimeSessionId session) {
    if (!m_api || !session) return false;
    RimeStatus status;
    RimeStructInit(status);
    if (!m_api->get_status(session, &status)) return false;
    bool result = status.is_ascii_mode != 0;
    m_api->free_status(&status);
    return result;
}

void LORimeEngine::SetAsciiMode(bool enabled, RimeSessionId session) {
    if (!m_api || !session) return;
    m_api->set_option(session, "ascii_mode", enabled ? 1 : 0);
}

// ============================================================================
// 组合控制
// ============================================================================

void LORimeEngine::ClearComposition(RimeSessionId session) {
    if (!m_api || !session) return;
    m_api->clear_composition(session);
}

std::wstring LORimeEngine::CommitComposition(RimeSessionId session) {
    if (!m_api || !session) return L"";
    m_api->commit_composition(session);
    return GetCommit(session);
}

void LORimeEngine::SelectCandidateOnCurrentPage(int index, RimeSessionId session) {
    if (!m_api || !session) return;
    m_api->select_candidate_on_current_page(session, index);
}

void LORimeEngine::ChangePage(bool backward, RimeSessionId session) {
    if (!m_api || !session) return;
    m_api->change_page(session, backward ? 1 : 0);
}

// ============================================================================
// 路径
// ============================================================================

std::wstring LORimeEngine::GetSharedDataDir() {
    if (m_sharedDataDir.empty()) {
        m_sharedDataDir = GetModuleDir() + L"\\rime";
    }
    return m_sharedDataDir;
}

std::wstring LORimeEngine::GetModuleDir() {
    wchar_t path[MAX_PATH];
    DWORD len = GetModuleFileNameW(g_hInstance, path, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return L"";
    std::wstring dir(path);
    size_t pos = dir.find_last_of(L"\\/");
    if (pos != std::wstring::npos) dir = dir.substr(0, pos);
    return dir;
}

std::wstring LORimeEngine::GetUserDataDir() {
    wchar_t localAppData[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData))) {
        return std::wstring(localAppData) + L"\\LOInputMethod\\rime";
    }
    return L"C:\\LOInputMethod\\rime";
}

void LORimeEngine::EnsureUserDirExists() {
    std::wstring dir = GetUserDataDir();
    // 创建父目录 \LOInputMethod（CreateDirectoryW 仅创建单级目录）
    size_t pos = dir.find_last_of(L"\\/");
    if (pos != std::wstring::npos) {
        CreateDirectoryW(dir.substr(0, pos).c_str(), nullptr);
    }
    CreateDirectoryW(dir.c_str(), nullptr);
}

// ============================================================================
// 按键码转换
// ============================================================================

int LORimeEngine::ConvertKeyCode(WPARAM wParam, wchar_t ch) {
    // 字母键 a-z / A-Z：统一返回小写字母值（0x61-0x7A）
    if (ch >= L'a' && ch <= L'z') {
        return static_cast<int>(ch);
    }
    if (ch >= L'A' && ch <= L'Z') {
        return static_cast<int>(ch - L'A' + L'a');
    }

    // 数字键 0-9：VK_0(0x30)-VK_9(0x39) 映射到 0x30-0x39（恒等映射）
    if (wParam >= '0' && wParam <= '9') {
        return static_cast<int>(wParam);
    }

    // 特殊键映射
    switch (wParam) {
    case VK_RETURN:  return 0xFF0D;  // XK_Return
    case VK_TAB:     return 0xFF09;   // XK_Tab
    case VK_SPACE:   return 0x0020;   // XK_space
    case VK_BACK:    return 0xFF08;   // XK_BackSpace
    case VK_ESCAPE:  return 0xFF1B;   // XK_Escape
    case VK_LEFT:    return 0xFF51;   // XK_Left
    case VK_UP:      return 0xFF52;   // XK_Up
    case VK_RIGHT:   return 0xFF53;   // XK_Right
    case VK_DOWN:    return 0xFF54;   // XK_Down
    case VK_SHIFT:
        // 通过 GetKeyState 区分左 / 右 Shift
        return (GetKeyState(VK_RSHIFT) & 0x8000) ? 0xFFE2 : 0xFFE1;
    case VK_CONTROL: return 0xFFE3;   // XK_Control_L
    case VK_MENU:    return 0xFE03;   // XK_ISO_Level3_Shift（Alt）
    case VK_CAPITAL: return 0xFFE5;   // XK_Caps_Lock
    }

    // 可打印 ASCII 字符（标点、符号等 0x20-0x7E）：直接返回字符值
    if (ch >= 0x20 && ch <= 0x7E) {
        return static_cast<int>(ch);
    }

    return 0;
}

int LORimeEngine::ConvertModifiers(DWORD modifiers, int keycode) {
    int mask = 0;

    // 若当前按键本身即 Shift 键，不传递 kShiftMask
    bool isShiftKey = (keycode == 0xFFE1 || keycode == 0xFFE2);
    if (!isShiftKey && (modifiers & LO_MOD_SHIFT)) {
        mask |= (1 << 0);  // kShiftMask
    }
    if (modifiers & LO_MOD_CONTROL) {
        mask |= (1 << 2);  // kControlMask
    }
    if (modifiers & LO_MOD_ALT) {
        mask |= (1 << 3);  // kAltMask
    }
    if (modifiers & LO_MOD_SUPER) {
        mask |= (1 << 6);  // kSuperMask
    }
    if (modifiers & LO_MOD_CAPSLOCK) {
        mask |= (1 << 1);  // kLockMask
    }

    return mask;
}

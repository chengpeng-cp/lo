# 项目长期记忆

## 卸载/清理相关约定

- macOS 清理逻辑只维护一份：`macos/scripts/uninstall.sh`。GUI（`macos/Uninstaller`）与打包脚本都复用它；新增残留路径时先改脚本，再同步 Swift 里的原生补充逻辑（目前只有输入源列表）。
- 发布只出一个 macOS 镜像 `语境输入法-<版本>.dmg`，里面同时放「语境输入法安装器.app」和「语境输入法卸载工具.app」；`package-uninstaller.sh` 只用于开发时单独打卸载 DMG（`--app-only` 供 package.sh 复用）。
- 命令行卸载会先 `sudo` 清理 `/Library/Input Methods`，成功后才动用户数据，避免半卸载状态；磁盘清理失败会让 `--system-only` 返回非 0，GUI 据此中止。
- Windows 清理逻辑集中在 `windows/installer/cleanup.nsh` 的宏里，`installer.nsi` 卸载区段与 `uninstaller.nsi` 必须同时复用，避免两套实现漂移。
- 卸载工具默认清空 Rime 词库与用户词典（`--purge`），但检测到其他 Rime 输入法数据时只删 `build/`、`installation.yaml`、`user.yaml`、`luna_pinyin*`、`LOInputMethod.log`。
- 本机构建 Swift 包时若报 sandbox-exec 权限错误，使用 `swift build --disable-sandbox`。
- macOS 的中英文切换是**输入法内部模式**（对齐微信输入法）：`LOShiftMonitor` 每 30ms 轮询 Shift 状态识别短按，直接切 Rime `ascii_mode`，不切系统输入源、不需要辅助功能权限、不依赖 App 转发 flagsChanged。菜单栏仍显示「语境」，这是刻意设计。CapsLock 切系统 ABC 仍交给 macOS 原生逻辑，微信/飞书等应用可能不生效。
- 本地打包含稳定开发证书：`CODESIGN_IDENTITY="LO Input Method Development"`，否则 ad-hoc 签名变化会让辅助功能授权在重装后失效；CI 无证书时回退 ad-hoc。

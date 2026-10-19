import Foundation

/// Keep path quoting and the replace/rollback transaction independent of the UI.
enum InstallerScripts {
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func install(payload: String, target: String, userBundle: String) -> String {
        let suffix = UUID().uuidString
        return """
        #!/bin/bash
        set -euo pipefail
        payload=\(shellQuote(payload))
        target=\(shellQuote(target))
        user_bundle=\(shellQuote(userBundle))
        lsregister='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister'
        staging=\(shellQuote(target + ".install-" + suffix))
        backup=\(shellQuote(target + ".backup-" + suffix))
        installed=0
        committed=0
        cleanup() {
            status=$?
            trap - EXIT
            if [ "$status" -ne 0 ] && [ "$committed" -eq 0 ]; then
                if [ "$installed" -eq 1 ]; then /bin/rm -rf "$target"; fi
                if [ -e "$backup" ]; then /bin/mv "$backup" "$target"; fi
            fi
            /bin/rm -rf "$staging"
            exit "$status"
        }
        trap cleanup EXIT
        # Remove stale LaunchServices entries created by older installers while
        # running as root. The replacement is registered later in the user's session.
        "$lsregister" -u "$target" 2>/dev/null || true
        "$lsregister" -u "$user_bundle" 2>/dev/null || true
        /bin/mkdir -p "$(/usr/bin/dirname "$target")"
        /usr/bin/ditto "$payload" "$staging"
        /usr/bin/codesign --verify --deep --strict "$staging"
        /usr/bin/killall LOInputMethod 2>/dev/null || true
        if [ -e "$target" ]; then /bin/mv "$target" "$backup"; fi
        /bin/mv "$staging" "$target"
        installed=1
        /usr/bin/codesign --verify --deep --strict "$target"
        # The verified replacement is now authoritative. Backup removal may be partial
        # when an old file is locked, so cleanup must never roll back after this point.
        committed=1
        if [ "$user_bundle" != "$target" ]; then
            if ! /bin/rm -rf "$user_bundle"; then
                printf 'LO_INSTALL_CLEANUP_WARNING: New version retained; old user bundle could not be fully removed: %s\\n' "$user_bundle"
            fi
        fi
        if ! /bin/rm -rf "$backup"; then
            printf 'LO_INSTALL_CLEANUP_WARNING: New version retained; old backup could not be fully removed: %s\\n' "$backup"
        fi
        echo LO_INSTALL_DONE
        """
    }
}

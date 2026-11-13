#!/usr/bin/env bash
# Update xpm in the live environment before a pacman-backend install starts.
# This helper is pacman-only: the xpm backend uses the bundled live xpm and
# never falls back to pacman for bootstrap.
#
# The live xpm is the bootstrap version; the target still installs xpm/xpm-aur
# from [x] through the normal backend.

update_live_xpm_pacman() {
    command -v pacman >/dev/null 2>&1 || {
        echo "early-xpm: pacman unavailable; using bundled xpm" >&2
        return 0
    }
    if ! network_online; then
        echo "early-xpm: no network; using bundled xpm" >&2
        return 0
    fi
    local old
    old="$(mktemp /run/xpm-bundled.XXXXXX)"
    if ! cp -f "$(command -v xpm)" "$old" 2>/dev/null; then
        old=""
    fi
    echo "== updating live xpm from [x]"
    if ! pacman -Sy --noconfirm >/dev/null 2>&1; then
        echo "early-xpm: repository sync failed; using bundled xpm" >&2
        [[ -n "$old" ]] && rm -f "$old"
        return 0
    fi
    if ! pacman -S --noconfirm --needed xpm >/dev/null 2>&1; then
        echo "early-xpm: xpm upgrade failed; using bundled xpm" >&2
        [[ -n "$old" ]] && rm -f "$old"
        return 0
    fi
    hash -r
    if xpm --version >/dev/null 2>&1; then
        xpm --version | head -1
        network_ui_ok "live xpm updated"
        [[ -n "$old" ]] && rm -f "$old"
        return 0
    fi
    if [[ -n "$old" ]]; then
        echo "early-xpm: updated xpm is unusable; restoring bundled binary" >&2
        cp -f "$old" "$(command -v xpm)" 2>/dev/null || true
        rm -f "$old"
    fi
    return 0
}

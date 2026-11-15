#!/usr/bin/env bash
set -euo pipefail

# Create the post-first-boot generation once. The installer records 0001 as
# the installation baseline; the first boot finishes systemd presets and other
# boot-time setup, so 0002 is the first generation that describes the running
# system as users see it. The marker lives on @xstate, outside snapshots.
STATE="${X_GEN_STATE:-/var/lib/x}"
MARKER="$STATE/first-boot.done"
INSTALL_GEN="$STATE/generations/0001/manifest.json"

[[ -f "$MARKER" ]] && exit 0
[[ -f "$INSTALL_GEN" ]] || exit 0
command -v x >/dev/null 2>&1 || exit 0

current="$(cat "$STATE/current" 2>/dev/null || true)"
if [[ -n "$current" && "$current" != "0001" ]]; then
    # A first-boot generation already exists (or the state was migrated).
    touch "$MARKER"
    exit 0
fi

x gen new --reason first-boot --label "first boot"
touch "$MARKER"

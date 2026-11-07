#!/usr/bin/env bash
set -euo pipefail

# x installer entry point in the live environment. Runs the configurator and, if
# confirmed, the installer. With X_DRY=1 it only shows the plan.
#   X_SKIP_INSTALLER=1  skips the installer (useful in dev/tests)

if [[ "${X_SKIP_INSTALLER:-0}" == "1" ]]; then
    echo "x-install: skipped"
    exit 0
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/ui.sh"
source "$DIR/network.sh"

if [[ "${X_DRY:-0}" == "1" ]]; then
    JSON="${X_INSTALL_JSON:-/tmp/x-install.json}"
    [[ -f "$JSON" ]] || printf '{"disk":"/dev/sda","hostname":"x","username":"x","password":""}\n' > "$JSON"
    bash "$DIR/install.sh"
    exit 0
fi

echo "== X Installer =="
# Network is needed before the configurator so WiFi can be selected before any
# destructive disk operation, and so the live xpm can be refreshed later.
if ! network_setup; then
    echo "installer: no network; connect Ethernet or WiFi and run xinstall again" >&2
    exit 1
fi
bash "$DIR/configurator.sh" || exit 1
bash "$DIR/install.sh"

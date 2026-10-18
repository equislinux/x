#!/usr/bin/env bash
set -euo pipefail

# Static checks for the installer defaults that do not need a VM:
# the created user must get zsh installed in every profile and as its shell.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$SRC/airootfs/root/x-installer/install.sh"
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        printf 'ok - %s\n' "$desc"
    else
        printf 'FAIL - %s\n' "$desc"
        FAIL=1
    fi
}

check "install.sh has valid bash syntax" bash -n "$INST"
check "zsh is in the unconditional base package set" \
    grep -Eq '^EXTRA="\$EXTRA .*\bzsh\b' "$INST"
check "the user is created with /usr/bin/zsh" \
    grep -q 'useradd -m -G wheel -s /usr/bin/zsh' "$INST"
check "the installer verifies zsh before creating the user" \
    grep -q 'command -v zsh >/dev/null && grep -qx /usr/bin/zsh /etc/shells' "$INST"
check "the core profile no longer duplicates zsh" \
    bash -c "! grep -q 'PKGS=\"\$EXTRA vim zsh\"' '$INST'"

if [[ "$FAIL" -eq 0 ]]; then
    echo "installer-defaults: OK"
else
    echo "installer-defaults: failures detected"
    exit 1
fi

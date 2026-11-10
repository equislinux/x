#!/usr/bin/env bash
set -euo pipefail

# Unattended autoinstall. It activates ONLY if the cmdline carries xauto=1 and
# a disk labeled cidata containing x-install.json exists.
#   /dev/disk/by-label/cidata  ->  x-install.json  ({"disk":"/dev/vda", ...})
# Runs as a systemd service (x-autoinstall.service) in the live environment.

dbg() {
    printf 'autoinstall: %s\n' "$*" >/dev/ttyS0 2>/dev/null || printf 'autoinstall: %s\n' "$*" >/dev/console 2>/dev/null || true
}

dbg "cmdline: $(cat /proc/cmdline)"

grep -Fqa 'xauto=1' /proc/cmdline || {
    dbg "no xauto=1; skipping"
    exit 0
}

udevadm settle || true

CIMNT=/run/cidata
mkdir -p "$CIMNT"

DEV="$(blkid -L cidata 2>/dev/null || true)"
dbg "cidata dev: ${DEV:-none}"

if [[ -z "$DEV" ]]; then
    dbg "no cidata disk; skipping"
    exit 0
fi

if ! mount -o ro "$DEV" "$CIMNT"; then
    dbg "could not mount cidata at $CIMNT"
    exit 0
fi

JSON="$CIMNT/x-install.json"
if [[ ! -f "$JSON" ]]; then
    dbg "x-install.json missing on cidata; skipping"
    umount "$CIMNT"
    exit 0
fi

if [[ -f "$CIMNT/x-install.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CIMNT/x-install.env"
    set +a
fi

dbg "unattended install from $DEV"
export X_AUTO=1
LOG=/tmp/x-install.log
set +e
# Stream the log to the service console (ttyS0) as the install progresses so a
# hang is visible without waiting for the final cat.
X_INSTALL_JSON="$JSON" bash -x /root/x-installer/install.sh 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
dbg "install.sh rc=$rc"
umount "$CIMNT"
exit "$rc"

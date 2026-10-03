#!/usr/bin/env bash
set -euo pipefail

pacman-key --init
pacman-key --populate archlinux

# Trust the project [x] repository key in the live keyring. The published
# database and packages are signed; the installer prepares the target keyring
# from this one (pacstrap without -K), and the live [x] repo is Required.
if [[ -f /etc/pacman.d/x-repo.pub ]]; then
    pacman-key --add /etc/pacman.d/x-repo.pub
    X_KEY_FPR="$(LC_ALL=C gpg --with-colons --show-keys /etc/pacman.d/x-repo.pub 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
    if [[ -n "$X_KEY_FPR" ]]; then
        pacman-key --lsign-key "$X_KEY_FPR"
    else
        echo "warning: could not resolve the [x] key fingerprint" >&2
    fi
fi

# Autoinstall service (only activates with xauto=1 + cidata).
systemctl enable x-autoinstall.service >/dev/null 2>&1 || true

# Network in the live environment (DHCP) for the installer and rescue.
# NetworkManager is the single manager: the stock iwd/networkd symlinks were
# removed so two managers do not fight over the same NIC.
systemctl enable NetworkManager.service >/dev/null 2>&1 || true
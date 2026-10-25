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
check "configurator offers an optional virtualization stack" \
    grep -q 'virtualization' "$SRC/airootfs/root/x-installer/configurator.sh"
check "install.sh reads the virtualization option" \
    grep -q 'jget virtualization' "$INST"
check "virtualization installs qemu, libvirt and virt-manager" \
    grep -q 'qemu-desktop.*libvirt.*virt-manager' "$INST"
check "virtualization adds the user to kvm and libvirt" \
    grep -q 'usermod -aG kvm,libvirt' "$INST"
check "virtualization enables socket activation" \
    grep -q 'systemctl enable libvirtd.socket virtlogd.socket' "$INST"
check "virtualization autostarts the default libvirt network" \
    grep -q 'networks/autostart/default.xml' "$INST"
check "configurator offers Hyprland, niri, KDE and none" \
    grep -q 'Desktop environment' "$SRC/airootfs/root/x-installer/configurator.sh"
check "install.sh reads the desktop option" \
    grep -q 'jget desktop' "$INST"
check "KDE installs Plasma and bundles the X settings package" \
    bash -c "grep -q 'plasma-meta kde-applications' '$INST' && ls '$SRC'/airootfs/root/x-installer/packages/x-kde-settings-*.pkg.tar.zst >/dev/null 2>&1"
check "niri uses the equisdots niri installer" \
    grep -q '/usr/share/x/tools/niri-install.sh' "$INST"
check "KDE enables SDDM" \
    grep -q 'systemctl enable sddm.service' "$INST"

if [[ "$FAIL" -eq 0 ]]; then
    echo "installer-defaults: OK"
else
    echo "installer-defaults: failures detected"
    exit 1
fi

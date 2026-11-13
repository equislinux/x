#!/usr/bin/env bash
set -euo pipefail

# Static checks for the installer defaults that do not need a VM:
# the created user must get zsh installed in every profile and as its shell.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$SRC/airootfs/root/x-installer/install.sh"
CONF="$SRC/airootfs/root/x-installer/configurator.sh"
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
check "the live ISO ships xpm" \
    grep -qx 'xpm' "$SRC/packages.x86_64"
check "the live xpm configuration is valid TOML" \
    python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$SRC/airootfs/etc/xpm.conf"
check "the live xpm configuration uses the native keyring" \
    python3 -c 'import sys, tomllib; o = tomllib.load(open(sys.argv[1], "rb"))["options"]; assert o["root_dir"] == "/"; assert o["db_path"] == "/var/lib/xpm"; assert o["cache_dir"] == "/var/cache/xpm/pkg"; assert o["gpg_dir"] == "/etc/xpm/gnupg"; assert "pacman_db" not in o; assert o["mirror_pacman"] is False; assert o["shell_integration"] is False; assert o["sig_level"] == "required"' "$SRC/airootfs/etc/xpm.conf"
check "the live xpm configuration trusts x, core and extra" \
    python3 -c 'import sys, tomllib; r = tomllib.load(open(sys.argv[1], "rb"))["repo"]; assert [x["name"] for x in r[:3]] == ["x", "core", "extra"]; assert r[0]["server"] == ["https://equislinux.github.io/x-repo/repo/x86_64"]; assert r[0]["sig_level"] == "required"; assert all("$repo" in x["server"][0] and "$arch" in x["server"][0] for x in r[1:3])' "$SRC/airootfs/etc/xpm.conf"
check "install.sh reads the backend from the JSON seed" \
    grep -q 'jget backend' "$INST"
check "install.sh accepts X_INSTALL_BACKEND and defaults to pacman" \
    bash -c "grep -q 'X_INSTALL_BACKEND' '$INST' && grep -q 'BACKEND:-pacman' '$INST'"
check "install.sh validates the backend" \
    grep -q 'invalid backend' "$INST"
check "mkinitcpio is an explicit package" \
    grep -q 'linux-firmware mkinitcpio' "$INST"
check "xpm is installed in the target for the xpm backend" \
    grep -q 'BACKEND" == "xpm" ]] && EXTRA="$EXTRA xpm"' "$INST"
check "xpm gets a target bootstrap configuration" \
    grep -q 'xpm_write_config "$XPM_BOOTSTRAP" "$MNT"' "$INST"
check "xpm gets a target runtime configuration" \
    grep -q 'xpm_write_config "$MNT/etc/xpm.conf"' "$INST"
check "xpm uses a native GnuPG keyring without shell integration" \
    bash -c "grep -q 'XPM_GPGDIR=\"\$dir\" /usr/local/bin/x-repo-key' '$INST' && grep -q -- '--no-shell-integration' '$INST'"
check "xpm refuses to fall back when native flags are missing" \
    bash -c "grep -q -- '--no-alpm-hooks' '$INST' && grep -q 'refusing to fall back to pacman' '$INST'"
check "xpm installs base before the remaining profile" \
    bash -c "grep -q -- '--scriptlets=auto --no-confirm install --needed base' '$INST' && grep -q -- '--scriptlets=auto --no-confirm install --needed \$PKGS' '$INST'"
check "installer offers the base package manager choice" \
    bash -c "grep -q 'Package manager for the base system' '$CONF' && grep -q '\"backend\":\"\$BACKEND\"' '$CONF'"
check "xpm backend requires a post-parity target xpm" \
    grep -q '0.1.0-4' "$INST"
check "configurator refuses xpm without the native flags" \
    grep -q 'refusing to fall back to pacman' "$CONF"
check "xpm backend checks the target supports --no-alpm-hooks" \
    grep -q 'xpm_check_target_backend' "$INST"
check "xpm does not mirror or import pacman databases" \
    bash -c "! sed -n '/# XPM-BACKEND-BEGIN/,/# XPM-BACKEND-END/p' '$INST' | grep -Eq '(^|[^[:alnum:]_])(sync-pacman-db|import-pacman|pacman_db|mirror_pacman)([^[:alnum:]_]|$)'"
check "the xpm branch contains no pacman calls" \
    bash -c "! sed -n '/# XPM-BACKEND-BEGIN/,/# XPM-BACKEND-END/p' '$INST' | grep -Eq '(^|[^[:alnum:]_])(pacman|pacman-key|pacstrap|sync-pacman-db|import-pacman)([^[:alnum:]_]|$)'"
check "the xpm local kernel path uses xpm, not pacman" \
    bash -c "! sed -n '/^install_local_x_kernel_xpm()/,/^}/p' '$INST' | grep -Eq '(^|[^[:alnum:]_])(pacman|pacman-key|pacstrap|sync-pacman-db|import-pacman)([^[:alnum:]_]|$)'"
check "the xpm local kernel path verifies detached signatures" \
    grep -q 'gpg --batch --homedir "\$gpgdir" --verify "\$main.sig" "\$main"' "$INST"
check "the pacman branch keeps pacstrap and pacman -U" \
    bash -c "sed -n '/# PACMAN-BACKEND-BEGIN/,/# PACMAN-BACKEND-END/p' '$INST' | grep -q 'pacstrap' && sed -n '/# PACMAN-BACKEND-BEGIN/,/# PACMAN-BACKEND-END/p' '$INST' | grep -q 'pacman -U'"
check "the pacman backend still initializes pacman-key" \
    grep -q 'pacman-key --gpgdir "\$GPGDIR" --init' "$INST"
check "live boot services do not run pacman-key" \
    bash -c "! grep -Rqs 'pacman-key' '$SRC/airootfs/etc/systemd/system' '$SRC/airootfs/usr/local/bin/x-repo-key'"
check "pacman-init is not enabled in the live image" \
    bash -c "! test -e '$SRC/airootfs/etc/systemd/system/pacman-init.service' && ! test -e '$SRC/airootfs/etc/systemd/system/multi-user.target.wants/pacman-init.service'"
check "x-keyring prepares the native xpm keyring" \
    bash -c "grep -q 'ExecStart=/usr/local/bin/x-repo-key' '$SRC/airootfs/etc/systemd/system/x-keyring.service' && ! grep -q 'pacman-init' '$SRC/airootfs/etc/systemd/system/x-keyring.service'"
check "xpm verifies the installed xpm before the first generation" \
    grep -q 'the installed xpm cannot query its database' "$INST"
check "target pseudo filesystems are unmounted before genfstab" \
    bash -c "awk 'index(\$0, \"xpm_unbind_pseudo || exit 1\") {u=NR} /^genfstab / {g=NR} END {exit !(u && g && u < g)}' '$INST'"
check "the xpm backend finalizes the target before genfstab" \
    bash -c "grep -q 'depmod -a' '$INST' && grep -q 'mkinitcpio -P' '$INST'"
check "e2e harness exposes --backend" \
    grep -q -- '"--backend"' "$SRC/tests/e2e-autoinstall.py"
check "e2e harness seeds the backend" \
    grep -q '"backend":"{self.args.backend}"' "$SRC/tests/e2e-autoinstall.py"
check "e2e harness uses xpm query for the xpm backend" \
    grep -q 'xpm query' "$SRC/tests/e2e-autoinstall.py"

if [[ "$FAIL" -eq 0 ]]; then
    echo "installer-defaults: OK"
else
    echo "installer-defaults: failures detected"
    exit 1
fi

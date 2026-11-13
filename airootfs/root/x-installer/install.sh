#!/usr/bin/env bash
set -euo pipefail

# X installer: partitions, installs packages with xpm or pacstrap, configures,
# provisions and installs the bootloader in chroot.
#   X_INSTALL_JSON  config path (default /tmp/x-install.json)
#   X_DRY=1         validate and print the plan only (tests)

source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/network.sh"
source "$(dirname "${BASH_SOURCE[0]}")/early-xpm.sh"

JSON="${X_INSTALL_JSON:-/tmp/x-install.json}"
DRY="${X_DRY:-0}"

jget() {
    sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$JSON"
}

[[ -f "$JSON" ]] || { echo "installer: $JSON does not exist (run the configurator)" >&2; exit 1; }

DISK="$(jget disk)"
HOST="$(jget hostname)"
USER="$(jget username)"
PASS="$(jget password)"
LANG_CODE="$(jget language)";         LANG_CODE="${LANG_CODE:-en}"
LOCALE="$(jget locale)";              LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="$(jget keyboard)";            KEYMAP="${KEYMAP:-us}"
TIMEZONE="$(jget timezone)";          TIMEZONE="${TIMEZONE:-UTC}"
PROFILE="$(jget profile)";            PROFILE="${PROFILE:-full}"
BOOT="$(jget bootloader)";            BOOT="${BOOT:-grub}"
ENC="$(jget encryption)";             ENC="${ENC:-no}"
LUKS_PASS="$(jget luks_password)"
HYPR="$(jget hyprland)";              HYPR="${HYPR:-no}"
HYPR_REF="$(jget hyprland_ref)"
case "$HYPR" in yes|online) ;; *) HYPR="no" ;; esac
DESKTOP="$(jget desktop)"
if [[ -z "$DESKTOP" ]]; then
    case "$HYPR" in yes|online) DESKTOP="hyprland" ;; *) DESKTOP="none" ;; esac
elif [[ "$DESKTOP" == "hyprland" ]]; then
    # New selector: Hyprland is always full online.
    HYPR="online"
fi
case "$DESKTOP" in hyprland|niri|kde|none) ;; *) echo "installer: invalid desktop '$DESKTOP' (hyprland|niri|kde|none)" >&2; exit 1 ;; esac
[[ "$DESKTOP" == "hyprland" ]] || HYPR="no"
AGENTS="$(jget agents)";              AGENTS="${AGENTS:-no}"
VIRT="$(jget virtualization)";        VIRT="${VIRT:-no}"
case "$VIRT" in yes|no) ;; *) VIRT="no" ;; esac
MODE="$(jget mode)";                  MODE="${MODE:-wipe}"
ESP_OVERRIDE="$(jget esp)"
MIN_SIZE="$(jget min_size)";          MIN_SIZE="${MIN_SIZE:-20}"
KERNEL="$(jget kernel)";              KERNEL="${KERNEL:-linux}"
KERNEL_PARAMS="$(jget kernel_params)"
BACKEND="$(jget backend)"
BACKEND="${X_INSTALL_BACKEND:-${BACKEND:-pacman}}"
WIFI_SSID="$(jget wifi_ssid)"
WIFI_PASSWORD="$(jget wifi_password)"
export X_WIFI_SSID="${X_WIFI_SSID:-$WIFI_SSID}"
export X_WIFI_PASSWORD="${X_WIFI_PASSWORD:-$WIFI_PASSWORD}"

[[ -n "$DISK" && -n "$HOST" && -n "$USER" ]] || { echo "installer: incomplete JSON" >&2; exit 1; }
case "$BACKEND" in
    pacman|xpm) ;;
    *) echo "installer: invalid backend '$BACKEND' (pacman|xpm)" >&2; exit 1 ;;
esac
[[ "$MODE" == "wipe" || "$MODE" == "dualboot" ]] || { echo "installer: invalid mode '$MODE' (wipe|dualboot)" >&2; exit 1; }
[[ "$MIN_SIZE" =~ ^[0-9]+$ ]] || { echo "installer: min_size must be a number of GiB" >&2; exit 1; }
case "$KERNEL" in
    linux|linux-lts|linux-zen|linux-hardened|linux-rt|linux-rt-lts|linux-x|linux-x-mainline) ;;
    *) echo "installer: unsupported kernel '$KERNEL' (linux|linux-lts|linux-zen|linux-hardened|linux-rt|linux-rt-lts|linux-x|linux-x-mainline)" >&2; exit 1 ;;
esac
KERNEL_LOCAL=0
case "$KERNEL" in
    linux-x|linux-x-mainline) KERNEL_LOCAL=1 ;;
esac
if [[ -n "$KERNEL_PARAMS" && ! "$KERNEL_PARAMS" =~ ^[A-Za-z0-9_=.,:/@%+-]+([[:space:]][A-Za-z0-9_=.,:/@%+-]+)*$ ]]; then
    echo "installer: kernel_params contains unsupported characters" >&2
    exit 1
fi
[[ "$HOST" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || { echo "installer: invalid hostname" >&2; exit 1; }
[[ "$USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "installer: invalid username" >&2; exit 1; }

if [[ "$DRY" == "1" ]]; then
    echo "install plan:"
    if [[ "$MODE" == "dualboot" ]]; then
        echo "  disk:      $DISK (dualboot: free space only, existing partitions preserved)"
    else
        echo "  disk:      $DISK (will be erased)"
    fi
    echo "  mode:      $MODE (min free: ${MIN_SIZE} GiB)"
    echo "  hostname:  $HOST"
    echo "  user:      $USER"
    echo "  language:  $LANG_CODE ($LOCALE)  keyboard: $KEYMAP  timezone: $TIMEZONE"
    echo "  profile:   $PROFILE"
    echo "  kernel:    $KERNEL"
    echo "  bootloader:$BOOT"
    echo "  backend:   $BACKEND"
    echo "  encryption:$ENC   desktop:$DESKTOP   agents:$AGENTS   virtualization:$VIRT"
    echo "  extra kernel params: ${KERNEL_PARAMS:-none}"
    exit 0
fi

[[ "$(id -u)" -eq 0 ]] || { echo "installer: requires root" >&2; exit 1; }
[[ -b "$DISK" ]] || { echo "installer: $DISK is not a block device" >&2; exit 1; }
if [[ "$DISK" =~ ^/dev/(fd|sr|loop|zram|ram|dm-) ]]; then
    echo "installer: $DISK is not an installable disk" >&2
    exit 1
fi
LIVE_SRC="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
if [[ -n "$LIVE_SRC" ]]; then
    LIVE_DISK="$(lsblk -no PKNAME "$LIVE_SRC" 2>/dev/null | head -1 || true)"
    if [[ -n "$LIVE_DISK" && "$DISK" == "/dev/$LIVE_DISK" ]]; then
        echo "installer: $DISK contains the running live medium" >&2
        exit 1
    fi
fi

partdev() {
    local name="${1##*/}"
    if [[ "$name" =~ [0-9]$ ]]; then
        printf '%sp' "$1"
    else
        printf '%s' "$1"
    fi
}

MNT=/mnt
INSTALL_STEP=0
INSTALL_STEPS=11
installer_progress() {
    local label="$1"
    INSTALL_STEP=$((INSTALL_STEP + 1))
    (( INSTALL_STEP <= INSTALL_STEPS )) || INSTALL_STEP=$INSTALL_STEPS
    local percent=$(( INSTALL_STEP * 100 / INSTALL_STEPS ))
    local filled=$(( percent * 20 / 100 ))
    printf '\n[%s%s] %3d%%  %s\n' \
        "$(printf 'x%.0s' $(seq 1 "$filled"))" \
        "$(printf -- '-%.0s' $(seq 1 $((20 - filled))))" \
        "$percent" "$label"
}

installer_progress "Network and connectivity"
if ! network_setup; then
    echo "installer: could not configure the network; a connection is required to install" >&2
    exit 1
fi
PKGLIST="${X_PKGLIST:-/root/x-installer/packages.x86_64}"
XPM_BOOTSTRAP=/run/xpm-bootstrap.conf
XPM_PSEUDO_MOUNTED=0

xpm_write_config() {
    local file="$1" root="$2" cache="$3"
    local prefix="${root%/}"
    local mirror="${X_XPM_ARCH_MIRROR:-https://geo.mirror.pkgbuild.com/\$repo/os/\$arch}"
    {
        printf '[options]\n'
        printf 'root_dir = "%s"\n' "$root"
        printf 'db_path = "%s/var/lib/xpm"\n' "$prefix"
        printf 'cache_dir = "%s"\n' "$cache"
        printf 'log_file = "%s/var/log/xpm.log"\n' "$prefix"
        printf 'gpg_dir = "%s/etc/xpm/gnupg"\n' "$prefix"
        printf 'mirror_pacman = false\n'
        printf 'shell_integration = false\n'
        printf 'sig_level = "required"\n'
        printf 'database_sig_level = "optional"\n'
        printf 'architecture = "x86_64"\n'
        printf 'color = false\n'
        printf 'parallel_downloads = 5\n'
        printf '\n[[repo]]\n'
        printf 'name = "x"\n'
        printf 'server = ["%s"]\n' "${X_XPM_X_REPO:-https://equislinux.github.io/x-repo/repo/x86_64}"
        printf 'sig_level = "required"\n'
        printf 'database_sig_level = "required"\n'
        local repo
        for repo in core extra; do
            printf '\n[[repo]]\n'
            printf 'name = "%s"\n' "$repo"
            printf 'server = ["%s"]\n' "$mirror"
            printf 'sig_level = "required"\n'
            printf 'database_sig_level = "optional"\n'
        done
    } > "$file"
}

xpm_bind_pseudo() {
    mkdir -p "$MNT/dev" "$MNT/dev/pts" "$MNT/proc" "$MNT/sys" "$MNT/run"
    XPM_PSEUDO_MOUNTED=1
    mount --rbind /dev "$MNT/dev"
    mount --rbind /proc "$MNT/proc"
    mount --rbind /sys "$MNT/sys"
    mount --rbind /run "$MNT/run"
}

xpm_unbind_pseudo() {
    [[ "$XPM_PSEUDO_MOUNTED" == "1" ]] || return 0
    local p
    for p in run sys proc dev; do
        if mountpoint -q "$MNT/$p"; then
            umount -R "$MNT/$p" 2>/dev/null || umount -Rl "$MNT/$p" 2>/dev/null || true
        fi
        if mountpoint -q "$MNT/$p"; then
            echo "installer: could not unmount $MNT/$p" >&2
            return 1
        fi
    done
    XPM_PSEUDO_MOUNTED=0
}

xpm_check_backend() {
    if ! command -v xpm >/dev/null 2>&1; then
        echo "installer: the xpm backend needs xpm in the live environment" >&2
        return 1
    fi
    local help
    help="$(xpm --help 2>&1 || true)"
    if ! grep -q -- '--scriptlets' <<<"$help" \
        || ! grep -q -- '--no-shell-integration' <<<"$help" \
        || ! grep -q -- '--no-alpm-hooks' <<<"$help"; then
        echo "installer: the live xpm lacks the native backend (--scriptlets/--no-shell-integration/--no-alpm-hooks); refusing to fall back to pacman" >&2
        return 1
    fi
    if ! xpm diff --help >/dev/null 2>&1 \
        || ! xpm history --help >/dev/null 2>&1 \
        || ! xpm query --help >/dev/null 2>&1; then
        echo "installer: the live xpm lacks query/diff/history; refusing to fall back to pacman" >&2
        return 1
    fi
}

xpm_check_target_backend() {
    local help
    help="$(arch-chroot "$MNT" xpm --help 2>&1 || true)"
    if ! grep -q -- '--no-alpm-hooks' <<<"$help"; then
        echo "installer: the installed xpm lacks --no-alpm-hooks; publish the native xpm before using X_INSTALL_BACKEND=xpm" >&2
        return 1
    fi
}

xpm_prepare_keyring() {
    local dir="$1"
    XPM_GPGDIR="$dir" /usr/local/bin/x-repo-key
}

# xpm installs the kernel files under /usr/lib/modules, but mkinitcpio needs
# the /boot/vmlinuz-* copy and preset that the mkinitcpio ALPM hook normally
# creates. The local kernel transaction disables ALPM hooks (so the hook's
# pacman -Qoq is never called), then this helper creates them explicitly.
xpm_install_local_kernel_boot() {
    local pkgbase="$1" kver
    kver="$(arch-chroot "$MNT" bash -c '
        for f in /usr/lib/modules/*/pkgbase; do
            [ -f "$f" ] || continue
            if [ "$(cat "$f")" = "$1" ]; then
                basename "${f%/pkgbase}"
            fi
        done
    ' _ "$pkgbase" | head -1)"
    if [[ -z "$kver" ]]; then
        echo "installer: could not find the $pkgbase module tree in the target" >&2
        exit 1
    fi
    arch-chroot "$MNT" install -Dm644 \
        "/usr/lib/modules/$kver/vmlinuz" "/boot/vmlinuz-$pkgbase"
    arch-chroot "$MNT" bash -c '
        set -e
        preset="/etc/mkinitcpio.d/$1.preset"
        if [ ! -f "$preset" ]; then
            install -d /etc/mkinitcpio.d
            sed "s|%PKGBASE%|$1|g" /usr/share/mkinitcpio/hook.preset > "$preset"
        fi
    ' _ "$pkgbase"
    arch-chroot "$MNT" depmod -a
    arch-chroot "$MNT" mkinitcpio -P
    local image
    for image in "/boot/vmlinuz-$pkgbase" "/boot/initramfs-$pkgbase.img"; do
        if ! arch-chroot "$MNT" test -f "$image"; then
            echo "installer: $image is missing after the xpm kernel install" >&2
            exit 1
        fi
    done
}

install_local_x_kernel_xpm() {
    [[ "$KERNEL_LOCAL" == "1" ]] || return 0
    local dir=/root/x-installer/kernel-packages main headers
    local gpgdir="$MNT/etc/xpm/gnupg"
    main="$(find "$dir" -maxdepth 1 -type f -name "$KERNEL-[0-9]*.pkg.tar.zst" -print -quit 2>/dev/null || true)"
    headers="$(find "$dir" -maxdepth 1 -type f -name "$KERNEL-headers-[0-9]*.pkg.tar.zst" -print -quit 2>/dev/null || true)"
    if [[ -z "$main" || -z "$headers" ]]; then
        echo "installer: local $KERNEL packages are missing from the ISO ($dir)" >&2
        exit 1
    fi
    if [[ ! -f "$main.sig" || ! -f "$headers.sig" ]]; then
        echo "installer: local $KERNEL signatures are missing from the ISO ($dir)" >&2
        exit 1
    fi
    gpg --batch --homedir "$gpgdir" --verify "$main.sig" "$main" >/dev/null
    gpg --batch --homedir "$gpgdir" --verify "$headers.sig" "$headers" >/dev/null
    echo "== installing $KERNEL from the bundled ISO packages (xpm)"
    X_GEN_SKIP=1 "${XPM_NO_HOOKS[@]}" --scriptlets=auto --no-confirm install --needed "$main" "$headers"
    xpm_install_local_kernel_boot "$KERNEL"
}

install_local_x_kernel_pacman() {
    [[ "$KERNEL_LOCAL" == "1" ]] || return 0
    local dir=/root/x-installer/kernel-packages main headers
    main="$(find "$dir" -maxdepth 1 -type f -name "$KERNEL-[0-9]*.pkg.tar.zst" -print -quit 2>/dev/null || true)"
    headers="$(find "$dir" -maxdepth 1 -type f -name "$KERNEL-headers-[0-9]*.pkg.tar.zst" -print -quit 2>/dev/null || true)"
    if [[ -z "$main" || -z "$headers" ]]; then
        echo "installer: local $KERNEL packages are missing from the ISO ($dir)" >&2
        exit 1
    fi
    echo "== installing $KERNEL from the bundled ISO packages (pacman)"
    # pacman -U loads the enabled repos. On the pacman path the target
    # mirrorlist has not been copied yet, so seed it from the live environment.
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        install -Dm644 /etc/pacman.d/mirrorlist "$MNT/etc/pacman.d/mirrorlist"
    fi
    cp -f "$main" "$headers" "$MNT/root/"
    arch-chroot "$MNT" pacman -U --noconfirm \
        "/root/$(basename "$main")" "/root/$(basename "$headers")" >/dev/null
    rm -f "$MNT/root/$(basename "$main")" "$MNT/root/$(basename "$headers")"
    arch-chroot "$MNT" depmod -a || true
    arch-chroot "$MNT" mkinitcpio -P || true
}

cleanup() {
    rm -f "$MNT/etc/sudoers.d/x-hypr-install" 2>/dev/null || true
    xpm_unbind_pseudo 2>/dev/null || true
    umount -R "$MNT" 2>/dev/null || umount -Rl "$MNT" 2>/dev/null || true
    if [[ -b /dev/mapper/xroot ]]; then
        if [[ "${X_AUTO:-0}" == "1" ]]; then
            # The unattended live session powers off right after rc=0; closing
            # the mapping here can block on udev/device references. The reboot
            # releases it, so do not risk hanging the install.
            :
        else
            # Interactive installs: never block on udev keeping a transient
            # reference after unmounting. A deferred close returns immediately;
            # dmsetup is the last resort for an already-unused mapping.
            timeout -k 2 5 cryptsetup close --deferred xroot 2>/dev/null || true
            timeout -k 2 5 cryptsetup close xroot 2>/dev/null || true
            if [[ -b /dev/mapper/xroot ]]; then
                dmsetup remove xroot 2>/dev/null || true
            fi
        fi
    fi
    rm -f "${X_INSTALL_JSON:-/tmp/x-install.json}" 2>/dev/null || true
}
trap cleanup EXIT

installer_progress "Preparing disk and install mode"
echo "== install backend: $BACKEND"
echo "== partitioning $DISK (mode: $MODE)"
if [[ "$MODE" == "dualboot" ]]; then
    # Install into the largest unallocated region, preserving every existing
    # partition and the ESP. UEFI only in this first iteration.
    [[ -d /sys/firmware/efi ]] || { echo "installer: dualboot requires UEFI firmware" >&2; exit 1; }
    ptype="$(blkid -p -s PTTYPE -o value "$DISK" 2>/dev/null || true)"
    [[ "$ptype" == "gpt" ]] || { echo "installer: dualboot requires a GPT disk (found: ${ptype:-unknown})" >&2; exit 1; }

    EFI=""
    ROOTP=""
    if [[ -n "$ESP_OVERRIDE" ]]; then
        EFI="$ESP_OVERRIDE"
        [[ -b "$EFI" ]] || { echo "installer: esp=$EFI is not a block device" >&2; exit 1; }
    else
        # PARTTYPE from lsblk (no blkid cache issues right after sgdisk).
        while read -r dev parttype; do
            [[ -z "$dev" || "$dev" == "$DISK" ]] && continue
            if [[ "${parttype,,}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
                EFI="$dev"
                break
            fi
        done < <(lsblk -ln -o PATH,PARTTYPE "$DISK" 2>/dev/null)
        [[ -n "$EFI" ]] || { echo "installer: no EFI System Partition found on $DISK (pass esp=...)" >&2; exit 1; }
    fi

    start="$(sgdisk -F "$DISK" 2>/dev/null || true)"
    end="$(sgdisk -E "$DISK" 2>/dev/null || true)"
    if ! [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || (( start <= 0 || end <= start )); then
        echo "installer: no usable free space on $DISK" >&2
        exit 1
    fi
    ssz="$(blockdev --getss "$DISK" 2>/dev/null || echo 512)"
    free_gib=$(( (end - start + 1) * ssz / 1024 / 1024 / 1024 ))
    if (( free_gib < MIN_SIZE )); then
        echo "installer: free region is ${free_gib} GiB, need at least ${MIN_SIZE} GiB (min_size)" >&2
        exit 1
    fi
    echo "   reusing ESP: $EFI (never formatted)"
    echo "   free region: $(( end - start + 1 )) sectors (~${free_gib} GiB) -> new root partition"
    sgdisk -n "0:${start}:${end}" -t 0:8300 "$DISK"
    partnum="$(sgdisk -p "$DISK" | awk '/^[[:space:]]*[0-9]+[[:space:]]/ {n=$1} END {print n}')"
    ROOTP="$(partdev "$DISK")${partnum}"
    partprobe "$DISK" || true
    sleep 2
else
    sgdisk --zap-all "$DISK"
    if [[ "$BOOT" == "grub" ]]; then
        sgdisk -n 1:0:+1M -t 1:ef02 -n 2:0:+1G -t 2:ef00 -n 3:0:0 -t 3:8300 "$DISK"
        EFI="$(partdev "$DISK")2"
        ROOTP="$(partdev "$DISK")3"
    else
        sgdisk -n 1:0:+1G -t 1:ef00 -n 2:0:0 -t 2:8300 "$DISK"
        EFI="$(partdev "$DISK")1"
        ROOTP="$(partdev "$DISK")2"
    fi
    partprobe "$DISK" || true
    sleep 1
fi

ROOT_DEV="$ROOTP"
LUKS_UUID=""
if [[ "$ENC" == "yes" ]]; then
    [[ -n "$LUKS_PASS" ]] || LUKS_PASS="$PASS"
    echo "== luks2 on $ROOTP"
    printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 --batch-mode "$ROOTP"
    # Idempotent: a stale mapping from a previous run must not abort the install.
    cryptsetup close xroot 2>/dev/null || true
    printf '%s' "$LUKS_PASS" | cryptsetup open "$ROOTP" xroot
    ROOT_DEV=/dev/mapper/xroot
    LUKS_UUID="$(blkid -s UUID -o value "$ROOTP")"
fi

echo "== formatting"
if [[ "$MODE" == "wipe" ]]; then
    mkfs.vfat -F32 "$EFI"
else
    echo "   keeping the existing ESP unformatted ($EFI)"
fi
mkfs.btrfs -f "$ROOT_DEV"

echo "== btrfs subvolumes (@, @home, @snapshots, @xstate)"
mount "$ROOT_DEV" "$MNT"
btrfs subvolume create "$MNT/@" >/dev/null
btrfs subvolume create "$MNT/@home" >/dev/null
btrfs subvolume create "$MNT/@snapshots" >/dev/null
btrfs subvolume create "$MNT/@xstate" >/dev/null
umount "$MNT"

echo "== mounting"
mount -o "subvol=@,noatime" "$ROOT_DEV" "$MNT"
mkdir -p "$MNT/boot" "$MNT/home" "$MNT/.snapshots" "$MNT/var/lib/x"
mount -o "subvol=@home,noatime" "$ROOT_DEV" "$MNT/home"
mount -o "subvol=@snapshots,noatime" "$ROOT_DEV" "$MNT/.snapshots"
mount -o "subvol=@xstate,noatime" "$ROOT_DEV" "$MNT/var/lib/x"
chmod 700 "$MNT/.snapshots" "$MNT/var/lib/x"
mount "$EFI" "$MNT/boot"

# Package set per profile.
EXTRA="base base-devel"
[[ "$KERNEL_LOCAL" == "1" ]] || EXTRA="$EXTRA $KERNEL $KERNEL-headers"
EXTRA="$EXTRA linux-firmware mkinitcpio sudo networkmanager openssh git jq x-release x-wallpapers btrfs-progs"
[[ "$BACKEND" == "xpm" ]] && EXTRA="$EXTRA xpm"
# Terminal and audio stack are always installed (work without the Hyprland setup).
# zsh is part of the base set (not only the core profile): every created user
# gets it as the login shell.
EXTRA="$EXTRA kitty pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils sddm zsh rsync curl python"
[[ "$BOOT" == "grub" ]] && EXTRA="$EXTRA grub efibootmgr"
[[ "$MODE" == "dualboot" && "$BOOT" == "grub" ]] && EXTRA="$EXTRA os-prober"
[[ "$ENC" == "yes" ]] && EXTRA="$EXTRA cryptsetup"
# Optional virtualization stack: QEMU/KVM, libvirt, GUI and UEFI/TPM guests.
if [[ "$VIRT" == "yes" ]]; then
    EXTRA="$EXTRA qemu-desktop qemu-img qemu-system-aarch64 libvirt virt-manager virt-install libosinfo virt-viewer dnsmasq iptables edk2-ovmf edk2-aarch64 swtpm dmidecode"
fi
# KDE Plasma is installed online from the official repositories; the X
# branding layer (x-kde-settings) comes from the signed [x] repository.
if [[ "$DESKTOP" == "kde" ]]; then
    EXTRA="$EXTRA plasma-meta kde-applications"
fi
if [[ "$PROFILE" == "core" ]]; then
    PKGS="$EXTRA vim"
else
    PKGS="$EXTRA"
    if [[ -f "$PKGLIST" ]]; then
        PKGS="$PKGS $(sed 's/#.*//' "$PKGLIST" | tr '\n' ' ')"
    fi
fi

installer_progress "Checking network"
if ! network_online; then
    echo "installer: network disappeared after setup; aborting" >&2
    exit 1
fi
echo "network available"

# Keyrings are backend-specific. The xpm path uses a native GnuPG keyring under
# /etc/xpm/gnupg and never calls pacman-key. The pacman path initializes its own
# keyring after the user has explicitly selected that backend.
installer_progress "Preparing keyring"
if [[ "$BACKEND" == "xpm" ]]; then
    echo "== native xpm keyring (live + target)"
    xpm_check_backend
    xpm_prepare_keyring /etc/xpm/gnupg
    xpm_prepare_keyring "$MNT/etc/xpm/gnupg"
else
    echo "== pacman keyring (live + target)"
    pacman-key --init
    pacman-key --populate archlinux
    LIVE_KEY=/etc/pacman.d/x-repo.pub
    if [[ -f "$LIVE_KEY" ]]; then
        pacman-key --add "$LIVE_KEY"
        X_KEY_FPR="$(LC_ALL=C gpg --with-colons --show-keys "$LIVE_KEY" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
        if [[ -n "$X_KEY_FPR" ]]; then
            pacman-key --lsign-key "$X_KEY_FPR"
        else
            echo "installer: could not resolve the [x] key fingerprint" >&2
            exit 1
        fi
    else
        echo "installer: $LIVE_KEY missing in the live; [x] cannot be required" >&2
        exit 1
    fi

    GPGDIR="$MNT/etc/pacman.d/gnupg"
    mkdir -p "$GPGDIR"
    chmod 700 "$GPGDIR"
    pacman-key --gpgdir "$GPGDIR" --init
    pacman-key --gpgdir "$GPGDIR" --populate archlinux
    pacman-key --gpgdir "$GPGDIR" --add "$LIVE_KEY"
    pacman-key --gpgdir "$GPGDIR" --lsign-key "$X_KEY_FPR"
    install -Dm644 "$LIVE_KEY" "$MNT/etc/pacman.d/x-repo.pub"

    # Keep the live bootstrap current on the explicit pacman backend.
    installer_progress "Updating live xpm"
    update_live_xpm_pacman
fi

if [[ "$BACKEND" == "xpm" ]]; then
    # XPM-BACKEND-BEGIN
    installer_progress "Installing base packages"
    echo "== xpm target bootstrap"
    XPM_CACHE="${X_XPM_CACHE:-$MNT/var/cache/xpm/pkg}"
    mkdir -p "$XPM_CACHE" "$MNT/var/lib/xpm" "$MNT/etc/xpm"
    xpm_write_config "$XPM_BOOTSTRAP" "$MNT" "$XPM_CACHE"
    XPM=(xpm --config "$XPM_BOOTSTRAP" --root "$MNT" --dbpath "$MNT/var/lib/xpm" --cachedir "$XPM_CACHE" --no-shell-integration)
    XPM_NO_HOOKS=("${XPM[@]}" --no-alpm-hooks)

    echo "== xpm sync (target databases; official repos + [x])"
    "${XPM[@]}" --scriptlets=skip --no-confirm sync
    xpm_target_version="$("${XPM[@]}" info xpm 2>/dev/null | awk '/^Version[[:space:]]*:/ {print $3; exit}')"
    if [[ -z "$xpm_target_version" ]] || (( $(vercmp "$xpm_target_version" 0.1.0-4) < 0 )); then
        echo "installer: target [x] repo provides xpm ${xpm_target_version:-unknown}; the xpm backend needs >= 0.1.0-4. Publish the native xpm release or choose the other backend." >&2
        exit 1
    fi
    echo "== xpm phase 1/4 (filesystem + bash)"
    X_GEN_SKIP=1 "${XPM[@]}" --scriptlets=skip --no-confirm install --needed filesystem bash
    xpm_bind_pseudo
    # Preinstall archlinux-keyring without its post_install scriptlet. The
    # native keyring was prepared above, so the scriptlet must not run.
    echo "== xpm phase 2/4 (target keyring package)"
    X_GEN_SKIP=1 "${XPM[@]}" --scriptlets=skip --no-confirm install --needed archlinux-keyring
    echo "== xpm phase 3/4 (base package set)"
    X_GEN_SKIP=1 "${XPM[@]}" --scriptlets=auto --no-confirm install --needed base
    echo "== xpm phase 4/4 (remaining packages)"
    X_GEN_SKIP=1 "${XPM[@]}" --scriptlets=auto --no-confirm install --needed $PKGS

    echo "== installing x-scripts (offline payload from the live; xpm)"
    XS_PKG="$(ls /root/x-installer/packages/x-scripts-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
    if [[ -n "$XS_PKG" ]]; then
        X_GEN_SKIP=1 "${XPM[@]}" --scriptlets=require --no-confirm install --needed "$XS_PKG"
    else
        echo "warning: x-scripts package not found in the live" >&2
    fi

    if [[ "$DESKTOP" == "kde" ]]; then
        XKDE_PKG="$(ls /root/x-installer/packages/x-kde-settings-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
        if [[ -n "$XKDE_PKG" ]]; then
            echo "== installing x-kde-settings (bundled; xpm)"
            X_GEN_SKIP=1 "${XPM[@]}" --scriptlets=require --no-confirm install --needed "$XKDE_PKG"
        else
            echo "warning: x-kde-settings not found in the live; KDE will use stock Plasma branding" >&2
        fi
    fi

    mkdir -p "$MNT/var/lib/xpm"
    xpm_write_config "$MNT/etc/xpm.conf" "/" "/var/cache/xpm/pkg"

    xpm_check_target_backend
    # A transaction killed by a live-environment reboot can leave a stale xpm
    # lock; the install is complete and no xpm transaction is running.
    rm -f "$MNT/var/lib/xpm/transaction.lock"

    install_local_x_kernel_xpm

    TARGET_XPM_QUERY="/tmp/target-xpm-query.$$"
    if ! arch-chroot "$MNT" xpm query > "$TARGET_XPM_QUERY" 2>/dev/null; then
        echo "installer: the installed xpm cannot query its database; publish the native xpm before using X_INSTALL_BACKEND=xpm" >&2
        rm -f "$TARGET_XPM_QUERY"
        exit 1
    fi
    for pkg in xpm base mkinitcpio x-scripts; do
        if ! awk -v want="$pkg" '$1 == want { found = 1 } END { exit !found }' "$TARGET_XPM_QUERY"; then
            echo "installer: xpm database is missing '$pkg' after the base install" >&2
            rm -f "$TARGET_XPM_QUERY"
            exit 1
        fi
    done
    if [[ "$KERNEL_LOCAL" == "1" ]]; then
        for pkg in "$KERNEL" "$KERNEL-headers"; do
            if ! awk -v want="$pkg" '$1 == want { found = 1 } END { exit !found }' "$TARGET_XPM_QUERY"; then
                echo "installer: xpm database is missing '$pkg' after the local kernel install" >&2
                rm -f "$TARGET_XPM_QUERY"
                exit 1
            fi
        done
    fi
    rm -f "$TARGET_XPM_QUERY"

    echo "== xpm finalize (ldconfig/sysusers/tmpfiles/ca-trust/depmod/mkinitcpio)"
    arch-chroot "$MNT" ldconfig
    arch-chroot "$MNT" systemd-sysusers
    arch-chroot "$MNT" systemd-tmpfiles --create
    if arch-chroot "$MNT" test -x /usr/bin/update-ca-trust; then
        arch-chroot "$MNT" update-ca-trust
    fi
    arch-chroot "$MNT" depmod -a
    arch-chroot "$MNT" mkinitcpio -P
    for image in "/boot/vmlinuz-$KERNEL" "/boot/initramfs-$KERNEL.img"; do
        if ! arch-chroot "$MNT" test -f "$image"; then
            echo "installer: $image is missing after mkinitcpio" >&2
            exit 1
        fi
    done
    xpm_unbind_pseudo || exit 1
    # XPM-BACKEND-END
else
    # PACMAN-BACKEND-BEGIN
    echo "== pacstrap (online; official repos + [x])"
    pacstrap "$MNT" $PKGS

    echo "== installing x-scripts (offline payload from the live)"
    XS_PKG="$(ls /root/x-installer/packages/x-scripts-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
    if [[ -n "$XS_PKG" ]]; then
        cp -f "$XS_PKG" "$MNT/root/"
        arch-chroot "$MNT" pacman -U --noconfirm "/root/$(basename "$XS_PKG")" >/dev/null
        rm -f "$MNT/root/$(basename "$XS_PKG")"
    else
        echo "warning: x-scripts package not found in the live" >&2
    fi

    # KDE branding is bundled in the live payload so the online Plasma install gets
    # a complete X layer even before x-kde-settings is published as a new package.
    if [[ "$DESKTOP" == "kde" ]]; then
        XKDE_PKG="$(ls /root/x-installer/packages/x-kde-settings-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
        if [[ -n "$XKDE_PKG" ]]; then
            echo "== installing x-kde-settings (bundled)"
            cp -f "$XKDE_PKG" "$MNT/root/"
            arch-chroot "$MNT" pacman -U --noconfirm "/root/$(basename "$XKDE_PKG")" >/dev/null
            rm -f "$MNT/root/$(basename "$XKDE_PKG")"
        else
            echo "warning: x-kde-settings not found in the live; KDE will use stock Plasma branding" >&2
        fi
    fi

    install_local_x_kernel_pacman
    # PACMAN-BACKEND-END
fi

network_persist_to_target "$MNT"

installer_progress "Base configuration"
# SDDM's X theme uses Hack Nerd Font. Prefer the signed x-scripts payload so
# future font/theme changes do not require an ISO rebuild; keep an inline
# fallback for older x-scripts payloads. Failure is non-fatal.
echo "== system font (SDDM)"
if [[ -x "$MNT/usr/share/x/install/payloads/10-fonts.sh" ]]; then
    arch-chroot "$MNT" /usr/share/x/install/payloads/10-fonts.sh || \
        echo "warning: font payload failed; SDDM may use fallback glyphs" >&2
else
    arch-chroot "$MNT" bash -c '
        set -e
        url=https://raw.githubusercontent.com/xscriptor-colors/terminal/main/assets/fonts/HackNerdFont/HackNerdFont-Regular.ttf
        tmp=$(mktemp)
        trap "rm -f $tmp" EXIT
        curl -fsSL --retry 2 --connect-timeout 10 "$url" -o "$tmp"
        install -d -m 0755 /usr/share/fonts/HackNerdFont
        install -m 0644 "$tmp" /usr/share/fonts/HackNerdFont/HackNerdFont-Regular.ttf
        command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
    ' || echo "warning: font download failed; SDDM may use fallback glyphs" >&2
fi

echo "== base configuration"
genfstab -U "$MNT" >> "$MNT/etc/fstab"
# Volatile /tmp as tmpfs: keeps generation snapshots free of transient files.
printf 'tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0\n' >> "$MNT/etc/fstab"

arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
arch-chroot "$MNT" bash -c "sed -i 's/^#$LOCALE/$LOCALE/' /etc/locale.gen && locale-gen >/dev/null"
printf 'LANG=%s\n' "$LOCALE" > "$MNT/etc/locale.conf"
printf 'KEYMAP=%s\n' "$KEYMAP" > "$MNT/etc/vconsole.conf"
printf '%s\n' "$HOST" > "$MNT/etc/hostname"

if [[ "$BACKEND" == "pacman" ]]; then
    # Working mirrorlist for the installed system (pacman ships one commented out).
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        cp /etc/pacman.d/mirrorlist "$MNT/etc/pacman.d/mirrorlist"
    fi

    # Make the [x] repo available on the installed system.
    if ! grep -q '^\[x\]' "$MNT/etc/pacman.conf"; then
        cat >> "$MNT/etc/pacman.conf" <<'EOF'

[x]
# Key imported and locally signed during install (/etc/pacman.d/x-repo.pub).
SigLevel = Required
Server = https://equislinux.github.io/x-repo/repo/x86_64
EOF
    fi
fi

installer_progress "User and AUR tools"
echo "== user"
arch-chroot "$MNT" useradd -m -G wheel -s /usr/bin/zsh "$USER"
# The zsh package owns /usr/bin/zsh and registers it in /etc/shells. Fail
# loudly if the base set ever drops it instead of leaving a broken login shell.
arch-chroot "$MNT" bash -c 'command -v zsh >/dev/null && grep -qx /usr/bin/zsh /etc/shells'
printf '%s:%s\n' "$USER" "$PASS" | arch-chroot "$MNT" chpasswd
arch-chroot "$MNT" sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
if [[ "$VIRT" == "yes" ]]; then
    # libvirt (system connection) and kvm (/dev/kvm) access for the user.
    arch-chroot "$MNT" groupadd -f kvm
    arch-chroot "$MNT" groupadd -f libvirt
    arch-chroot "$MNT" usermod -aG kvm,libvirt "$USER"
fi

# xfetch and xtop ship as AUR binary packages; installing them through
# xpm-aur keeps them tracked and upgradable without compiling during setup.
AUR_XFETCH="${X_AUR_XFETCH:-xfetch-core-bin}"
AUR_XTOP="${X_AUR_XTOP:-xtop-bin}"
echo "== AUR tools ($AUR_XFETCH, $AUR_XTOP)"
if [[ "$BACKEND" == "xpm" ]]; then
    arch-chroot "$MNT" xpm --no-alpm-hooks install --no-confirm --needed xpm-aur >/dev/null 2>&1
else
    # xpm-aur is a normal [x] package; xpm is its runtime. Seed xpm's
    # database from pacman before it installs the AUR binary packages.
    arch-chroot "$MNT" pacman -S --needed --noconfirm xpm-aur >/dev/null 2>&1
    arch-chroot "$MNT" xpm import-pacman --force >/dev/null 2>&1
fi
cat > "$MNT/etc/sudoers.d/x-aur-install" <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "XPM_ALPM_HOOKS_DIRS"
EOF
chmod 440 "$MNT/etc/sudoers.d/x-aur-install"
arch-chroot "$MNT" install -d -m 755 /run/xpm/no-alpm-hooks
arch-chroot "$MNT" runuser -u "$USER" -- env \
    XPM_ALPM_HOOKS_DIRS=/run/xpm/no-alpm-hooks \
    xpm-aur -S --aur --needed --noconfirm "$AUR_XFETCH" "$AUR_XTOP"
rm -f "$MNT/etc/sudoers.d/x-aur-install"

installer_progress "Provisioning x-scripts"
echo "== provisioning (x-scripts)"
if [[ "$BACKEND" == "xpm" ]]; then
    arch-chroot "$MNT" env X_PKG_BACKEND=xpm X_HW_AUTO=0 X_GEN_SKIP=1 x setup
    arch-chroot "$MNT" runuser -u "$USER" -- env X_PKG_BACKEND=xpm X_HYPRLAND=0 X_HW_AUTO=0 /usr/bin/x setup --user
else
    arch-chroot "$MNT" env X_HW_AUTO=0 X_GEN_SKIP=1 x setup
    arch-chroot "$MNT" runuser -u "$USER" -- env X_HYPRLAND=0 X_HW_AUTO=0 /usr/bin/x setup --user
fi

# Audio stack enabled for all users (pipewire/wireplumber) + network.
arch-chroot "$MNT" systemctl --global enable pipewire pipewire-pulse wireplumber >/dev/null 2>&1 || true

if [[ "$VIRT" == "yes" ]]; then
    echo "== virtualization (QEMU/KVM + libvirt + virt-manager)"
    arch-chroot "$MNT" systemctl enable libvirtd.socket virtlogd.socket >/dev/null 2>&1 || true
    install -d -m 0755 "$MNT/etc/libvirt/qemu/networks/autostart"
    if [[ -f "$MNT/etc/libvirt/qemu/networks/default.xml" ]]; then
        ln -sfn ../default.xml "$MNT/etc/libvirt/qemu/networks/autostart/default.xml"
    fi
    if [[ ! -e /dev/kvm ]]; then
        echo "warning: /dev/kvm is not available here; guests will run without KVM acceleration"
    fi
    if [[ "$PROFILE" == "core" && "$HYPR" == "no" ]]; then
        echo "note: virt-manager needs a graphical desktop; virsh/virt-install work from the CLI"
    fi
fi

installer_progress "Installing desktop"
if [[ "$DESKTOP" == "hyprland" ]]; then
    echo "== installing the Hyprland/equisdots desktop (as user, with temporary passwordless sudo)"
    cat > "$MNT/etc/sudoers.d/x-hypr-install" <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 440 "$MNT/etc/sudoers.d/x-hypr-install"
    set +e
    if [[ "$HYPR" == "online" ]]; then
        echo "== Hyprland source: latest from equisdots (online)"
        # X_HYPR_ONLINE ignores the bundled snapshot; hyprland_ref (JSON) pins
        # the equisdots ref. On failure fall back to the packaged snapshot.
        HYPR_ENV="X_HYPR_ONLINE=1"
        [[ -n "$HYPR_REF" ]] && HYPR_ENV="$HYPR_ENV X_HYPR_REF=$HYPR_REF"
        arch-chroot "$MNT" runuser -u "$USER" -- env $HYPR_ENV /usr/share/x/tools/hyprland-install.sh
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "warning: online desktop setup failed (rc=$rc); falling back to the bundled snapshot"
            arch-chroot "$MNT" runuser -u "$USER" -- /usr/share/x/tools/hyprland-install.sh
            rc=$?
        fi
    else
        arch-chroot "$MNT" runuser -u "$USER" -- /usr/share/x/tools/hyprland-install.sh
        rc=$?
    fi
    echo "hyprland setup exited with $rc"
    set -e
    rm -f "$MNT/etc/sudoers.d/x-hypr-install"
fi

if [[ "$DESKTOP" == "niri" ]]; then
    echo "== installing the niri/equisdots desktop (as user, with temporary passwordless sudo)"
    cat > "$MNT/etc/sudoers.d/x-niri-install" <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 440 "$MNT/etc/sudoers.d/x-niri-install"
    set +e
    arch-chroot "$MNT" runuser -u "$USER" -- /usr/share/x/tools/niri-install.sh
    rc=$?
    echo "niri setup exited with $rc"
    set -e
    rm -f "$MNT/etc/sudoers.d/x-niri-install"
fi

if [[ "$DESKTOP" == "kde" ]]; then
    # x-kde-settings ships the X look-and-feel + /etc/skel config; the Plasma
    # autostart applies the global theme on the first graphical login.
    arch-chroot "$MNT" systemctl disable plasmalogin.service >/dev/null 2>&1 || true
    arch-chroot "$MNT" systemctl enable sddm.service >/dev/null 2>&1 || true
fi

if [[ "$AGENTS" == "yes" ]]; then
    echo "== installing the opencode CLI (opencode-bin from [x])"
    if [[ "$BACKEND" == "xpm" ]]; then
        arch-chroot "$MNT" xpm --no-alpm-hooks install --no-confirm --needed opencode-bin >/dev/null 2>&1 \
            || echo "warning: opencode-bin not installed (is it published in [x]?)"
    else
        arch-chroot "$MNT" pacman -S --needed --noconfirm opencode-bin >/dev/null 2>&1 \
            || echo "warning: opencode-bin not installed (is it published in [x]?)"
    fi
    echo "== installing the Xscriptor AI agents/skills bundle (as user)"
    set +e
    arch-chroot "$MNT" runuser -u "$USER" -- env \
        HOME="/home/$USER" XDG_CONFIG_HOME="/home/$USER/.config" \
        /usr/bin/x agent install --bundle x
    echo "agent setup exited with $?"
    set -e
fi

if [[ "$ENC" == "yes" ]]; then
    echo "== initramfs (LUKS)"
    arch-chroot "$MNT" bash -c 'sed -i "s/^HOOKS=.*/HOOKS=(base udev autodetect modconf keyboard keymap consolefont block encrypt filesystems)/" /etc/mkinitcpio.conf'
    arch-chroot "$MNT" mkinitcpio -P >/dev/null
fi

CMDROOT="root=UUID=$(blkid -s UUID -o value "$ROOT_DEV") rw rootflags=subvol=@"
[[ "$ENC" == "yes" ]] && CMDROOT="cryptdevice=UUID=$LUKS_UUID:xroot root=/dev/mapper/xroot rw rootflags=subvol=@"
[[ -n "$KERNEL_PARAMS" ]] && CMDROOT="$CMDROOT $KERNEL_PARAMS"

# Apply branding (os-release/GRUB hooks) BEFORE the bootloader step so a LUKS
# cmdline written afterwards is not clobbered by x-release-apply.
if [[ -x "$MNT/usr/bin/x-release-apply" ]]; then
    arch-chroot "$MNT" /usr/bin/x-release-apply || true
fi

installer_progress "Installing bootloader"
echo "== bootloader ($BOOT)"
if [[ "$BOOT" == "systemd-boot" ]]; then
    # bootctl also writes the fallback \EFI\BOOT\BOOTX64.EFI; in dualboot that
    # file may belong to Windows, so save and restore it around bootctl.
    saved_fallback=""
    if [[ "$MODE" == "dualboot" && -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]]; then
        saved_fallback="$(mktemp)"
        cp -a "$MNT/boot/EFI/BOOT/BOOTX64.EFI" "$saved_fallback"
    fi
    arch-chroot "$MNT" bootctl --esp-path=/boot install >/dev/null
    if [[ -n "$saved_fallback" ]]; then
        cp -a "$saved_fallback" "$MNT/boot/EFI/BOOT/BOOTX64.EFI"
        rm -f "$saved_fallback"
        echo "   restored the pre-existing EFI/BOOT/BOOTX64.EFI (left untouched)"
    fi
    # Ensure a removable fallback exists for firmware that only boots
    # \EFI\BOOT\BOOTX64.EFI (wipe mode; in dualboot the existing one wins).
    if [[ ! -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]]; then
        mkdir -p "$MNT/boot/EFI/BOOT"
        cp "$MNT/boot/EFI/systemd/systemd-bootx64.efi" "$MNT/boot/EFI/BOOT/BOOTX64.EFI"
    fi
    mkdir -p "$MNT/boot/loader/entries"
    cat > "$MNT/boot/loader/loader.conf" <<'EOF'
default x.conf
timeout 5
console-mode max
EOF
    cat > "$MNT/boot/loader/entries/x.conf" <<EOF
title   X Linux
linux   /vmlinuz-$KERNEL
initrd  /initramfs-$KERNEL.img
options $CMDROOT
EOF
else
    arch-chroot "$MNT" bash -c "sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$CMDROOT\"|' /etc/default/grub"
    if [[ "$MODE" == "dualboot" ]]; then
        # Unique bootloader-id: never overwrite EFI/Microsoft/**; os-prober
        # adds the Windows entry to the generated menu.
        arch-chroot "$MNT" bash -c "grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub && sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
        arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=x --recheck
    else
        arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck
        arch-chroot "$MNT" grub-install --target=i386-pc --boot-directory=/boot "$DISK"
    fi
    arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
fi

# Firmware entry: bootctl/grub-install can silently skip writing the EFI
# variable (e.g. when running inside a chroot); make sure it exists. In
# dualboot this matters most: the fallback may belong to Windows.
if [[ -d /sys/firmware/efi ]] && command -v efibootmgr >/dev/null 2>&1; then
    espnum="$(lsblk -no PARTN "$EFI" 2>/dev/null | tr -d ' ')"
    if [[ -n "$espnum" ]]; then
        if [[ "$BOOT" == "systemd-boot" ]]; then
            if ! efibootmgr 2>/dev/null | grep -q 'Linux Boot Manager'; then
                efibootmgr -c -d "$DISK" -p "$espnum" -L 'Linux Boot Manager' \
                    -l '\EFI\systemd\systemd-bootx64.efi' >/dev/null 2>&1 || true
            fi
        elif [[ "$MODE" == "dualboot" ]]; then
            if ! efibootmgr 2>/dev/null | grep -q 'X Linux'; then
                efibootmgr -c -d "$DISK" -p "$espnum" -L 'X Linux' \
                    -l '\EFI\x\grubx64.efi' >/dev/null 2>&1 || true
            fi
        fi
    fi
fi

# Never report a successful install whose ESP has no UEFI loader. grub-install
# and bootctl can return 0 inside a chroot while writing nothing useful.
if [[ -d /sys/firmware/efi ]]; then
    if [[ "$BOOT" == "systemd-boot" ]]; then
        if [[ ! -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" && ! -f "$MNT/boot/EFI/systemd/systemd-bootx64.efi" ]]; then
            echo "installer: no UEFI loader found on the ESP ($MNT/boot)" >&2
            exit 1
        fi
    elif [[ "$MODE" == "dualboot" ]]; then
        if [[ ! -f "$MNT/boot/EFI/x/grubx64.efi" && ! -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]]; then
            echo "installer: no GRUB EFI loader found on the ESP ($MNT/boot)" >&2
            exit 1
        fi
    else
        if [[ ! -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]]; then
            echo "installer: no removable GRUB EFI loader found on the ESP ($MNT/boot)" >&2
            exit 1
        fi
    fi
fi

# Dualboot: keep the Windows Boot Manager first in the firmware order while
# still registering the X entry (best effort; requires efibootmgr).
if [[ "$MODE" == "dualboot" ]]; then
    win="$(efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\* Windows Boot Manager.*/\1/p' | head -1)"
    if [[ -n "$win" ]]; then
        order="$win"
        for entry in $(efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*.*/\1/p'); do
            [[ "$entry" == "$win" ]] && continue
            order="$order,$entry"
        done
        efibootmgr -o "$order" >/dev/null 2>&1 || true
    fi
fi

# First generation: snapshot of the installed system + manifest (base for
# rollbacks and granular restores; see scripts/docs/en/generations.md).
installer_progress "Creating first generation"
echo "== first generation"
if arch-chroot "$MNT" test -x /usr/bin/x; then
    if [[ "$BACKEND" == "xpm" ]]; then
        arch-chroot "$MNT" env X_PKG_BACKEND=xpm X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ \
            X_GEN_SUBVOL_PREFIX=/@snapshots \
            x gen new --reason install --label first \
            || echo "warning: the first generation could not be created" >&2
    else
        arch-chroot "$MNT" env X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ \
            X_GEN_SUBVOL_PREFIX=/@snapshots \
            x gen new --reason install --label first \
            || echo "warning: the first generation could not be created" >&2
    fi
else
    echo "warning: x CLI not found in the target; skipping the first generation" >&2
fi

echo
echo "installation complete. Reboot and remove the installation medium."

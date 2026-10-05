#!/usr/bin/env bash
set -euo pipefail

# X installer: partitions, pacstrap, configures, provisions, installs the
# bootloader in chroot.
#   X_INSTALL_JSON  config path (default /tmp/x-install.json)
#   X_DRY=1         validate and print the plan only (tests)

source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

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
AGENTS="$(jget agents)";              AGENTS="${AGENTS:-no}"
MODE="$(jget mode)";                  MODE="${MODE:-wipe}"
ESP_OVERRIDE="$(jget esp)"
MIN_SIZE="$(jget min_size)";          MIN_SIZE="${MIN_SIZE:-20}"
KERNEL_PARAMS="$(jget kernel_params)"

[[ -n "$DISK" && -n "$HOST" && -n "$USER" ]] || { echo "installer: incomplete JSON" >&2; exit 1; }
[[ "$MODE" == "wipe" || "$MODE" == "dualboot" ]] || { echo "installer: invalid mode '$MODE' (wipe|dualboot)" >&2; exit 1; }
[[ "$MIN_SIZE" =~ ^[0-9]+$ ]] || { echo "installer: min_size must be a number of GiB" >&2; exit 1; }
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
    echo "  bootloader:$BOOT"
    echo "  encryption:$ENC   hyprland:$HYPR   agents:$AGENTS"
    echo "  extra kernel params: ${KERNEL_PARAMS:-none}"
    exit 0
fi

[[ "$(id -u)" -eq 0 ]] || { echo "installer: requires root" >&2; exit 1; }
[[ -b "$DISK" ]] || { echo "installer: $DISK is not a block device" >&2; exit 1; }

partdev() {
    local name="${1##*/}"
    if [[ "$name" =~ [0-9]$ ]]; then
        printf '%sp' "$1"
    else
        printf '%s' "$1"
    fi
}

MNT=/mnt
PKGLIST="${X_PKGLIST:-/root/x-installer/packages.x86_64}"

cleanup() {
    rm -f "$MNT/etc/sudoers.d/x-hypr-install" 2>/dev/null || true
    umount -R "$MNT" 2>/dev/null || umount -Rl "$MNT" 2>/dev/null || true
    if [[ -b /dev/mapper/xroot ]]; then
        # udev can keep a transient reference right after unmounting: retry
        # instead of leaving the mapping open (it would block a re-install).
        local i
        for i in 1 2 3 4 5; do
            cryptsetup close xroot 2>/dev/null && break
            sleep 1
        done
        if [[ -b /dev/mapper/xroot ]]; then
            dmsetup remove xroot 2>/dev/null || true
        fi
    fi
    rm -f "${X_INSTALL_JSON:-/tmp/x-install.json}" 2>/dev/null || true
}
trap cleanup EXIT

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
EXTRA="base base-devel linux linux-firmware sudo networkmanager openssh git jq x-release btrfs-progs xfetch-git xtop-git"
# Terminal and audio stack are always installed (work without the Hyprland setup).
EXTRA="$EXTRA kitty pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils sddm"
[[ "$BOOT" == "grub" ]] && EXTRA="$EXTRA grub efibootmgr"
[[ "$MODE" == "dualboot" && "$BOOT" == "grub" ]] && EXTRA="$EXTRA os-prober"
[[ "$ENC" == "yes" ]] && EXTRA="$EXTRA cryptsetup"
if [[ "$PROFILE" == "core" ]]; then
    PKGS="$EXTRA vim zsh"
else
    PKGS="$EXTRA"
    if [[ -f "$PKGLIST" ]]; then
        PKGS="$PKGS $(sed 's/#.*//' "$PKGLIST" | tr '\n' ' ')"
    fi
fi

echo "== waiting for network"
NET_OK=0
for i in $(seq 1 60); do
    if getent ahostsv4 geo.mirror.pkgbuild.com >/dev/null 2>&1; then
        echo "network available"
        NET_OK=1
        break
    fi
    sleep 2
done
if [[ "$NET_OK" -ne 1 ]]; then
    echo "installer: no network after 120s; aborting" >&2
    exit 1
fi

# Keyrings. The published [x] database is signed, so pacman needs the project
# key. Two targets:
#   - live: pacman-init.service recreates /etc/pacman.d/gnupg at boot (tmpfs),
#     and pacstrap verifies the [x] database with the live keyring -> re-add
#     and locally sign the key here (idempotent; x-keyring.service also does
#     it at boot).
#   - target: prepared here so the installed system trusts [x] (Required).
echo "== keyring (live + target)"
# Idempotent: pacman-init.service usually did this at boot, but autoinstall can
# race with it, so make sure the live keyring exists and has the Arch keys
# (pacstrap verifies core/extra and [x] against the live keyring).
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

echo "== base configuration"
genfstab -U "$MNT" >> "$MNT/etc/fstab"
# Volatile /tmp as tmpfs: keeps generation snapshots free of transient files.
printf 'tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0\n' >> "$MNT/etc/fstab"

arch-chroot "$MNT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
arch-chroot "$MNT" bash -c "sed -i 's/^#$LOCALE/$LOCALE/' /etc/locale.gen && locale-gen >/dev/null"
printf 'LANG=%s\n' "$LOCALE" > "$MNT/etc/locale.conf"
printf 'KEYMAP=%s\n' "$KEYMAP" > "$MNT/etc/vconsole.conf"
printf '%s\n' "$HOST" > "$MNT/etc/hostname"

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
Server = https://xlnux.github.io/x-repo/repo/x86_64
EOF
fi

echo "== user"
arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$USER"
printf '%s:%s\n' "$USER" "$PASS" | arch-chroot "$MNT" chpasswd
arch-chroot "$MNT" sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "== provisioning (x-scripts)"
arch-chroot "$MNT" env X_HW_AUTO=0 X_GEN_SKIP=1 x setup
arch-chroot "$MNT" runuser -u "$USER" -- env X_HYPRLAND=0 X_HW_AUTO=0 /usr/bin/x setup --user

# Audio stack enabled for all users (pipewire/wireplumber) + network.
arch-chroot "$MNT" systemctl --global enable pipewire pipewire-pulse wireplumber >/dev/null 2>&1 || true

if [[ "$HYPR" == "yes" ]]; then
    echo "== installing the Hyprland/equisdots desktop (as user, with temporary passwordless sudo)"
    cat > "$MNT/etc/sudoers.d/x-hypr-install" <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 440 "$MNT/etc/sudoers.d/x-hypr-install"
    set +e
    arch-chroot "$MNT" runuser -u "$USER" -- /usr/share/x/tools/hyprland-install.sh
    echo "hyprland setup exited with $?"
    set -e
    rm -f "$MNT/etc/sudoers.d/x-hypr-install"
fi

if [[ "$AGENTS" == "yes" ]]; then
    echo "== installing the opencode CLI (opencode-bin from [x])"
    arch-chroot "$MNT" pacman -S --needed --noconfirm opencode-bin >/dev/null 2>&1 \
        || echo "warning: opencode-bin not installed (is it published in [x]?)"
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
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
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
echo "== first generation"
if arch-chroot "$MNT" test -x /usr/bin/x; then
    arch-chroot "$MNT" env X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ \
        X_GEN_SUBVOL_PREFIX=/@snapshots \
        x gen new --reason install --label first \
        || echo "warning: the first generation could not be created" >&2
else
    echo "warning: x CLI not found in the target; skipping the first generation" >&2
fi

echo
echo "installation complete. Reboot and remove the installation medium."

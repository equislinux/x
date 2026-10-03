#!/usr/bin/env bash
set -euo pipefail

# X installer configurator (text). Collects install options and writes the
# JSON config used by install.sh.
#   X_CONFIG_OUT  output path (default /tmp/x-install.json)

source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

OUT="${X_CONFIG_OUT:-/tmp/x-install.json}"
DRY="${X_DRY:-0}"

valid_hostname() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; }
valid_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_secret() { ! [[ "$1" =~ [\"\\] ]]; }

# Disk list (block devices of type disk).
mapfile -t DISKS < <(lsblk -dno NAME,SIZE,TYPE 2>/dev/null | awk '$3=="disk" {print "/dev/"$1" ("$2")"}')

DISK=""
while [[ -z "$DISK" ]]; do
    if (( ${#DISKS[@]} == 0 )); then
        echo "configurator: no disks found" >&2
        exit 1
    fi
    select_one DISK "Select the installation disk" "${DISKS[@]}"
    DISK="${DISK%% *}"
done

# Install mode: wipe the disk or install into its free space (dualboot).
MODE=""
select_one MODE "Install mode" \
    "Wipe the disk (delete everything)" \
    "Dualboot (use free space, keep existing OS)"
[[ "$MODE" == "Dualboot (use free space, keep existing OS)" ]] && MODE="dualboot" || MODE="wipe"

# Language -> system locale.
LANG_OPTIONS=("English" "Español" "Deutsch" "Français")
LANG_LABEL=""
select_one LANG_LABEL "System language" "${LANG_OPTIONS[@]}"
case "$LANG_LABEL" in
    "Español")  LANG_CODE="es"; LOCALE="es_ES.UTF-8" ;;
    "Deutsch")  LANG_CODE="de"; LOCALE="de_DE.UTF-8" ;;
    "Français") LANG_CODE="fr"; LOCALE="fr_FR.UTF-8" ;;
    *)          LANG_CODE="en"; LOCALE="en_US.UTF-8" ;;
esac

# Keyboard layout (vconsole).
KB_OPTIONS=("us" "es" "de" "fr" "uk" "latam" "br-abnt2")
KEYMAP=""
while [[ -z "$KEYMAP" ]]; do
    select_one KEYMAP "Keyboard layout" "${KB_OPTIONS[@]}"
done

# Timezone (curated subset).
TZ_OPTIONS=("UTC" "Europe/Madrid" "Europe/London" "Europe/Berlin" "America/Mexico_City"
            "America/Argentina/Buenos_Aires" "America/Los_Angeles" "Asia/Tokyo")
TIMEZONE=""
while [[ -z "$TIMEZONE" ]]; do
    select_one TIMEZONE "Timezone" "${TZ_OPTIONS[@]}"
done

HOST=""
while [[ -z "$HOST" ]]; do
    ask_value HOST "Hostname (default: x)"
    HOST="${HOST:-x}"
    valid_hostname "$HOST" || { echo "invalid hostname"; HOST=""; }
done

USER=""
while [[ -z "$USER" ]]; do
    ask_value USER "Username"
    valid_user "$USER" || { echo "invalid username"; USER=""; }
done

PASS=""
PASS2="x"
while [[ -z "$PASS" || "$PASS" != "$PASS2" ]]; do
    ask_password PASS "User password"
    ask_password PASS2 "Repeat the password"
    if ! valid_secret "$PASS"; then
        echo "password cannot contain \" or \\"
        PASS=""; PASS2="x"
    elif [[ -n "$PASS" && "$PASS" != "$PASS2" ]]; then
        echo "passwords do not match"
    fi
done

# Package profile.
PROFILE=""
select_one PROFILE "Package profile" "Full (all packages)" "Core (minimal system)"
[[ "$PROFILE" == "Core (minimal system)" ]] && PROFILE="core" || PROFILE="full"

# Bootloader.
BOOT=""
select_one BOOT "Bootloader" "GRUB (BIOS + UEFI)" "systemd-boot (UEFI only)"
[[ "$BOOT" == "systemd-boot (UEFI only)" ]] && BOOT="systemd-boot" || BOOT="grub"

# Root encryption (LUKS).
ENC="no"
if confirm_yes "Encrypt the root filesystem (LUKS)?" n; then
    ENC="yes"
    LUKS_PASS="$PASS"
    if ! confirm_yes "Use the user password as the LUKS passphrase?" y; then
        LUKS_PASS=""
        LUKS2="x"
        while [[ -z "$LUKS_PASS" || "$LUKS_PASS" != "$LUKS2" ]]; do
            ask_password LUKS_PASS "LUKS passphrase"
            ask_password LUKS2 "Repeat the LUKS passphrase"
            if ! valid_secret "$LUKS_PASS"; then
                echo "passphrase cannot contain \" or \\"
                LUKS_PASS=""; LUKS2="x"
            elif [[ -n "$LUKS_PASS" && "$LUKS_PASS" != "$LUKS2" ]]; then
                echo "passphrases do not match"
            fi
        done
    fi
else
    LUKS_PASS=""
fi

# Install Hyprland during setup (instead of first boot)?
HYPR="no"
confirm_yes "Install the Hyprland setup during installation (needs network)?" n && HYPR="yes"

if [[ "$DRY" == "1" ]]; then
    printf '{"disk":"%s","mode":"%s","hostname":"%s","username":"%s","language":"%s","locale":"%s","keyboard":"%s","timezone":"%s","profile":"%s","bootloader":"%s","encryption":"%s","hyprland":"%s"}\n' \
        "$DISK" "$MODE" "$HOST" "$USER" "$LANG_CODE" "$LOCALE" "$KEYMAP" "$TIMEZONE" "$PROFILE" "$BOOT" "$ENC" "$HYPR"
    exit 0
fi

if [[ "$MODE" == "dualboot" ]]; then
    if ! confirm_yes "Dualboot: X will be installed into the free space of $DISK; existing partitions and the ESP are preserved. Continue?" n; then
        echo "configurator: cancelled, dropping to a shell"
        exit 1
    fi
else
    if ! confirm_yes "WARNING: everything on $DISK will be erased. Continue?" n; then
        echo "configurator: cancelled, dropping to a shell"
        exit 1
    fi
fi

cat > "$OUT" <<EOF
{"disk":"$DISK","mode":"$MODE","hostname":"$HOST","username":"$USER","password":"$PASS","language":"$LANG_CODE","locale":"$LOCALE","keyboard":"$KEYMAP","timezone":"$TIMEZONE","profile":"$PROFILE","bootloader":"$BOOT","encryption":"$ENC","luks_password":"$LUKS_PASS","hyprland":"$HYPR"}
EOF
chmod 600 "$OUT"
echo "configuration written to $OUT"

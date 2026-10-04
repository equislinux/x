#!/usr/bin/env bash
set -Eeuo pipefail

# DEPRECATED: the maintained WSL path is the `xlnux/wsl` repo (importable
# rootfs + Windows importer) with provisioning from `xlnux/wsl-scripts`.
# This legacy builder is kept for reference only and is not exercised by the
# test suite.

# Configuration
PROFILE_DIR="$(pwd)"
WORK_DIR="${PROFILE_DIR}/work-wsl"
OUT_DIR="${PROFILE_DIR}/out-wsl"
ROOTFS_DIR="${WORK_DIR}/rootfs"
PACMAN_CONF="${PROFILE_DIR}/pacman.conf"
PACKAGES_FILE="${PROFILE_DIR}/packages.x86_64"

# Date for versioning
DATE_TAG="$(date +%Y.%m.%d)"
OUTPUT_TAR="${OUT_DIR}/x-${DATE_TAG}.tar.zst"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[xbuildwsl] $1${NC}"
}

# 1. Checks
if [[ ! -f "$PACMAN_CONF" ]]; then
    echo "Error: pacman.conf not found."
    exit 1
fi
if [[ ! -f "profiledef.sh" ]]; then
    echo "Error: profiledef.sh not found."
    exit 1
fi
if ! command -v zstd &> /dev/null; then
    echo "Error: zstd is not installed. Please install it to continue."
    exit 1
fi

# 2. Cleanup (Clean start)
log "Cleaning work and output directories..."
# Unmount if valid mountpoints exist to avoid busy errors
for mp in "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/run"; do
  if mountpoint -q "$mp"; then
    sudo umount -l "$mp" || true
  fi
done

sudo rm -rf "$WORK_DIR" "$OUT_DIR"
mkdir -p "$ROOTFS_DIR"
mkdir -p "$OUT_DIR"

# 3. Read Packages
log "Reading packages from $PACKAGES_FILE..."
PACKAGES=$(grep -vE '^\s*#' "$PACKAGES_FILE" | tr '\n' ' ')

# 4. Bootstrap (Install Base System)
log "Installing packages via pacstrap..."
# Remove -M to allowing copying host mirrorlist so repos work inside
sudo pacstrap -C "$PACMAN_CONF" -c -G "$ROOTFS_DIR" base $PACKAGES

# 5. Copy Custom Files (airootfs)
log "Copying airootfs configuration..."
sudo cp -r "${PROFILE_DIR}/airootfs/"* "$ROOTFS_DIR/"

# 5b. Copy pacman.conf to preserve custom repos (e.g. [x] repo)
log "Copying custom pacman.conf to target..."
sudo cp "${PACMAN_CONF}" "$ROOTFS_DIR/etc/pacman.conf"
sudo chown root:root "$ROOTFS_DIR/etc/pacman.conf"
sudo chmod 644 "$ROOTFS_DIR/etc/pacman.conf"

# 6. Apply Permissions (from profiledef.sh)
log "Applying file permissions from profiledef.sh..."
(
    declare -A file_permissions
    source "${PROFILE_DIR}/profiledef.sh"
    for file in "${!file_permissions[@]}"; do
        perm_string="${file_permissions[$file]}"
        IFS=':' read -r owner group mode <<< "$perm_string"
        target="$ROOTFS_DIR$file"
        if [ -e "$target" ]; then
            sudo chown "$owner:$group" "$target"
            sudo chmod "$mode" "$target"
        else
            echo "  - Warning: Target file $target not found."
        fi
    done
)

# 7. Customize
log "Running customization..."
sudo arch-chroot "$ROOTFS_DIR" /bin/bash -c "pacman-key --init && pacman-key --populate archlinux"

if [ -f "$ROOTFS_DIR/root/customize_airootfs.sh" ]; then
    log "Running customize_airootfs.sh..."
    sudo arch-chroot "$ROOTFS_DIR" /root/customize_airootfs.sh
fi

# 8. Optimization (Clean Cache)
log "Cleaning pacman cache to reduce size..."
# Manually remove cache files to be absolutely sure
sudo rm -rf "$ROOTFS_DIR/var/cache/pacman/pkg/"*
# Optionally remove sync dbs if desired, but keeping them (commented out) so pacman works immediately
# sudo rm -rf "$ROOTFS_DIR/var/lib/pacman/sync/"*

# 9. Create Tarball
log "Creating WSL tarball: $OUTPUT_TAR"
log "Using zstd -19 --long for maximum compression (this may take a while)..."
# Use pipe to zstd for max compression
sudo tar -C "$ROOTFS_DIR" \
    --exclude='./root/.automated_script.sh' \
    --exclude='./root/x-postinstall.sh' \
    -c . | zstd -T0 -19 --long -o "$OUTPUT_TAR"

log "Done! WSL Image created at: $OUTPUT_TAR"
log "You can import this into WSL. See instructions in WSL_GUIDE.md"


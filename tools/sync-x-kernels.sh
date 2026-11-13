#!/usr/bin/env bash
# Copy the signed X kernel packages from the sibling x-kernel build output into
# the live ISO. The installer installs them with xpm (xpm backend) or pacman -U
# (pacman backend), so the ISO does not depend on SourceForge redirects.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XK="${X_KERNEL_DIR:-$ROOT/../x-kernel}"
DEST="$ROOT/airootfs/root/x-installer/kernel-packages"

rm -rf "$DEST"
mkdir -p "$DEST"

copy_family() {
    local dir="$1" pkgbase="$2" file found=0
    [[ -d "$dir" ]] || { echo "sync-x-kernels: missing $dir; skipping $pkgbase" >&2; return 0; }
    for pattern in "$pkgbase-[0-9]*.pkg.tar.zst" "$pkgbase-headers-[0-9]*.pkg.tar.zst"; do
        for file in "$dir"/$pattern; do
            [[ -f "$file" ]] || continue
            install -m 0644 "$file" "$DEST/"
            [[ -f "$file.sig" ]] && install -m 0644 "$file.sig" "$DEST/"
            found=1
        done
    done
    (( found )) || echo "sync-x-kernels: no $pkgbase packages in $dir" >&2
}

copy_family "$XK/out/linux-x/stable" linux-x
copy_family "$XK/out/linux-x-mainline/mainline" linux-x-mainline

count="$(find "$DEST" -maxdepth 1 -type f -name '*.pkg.tar.zst' | wc -l)"
echo "sync-x-kernels: bundled $count package(s) in $DEST"
(( count > 0 ))

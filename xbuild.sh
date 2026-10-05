#!/usr/bin/env bash
set -Eeuo pipefail

LOG="build-$(date +%Y%m%d-%H%M).log"

# 0) Check that pacman.conf and the current profile (profiledef.sh) exist
[[ -f pacman.conf ]] || { echo "pacman.conf is missing in this directory"; exit 1; }
[[ -f profiledef.sh ]] || { echo "profiledef.sh is missing (you are not in the archiso profile root)"; exit 1; }

# 1) Attempt a clean unmount (avoids "target is busy" errors)
for mp in work/x86_64/airootfs/proc work/x86_64/airootfs/sys work/x86_64/airootfs/dev work/x86_64/airootfs/run; do
  if mountpoint -q "$mp"; then
    sudo umount -l "$mp" || true   # -l lazy umount
  fi
done
# If anything else is still mounted inside airootfs, do a recursive "lazy" umount:
if mountpoint -q work/x86_64/airootfs; then
  sudo umount -Rl work/x86_64/airootfs || true
fi

# 2) Clean work/ and out/
sudo rm -rf work out

# 3) Verbose build with explicit paths
sudo mkarchiso -C pacman.conf -v -w ./work -o ./out . 2>&1 | tee "$LOG"

# 4) Verify the ISO and print a clear message
ISO_COUNT=$(find ./out -maxdepth 2 -type f -name '*.iso' | wc -l)
if [[ "$ISO_COUNT" -gt 0 ]]; then
  echo "ISO created:"
  find ./out -maxdepth 2 -type f -name '*.iso' -printf ' - %p (%k KB)\n'
else
  echo "No ISO found in ./out. Check the log: $LOG"
  echo "Common causes: not enough disk space, an error in profiledef.sh, or a failing live helper or pacman hook."
  exit 2
fi

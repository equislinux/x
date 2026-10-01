# Project State

This document summarizes the current state of the X Linux project based on repository contents, scripts, and roadmap progress.

## Snapshot

- Status: active development.
- Distribution model: Arch-based custom spin built with `mkarchiso`.
- Delivery targets:
  - Bootable live ISO.
  - WSL-importable root filesystem tarballs.
- Repository model: includes a custom `[x]` pacman repository.

## What Is Already Implemented

### Identity and Branding

- System identity files are present in `airootfs/etc/` (including `os-release` and `motd`).
- Bootloader branding assets and config are present (`grub/`, `syslinux/`, `efiboot/`).
- Desktop-related branding automation exists in post-install scripts under `airootfs/root/`.

### Installation and Automation

- Calamares was removed; the live ISO no longer ships a graphical installer or the
  `x-calamares-config`/`x-live-session` packages.
- Installation and provisioning are being reworked around scripts (see the reboot
  roadmap in the workspace root).
- Post-install automation lives in `airootfs/root/x-postinstall.sh`.
- **Generations**: the installer creates `@`/`@home`/`@snapshots`/`@xstate`
  btrfs subvolumes and a bootable first generation; the payload (`x-scripts`)
  records bootable snapshots with manifests, supports rollback and granular
  restore, and ships pacman hooks that capture every transaction. See
  `generations.md`.

### Build Tooling

- ISO build script: `xbuild.sh`.
- WSL build scripts: `xbuildwsl.sh` and `xbuildwslc.sh`.
- ArchISO profile definition is maintained in `profiledef.sh`.

### Project Operations

- `ROADMAP.md` is integrated with GitHub Issues sync through `.github/workflows/roadmap-sync.yml`.
- The sync script (`.github/scripts/sync_roadmap.py`) can create and synchronize issue states from roadmap checkboxes.

## In Progress or Pending Areas

According to `ROADMAP.md`, notable pending areas include:

- Full package repository lifecycle completion.
- Improved installation UX and first-boot experience.
- Expanded user-facing documentation.
- Automated release pipeline (build/sign/versioning strategy).

## Risks and Notes

- Build scripts require `sudo` and assume an Arch-like host environment with required tools installed.
- `pacman.conf` currently uses `SigLevel = Optional TrustAll` for the custom repo, which is convenient for development but should be revisited for hardened release workflows.
- WSL guidance exists in multiple places; this has now been normalized into `docs/build-wsl.md` for consistency.

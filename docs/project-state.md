# Project State

This document summarizes the current state of the X Linux project based on repository contents, scripts, and roadmap progress (last reviewed 2026-10-10).

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
- Bootloader branding assets and config are present (`grub/`, `syslinux/`), one per firmware (`bios.syslinux` + `uefi.grub`).
- Desktop-related branding automation exists in post-install scripts under `airootfs/root/`.

### Installation and Automation

- Calamares was removed; the live ISO no longer ships a graphical installer or the
  `x-calamares-config`/`x-live-session` packages.
- Installation is a script-driven text installer (`airootfs/root/x-installer`):
  BIOS/UEFI, GRUB/systemd-boot, LUKS, dualboot, core/full profiles, optional
  Hyprland desktop and kernel selection (`linux`, `linux-lts`, `linux-zen`).
  See `installation.md` and `en|es/installer.md`.
- Post-install automation lives in `airootfs/root/x-postinstall.sh`.
- **Generations**: the installer creates `@`/`@home`/`@snapshots`/`@xstate`
  btrfs subvolumes and a bootable first generation; the payload (`x-scripts`)
  records bootable snapshots with manifests, supports rollback and granular
  restore, and ships pacman hooks that capture every transaction. See
  `generations.md`.

### Build Tooling

- ISO build script: `xbuild.sh`.
- WSL rootfs builds live in the dedicated `equislinux/wsl` / `equislinux/wsl-scripts` repositories.
- ArchISO profile definition is maintained in `profiledef.sh`.

### Project Operations

- Releases are cut locally: `xbuild.sh` builds the ISO and
  `x-repo/scripts/publish-iso.sh` signs and uploads it to SourceForge, refreshing
  the web index (`releases.json`).
- Validation runs locally: `scripts/test/validate.sh`, the btrfs suite and the
  QEMU end-to-end harness (`tests/e2e-autoinstall.py`). No GitHub Actions by
  design (owner decision).
- Public documentation: <https://equislinux.github.io/web/> (sources in `equislinux/wiki`).

## In Progress or Pending Areas

Notable open areas (see also `ROADMAP.md` and `x-repo/docs/`):

- `xpm` hardening: two P1 bugs (gcc-libs dependency cycle in the resolver and
  hardlink extraction for `zoneinfo` on real Arch packages).
- WSL integrations with the full system (`x setup`/`x home`) — feasibility
  research pending (parked by decision).
- Crypto housekeeping: offline backup of the project key and a rotation plan
  (`x-repo/docs/en|es/signing.md`).
- CI stays local until the stack consolidates; UKI/Secure Boot parked (a
  Microsoft-signed shim is the only zero-touch route for the ISO).

## Risks and Notes

- Build scripts require `sudo` and assume an Arch-like host environment with required tools installed.
- The custom repo is signed with the project key: the live ISO and the installed target use `SigLevel = Required` with the key embedded at `/etc/pacman.d/x-repo.pub`; the build host config (`x/pacman.conf`) uses `Never` for `[x]`.
- WSL guidance exists in multiple places; this has now been normalized into `docs/build-wsl.md` for consistency.

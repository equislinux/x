# Project Structure

This document describes the repository composition and the role of key files and directories.

## Top-Level Layout

```text
x/
├── airootfs/                  # Root filesystem overlay copied into the image/rootfs
├── grub/                      # GRUB configuration files
├── syslinux/                  # Syslinux boot configuration and assets
├── .github/                   # CI/workflow automation
├── profiledef.sh              # ArchISO profile metadata and permissions
├── pacman.conf                # pacman configuration (includes [x] repo)
├── packages.x86_64            # Package manifest for builds
├── xbuild.sh                  # ISO build script
├── xbuildwsl.sh               # WSL rootfs build script (gzip output)
├── xbuildwslc.sh              # WSL rootfs build script (zstd output)
├── ROADMAP.md                 # Project roadmap
└── README.md                  # Main project entrypoint
```

## `airootfs/` Composition

`airootfs/` is the most important directory in the project. Its content is overlaid into the target filesystem during image/rootfs builds.

- `airootfs/etc/`: system-level configuration and branding.
- `airootfs/root/`: automation scripts (live/install hooks).
- `airootfs/usr/local/bin/`: helper scripts available in the live environment.
- `airootfs/usr/local/share/`: branding assets (wallpapers, images, sound templates).

## Build-Critical Files

- `profiledef.sh`: defines ISO metadata, boot modes, image behavior, and selected file permissions.
- `packages.x86_64`: package list used by build scripts.
- `pacman.conf`: repository configuration used by both ISO and WSL build flows.

## Build Outputs

- ISO flow (`xbuild.sh`) writes artifacts to `out/`.
- WSL flow (`xbuildwsl.sh` and `xbuildwslc.sh`) writes artifacts to `out-wsl/`.
- Temporary build work directories are `work/` and `work-wsl/`.

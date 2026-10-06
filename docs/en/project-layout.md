# Project layout reference

> Other languages: [Español](../es/project-layout.md)

Reference of the repository composition and the role of its key files and
directories. See also the top-level `README.md` and the single-language guides
under `docs/`.

## Top-level layout

```text
x/  (equislinux/x)
|-- airootfs/                  # root filesystem overlay for the ISO/rootfs
|-- grub/                      # GRUB config used on the ISO (grub.cfg, loopback.cfg)
|-- syslinux/                  # Syslinux boot config and assets
|-- .github/                   # workflows and scripts (roadmap-issue sync)
|-- profiledef.sh              # ArchISO profile metadata, boot modes, permissions
|-- pacman.conf                # pacman config, includes the [x] repository
|-- packages.x86_64            # full live package manifest
|-- bootstrap_packages.x86_64  # minimal bootstrap set for archiso
|-- xbuild.sh                  # ISO build script (recommended)
|-- x.sh                       # minimal one-liner mkarchiso build
|-- ROADMAP.md                 # project roadmap
|-- README.md                  # repository entry point
|-- CODE_OF_CONDUCT.md         # community guidelines
|-- CONTRIBUTING.md            # contribution guide
|-- LICENSE                    # GPL-3.0
|-- SECURITY.md                # security policy
|-- SUPPORT.md                 # support channels
|-- out/                       # ISO build output (gitignored)
|-- work/                      # archiso working directory (gitignored)
|-- build-*.log                # timestamped build logs (gitignored)
`-- docs/
    |-- build-iso.md           # single-language ISO guide
    |-- build-wsl.md           # canonical WSL guide
    |-- installation.md        # single-language installer overview
    |-- project-state.md       # state snapshot
    |-- project-structure.md   # single-language structure reference
    |-- vm-testing.md          # VM testing commands
    |-- x-repository.md        # the [x] pacman repository
    |-- en/                    # English documentation (this set)
    `-- es/                    # Spanish documentation
```

## `airootfs/` composition

`airootfs/` is overlaid into the image/rootfs during builds. Its most relevant
parts:

| Path | Role |
|------|------|
| `airootfs/etc/` | System-level configuration and branding for the live image. |
| `airootfs/etc/hostname` | Live hostname (`x`). |
| `airootfs/etc/default/grub` | GRUB config (`GRUB_DISTRIBUTOR="X"`). |
| `airootfs/etc/motd` | Message of the day shown on the live TTY. |
| `airootfs/etc/pacman.conf` | pacman config for the live image. |
| `airootfs/etc/pacman.d/mirrorlist` | Mirrors used by the live image. |
| `airootfs/etc/locale.conf` | Default locale of the live image. |
| `airootfs/etc/mkinitcpio.conf.d/` | mkinitcpio (archiso) overrides. |
| `airootfs/etc/systemd/network/` | DHCP networkd configs (ethernet/wlan/wwan). |
| `airootfs/etc/systemd/system/` | Live systemd units, including `x-autoinstall.service` and live-helper services. |
| `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf` | Root autologin on TTY1. |
| `airootfs/etc/systemd/system/etc-pacman.d-gnupg.mount` | archiso keyring handling. |
| `airootfs/root/.automated_script.sh` | Official archiso `script=` automation runner. |
| `airootfs/root/.zlogin` | zsh login hook that starts the installer on TTY1. |
| `airootfs/etc/systemd/system/multi-user.target.wants/` | Committed enablement symlinks for live services (`x-autoinstall`, `x-keyring`, NetworkManager, ...). |
| `airootfs/root/x-installer/` | The text installer (see [Text installer](installer.md)). |
| `airootfs/root/x-postinstall.sh` | Legacy first-boot branding script; not invoked by the current installer (provisioning goes through the `x-scripts` payload). |
| `airootfs/usr/local/bin/` | Live helpers: `choose-mirror`, `livecd-sound`, `Installation_guide`, `xinstall`. |
| `airootfs/usr/local/share/livecd-sound/` | Sound template for `livecd-sound`. |

## `airootfs/root/x-installer/`

The text installer shipped in the live image:

| File | Purpose |
|------|---------|
| `installer.sh` | Entry point; runs the configurator then the installer. |
| `configurator.sh` | Interactive configuration (gum/plain prompts); writes the JSON plan. |
| `install.sh` | Performs partitioning, `pacstrap`, base config, user, provisioning, bootloader. |
| `autoinstall.sh` | Unattended installer (triggered by `xauto=1` + `cidata` disk). |
| `ui.sh` | Shared UI helpers used by the other scripts. |
| `packages.x86_64` | Default manifest for the `full` package profile. |
| `packages/` | Offline `x-scripts-*.pkg.tar.zst` payload bundled into the live image. |

## Build-critical files

- `profiledef.sh`: ArchISO profile metadata, boot modes (`bios.syslinux`,
  `uefi.grub`), image format (squashfs/xz), and file permissions.
- `packages.x86_64`: package manifest for the live environment, including the
  X packages `x-release` and `x-dev` from the `[x]` repository.
- `bootstrap_packages.x86_64`: minimal package set used by archiso for the
  bootstrap root.
- `pacman.conf`: repository configuration used by the ISO build flow; adds
  the `[x]` repository.
- `xbuild.sh` / `x.sh`: ISO build entry points.

## Bootloader assets

| Directory | Content |
|-----------|---------|
| `grub/` | `grub.cfg`, `loopback.cfg` used on the ISO (UEFI GRUB boot). |
| `syslinux/` | Syslinux configuration and splash for BIOS boot of the ISO. |

The ISO boot modes are `bios.syslinux` + `uefi.grub` (`profiledef.sh`), so
there is a single bootloader per firmware. The `autoinstall` menu entry
(hotkey `a`) exists in both paths with `xauto=1 console=ttyS0`.

The bootloader installed *into the target system* by `install.sh` is separate
from these ISO boot assets: GRUB (BIOS + UEFI) or systemd-boot (UEFI only).

## Documentation

The repository keeps the existing single-language guides in `docs/`
(`build-iso.md`, `build-wsl.md`, `installation.md`, `project-state.md`,
`project-structure.md`, `vm-testing.md`, `x-repository.md`). The structured,
bilingual documentation set lives under `docs/en/` and `docs/es/`.

## Build outputs

- ISO flow (`xbuild.sh`): `out/` artifacts; temporary work under `work/`.
- WSL rootfs builds live in the dedicated `equislinux/wsl` repository.
- All build outputs and `build-*.log` files are gitignored.

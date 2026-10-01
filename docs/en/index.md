# X distribution repository

> Other languages: [Español](../es/index.md)

This is the documentation index for the `x` repository (`xlnux/x`), the home
of the **X** distribution (formerly known as *X Linux* / `x-linux`). X is a
custom Arch Linux spin focused on simplicity, clean branding, and reproducible
builds. It ships its own package repository (`x-repo`) so X-specific packages
can be installed directly with `pacman`.

## Overview

The repository contains the distribution build source, not a user-facing
product on its own. It provides:

- An **archiso profile** that produces the bootable **live ISO**.
- A **text installer** that runs automatically in the live environment
  (no graphical installer; Calamares was removed).
- **Provisioning** of the installed system through the `x-scripts` payload,
  shipped offline inside the ISO.
- Helpers to build **WSL-importable root filesystem tarballs**.

The ISO uses the standard `mkarchiso` workflow. A custom `[x]` pacman
repository is declared in `pacman.conf` and is used both at build time and on
the installed system, so X branding and tooling packages (`x-release`,
`x-dev`) install with `pacman`.

## Project status

The distribution is under active development. The current work is the *reboot*
initiative (script-based provisioning in the style of Omarchy, with X's own
decisions and tooling). See `ROADMAP.md` for the roadmap and
`docs/project-state.md` for a state snapshot.

## How this repository maps to the organization

The workspace groups each xlnux repository under `x-lnux/`. Repo names were
renamed at some point, so older references to `x-linux` (the distro) or to an
`x` scripts repo must be read with this mapping in mind:

| Repository | Role |
|------------|------|
| `xlnux/x` | **The distro (this repo).** archiso profile, live ISO, text installer, WSL rootfs builds. |
| `xlnux/scripts` | Provisioning payload and the `x` CLI (`x setup`, `x theme`, ...). Packaged as `x-scripts` and installed by the text installer. |
| `xlnux/x-repo` | X binary package repository (hosted on GitHub Pages, `[x]` in `pacman.conf`) plus the package portal. |
| `xlnux/xpm` | X package manager (Rust). |
| `xlnux/xpkg` | X packaging tool for developers (Rust). |
| `equisdots/*` | Org that owns the desktop stack (Hyprland Lua config, Quickshell shell, palettes, engines, SDDM login) consumed read-only by the Hyprland setup tool in `scripts`; its official installer is `equisdots/dots`. |

Related documentation in this repository:

- [Build the ISO and WSL rootfs](building.md)
- [Text installer](installer.md)
- [Generations (btrfs snapshots, rollback, restore)](generations.md)
- [Testing in a VM](vm-testing.md)
- [Project layout reference](project-layout.md)

## Highlights

- **Branding.** Identity applied to GRUB (`GRUB_DISTRIBUTOR="X"`), the ISO
  label/publisher, MOTD, and installed packages.
- **Text installer.** `configurator.sh` collects options and writes a JSON
  plan; `install.sh` partitions (GPT/btrfs), runs `pacstrap`, configures the
  base system, provisions with `x-scripts`, and installs a bootloader.
- **Unattended install.** Kernel cmdline `xauto=1` plus a disk labeled
  `cidata` containing `x-install.json` triggers the autoinstall path.
- **System generations.** The installer creates `@`/`@home`/`@snapshots`/
  `@xstate` btrfs subvolumes and a bootable first generation; the payload
  records bootable snapshots with manifests, rollback and granular restore
  (`x gen`), plus dotfile generations (`x home`) and pacman hooks. See
  [Generations](generations.md).
- **Offline provisioning payload.** The `x-scripts` package and the Hyprland
  config snapshot ship inside the ISO, so provisioning does not depend on
  downloading them during install.
- **WSL support.** `xbuildwsl.sh` / `xbuildwslc.sh` produce rootfs tarballs.

## Development model

- `main` is the branch described by this documentation.
- The reboot initiative is developed on the `x/reboot` branch of each repo
  (`origin/x/reboot`).
- Older remote branches (`checkpoint/calamares-installer-v1`, `dev`) are
  historical and do not reflect the current installer.

## Scope

Everything in this repository is part of the xlnux organization. Only
references related to building, installing, and provisioning X live here;
user-facing setup logic lives in the `x-scripts` payload.

# Build WSL Guide

X for WSL is built and provisioned from dedicated repositories; this
repository (`xlnux/x`) only ships the ISO profile and the installer.

| Repository | Role |
|------------|------|
| [`xlnux/wsl`](https://github.com/xlnux/wsl) | `build-rootfs.sh` builds an importable rootfs tarball (`.tar.gz` + `.sha256`) and `install.ps1` imports it on Windows. Published release: `v0.1.0`. |
| [`xlnux/wsl-scripts`](https://github.com/xlnux/wsl-scripts) | Two-stage in-distro provisioning (`stage-root.sh` / `stage-user.sh`): locale, keymap, timezone, user, shell, sudo and rc files. |

## Build

On an Arch-like host:

```bash
git clone https://github.com/xlnux/wsl
cd wsl && sudo ./build-rootfs.sh
```

The artifact lands in `out/` (`x-wsl-rootfs.tar.gz` plus its `.sha256`). The
rootfs intentionally ships no kernel, firmware or NetworkManager: WSL provides
the kernel and networking.

## Import

On Windows (WSL Store >= 0.67.6, Windows 11 / Server 2022+):

```powershell
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz --version 2
```

Tar streams (optionally compressed) import directly; do not unpack first.

## First boot

```bash
# root stage: tools, locale, keymap, timezone, user, sudo
./install.sh
# then terminate and re-enter as the created user for the user stage
```

See `xlnux/wsl` and `xlnux/wsl-scripts` for the authoritative flow and
options.

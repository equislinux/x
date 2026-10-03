# Building the ISO

> Other languages: [Español](../es/building.md)

This guide explains how to build the X live ISO from this repository with
`xbuild.sh`, and summarizes the separate WSL rootfs build scripts.

## Prerequisites

- A Linux environment with the ArchISO tooling available (Arch Linux or a
  compatible distribution).
- `sudo` access.
- The `archiso` package.
- Enough disk space (several GB) and network access to download packages.

Install the dependency:

```bash
sudo pacman -S archiso
```

## Build command

Run from the repository root:

```bash
./xbuild.sh
```

## What `xbuild.sh` does

1. Validates that `pacman.conf` and `profiledef.sh` exist in the current
   directory.
2. Attempts a lazy unmount of stale mount points under
   `work/x86_64/airootfs` (avoids "target is busy" errors from previous runs).
3. Removes the previous `work/` and `out/` directories.
4. Runs `sudo mkarchiso -C pacman.conf -v -w ./work -o ./out .`, teeing all
   output into a timestamped log file.
5. Verifies that at least one ISO was produced and prints the artifact path and
   size; otherwise it prints a message and exits with a non-zero status.

A minimal one-liner equivalent, `x.sh`, performs the same `mkarchiso` build but
without the cleanup and verification steps. `xbuild.sh` is the recommended
entry point.

## Outputs

- ISO artifact: `out/x-YYYY.MM.DD-x86_64.iso` (the version date comes from
  `profiledef.sh`).
- Build log: `build-YYYYMMDD-HHMM.log` in the repository root.

Both `work/` and `out/` are recreated on each build and are gitignored, as are
the `build-*.log` files.

## Profile facts

`profiledef.sh` defines the ISO metadata used by `mkarchiso`:

- `iso_name`: `x`
- `iso_version`: `YYYY.MM.DD` (date-based)
- `iso_label`: `x_YYYYMM`
- `iso_publisher`: `Xscriptor <https://xscriptor.io/x>`
- `iso_application`: `X Live/Rescue DVD`
- Boot modes: `bios.syslinux` and `uefi.grub`
- Root filesystem image: squashfs, xz-compressed
- File permissions for sensitive/live files (for example `/etc/shadow`,
  the `airootfs/root` scripts, and the `/usr/local/bin` live helpers including
  `xinstall`).

## Packages and repositories used by the build

- `packages.x86_64` is the full package manifest for the live ISO. It includes
  the base system plus recovery/live tooling, fonts, a browser (Firefox),
  the X packages `x-release` and `x-dev` (from the `[x]` repository), and `gum`
  (used by the text installer UI).
- `bootstrap_packages.x86_64` is the minimal set (`base`,
  `arch-install-scripts`) used by archiso for the bootstrap root.
- `pacman.conf` adds the custom repository:

  ```ini
  [x]
  SigLevel = Never
  Server = https://xlnux.github.io/x-repo/repo/x86_64
  ```

  The *build host* uses `Never` (it may not have the project key). The **live
  ISO and the installed target** use `SigLevel = Required`: the public key
  ships at `/etc/pacman.d/x-repo.pub` and `customize_airootfs.sh`/`install.sh`
  import and locally sign it in the live and target keyrings.
- The provisioning payload (`x-scripts`) is shipped **offline** inside the ISO
  at `airootfs/root/x-installer/packages/x-scripts-*.pkg.tar.zst`, so the
  installer does not need to fetch it from the network during installation.

## Troubleshooting

- If no ISO is generated, inspect the build log first (`build-*.log`).
- Common failure causes:
  - insufficient disk space;
  - errors in profile customization logic;
  - invalid profile configuration in `profiledef.sh`;
  - stale mounts under `work/x86_64/airootfs` (the script tries to clean them;
    unmount with `sudo umount -R work/x86_64/airootfs` if needed).

## WSL builds (separate scripts)

WSL root filesystem tarballs are built with their own scripts, not
`xbuild.sh`:

| Script | Output |
|--------|--------|
| `sudo ./xbuildwsl.sh` | `out-wsl/x-YYYY.MM.DD.tar.gz` (gzip) |
| `sudo ./xbuildwslc.sh` | `out-wsl/x-YYYY.MM.DD.tar.zst` (zstd; requires `zstd`) |

Both scripts bootstrap a rootfs under `work-wsl/rootfs` with `pacstrap`,
copy the `airootfs` overlay, apply the permissions declared in
`profiledef.sh`, run the customization step in `arch-chroot`, clean the pacman
cache, and create the tarball. They require an Arch-like environment with
`pacstrap`/`arch-chroot` and `sudo`.

Notes:

- WSL cannot import `.tar.zst` archives directly; decompress first
  (`zstd -d`) to get a `.tar` and then run `wsl --import`.
- `xbuildwslc.sh` excludes the live-only helper scripts
  (`.automated_script.sh`, `x-postinstall.sh`) from the archive.
- See `docs/build-wsl.md` for the canonical WSL flow and `WSL_GUIDE.md` for a
  longer, legacy walkthrough.

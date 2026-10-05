# Text installer

> Other languages: [Español](../es/installer.md)

X is installed from the **live ISO** using a **text installer**. There is no
graphical installer (Calamares was removed). Everything below lives under
`airootfs/root/x-installer/` in this repository and is shipped in the live
environment at `/root/x-installer/`.

## Entry points and when the installer runs

- The live environment auto-logs in as `root` on TTY1 (agetty autologin) with
  zsh.
- `/root/.zlogin` first runs `/root/.automated_script.sh` (the official
  archiso `script=` mechanism) if present, and then launches the installer on
  TTY1, **unless** the kernel cmdline contains `script=` or `xauto=1`.
- The entry point is `installer.sh` (`/root/x-installer/installer.sh`).
- A shortcut is available in the live shell:

  ```bash
  xinstall
  ```

  `xinstall` (`/usr/local/bin/xinstall`) simply execs `installer.sh`. If you
  are dropped to a plain shell instead of the installer, run `xinstall` or
  `bash /root/x-installer/installer.sh`.

## Installer layout

```text
/root/x-installer/
|-- installer.sh        # entry point (configurator + install)
|-- configurator.sh     # interactive configuration, writes a JSON plan
|-- install.sh          # performs the actual installation
|-- autoinstall.sh      # unattended entry (xauto=1 + cidata disk)
|-- ui.sh               # UI helpers: gum with plain-prompt fallback
|-- packages.x86_64     # default manifest for the "full" package profile
`-- packages/           # offline x-scripts payload (*.pkg.tar.zst)
```

A systemd unit, `x-autoinstall.service`, is enabled in the live image
(`airootfs/etc/systemd/system/`) and drives the unattended path. See
[Autoinstall](#autoinstall) below.

## Interactive flow

`installer.sh` runs the configurator and, if it succeeds, the installer.

1. `configurator.sh` collects the options below and writes
   `/tmp/x-install.json` (mode 600).
2. `install.sh` reads that JSON, validates it, and performs the installation.

With `X_DRY=1`, the plan is shown without touching the disk (see
[Environment variables](#environment-variables)).

### Configurator options (`configurator.sh`)

The UI uses `gum` (`choose`, `input`, `confirm`) when available and falls back
to plain text prompts otherwise (`ui.sh`).

| Step | Options | Stored value |
|------|---------|--------------|
| Disk | any block device of type `disk` (from `lsblk`) | `disk` (e.g. `/dev/sda`) |
| System language | English, Español, Deutsch, Français | `language` + `locale` |
| Keyboard layout | `us`, `es`, `de`, `fr`, `uk`, `latam`, `br-abnt2` | `keyboard` |
| Timezone | `UTC`, `Europe/Madrid`, `Europe/London`, `Europe/Berlin`, `America/Mexico_City`, `America/Argentina/Buenos_Aires`, `America/Los_Angeles`, `Asia/Tokyo` | `timezone` |
| Hostname | free text (default `x`) | `hostname` |
| Username | free text | `username` |
| User password | free text (repeated) | `password` |
| Package profile | `Full (all packages)` / `Core (minimal system)` | `profile` (`full`/`core`) |
| Bootloader | `GRUB (BIOS + UEFI)` / `systemd-boot (UEFI only)` | `bootloader` (`grub`/`systemd-boot`) |
| Root encryption (LUKS) | yes/no | `encryption` (`yes`/`no`) |
| LUKS passphrase | reuse user password or dedicated | `luks_password` |
| Install Hyprland setup | yes/no (requires network) | `hyprland` (`yes`/`no`) |
| Install Xscriptor AI agents | yes/no (requires network) | `agents` (`yes`/`no`) |

Language-to-locale mapping used by the configurator:

| Language | `language` | `locale` |
|----------|------------|----------|
| English | `en` | `en_US.UTF-8` |
| Español | `es` | `es_ES.UTF-8` |
| Deutsch | `de` | `de_DE.UTF-8` |
| Français | `fr` | `fr_FR.UTF-8` |

Validation rules: hostname must match `^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$`;
username `^[a-z_][a-z0-9_-]{0,31}$`; passwords/passphrases cannot contain
`"` or `\`.

Before writing the config, the configurator asks for final confirmation that
everything on the selected disk will be erased. The resulting JSON looks like:

```json
{"disk":"/dev/sda","hostname":"x","username":"x","password":"secret","language":"en","locale":"en_US.UTF-8","keyboard":"us","timezone":"UTC","profile":"full","bootloader":"grub","encryption":"no","luks_password":"","hyprland":"no","agents":"no"}
```

The JSON is written to the path in `X_CONFIG_OUT` (default
`/tmp/x-install.json`). Only `disk`, `hostname`, `username`, and `password`
are required; the remaining keys have sensible defaults when absent.

## Installation steps (`install.sh`)

1. **Parse and validate** the JSON (`disk`, `hostname`, `username`), require
   root and a real block device.
2. **Partition** with GPT (`sgdisk --zap-all` first):
   - `grub`: 1 MiB `bios_grub` partition, 1 GiB EFI partition, rest = root.
   - `systemd-boot`: 1 GiB EFI partition, rest = root.
   (1 GiB leaves room for several generations of boot entries.)
3. **LUKS** (if `encryption=yes`): `cryptsetup luksFormat --type luks2` on the
   root partition (passphrase from `luks_password`, falling back to the user
   password) and open it as `/dev/mapper/xroot`.
4. **Format and mount**: the EFI partition as FAT32 (`mkfs.vfat -F32`) mounted
   at `/mnt/boot`; the root (or LUKS mapping) as btrfs with the `@`, `@home`,
   `@snapshots` and `@xstate` subvolumes mounted at `/`, `/home`,
   `/.snapshots` and `/var/lib/x`. `/tmp` is appended to the fstab as tmpfs.
5. **Package set**:
   - Base set: `base base-devel linux linux-firmware sudo networkmanager
     openssh git jq x-release btrfs-progs xfetch-git xtop-git kitty pipewire
     pipewire-pulse pipewire-alsa wireplumber alsa-utils sddm`, plus
     `grub efibootmgr` for GRUB and `cryptsetup` for LUKS. `btrfs-progs` is
     required by the generations engine; the X tools (`xfetch`, `xtop`) are
     installed in every profile.
   - `full` profile: adds every package in the manifest pointed to by
     `X_PKGLIST` (default `/root/x-installer/packages.x86_64`).
   - `core` profile: adds only `vim zsh`.
   - The `full` profile with the Hyprland desktop compiles AUR packages
     (`quickshell-git`, `swayosd-git`, ...): give the installer **≥6 GB RAM**;
     on low-RAM machines it limits the build jobs automatically.
6. **Prepare the keyrings** and **wait for network** (DNS check against
   `geo.mirror.pkgbuild.com`, up to ~120 s), then `pacstrap /mnt <pkgs>` from
   the official mirrors plus the signed `[x]` repository (`Required`).
   - Live: `/etc/pacman.d/x-repo.pub` is added and locally signed
     (`pacman-key --init/--populate archlinux/--add/--lsign-key`). This is
     re-applied at boot by `x-keyring.service` because `pacman-init.service`
     recreates `/etc/pacman.d/gnupg` on a tmpfs; `install.sh` repeats it
     idempotently before `pacstrap` (which verifies against the live keyring).
   - Target: `pacman-key --gpgdir /mnt/etc/pacman.d/gnupg --init`,
     `--populate archlinux`, add + locally sign the same key.
7. **Install `x-scripts` offline**: the payload
   `packages/x-scripts-*.pkg.tar.zst` present in the live environment is copied
   into the target and installed with `pacman -U` inside the chroot.
8. **Base configuration**: `genfstab`, timezone symlink, `locale.gen` +
   `/etc/locale.conf`, `KEYMAP` in `/etc/vconsole.conf`, hostname, copy of the
   working mirrorlist, and the `[x]` repository appended to the target's
   `pacman.conf` if missing.
9. **User**: create the user (member of `wheel`, login shell `bash`), set the
   password with `chpasswd`, and enable `%wheel` in `sudoers`.
10. **Provisioning** with the `x` CLI from the `x-scripts` package:
    - system phases as root: `X_HW_AUTO=0 x setup`;
    - user phases as the new user:
      `X_HYPRLAND=0 X_HW_AUTO=0 x setup --user`.
    - PipeWire/Pulse/WirePlumber are enabled for all users; the Hyprland setup
      is **deferred** to a later step/point (not run here when
      `hyprland=no`).
    - optional AI agents (`agents=yes`): after provisioning,
      `x agent install --bundle x` runs as the target user with
      `HOME=/home/<user>` (Xscriptor bundle: agents, skills and commands for
      OpenCode).
11. **Hyprland setup** (only if `hyprland=yes`): a temporary passwordless-sudo
    drop-in is created, and
    `/usr/share/x/tools/hyprland-install.sh` runs as the target user. The drop-in
    is removed afterwards. The tool prefers the offline equisdots snapshot
    shipped in the package (`/usr/share/x/config/equisdots`); it only clones
    the official `equisdots/dots` installer as an online fallback. NVIDIA is
    owned by the system hardware phase; the tool falls back to the upstream
    equisdots NVIDIA setup only if a GPU is present without a driver.
12. **Initramfs (LUKS only)**: replace `HOOKS` in `mkinitcpio.conf` to include
    the `encrypt` hook and rebuild with `mkinitcpio -P`.
13. **Branding**: `x-release-apply` (from `x-release`) is run *before* the
    bootloader step so a LUKS kernel cmdline written afterwards is not
    overwritten.
14. **Bootloader**:
    - `grub`: `grub-install` for `x86_64-efi` (removable) and `i386-pc`
      (booting from the whole disk), then `grub-mkconfig`.
      `GRUB_CMDLINE_LINUX` always carries the root command line with
      `rootflags=subvol=@` (plus `cryptdevice=UUID=<luks-uuid>:xroot
      root=/dev/mapper/xroot` under LUKS).
    - `systemd-boot`: `bootctl --esp-path=/boot install`, a `BOOTX64.EFI`
      removable fallback if needed, and a loader entry
      `X Linux` (UEFI only) with the matching `root=` or `cryptdevice=`
      cmdline.
15. **First generation**: inside the chroot,
    `X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ x gen new --reason install
    --label first` creates `/.snapshots/0001`, the manifest under
    `/var/lib/x/generations/0001` and the boot entries (systemd-boot
    `loader/entries/x-gen-0001.conf`, GRUB `custom.cfg`). This is the base for
    rollbacks and granular restores; see `generations.md`.
16. **Cleanup**: on exit, mounts are unmounted, the LUKS mapping is closed if
    open, and the install JSON is removed.

A message tells you the installation is complete; reboot and remove the
installation medium.

## Autoinstall

The installer supports unattended installation from the live ISO:

- The kernel cmdline must contain **`xauto=1`**.
- A storage device labeled **`cidata`** must exist and contain an
  **`x-install.json`** file (for example an extra virtual disk in QEMU).

`x-autoinstall.service` (enabled in the live image) runs
`autoinstall.sh`, which:

1. Skips immediately if `xauto=1` is not present on the cmdline.
2. Looks up the device by label (`blkid -L cidata`); skips if absent.
3. Mounts it read-only at `/run/cidata`.
4. Runs `install.sh` with `X_INSTALL_JSON` pointing at
   `/run/cidata/x-install.json`.
5. Writes the log to `/tmp/x-install.log` and echoes it to the serial console
   / console, then unmounts.

The JSON for an unattended run only requires the base keys, for example:

```json
{"disk":"/dev/vda","hostname":"x-vm","username":"x","password":"secret","profile":"core","bootloader":"grub","encryption":"no","hyprland":"no","kernel_params":"console=ttyS0"}
```

`kernel_params` is optional: extra kernel command-line parameters appended to
the installed system's cmdline (restricted to a safe character set and
validated before partitioning). It is useful for headless validation, e.g.
`"kernel_params":"console=ttyS0"` to keep the serial console after install.

See [Testing in a VM](vm-testing.md) for an example cidata disk.

The other automation mechanism is the official archiso **`script=`** cmdline
(`/root/.automated_script.sh` downloads or copies a script and executes it).
When `script=` or `xauto=1` is present, the interactive installer is not
launched.

## Kernel cmdline reference

| Parameter | Effect |
|-----------|--------|
| `script=<url or path>` | Runs the official archiso automation script; interactive installer is skipped. |
| `xauto=1` | Enables the unattended autoinstall (needs a `cidata` disk with `x-install.json`). |
| `accessibility=` | Sets single-line zle (screen-reader friendly TTY). |

## Environment variables

| Variable | Default | Scope | Effect |
|----------|---------|-------|--------|
| `X_SKIP_INSTALLER` | unset | live | `1` makes `installer.sh` print "skipped" and exit. |
| `X_DRY` | `0` | live | `1` shows the plan only; nothing is written or erased. |
| `X_CONFIG_OUT` | `/tmp/x-install.json` | configurator | Where the config JSON is written. |
| `X_INSTALL_JSON` | `/tmp/x-install.json` | installer | JSON config consumed by `install.sh`. |
| `X_PKGLIST` | `/root/x-installer/packages.x86_64` | installer | Package manifest used by the `full` profile. |
| `X_HYPRLAND` | payload default `1` | payload (`x setup`) | Set to `0` by the installer to defer the Hyprland setup. |
| `X_HW_AUTO` | payload default `1` | payload (`x setup`) | Set to `0` during install to disable hardware auto-detection. |

Notes:

- `X_DRY=1` in `installer.sh` ensures a JSON exists (with a placeholder if
  needed) and runs `install.sh`, which prints the install plan and exits
  without touching the disk. The configurator, when run with `X_DRY=1`, writes
  the JSON without the password and stops before the erase confirmation.
- `X_HYPRLAND`/`X_HW_AUTO` belong to the `x-scripts` payload; the installer
  sets them when calling `x setup`.

## Live medium vs installed system (credentials)

The live medium is intentionally permissive so it can be used without a
password: root autologin on tty1, empty root password and sshd with
`PermitRootLogin yes` + password authentication. **All of that ships only in
`airootfs`** (the live squashfs).

The installer never copies those files to the target: the installed system
takes `/etc/shadow` from the `shadow` package (root locked), creates the wheel
user from the seed and does **not** enable sshd. Keep that rule when adding
post-install automation: never copy `/etc` from the live into the target.

## Dualboot mode

`install.sh` supports two modes (`"mode"` in the JSON): `wipe` (default)
erases the disk and builds a fresh GPT; `dualboot` installs into the
**largest unallocated region**, preserving every existing partition and the
Windows bootloader. The configurator asks for the mode.

`dualboot` is UEFI-only in this iteration and requires a GPT disk with an
existing EFI System Partition:

| Field | Values | Meaning |
|-------|--------|---------|
| `mode` | `wipe` / `dualboot` | install strategy |
| `esp` | partition (optional) | reuse this ESP instead of auto-detecting the `ef00` one |
| `min_size` | GiB (default 20) | minimum free region accepted |

What it does:

1. Validates UEFI + GPT + an existing ESP; never runs `sgdisk --zap-all`.
2. Takes the largest free block (`sgdisk -F`/`-E`), checks `min_size` and
   creates **only** the root partition there (`sgdisk -n 0:start:end -t
   0:8300`). Existing entries are never modified.
3. Mounts the existing ESP at `/mnt/boot` and never formats it; btrfs +
   `@`/`@home`/`@snapshots`/`@xstate` exactly as in wipe mode.
4. Bootloader without touching `EFI/Microsoft/**`:
   - systemd-boot: `bootctl install` on the shared ESP; sd-boot auto-detects
     the Windows Boot Manager and lists it in the menu. The pre-existing
     fallback `EFI/BOOT/BOOTX64.EFI` (possibly Windows') is saved and restored
     around `bootctl`.
   - GRUB: `grub-install --target=x86_64-efi --bootloader-id=x` plus
     `os-prober` (`GRUB_DISABLE_OS_PROBER=false`) to add the Windows entry.
5. Keeps the Windows Boot Manager first in the firmware order (best effort via
   `efibootmgr`), and X generations never overwrite Microsoft files.

Caveats: BIOS/MBR dualboot is not supported, and shrinking an existing
partition to make room is out of scope (the free space must already exist).

## Requirements and caveats

- Installation requires **network access**: `pacstrap` pulls from the official
  Arch mirrors and the `[x]` repository. An offline mirror bundled in the ISO
  is pending (see the workspace ROADMAP).
- The target disk is completely erased.
- `systemd-boot` is **UEFI only**; GRUB writes both a BIOS (with the
  `bios_grub` partition) and a UEFI (removable) path, so either boot mode
  works.
- LUKS uses LUKS2 with the legacy `encrypt` initramfs hook.

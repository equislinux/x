# Generations (installer side)

X Linux uses **btrfs subvolumes** so the provisioning payload can version the
system: every relevant change records a bootable snapshot plus a manifest
(`x gen new`), `x gen rollback` switches the default boot and `x gen restore`
recovers individual paths. This document covers only the installer side; the
engine, CLI and semantics live in `equislinux/scripts`
(`docs/en/generations.md`).

## Disk layout

GPT with a 1G EFI partition (room for several generations of boot entries) and
a btrfs root partition (inside LUKS2 when encryption is enabled):

| Subvolume | Mount | Content |
|-----------|-------|---------|
| `@` | `/` | Root tree (writable; the first generation, live subvol `/@`) |
| `@home` | `/home` | User data (never touched by rollback) |
| `@snapshots` | `/.snapshots` | Generation snapshots, mode 0700 |
| `@xstate` | `/var/lib/x` | Shared generation metadata, mode 0700 |

`/etc/fstab` is generated with `genfstab` while all subvolumes are mounted;
`/tmp` is appended as tmpfs so snapshots never capture transient files.

## Boot

The kernel cmdline (GRUB `GRUB_CMDLINE_LINUX` and the systemd-boot
`loader/entries/x.conf`) carries `rootflags=subvol=@` for the first generation;
the root UUID is added as usual (`root=UUID=...`, or `cryptdevice=...` +
`/dev/mapper/xroot` under LUKS). Later generations are forked from the live
root into `/.snapshots/<id>` and their fstab is self-patched by the engine, so
each one boots with `rootflags=subvol=/@snapshots/<id>`.

## First generation

After the bootloader step the installer runs, inside the target chroot:

```bash
X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ x gen new --reason install --label first
```

This records `/var/lib/x/generations/0001/` (manifest, package list, enabled
services, archived kernel/initramfs in the shared `@xstate` subvolume), creates
the `/.snapshots/0001` snapshot and writes the boot entries:

- systemd-boot: `/boot/loader/entries/x-gen-0001.conf` (+ `x.conf` mirror) and
  the loader default.
- GRUB: `/boot/grub/custom.cfg` with `set default=x-gen-0001` and one
  `menuentry` per kept generation.

`X_GEN_CMDLINE` records the real target cmdline because `/proc/cmdline` inside
the chroot belongs to the live ISO; `X_GEN_LIVE_SUBVOL` tells the engine that
generation 0001 is the live `/@` subvol (not a `/.snapshots` fork).

During installation `x setup` runs with `X_GEN_SKIP=1`: the first generation is
created once, by the installer, after branding and bootloader are in place.

## Requirements

- `btrfs-progs` in the target (already in `packages.x86_64` and the live
  package list).
- ESP size: 1G is the default in new installs (older 512M installs still work;
  the engine prunes ESP copies beyond `X_GEN_BOOT_KEEP`, default 3).
- The payload records generations only when the root filesystem is btrfs; on
  other setups every generation hook is a no-op and `x gen` reports that
  generations are unavailable.

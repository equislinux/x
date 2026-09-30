# Generations (installer side)

X Linux uses **btrfs subvolumes** so the provisioning payload can version the
system: each relevant change creates an immutable snapshot plus a manifest
(`x gen new`). This document covers only the installer side; the engine and
commands live in `xlnux/scripts` (`docs/en/generations.md`).

## Disk layout

GPT with a 512M EFI partition and a btrfs root partition (inside LUKS2 when
encryption is enabled):

| Subvolume | Mount | Content |
|-----------|-------|---------|
| `@` | `/` | Root tree (writable; the live generation) |
| `@home` | `/home` | User data (not snapshotted per generation) |
| `@snapshots` | `/.snapshots` | Read-only generation snapshots (mode 0700) |

`/etc/fstab` is generated with `genfstab` while all three subvolumes are
mounted; `/tmp` is appended as tmpfs so snapshots never capture transient
files.

## Boot

The kernel cmdline (GRUB `GRUB_CMDLINE_LINUX` and the systemd-boot
`loader/entries/x.conf`) always carries `rootflags=subvol=@`; the root UUID is
added as usual (`root=UUID=...`, or `cryptdevice=...` + `/dev/mapper/xroot`
under LUKS).

## First generation

After the bootloader step the installer runs, inside the target chroot:

```bash
X_GEN_CMDLINE="$CMDROOT" x gen new --reason install --label first
```

This creates `/.snapshots/0001` plus `/var/lib/x/generations/0001/` (manifest,
package list, enabled services and an archived copy of the kernel/initramfs).
`X_GEN_CMDLINE` records the real target cmdline because `/proc/cmdline` inside
the chroot belongs to the live ISO.

During installation `x setup` runs with `X_GEN_SKIP=1`: the first generation is
created once, by the installer, after branding and bootloader are in place.

## Requirements

- `btrfs-progs` in the target (already in `packages.x86_64` and the live
  package list).
- The payload creates generations only when the root filesystem is btrfs; on
  other setups every generation hook is a no-op and `x gen` reports that
  generations are unavailable.

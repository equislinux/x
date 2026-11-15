# Installation

X Linux is installed from the **live ISO** using a **text installer** (no
graphical installer; Calamares was removed).

## Flow

1. The live environment boots to TTY1 and launches the installer (`/root/x-installer/`).
2. **Configurator** (`configurator.sh`): selects the disk, hostname, and user
   (UI via `gum`; falls back to plain prompts if unavailable). Writes `/tmp/x-install.json`.
3. **Installer** (`install.sh`):
   - Partitions (GPT: EFI 2G by default, 4/6/8/10G manual + btrfs; LUKS2
     optional) and creates the
     `@`/`@home`/`@snapshots`/`@xstate` subvolumes, mounted at `/mnt`.
   - xpm or `pacstrap`: base + live manifest (includes the `[x]` packages).
   - Configures locale/hostname, creates the user, and applies branding.
   - With `nvidia=yes` (or `auto` on detected NVIDIA hardware) installs the
     DKMS driver set, embeds the modules in initramfs, adds the DRM kernel
     parameters and orders `nvidia_drm` before the display manager.
   - Provisions with the **`x-scripts`** package: system phases (`x setup`,
     skipped from creating a generation via `X_GEN_SKIP=1`) and user phases
     (`x setup --user`; the Hyprland setup is deferred to first boot,
     `X_HYPRLAND=0` during installation).
   - Installs GRUB with `x` branding.
   - Creates the **first generation** (`x gen new --reason install`): snapshot
     base for rollbacks and granular restores, plus its boot entry (see
     `generations.md`).
   - Enables a one-shot first-boot service that records generation `0002`
     after systemd finishes starting, capturing first-boot service and `/etc`
     changes; `0002` becomes the default and `0001` stays as the baseline.

## Variables

- `script=<url|path>` on cmdline: automated installation (no configurator).
- `X_DRY=1`: shows the plan without touching anything.
- `X_SKIP_INSTALLER=1`: do not launch the installer at boot.
- `X_PKGLIST`: alternative package manifest (default
  `/root/x-installer/packages.x86_64`, used by the `full` profile).
- `"desktop":"hyprland"|"niri"|"kde"|"none"` selects the desktop installed
  online during the text install. `hyprland` is the legacy JSON key.
- `"virtualization":"yes"` in the JSON installs QEMU/KVM + libvirt +
  `virt-manager`, adds the user to `kvm`/`libvirt`, enables `libvirtd.socket`
  and autostarts the `default` NAT network. The GUI needs a desktop; `virsh`
  and `virt-install` work without one.

## Notes

- Installation uses the official repos + `[x]` (requires network). The offline
  mirror bundled in the ISO is pending design (see the workspace ROADMAP).
- End-to-end validation in QEMU: pending (requires a VM environment).

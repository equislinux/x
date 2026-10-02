# Testing X in a VM

> Other languages: [Español](../es/vm-testing.md)

Helper commands to run the X live ISO and to boot an installed disk with QEMU.
Adjust the paths (`ISO`, `DISK`) to your machine.

```bash
ISO=/home/x0z/Documents/repos/x-lnux/x/out/x-2026.09.06-x86_64.iso
DISK=/home/x0z/x-vm.qcow2
```

Adjust `ISO` to the artifact produced by `xbuild.sh` (see
[Building the ISO](building.md)); `out/` may contain more than one ISO.

## Launcher script (recommended)

`vm.sh` wraps the commands below from the terminal: it finds the newest ISO in
`out/`, creates the disk on first use, uses KVM when `/dev/kvm` is available and
handles BIOS/UEFI, the SSH forward and the `xauto` seed disk.

```bash
./vm.sh --deps                 # one-time: install archiso + qemu-desktop + OVMF
./vm.sh --build                # build the ISO (sudo ./xbuild.sh) and boot it
./vm.sh --uefi --boot disk     # boot an installed UEFI disk
./vm.sh --ssh-port 2222        # live ISO with ssh -p 2222 user@localhost
./vm.sh --print                # show the resolved QEMU command
```

`--help` lists every option (`--iso`, `--disk`, `--ram`, `--cpus`, `--no-kvm`,
`--display`, `--seed`, `--seed-json`). The manual commands below remain the
reference.

## Create a target disk (first time)

```bash
qemu-img create -f qcow2 "$DISK" 32G
```

## Boot the ISO (install / live, BIOS)

```bash
qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -cdrom "$ISO" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -boot d
```

The text installer runs automatically on the first TTY1 login (root autologin
via `/root/.zlogin`). If you are dropped to a shell instead, run the shortcut:

```bash
xinstall
```

`xinstall` (a live helper in `/usr/local/bin`) execs
`/root/x-installer/installer.sh`. You can also call it as
`bash /root/x-installer/installer.sh`. See [Text installer](installer.md).

## Boot the installed disk (BIOS boot: GRUB)

```bash
qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -boot c
```

## Boot the installed disk (UEFI: systemd-boot or GRUB EFI)

```bash
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/ovmf_vars.fd

qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -drive file=/usr/share/edk2/x64/OVMF_CODE.4m.fd,if=pflash,format=raw,readonly=on \
  -drive file=/tmp/ovmf_vars.fd,if=pflash,format=raw \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0
```

## Unattended install (optional)

To exercise the autoinstall path, provide a small seed disk labeled `cidata`
with an `x-install.json` and boot the ISO with `xauto=1` appended to the
kernel command line at the boot menu.

```bash
SEED=/tmp/cidata
rm -rf "$SEED" && mkdir -p "$SEED"
printf '{"disk":"/dev/vda","hostname":"x-vm","username":"x","password":"secret","profile":"core","bootloader":"grub","encryption":"no","hyprland":"no"}\n' \
  > "$SEED/x-install.json"

qemu-img create -f raw /home/x0z/cidata.img 64M
mkfs.vfat -n cidata /home/x0z/cidata.img
mcopy -i /home/x0z/cidata.img "$SEED/x-install.json" ::x-install.json
```

Then add the seed disk to the ISO boot command and pass `xauto=1` to the
kernel:

```bash
qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -cdrom "$ISO" \
  -drive file=/home/x0z/cidata.img,format=raw,if=virtio \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -boot d
```

`mkfs.vfat` needs `dosfstools` and `mcopy` needs `mtools` on the host. See
[Autoinstall](installer.md#autoinstall) for the exact trigger conditions.

Unattended-testing notes (learned in the 2026-10 P0 validation):

- `xauto=1` must be in the **kernel cmdline of the boot path you use**: for
  BIOS it is `syslinux/archiso_sys-linux.cfg`; for UEFI (bootmode
  `uefi.grub`) it is the `grub/` entries. A BIOS-only patch silently skips the
  autoinstall on UEFI (`autoinstall: no xauto=1; skipping` in the serial log).
- **Shut the guest down cleanly** (`poweroff`/`reboot` inside the guest, or the
  QEMU monitor `quit`) before killing QEMU. Killing the process can drop
  page-cache writes inside the guest and leave the installed system with
  zero-byte metadata.
- Capture the serial console (`-serial file:...`) and, if you run QEMU with
  `-display none`, add `-monitor unix:...,server=on,nowait` to take
  `screendump`s and drive the console with `sendkey`.

## Notes

- When **GRUB** is selected, the installer writes both a BIOS boot (GRUB +
  `bios_grub` partition) and a UEFI boot path, so either boot command works.
- **systemd-boot** is UEFI-only: boot the disk with the OVMF command above.
- `-netdev user` (slirp) provides NAT without libvirt/virtual networks.
- On hosts whose kernel lacks the `htb` qdisc (for example custom builds),
  libvirt's `default` network and VirtualBox host modules may fail; the direct
  QEMU commands above avoid both.

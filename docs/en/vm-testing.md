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

The ISO ships an **autoinstall** boot entry (hotkey `a`, `xauto=1` plus
`console=ttyS0`) in both paths: syslinux for BIOS and GRUB for UEFI. Boot that
entry with a seed disk labeled `cidata` containing `x-install.json`.

### Automated harness (recommended)

`tests/e2e-autoinstall.py` drives the whole flow locally (no CI, no root):
boots the ISO, presses the hotkey through the QEMU monitor, waits for the
installer on the serial console, powers off cleanly, boots the installed disk,
logs in over `ttyS0` and asserts `x gen status` (running/default `0001`) and
`x gen verify`.

```bash
python3 tests/e2e-autoinstall.py --mode uefi
python3 tests/e2e-autoinstall.py --mode bios
python3 tests/e2e-autoinstall.py --mode uefi --profile full --timeout 5400
```

Artifacts (disk, serial and QEMU logs) land in `../tmp/e2e/`. The seed JSON it
generates includes `"kernel_params":"console=ttyS0"` so the installed system
also exposes its console on the serial port.

### Manual seed disk

To exercise the path by hand, provide the seed disk and select the
**autoinstall** entry at the menu (or press `a`).

```bash
SEED=/tmp/cidata
rm -rf "$SEED" && mkdir -p "$SEED"
printf '{"disk":"/dev/vda","hostname":"x-vm","username":"x","password":"secret","profile":"core","bootloader":"grub","encryption":"no","hyprland":"no","kernel_params":"console=ttyS0"}\n' \
  > "$SEED/x-install.json"

qemu-img create -f raw /home/x0z/cidata.img 64M
mkfs.vfat -n cidata /home/x0z/cidata.img
mcopy -i /home/x0z/cidata.img "$SEED/x-install.json" ::x-install.json
```

Then add the seed disk to the ISO boot command and select the autoinstall
entry (`xauto=1` is already part of its kernel command line):

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

- `xauto=1` lives in the dedicated **autoinstall** entry of each bootloader:
  syslinux (BIOS) and `grub/` (UEFI). Selecting the default entry silently
  skips the autoinstall (`autoinstall: no xauto=1; skipping` in the serial
  log).
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

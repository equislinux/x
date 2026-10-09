# Pruebas de X en una máquina virtual

> Otros idiomas: [English](../en/vm-testing.md)

Comandos auxiliares para ejecutar el ISO en vivo de X y arrancar un disco ya
instalado con QEMU. Ajusta las rutas (`ISO`, `DISK`) a tu máquina.

```bash
ISO=/home/x0z/Documents/repos/x-lnux/x/out/x-2026.09.06-x86_64.iso
DISK=/home/x0z/x-vm.qcow2
```

Ajusta `ISO` al artefacto producido por `xbuild.sh` (consulta
[Construir el ISO](building.md)); `out/` puede contener más de un ISO.

## Script launcher (recomendado)

`vm.sh` envuelve los comandos de abajo desde la terminal: busca el ISO más
reciente en `out/`, crea el disco en el primer uso, usa KVM cuando `/dev/kvm`
está disponible y gestiona BIOS/UEFI, el reenvío SSH y el disco seed de
`xauto`.

```bash
./vm.sh --deps                 # una vez: instala archiso + qemu-desktop + OVMF
./vm.sh --build                # construye el ISO (sudo ./xbuild.sh) y lo arranca
./vm.sh --uefi --boot disk     # arranca un disco UEFI ya instalado
./vm.sh --ssh-port 2222        # ISO en vivo con ssh -p 2222 user@localhost
./vm.sh --print                # muestra el comando QEMU resultante
```

`--help` lista todas las opciones (`--iso`, `--disk`, `--ram`, `--cpus`,
`--no-kvm`, `--display`, `--seed`, `--seed-json`). Los comandos manuales de
abajo siguen siendo la referencia.

## Crear un disco de destino (primera vez)

```bash
qemu-img create -f qcow2 "$DISK" 32G
```

## Arrancar el ISO (instalar / en vivo, BIOS)

```bash
qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -cdrom "$ISO" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -boot d
```

El instalador de texto se ejecuta automáticamente en el primer login de TTY1
(autologin de root vía `/root/.zlogin`). Si caes a un shell en su lugar,
ejecuta el atajo:

```bash
xinstall
```

`xinstall` (una utilidad en vivo en `/usr/local/bin`) ejecuta
`/root/x-installer/installer.sh`. También puedes llamarlo como
`bash /root/x-installer/installer.sh`. Consulta
[Instalador de texto](installer.md).

## Arrancar el disco instalado (arranque BIOS: GRUB)

```bash
qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -boot c
```

## Arrancar el disco instalado (UEFI: systemd-boot o GRUB EFI)

```bash
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/ovmf_vars.fd

qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -drive file=/usr/share/edk2/x64/OVMF_CODE.4m.fd,if=pflash,format=raw,readonly=on \
  -drive file=/tmp/ovmf_vars.fd,if=pflash,format=raw \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0
```

## Instalación desatendida (opcional)

El ISO trae una entrada de arranque **autoinstall** (hotkey `a`, con
`xauto=1` y `console=ttyS0`) en ambas rutas: syslinux para BIOS y GRUB para
UEFI. Arrancá esa entrada con un disco semilla etiquetado `cidata` que
contenga `x-install.json`.

### Harness automatizado (recomendado)

`tests/e2e-autoinstall.py` maneja todo el flujo en local (sin CI ni root):
arranca el ISO, pulsa la hotkey por el monitor de QEMU, espera al instalador
en la consola serie, apaga limpiamente, arranca el disco instalado, entra por
`ttyS0` y verifica `x gen status` (running/default `0001`) y `x gen verify`.

```bash
python3 tests/e2e-autoinstall.py --mode uefi
python3 tests/e2e-autoinstall.py --mode bios
python3 tests/e2e-autoinstall.py --mode uefi --profile full --timeout 5400
python3 tests/e2e-autoinstall.py --mode uefi --kernel linux-lts
python3 tests/e2e-autoinstall.py --mode uefi --multikernel
```

Los artefactos (disco, logs serie y de QEMU) quedan en `../tmp/e2e/`. El JSON
semilla que genera incluye `"kernel_params":"console=ttyS0"` para que el
sistema instalado también exponga la consola en el puerto serie.

### Disco semilla manual

Para ejercitar la ruta a mano, prepará el disco semilla y seleccioná la
entrada **autoinstall** en el menú (o pulsá `a`).

```bash
SEED=/tmp/cidata
rm -rf "$SEED" && mkdir -p "$SEED"
printf '{"disk":"/dev/vda","hostname":"x-vm","username":"x","password":"secret","profile":"core","bootloader":"grub","kernel":"linux","encryption":"no","hyprland":"no","kernel_params":"console=ttyS0"}\n' \
  > "$SEED/x-install.json"

qemu-img create -f raw /home/x0z/cidata.img 64M
mkfs.vfat -n cidata /home/x0z/cidata.img
mcopy -i /home/x0z/cidata.img "$SEED/x-install.json" ::x-install.json
```

Después, añadí el disco semilla al comando de arranque del ISO y seleccioná
la entrada autoinstall (`xauto=1` ya es parte de su cmdline):

```bash
qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 -cpu host \
  -cdrom "$ISO" \
  -drive file=/home/x0z/cidata.img,format=raw,if=virtio \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -boot d
```

`mkfs.vfat` necesita `dosfstools` y `mcopy` necesita `mtools` en el host.
Consulta [Autoinstalación](installer.md#autoinstalación) para las condiciones
exactas de activación.

Notas de testing desatendido (aprendidas en la validación P0 de 2026-10):

- `xauto=1` vive en la entrada dedicada **autoinstall** de cada gestor:
  syslinux (BIOS) y `grub/` (UEFI). Arrancar la entrada por defecto saltea la
  autoinstalación (`autoinstall: no xauto=1; skipping` en el serial).
- **Apagá el guest limpiamente** (`poweroff`/`reboot` dentro del guest o
  `quit` del monitor QEMU) antes de matar QEMU. Matarlo puede perder escrituras
  en page cache del guest y dejar el sistema instalado con metadata en 0 bytes.
- Capturá el serial (`-serial file:...`) y, si usás `-display none`, agregá
  `-monitor unix:...,server=on,nowait` para tomar `screendump`s y manejar la
  consola con `sendkey`.

## Notas

- Cuando se selecciona **GRUB**, el instalador escribe tanto la ruta de
  arranque BIOS (GRUB + partición `bios_grub`) como la UEFI, de modo que
  cualquiera de los dos comandos de arranque funciona.
- **systemd-boot** es solo UEFI: arranca el disco con el comando OVMF de
  arriba.
- `-netdev user` (slirp) proporciona NAT sin libvirt/redes virtuales.
- En hosts cuyo kernel carece del qdisc `htb` (por ejemplo, builds
  personalizados), la red `default` de libvirt y los módulos de host de
  VirtualBox pueden fallar; los comandos QEMU directos de arriba evitan ambos.

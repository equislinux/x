# Generaciones (lado del instalador)

X Linux usa **subvolúmenes btrfs** para que el payload de aprovisionamiento
pueda versionar el sistema: cada cambio relevante registra un snapshot
booteable más un manifiesto (`x gen new`), `x gen rollback` cambia el arranque
por defecto y `x gen restore` recupera rutas individuales. Este documento cubre
solo el lado del instalador; el motor, la CLI y la semántica viven en
`equislinux/scripts` (`docs/es/generations.md`).

## Layout de disco

GPT con una partición EFI de 1G (lugar para varias generaciones de entries) y
una partición raíz btrfs (dentro de LUKS2 si el cifrado está habilitado):

| Subvolumen | Montaje | Contenido |
|------------|---------|-----------|
| `@` | `/` | Árbol raíz (escribible; la primera generación, subvol vivo `/@`) |
| `@home` | `/home` | Datos de usuario (el rollback no los toca) |
| `@snapshots` | `/.snapshots` | Snapshots de generación, modo 0700 |
| `@xstate` | `/var/lib/x` | Metadatos compartidos de generaciones, modo 0700 |

`/etc/fstab` se genera con `genfstab` con todos los subvolúmenes montados;
`/tmp` se agrega como tmpfs para que los snapshots no capturen archivos
transitorios.

## Arranque

El cmdline del kernel (GRUB `GRUB_CMDLINE_LINUX` y el
`loader/entries/x.conf` de systemd-boot) lleva `rootflags=subvol=@` para la
primera generación; el UUID raíz se agrega como siempre (`root=UUID=...`, o
`cryptdevice=...` + `/dev/mapper/xroot` con LUKS). Las generaciones posteriores
se bifurcan de la raíz viva en `/.snapshots/<id>` y el motor autoparchea su
fstab, así cada una arranca con `rootflags=subvol=/@snapshots/<id>`.

## Primera generación

Después del paso de gestor de arranque el instalador ejecuta, dentro del
chroot del destino:

```bash
X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ x gen new --reason install --label first
```

Esto registra `/var/lib/x/generations/0001/` (manifiesto, lista de paquetes,
servicios habilitados, kernel/initramfs archivados en el subvolumen compartido
`@xstate`), crea el snapshot `/.snapshots/0001` y escribe las entries de
arranque:

- systemd-boot: `/boot/loader/entries/x-gen-0001.conf` (+ espejo `x.conf`) y el
  default del loader.
- GRUB: `/boot/grub/custom.cfg` con `set default=x-gen-0001` y un `menuentry`
  por generación retenida.

Con varios kernels instalados, cada generación tiene una entry por pkgbase
(`x-gen-0001-linux-lts.conf`, `...-linux-zen.conf`); `x kernel list|install|remove`
los gestiona (el borrado mantiene los kernels archivados arrancables vía rollback).

`X_GEN_CMDLINE` registra el cmdline real del destino porque `/proc/cmdline`
dentro del chroot pertenece al ISO en vivo; `X_GEN_LIVE_SUBVOL` le dice al
motor que la generación 0001 es el subvolumen vivo `/@` (no una bifurcación en
`/.snapshots`).

Durante la instalación `x setup` corre con `X_GEN_SKIP=1`: la primera
generación la crea una sola vez el instalador, después del branding y el
gestor de arranque.

## Requisitos

- `btrfs-progs` en el destino (ya está en `packages.x86_64` y en la lista de
  paquetes del live).
- Tamaño del ESP: 1G es el default en instalaciones nuevas (las instalaciones
  viejas de 512M siguen funcionando; el motor poda las copias del ESP más allá
  de `X_GEN_BOOT_KEEP`, default 3).
- El payload registra generaciones solo si la raíz es btrfs; en otros setups
  cada hook es no-op y `x gen` reporta que no están disponibles.

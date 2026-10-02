# Instalador de texto

> Otros idiomas: [English](../en/installer.md)

X se instala desde el **ISO en vivo** con un **instalador de texto**. No hay
instalador gráfico (Calamares fue eliminado). Todo lo que se describe vive bajo
`airootfs/root/x-installer/` en este repositorio y viaja en el entorno en vivo
hasta `/root/x-installer/`.

## Puntos de entrada y cuándo se ejecuta el instalador

- El entorno en vivo hace *autologin* como `root` en TTY1 (autologin de
  agetty) con zsh.
- `/root/.zlogin` ejecuta primero `/root/.automated_script.sh` (el mecanismo
  oficial `script=` de archiso) si existe, y después lanza el instalador en
  TTY1, **salvo** que la línea de comandos del kernel contenga `script=` o
  `xauto=1`.
- El punto de entrada es `installer.sh` (`/root/x-installer/installer.sh`).
- Hay un atajo disponible en el shell en vivo:

  ```bash
  xinstall
  ```

  `xinstall` (`/usr/local/bin/xinstall`) simplemente ejecuta `installer.sh`.
  Si caes a un shell normal en lugar del instalador, ejecuta `xinstall` o
  `bash /root/x-installer/installer.sh`.

## Estructura del instalador

```text
/root/x-installer/
|-- installer.sh        # punto de entrada (configurador + instalador)
|-- configurator.sh     # configuración interactiva, escribe un plan JSON
|-- install.sh          # realiza la instalación real
|-- autoinstall.sh      # entrada desatendida (xauto=1 + disco cidata)
|-- ui.sh               # ayudas de interfaz: gum con fallback a prompts
|-- packages.x86_64     # manifiesto por defecto del perfil "full"
`-- packages/           # payload offline de x-scripts (*.pkg.tar.zst)
```

Una unidad de systemd, `x-autoinstall.service`, está habilitada en la imagen
en vivo (`airootfs/etc/systemd/system/`) y gestiona la ruta desatendida.
Consulta [Autoinstalación](#autoinstalación) más abajo.

## Flujo interactivo

`installer.sh` ejecuta el configurador y, si tiene éxito, el instalador.

1. `configurator.sh` recoge las opciones siguientes y escribe
   `/tmp/x-install.json` (permisos 600).
2. `install.sh` lee ese JSON, lo valida y realiza la instalación.

Con `X_DRY=1` solo se muestra el plan, sin tocar el disco (consulta
[Variables de entorno](#variables-de-entorno)).

### Opciones del configurador (`configurator.sh`)

La interfaz usa `gum` (`choose`, `input`, `confirm`) cuando está disponible y
cae a prompts de texto plano en caso contrario (`ui.sh`).

| Paso | Opciones | Valor almacenado |
|------|----------|------------------|
| Disco | cualquier dispositivo de bloque de tipo `disk` (de `lsblk`) | `disk` (p. ej. `/dev/sda`) |
| Idioma del sistema | English, Español, Deutsch, Français | `language` + `locale` |
| Distribución de teclado | `us`, `es`, `de`, `fr`, `uk`, `latam`, `br-abnt2` | `keyboard` |
| Zona horaria | `UTC`, `Europe/Madrid`, `Europe/London`, `Europe/Berlin`, `America/Mexico_City`, `America/Argentina/Buenos_Aires`, `America/Los_Angeles`, `Asia/Tokyo` | `timezone` |
| Hostname | texto libre (por defecto `x`) | `hostname` |
| Nombre de usuario | texto libre | `username` |
| Password del usuario | texto libre (repetido) | `password` |
| Perfil de paquetes | `Full (all packages)` / `Core (minimal system)` | `profile` (`full`/`core`) |
| Gestor de arranque | `GRUB (BIOS + UEFI)` / `systemd-boot (UEFI only)` | `bootloader` (`grub`/`systemd-boot`) |
| Cifrado de raíz (LUKS) | sí/no | `encryption` (`yes`/`no`) |
| Passphrase LUKS | reutilizar la del usuario o una dedicada | `luks_password` |
| Instalar el setup de Hyprland | sí/no (requiere red) | `hyprland` (`yes`/`no`) |

Mapeo idioma a locale que usa el configurador:

| Idioma | `language` | `locale` |
|--------|------------|----------|
| English | `en` | `en_US.UTF-8` |
| Español | `es` | `es_ES.UTF-8` |
| Deutsch | `de` | `de_DE.UTF-8` |
| Français | `fr` | `fr_FR.UTF-8` |

Reglas de validación: el hostname debe cumplir
`^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$`; el nombre de usuario
`^[a-z_][a-z0-9_-]{0,31}$`; las passwords/passphrases no pueden contener `"`
ni `\`.

Antes de escribir la configuración, el configurador pide una confirmación
final de que todo lo que haya en el disco seleccionado será borrado. El JSON
resultante tiene este aspecto:

```json
{"disk":"/dev/sda","hostname":"x","username":"x","password":"secret","language":"en","locale":"en_US.UTF-8","keyboard":"us","timezone":"UTC","profile":"full","bootloader":"grub","encryption":"no","luks_password":"","hyprland":"no"}
```

El JSON se escribe en la ruta de `X_CONFIG_OUT` (por defecto
`/tmp/x-install.json`). Solo se requieren `disk`, `hostname`, `username` y
`password`; el resto de claves tienen valores por defecto sensatos si no
están.

## Pasos de la instalación (`install.sh`)

1. **Analizar y validar** el JSON (`disk`, `hostname`, `username`); requiere
   root y un dispositivo de bloque real.
2. **Particionar** con GPT (`sgdisk --zap-all` primero):
   - `grub`: partición `bios_grub` de 1 MiB, partición EFI de 1 GiB, resto =
     raíz.
   - `systemd-boot`: partición EFI de 1 GiB, resto = raíz.
   (1 GiB deja lugar para varias generaciones de entries de arranque.)
3. **LUKS** (si `encryption=yes`): `cryptsetup luksFormat --type luks2` sobre
   la partición raíz (passphrase de `luks_password`, con fallback a la
   password del usuario) y apertura como `/dev/mapper/xroot`.
4. **Formatear y montar**: la partición EFI como FAT32 (`mkfs.vfat -F32`)
   montada en `/mnt/boot`; la raíz (o el mapeo LUKS) como btrfs con los
   subvolúmenes `@`, `@home`, `@snapshots` y `@xstate` montados en `/`,
   `/home`, `/.snapshots` y `/var/lib/x`. `/tmp` se agrega al fstab como
   tmpfs.
5. **Conjunto de paquetes**:
   - Conjunto base: `base base-devel linux linux-firmware sudo networkmanager
     openssh git jq x-release btrfs-progs kitty pipewire pipewire-pulse
     pipewire-alsa wireplumber alsa-utils sddm`, más `grub efibootmgr` para
     GRUB y `cryptsetup` para LUKS. `btrfs-progs` lo requiere el motor de
     generaciones y se instala en todos los perfiles.
   - Perfil `full`: añade todos los paquetes del manifiesto apuntado por
     `X_PKGLIST` (por defecto `/root/x-installer/packages.x86_64`).
   - Perfil `core`: añade solo `vim zsh`.
6. **Esperar a la red** (comprobación de DNS contra
   `geo.mirror.pkgbuild.com`, hasta ~120 s) y ejecutar
   `pacstrap -K /mnt <pkgs>` desde los mirrors oficiales más el repositorio
   `[x]`.
7. **Instalar `x-scripts` offline**: el payload
   `packages/x-scripts-*.pkg.tar.zst` presente en el entorno en vivo se copia
   al destino y se instala con `pacman -U` dentro del chroot.
8. **Configuración base**: `genfstab`, enlace simbólico de la zona horaria,
   `locale.gen` + `/etc/locale.conf`, `KEYMAP` en `/etc/vconsole.conf`,
   hostname, copia del mirrorlist funcional y anexado del repositorio `[x]` al
   `pacman.conf` del destino si no existe.
9. **Usuario**: crear el usuario (miembro de `wheel`, shell de login `bash`),
   fijar la password con `chpasswd` y habilitar `%wheel` en `sudoers`.
10. **Aprovisionamiento** con la CLI `x` del paquete `x-scripts`:
    - fases de sistema como root: `X_HW_AUTO=0 x setup`;
    - fases de usuario como el usuario nuevo:
      `X_HYPRLAND=0 X_HW_AUTO=0 x setup --user`.
    - PipeWire/Pulse/WirePlumber se habilitan para todos los usuarios; el
      setup de Hyprland queda **diferido** a un paso/punto posterior (no se
      ejecuta aquí cuando `hyprland=no`).
11. **Setup de Hyprland** (solo si `hyprland=yes`): se crea un drop-in
    temporal de sudo sin password y se ejecuta
    `/usr/share/x/tools/hyprland-install.sh` como el usuario destino. El
    drop-in se elimina después. La herramienta prefiere la instantánea offline
    del stack equisdots incluida en el paquete
    (`/usr/share/x/config/equisdots`); solo clona el instalador oficial
    `equisdots/dots` como fallback online. NVIDIA lo gestiona la fase de
    hardware del sistema; la herramienta recurre al setup NVIDIA de equisdots
    únicamente si hay GPU y ningún driver instalado.
12. **Initramfs (solo LUKS)**: sustituir `HOOKS` en `mkinitcpio.conf` para
    incluir el hook `encrypt` y reconstruir con `mkinitcpio -P`.
13. **Branding**: `x-release-apply` (del paquete `x-release`) se ejecuta
    *antes* del paso del gestor de arranque para que la línea de comandos del
    kernel de LUKS escrita después no se sobrescriba.
14. **Gestor de arranque**:
    - `grub`: `grub-install` para `x86_64-efi` (removable) y `i386-pc`
      (arranque desde el disco completo) y después `grub-mkconfig`.
      `GRUB_CMDLINE_LINUX` siempre lleva el cmdline de la raíz con
      `rootflags=subvol=@` (más `cryptdevice=UUID=<luks-uuid>:xroot
      root=/dev/mapper/xroot` con LUKS).
    - `systemd-boot`: `bootctl --esp-path=/boot install`, un fallback
      removable `BOOTX64.EFI` si hiciera falta y una entrada de arranque
      `X Linux` (solo UEFI) con la línea `root=` o `cryptdevice=` adecuada.
15. **Primera generación**: dentro del chroot,
    `X_GEN_CMDLINE="$CMDROOT" X_GEN_LIVE_SUBVOL=/@ x gen new --reason install
    --label first` crea `/.snapshots/0001`, el manifiesto en
    `/var/lib/x/generations/0001` y las entries de arranque (systemd-boot
    `loader/entries/x-gen-0001.conf`, GRUB `custom.cfg`). Es la base para
    rollbacks y restores granulares; ver `generations.md`.
16. **Limpieza**: al salir se desmontan los sistemas de archivos, se cierra el
    mapeo LUKS si está abierto y se elimina el JSON de instalación.

Un mensaje indica que la instalación ha terminado; reinicia y retira el medio
de instalación.

## Autoinstalación

El instalador soporta la instalación desatendida desde el ISO en vivo:

- La línea de comandos del kernel debe contener **`xauto=1`**.
- Debe existir un dispositivo de almacenamiento etiquetado como **`cidata`**
  con un archivo **`x-install.json`** (por ejemplo, un disco virtual extra en
  QEMU).

`x-autoinstall.service` (habilitada en la imagen en vivo) ejecuta
`autoinstall.sh`, que:

1. Se omite inmediatamente si `xauto=1` no está en la línea de comandos.
2. Busca el dispositivo por etiqueta (`blkid -L cidata`); se omite si no
   existe.
3. Lo monta en solo lectura en `/run/cidata`.
4. Ejecuta `install.sh` con `X_INSTALL_JSON` apuntando a
   `/run/cidata/x-install.json`.
5. Escribe el log en `/tmp/x-install.log` y lo reenvía a la consola serie /
   consola, y después desmonta.

El JSON de una ejecución desatendida solo requiere las claves base, por
ejemplo:

```json
{"disk":"/dev/vda","hostname":"x-vm","username":"x","password":"secret","profile":"core","bootloader":"grub","encryption":"no","hyprland":"no"}
```

Consulta [Pruebas en una máquina virtual](vm-testing.md) para un ejemplo de
disco cidata.

El otro mecanismo de automatización es el parámetro oficial **`script=`** de
archiso (`/root/.automated_script.sh` descarga o copia un script y lo
ejecuta). Cuando hay `script=` o `xauto=1`, el instalador interactivo no se
lanza.

## Referencia de la línea de comandos del kernel

| Parámetro | Efecto |
|-----------|--------|
| `script=<url or path>` | Ejecuta el script de automatización oficial de archiso; el instalador interactivo se omite. |
| `xauto=1` | Activa la autoinstalación desatendida (necesita un disco `cidata` con `x-install.json`). |
| `accessibility=` | Activa zle de una línea (TTY amigable con lectores de pantalla). |

## Variables de entorno

| Variable | Valor por defecto | Ámbito | Efecto |
|----------|-------------------|--------|--------|
| `X_SKIP_INSTALLER` | sin definir | en vivo | `1` hace que `installer.sh` imprima "skipped" y salga. |
| `X_DRY` | `0` | en vivo | `1` muestra solo el plan; no escribe ni borra nada. |
| `X_CONFIG_OUT` | `/tmp/x-install.json` | configurador | Dónde se escribe el JSON de configuración. |
| `X_INSTALL_JSON` | `/tmp/x-install.json` | instalador | JSON que consume `install.sh`. |
| `X_PKGLIST` | `/root/x-installer/packages.x86_64` | instalador | Manifiesto del perfil `full`. |
| `X_HYPRLAND` | payload por defecto `1` | payload (`x setup`) | El instalador lo fija a `0` para diferir el setup de Hyprland. |
| `X_HW_AUTO` | payload por defecto `1` | payload (`x setup`) | Se fija a `0` durante la instalación para desactivar la autodetección de hardware. |

Notas:

- Con `X_DRY=1`, `installer.sh` se asegura de que exista un JSON (con un valor
  provisional si hace falta) y ejecuta `install.sh`, que imprime el plan de
  instalación y sale sin tocar el disco. El configurador, ejecutado con
  `X_DRY=1`, escribe el JSON sin la password y se detiene antes de la
  confirmación de borrado.
- `X_HYPRLAND`/`X_HW_AUTO` pertenecen al payload `x-scripts`; el instalador
  las fija al llamar a `x setup`.

## Live vs sistema instalado (credenciales)

El medio live es deliberadamente permisivo para poder usarse sin contraseña:
autologin de root en tty1, password de root vacío y sshd con
`PermitRootLogin yes` + autenticación por password. **Todo eso vive solo en
`airootfs`** (el squashfs del live).

El instalador nunca copia esos archivos al destino: el sistema instalado toma
`/etc/shadow` del paquete `shadow` (root bloqueado), crea el usuario wheel
desde el seed y **no** habilita sshd. Mantené esa regla al agregar
automatización post-install: nunca copies `/etc` del live al destino.

## Dualboot (planificado)

Hoy `install.sh` borra el disco destino (`sgdisk --zap-all`) y crea un GPT
nuevo. El modo dualboot instalará X en el **espacio libre sin asignar**,
preservando las particiones existentes y el bootloader de Windows. Solo UEFI
en la primera iteración (BIOS/MBR queda fuera de alcance).

Campos de config propuestos:

| Campo | Valores | Significado |
|-------|---------|-------------|
| `mode` | `wipe` (default) / `dualboot` | estrategia de instalación |
| `esp` | partición (opcional) | reusar esta ESP en vez de crear una |
| `min_size` | GiB (default 20) | región libre mínima aceptada |

Flujo en modo `dualboot`:

1. Validar GPT + UEFI y una ESP existente (`ef00`); nunca correr
   `sgdisk --zap-all`.
2. Elegir la región libre más grande (`sgdisk -F`/`-E`), exigir `min_size` y
   crear **solo** la partición raíz ahí (`sgdisk -n N:start:end -t N:8300`).
   Las entradas existentes no se tocan.
3. Montar la ESP existente en `/mnt/boot`; nunca formatearla.
4. btrfs + `@`/`@home`/`@snapshots`/`@xstate` igual que en modo wipe.
5. Bootloader con ID único, sin reemplazar archivos de Microsoft:
   - GRUB: `grub-install --efi-directory=/boot --bootloader-id=x` +
     `os-prober` para agregar la entrada de Windows.
   - systemd-boot: `bootctl install` (auto-detecta Windows Boot Manager).
6. Las generaciones siguen funcionando: las entries de X viven en
   `x-gen-<id>`/`custom.cfg` y nunca pisan `EFI/Microsoft/**`; el Windows Boot
   Manager sigue siendo el default del firmware hasta que el usuario elija.

Plan de test VM: imagen de disco con GPT + ESP falsa (archivos Microsoft) +
partición de datos + espacio libre; instalar en modo dualboot; asertar GUIDs y
offsets originales, contenido de la ESP, ambas entradas de menú y boot de X.

## Requisitos y advertencias

- La instalación requiere **acceso a red**: `pacstrap` descarga desde los
  mirrors oficiales de Arch y el repositorio `[x]`. Un mirror offline incluido
  en el ISO está pendiente (consulta la ROADMAP del workspace).
- El disco de destino se borra por completo.
- `systemd-boot` es **solo UEFI**; GRUB escribe tanto la ruta BIOS (con la
  partición `bios_grub`) como la UEFI (removable), de modo que cualquiera de
  los dos modos de arranque funciona.
- LUKS usa LUKS2 con el hook `encrypt` clásico del initramfs.

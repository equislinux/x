# Referencia de la estructura del proyecto

> Otros idiomas: [English](../en/project-layout.md)

Referencia de la composición del repositorio y del rol de sus archivos y
directorios clave. Consulta también el `README.md` de la raíz y las guías
monolingües bajo `docs/`.

## Estructura de nivel superior

```text
x/  (xlnux/x)
|-- airootfs/                  # overlay del sistema de archivos raíz para el ISO/rootfs
|-- grub/                      # config de GRUB usada en el ISO (grub.cfg, loopback.cfg)
|-- syslinux/                  # config y assets de Syslinux
|-- .github/                   # workflows y scripts (sync hoja de ruta-issues)
|-- profiledef.sh              # metadatos del perfil ArchISO, modos de arranque, permisos
|-- pacman.conf                # config de pacman, incluye el repositorio [x]
|-- packages.x86_64            # manifiesto completo de paquetes del entorno en vivo
|-- bootstrap_packages.x86_64  # conjunto de arranque mínimo para archiso
|-- xbuild.sh                  # script de build del ISO (recomendado)
|-- x.sh                       # build mkarchiso minimalista en una línea
|-- xbuildwsl.sh               # build de rootfs WSL (tarball gzip)
|-- xbuildwslc.sh              # build de rootfs WSL (tarball zstd)
|-- ROADMAP.md                 # hoja de ruta del proyecto
|-- README.md                  # punto de entrada del repositorio
|-- WSL_GUIDE.md               # recorrido WSL antiguo
|-- CODE_OF_CONDUCT.md         # normas de la comunidad
|-- CONTRIBUTING.md            # guía de contribución
|-- LICENSE                    # GPL-3.0
|-- SECURITY.md                # política de seguridad
|-- SUPPORT.md                 # canales de soporte
|-- out/                       # salida del build del ISO (gitignored)
|-- work/                      # directorio de trabajo de archiso (gitignored)
|-- build-*.log                # logs de build con marca de tiempo (gitignored)
`-- docs/
    |-- build-iso.md           # guía ISO monolingüe
    |-- build-wsl.md           # guía WSL canónica
    |-- installation.md        # resumen monolingüe del instalador
    |-- project-state.md       # instantánea del estado
    |-- project-structure.md   # referencia de estructura monolingüe
    |-- vm-testing.md          # comandos de prueba en VM
    |-- x-repository.md        # el repositorio de paquetes [x]
    |-- en/                    # documentación en inglés (este conjunto)
    `-- es/                    # documentación en español
```

## Composición de `airootfs/`

`airootfs/` se superpone al sistema durante las builds de imagen/rootfs. Sus
partes más relevantes:

| Ruta | Rol |
|------|-----|
| `airootfs/etc/` | Configuración de sistema y branding de la imagen en vivo. |
| `airootfs/etc/hostname` | Hostname en vivo (`x`). |
| `airootfs/etc/default/grub` | Config de GRUB (`GRUB_DISTRIBUTOR="X"`). |
| `airootfs/etc/motd` | Mensaje del día mostrado en el TTY en vivo. |
| `airootfs/etc/pacman.conf` | Config de pacman de la imagen en vivo. |
| `airootfs/etc/pacman.d/mirrorlist` | Mirrors usados por la imagen en vivo. |
| `airootfs/etc/locale.conf` | Locale por defecto de la imagen en vivo. |
| `airootfs/etc/mkinitcpio.conf.d/` | Overrides de mkinitcpio (archiso). |
| `airootfs/etc/systemd/network/` | Configs de red DHCP (ethernet/wlan/wwan). |
| `airootfs/etc/systemd/system/` | Unidades de systemd del entorno en vivo, incluidas `x-autoinstall.service` y los servicios auxiliares. |
| `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf` | Autologin de root en TTY1. |
| `airootfs/etc/systemd/system/etc-pacman.d-gnupg.mount` | Gestión del keyring de archiso. |
| `airootfs/root/.automated_script.sh` | Ejecutor de la automatización oficial `script=` de archiso. |
| `airootfs/root/.zlogin` | Hook de login de zsh que inicia el instalador en TTY1. |
| `airootfs/root/customize_airootfs.sh` | Personalización ejecutada dentro del chroot durante la build. |
| `airootfs/root/x-installer/` | El instalador de texto (consulta [Instalador de texto](installer.md)). |
| `airootfs/root/x-postinstall.sh` | Script de branding de primer arranque antiguo; el instalador actual no lo invoca (el aprovisionamiento va por el payload `x-scripts`). |
| `airootfs/usr/local/bin/` | Utilidades en vivo: `choose-mirror`, `livecd-sound`, `Installation_guide`, `xinstall`. |
| `airootfs/usr/local/share/livecd-sound/` | Plantilla de sonido para `livecd-sound`. |

## `airootfs/root/x-installer/`

El instalador de texto incluido en la imagen en vivo:

| Archivo | Propósito |
|---------|-----------|
| `installer.sh` | Punto de entrada; ejecuta el configurador y después el instalador. |
| `configurator.sh` | Configuración interactiva (gum/prompts); escribe el plan JSON. |
| `install.sh` | Realiza el particionado, `pacstrap`, config base, usuario, aprovisionamiento y gestor de arranque. |
| `autoinstall.sh` | Instalador desatendido (activado por `xauto=1` + disco `cidata`). |
| `ui.sh` | Utilidades de interfaz compartidas por los demás scripts. |
| `packages.x86_64` | Manifiesto por defecto del perfil `full`. |
| `packages/` | Payload offline `x-scripts-*.pkg.tar.zst` incluido en la imagen en vivo. |

## Archivos críticos de la build

- `profiledef.sh`: metadatos del perfil ArchISO, modos de arranque
  (`bios.syslinux`, `uefi.grub`), formato de imagen (squashfs/xz) y permisos
  de archivo.
- `packages.x86_64`: manifiesto de paquetes del entorno en vivo, incluidos los
  paquetes de X `x-release` y `x-dev` del repositorio `[x]`.
- `bootstrap_packages.x86_64`: conjunto mínimo de paquetes que archiso usa
  para el root de arranque.
- `pacman.conf`: configuración de repositorios usada por los flujos de build
  del ISO y WSL; añade el repositorio `[x]`.
- `xbuild.sh` / `x.sh`: puntos de entrada del build del ISO.
- `xbuildwsl.sh` / `xbuildwslc.sh`: puntos de entrada del tarball de rootfs
  WSL.

## Assets de los gestores de arranque

| Directorio | Contenido |
|------------|-----------|
| `grub/` | `grub.cfg`, `loopback.cfg` usados en el ISO (arranque GRUB UEFI). |
| `syslinux/` | Configuración de Syslinux y splash para el arranque BIOS del ISO. |

Los modos de arranque del ISO son `bios.syslinux` + `uefi.grub`
(`profiledef.sh`): un solo gestor por firmware. La entrada `autoinstall`
(hotkey `a`) existe en ambas rutas con `xauto=1 console=ttyS0`.

El gestor de arranque instalado *en el sistema de destino* por `install.sh` es
independiente de estos assets del ISO: GRUB (BIOS + UEFI) o systemd-boot
(solo UEFI).

## Documentación

El repositorio conserva las guías monolingües existentes en `docs/`
(`build-iso.md`, `build-wsl.md`, `installation.md`, `project-state.md`,
`project-structure.md`, `vm-testing.md`, `x-repository.md`). El conjunto de
documentación estructurada y bilingüe vive en `docs/en/` y `docs/es/`.

## Salidas de build

- Flujo ISO (`xbuild.sh`): artefactos en `out/`; trabajo temporal en `work/`.
- Flujo WSL (`xbuildwsl*.sh`): artefactos en `out-wsl/`; rootfs en
  `work-wsl/rootfs`.
- Todas las salidas de build y los archivos `build-*.log` están en
  `.gitignore`.

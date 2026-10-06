# Construir el ISO

> Otros idiomas: [English](../en/building.md)

Esta guía explica cómo construir el ISO en vivo de X desde este repositorio
con `xbuild.sh`. El rootfs de WSL se construye desde el repositorio dedicado
`equislinux/wsl`.

## Prerrequisitos

- Un entorno Linux con las herramientas de ArchISO disponibles (Arch Linux o
  una distribución compatible).
- Acceso `sudo`.
- El paquete `archiso`.
- Suficiente espacio en disco (varios GB) y acceso a red para descargar
  paquetes.

Instala la dependencia:

```bash
sudo pacman -S archiso
```

## Comando de construcción

Ejecuta desde la raíz del repositorio:

```bash
./xbuild.sh
```

## Qué hace `xbuild.sh`

1. Comprueba que `pacman.conf` y `profiledef.sh` existen en el directorio
   actual.
2. Intenta un desmontaje *lazy* de los puntos de montaje obsoletos bajo
   `work/x86_64/airootfs` (evita errores de *"target is busy"* de ejecuciones
   anteriores).
3. Elimina los directorios previos `work/` y `out/`.
4. Ejecuta `sudo mkarchiso -C pacman.conf -v -w ./work -o ./out .`, volcando
   toda la salida a un archivo de log con marca de tiempo.
5. Verifica que se haya producido al menos un ISO e imprime la ruta y el
   tamaño del artefacto; si no, imprime un mensaje y sale con estado distinto
   de cero.

Existe un equivalente minimalista en una línea, `x.sh`, que ejecuta el mismo
`mkarchiso` pero sin los pasos de limpieza ni verificación. `xbuild.sh` es el
punto de entrada recomendado.

## Salidas

- Artefacto ISO: `out/x-YYYY.MM.DD-x86_64.iso` (la fecha de versión viene de
  `profiledef.sh`).
- Log de construcción: `build-YYYYMMDD-HHMM.log` en la raíz del repositorio.

Tanto `work/` como `out/` se recrean en cada construcción y están en
`.gitignore`, al igual que los archivos `build-*.log`.

## Datos del perfil

`profiledef.sh` define los metadatos del ISO que usa `mkarchiso`:

- `iso_name`: `x`
- `iso_version`: `YYYY.MM.DD` (basado en la fecha)
- `iso_label`: `x_YYYYMM`
- `iso_publisher`: `Xscriptor <https://xscriptor.io/x>`
- `iso_application`: `X Live/Rescue DVD`
- Modos de arranque: `bios.syslinux` y `uefi.grub`
- Imagen del sistema de archivos raíz: squashfs, comprimida con xz
- Permisos de archivo para ficheros sensibles/del entorno en vivo (por
  ejemplo `/etc/shadow`, los scripts de `airootfs/root` y las utilidades de
  `/usr/local/bin`, incluida `xinstall`).

## Paquetes y repositorios usados por la construcción

- `packages.x86_64` es el manifiesto completo de paquetes del ISO en vivo.
  Incluye el sistema base más *tooling* de rescate/en vivo, fuentes, un
  navegador (Firefox), los paquetes de X `x-release` y `x-dev` (del
  repositorio `[x]`) y `gum` (usado por la interfaz del instalador de texto).
- `bootstrap_packages.x86_64` es el conjunto mínimo (`base`,
  `arch-install-scripts`) que archiso usa para el root de arranque.
- `pacman.conf` añade el repositorio propio:

  ```ini
  [x]
  SigLevel = Never
  Server = https://equislinux.github.io/x-repo/repo/x86_64
  ```

  El *host de build* usa `Never` (puede no tener la clave del proyecto). El
  **ISO live y el destino instalado** usan `SigLevel = Required`: la clave
  pública viaja en `/etc/pacman.d/x-repo.pub`; en el entorno en vivo
  `pacman-init.service` recrea el keyring en tmpfs y `x-keyring.service`
  importa y firma localmente la clave del proyecto, mientras que `install.sh`
  prepara el keyring del destino de la misma forma.
- El *payload* de aprovisionamiento (`x-scripts`) se incluye **offline**
  dentro del ISO en `airootfs/root/x-installer/packages/x-scripts-*.pkg.tar.zst`,
  de modo que el instalador no necesita descargarlo de la red durante la
  instalación.

## Solución de problemas

- Si no se genera ningún ISO, inspecciona primero el log de construcción
  (`build-*.log`).
- Causas de fallo habituales:
  - espacio en disco insuficiente;
  - errores en un helper en vivo o en un hook de pacman;
  - configuración de perfil inválida en `profiledef.sh`;
  - montajes obsoletos bajo `work/x86_64/airootfs` (el script intenta
    limpiarlos; si hace falta, desmonta con
    `sudo umount -R work/x86_64/airootfs`).

## Construcciones WSL (repositorios dedicados)

WSL no se construye desde este repositorio. El flujo canónico vive en:

| Repositorio | Rol |
|-------------|-----|
| `equislinux/wsl` | `build-rootfs.sh` produce un tarball de rootfs importable (`.tar.gz` + `.sha256`); `install.ps1` lo importa en Windows. Release publicada: `v0.1.0`. |
| `equislinux/wsl-scripts` | Aprovisionamiento en dos etapas dentro de la distro (`stage-root.sh` / `stage-user.sh`). |

Consulta `docs/build-wsl.md` para el resumen; los dos repositorios de arriba
son la fuente de verdad.

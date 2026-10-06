# Repositorio de la distribución X

> Otros idiomas: [English](../en/index.md)

Este es el índice de documentación del repositorio `x` (`equislinux/x`), el hogar
de la distribución **X** (antes conocida como *X Linux* / `x-linux`). X es un
*spin* personalizado de Arch Linux centrado en la simplicidad, el *branding*
limpio y las construcciones reproducibles. Incluye su propio repositorio de
paquetes (`x-repo`) para poder instalar paquetes específicos de X directamente
con `pacman`.

## Visión general

El repositorio contiene la fuente de construcción de la distribución, no un
producto de cara al usuario por sí solo. Aporta:

- Un **perfil archiso** que produce el **ISO en vivo** arrancable.
- Un **instalador de texto** que se ejecuta automáticamente en el entorno en
  vivo (no hay instalador gráfico; Calamares fue eliminado).
- El **aprovisionamiento** del sistema instalado mediante el *payload*
  `x-scripts`, incluido de forma *offline* dentro del ISO.
- Utilidades para construir **tarballs de sistema de archivos importables en
  WSL**.
- **Generaciones del sistema**: el instalador crea los subvolúmenes
  `@`/`@home`/`@snapshots`/`@xstate` y una primera generación booteable; el
  payload registra snapshots con manifiesto, rollback y restore granular
  (`x gen`), más generaciones de dotfiles (`x home`) y hooks de pacman. Ver
  [Generaciones](generations.md).

El ISO usa el flujo estándar de `mkarchiso`. En `pacman.conf` se declara un
repositorio `[x]` de pacman propio que se usa tanto en la construcción como en
el sistema instalado, de modo que los paquetes de *branding* y herramientas de
X (`x-release`, `x-dev`) se instalan con `pacman`.

## Estado del proyecto

La distribución está en desarrollo activo. El trabajo actual es la iniciativa
*reboot* (aprovisionamiento basado en scripts al estilo de Omarchy, con
decisiones y *tooling* propios de X). Consulta `ROADMAP.md` para la hoja de
ruta y `docs/project-state.md` para una instantánea del estado.

## Cómo se mapea este repositorio en la organización

El *workspace* agrupa cada repositorio de equislinux bajo `x-lnux/`. Los nombres de
los repos se renombraron en su momento, por lo que las referencias antiguas a
`x-linux` (la distro) o a un repo `x` de scripts deben leerse con este mapeo:

| Repositorio | Rol |
|-------------|-----|
| `equislinux/x` | **La distro (este repo).** Perfil archiso, ISO en vivo, instalador de texto, construcción de rootfs para WSL. |
| `equislinux/scripts` | *Payload* de aprovisionamiento y la CLI `x` (`x setup`, `x theme`, ...). Se empaqueta como `x-scripts` y lo instala el instalador de texto. |
| `equislinux/x-repo` | Repositorio binario de paquetes de X (alojado en GitHub Pages, `[x]` en `pacman.conf`) y el portal de paquetes. |
| `equislinux/xpm` | Gestor de paquetes de X (Rust). |
| `equislinux/xpkg` | Herramienta de empaquetado de X para desarrolladores (Rust). |
| `equisdots/*` | Org dueña del stack de escritorio (config Lua de Hyprland, shell Quickshell, paletas, motores, login SDDM) consumido de solo lectura por la herramienta de instalación de Hyprland en `scripts`; su instalador oficial es `equisdots/dots`. |

Documentación relacionada en este repositorio:

- [Construir el ISO y el rootfs de WSL](building.md)
- [Generaciones (snapshots btrfs, rollback, restore)](generations.md)
- [Instalador de texto](installer.md)
- [Pruebas en una máquina virtual](vm-testing.md)
- [Referencia de la estructura del proyecto](project-layout.md)

## Aspectos destacados

- **Branding.** Identidad aplicada a GRUB (`GRUB_DISTRIBUTOR="X"`), a la
  etiqueta/editor del ISO, al MOTD y a los paquetes instalados.
- **Instalador de texto.** `configurator.sh` recoge las opciones y escribe un
  plan JSON; `install.sh` particiona (GPT/btrfs), ejecuta `pacstrap`,
  configura el sistema base, aprovisiona con `x-scripts` e instala un gestor
  de arranque.
- **Instalación desatendida.** El ISO incluye una entrada de arranque
  `autoinstall` (hotkey `a`, `xauto=1`) para un disco etiquetado `cidata` con
  un `x-install.json`.
- **Payload de aprovisionamiento offline.** El paquete `x-scripts` y la
  instantánea de la configuración de Hyprland viajan dentro del ISO, de modo
  que el aprovisionamiento no depende de descargarlos durante la instalación.
- **Soporte WSL.** El rootfs se construye en el repositorio dedicado
  `equislinux/wsl` (release `v0.1.0`) y se aprovisiona con `equislinux/wsl-scripts`.

## Modelo de desarrollo

- El desarrollo ocurre en `main` con ramas cortas por PR.
- Las ramas antiguas (`checkpoint/calamares-installer-v1`, `x/reboot`, `dev`)
  son históricas y no reflejan el código actual.

## Alcance

Todo lo que hay en este repositorio forma parte de la organización equislinux.
Aquí solo viven las referencias relacionadas con construir, instalar y
aprovisionar X; la lógica de configuración del usuario vive en el *payload*
`x-scripts`.

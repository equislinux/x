<h1 align="center"> X Linux </h1>

<div align="center">
  <p><b>Arch-based, snapshot-first Linux with a script-driven installer and its own package tooling.</b></p>
  <p>
    <a href="https://equislinux.github.io/web/">Website</a> •
    <a href="https://equislinux.github.io/web/en/docs/">Documentation</a> •
    <a href="https://equislinux.github.io/web/download/latest/">Download</a> •
    <a href="https://github.com/equislinux/wiki">Wiki sources</a>
  </p>
</div>

<p align="center">
    <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue.svg">
    <img alt="Language" src="https://img.shields.io/badge/Language-Shell-89e051?logo=gnu-bash&logoColor=white">
    <img alt="Platform" src="https://img.shields.io/badge/Platform-Arch%20Linux-1793D1?logo=arch-linux&logoColor=white">
    <img alt="Status" src="https://img.shields.io/badge/Status-Active%20Development-2ea44f">
</p>

<a href="https://equislinux.github.io/web/">
  <img src="https://equislinux.github.io/web/showcase/hero-desktop.jpg" alt="X Linux — Hyprland desktop (dark theme)" width="100%">
</a>

<hr />

<h2 align="center"> Table of Contents </h2>
<p align="center">
  <a href="#why-x">Why X</a> •
  <a href="#install">Install</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#build-the-iso">Build the ISO</a> •
  <a href="#project-status">Project Status</a> •
  <a href="#repositories">Repositories</a> •
  <a href="#documentation">Documentation</a>
</p>

<hr />

<h2 align="center" id="why-x"> Why X </h2>

<ul>
  <li><b>Bootable generations</b> — every package transaction is captured as a btrfs snapshot with its own boot entry. Roll back, diff, verify, pin, or export signed and encrypted bundles (<code>x gen</code>).</li>
  <li><b>Multi-kernel</b> — pick <code>linux</code>, <code>linux-lts</code> or <code>linux-zen</code> at install time or later with <code>x kernel install|remove</code>, protected by guard rails for the running and last kernel.</li>
  <li><b>Script-driven installer</b> — BIOS/UEFI, GRUB/systemd-boot, LUKS, dualboot, core or full (Hyprland) profiles, all in the terminal.</li>
  <li><b>Signed repository and native tooling</b> — the <code>[x]</code> pacman repository is signed (<code>SigLevel = Required</code>); <a href="https://github.com/equislinux/xpm">xpm</a> (package manager) and <a href="https://github.com/equislinux/xpkg">xpkg</a> (builder) drive a native <code>.xp</code> endpoint end-to-end.</li>
  <li><b>WSL</b> — an importable rootfs plus a friendly first-run setup: <a href="https://github.com/equislinux/wsl">equislinux/wsl</a> and <a href="https://github.com/equislinux/wsl-scripts">wsl-scripts</a>.</li>
</ul>

<hr />

<h2 align="center" id="install"> Install </h2>

<ol>
  <li><b>Download</b> the latest signed ISO from the stable link: <a href="https://equislinux.github.io/web/download/latest/">equislinux.github.io/web/download/latest</a></li>
  <li><b>Flash</b> it to a USB drive:
    <pre><code>sudo dd if=x-&lt;version&gt;-x86_64.iso of=/dev/sdX bs=8M conv=fsync status=progress</code></pre>
  </li>
  <li><b>Boot</b> it and follow the text installer — disk layout, kernel and profile. Full guide: <a href="./docs/installation.md">docs/installation.md</a>.</li>
</ol>

<hr />

<h2 align="center" id="screenshots"> Screenshots </h2>

<table>
  <tr>
    <td width="50%"><img src="https://equislinux.github.io/web/showcase/tools.png" alt="xtop and xfetch on the Hyprland desktop"></td>
    <td width="50%"><img src="https://equislinux.github.io/web/showcase/boot-generations.png" alt="Boot menu with bootable generations"></td>
  </tr>
  <tr>
    <td width="50%"><img src="https://equislinux.github.io/web/showcase/installer.png" alt="Text installer: btrfs subvolumes and keyring"></td>
    <td width="50%"><img src="https://equislinux.github.io/web/showcase/desktop-light.jpg" alt="X Linux desktop (light theme)"></td>
  </tr>
</table>

<p align="center"><i>
xtop and xfetch on the Hyprland desktop · the boot menu where every transaction is a generation · the text installer · the light theme
</i></p>

<p align="center">
  <img src="https://equislinux.github.io/web/showcase/demo.gif" alt="X Linux desktop demo — xtop and xfetch on Hyprland" width="720">
</p>

<hr />

<h2 align="center" id="build-the-iso"> Build the ISO </h2>

<pre><code>sudo pacman -S archiso
sudo ./xbuild.sh</code></pre>

<p>Output: <code>./out/*.iso</code> · Guide: <a href="./docs/build-iso.md">docs/build-iso.md</a> · VM testing: <a href="./docs/vm-testing.md">docs/vm-testing.md</a></p>

<hr />

<h2 align="center" id="project-status"> Project Status </h2>

<ul>
  <li><b>Active development.</b> Validated locally: full test suite, a real-btrfs suite and QEMU end-to-end runs (install → boot → generations → rollback).</li>
  <li><b>Releases:</b> signed ISOs published on SourceForge; the stable link above always points to the current release.</li>
  <li><b>Detailed state:</b> <a href="./docs/project-state.md">docs/project-state.md</a> · <a href="./docs/generations.md">docs/generations.md</a></li>
</ul>

<hr />

<h2 align="center" id="repositories"> Repositories </h2>

<ul>
  <li><a href="https://github.com/equislinux/x">x</a> — this repo: archiso profile, text installer and ISO build.</li>
  <li><a href="https://github.com/equislinux/scripts">scripts</a> — provisioning payload and the <code>x</code> CLI (generations, setup, themes, kernels).</li>
  <li><a href="https://github.com/equislinux/x-repo">x-repo</a> — signed <code>[x]</code> package repository and portals.</li>
  <li><a href="https://github.com/equislinux/xpm">xpm</a> — package manager (Rust, ALPM format, native <code>.xp</code>).</li>
  <li><a href="https://github.com/equislinux/xpkg">xpkg</a> — package builder (XBUILD/PKGBUILD to <code>.xp</code>).</li>
  <li><a href="https://github.com/equislinux/wsl">wsl</a> — importable WSL rootfs and Windows importer.</li>
  <li><a href="https://github.com/equislinux/wsl-scripts">wsl-scripts</a> — WSL first-run setup.</li>
  <li><a href="https://github.com/equislinux/web">web</a> — documentation portal (this site).</li>
  <li><a href="https://github.com/equislinux/wiki">wiki</a> — documentation sources (English/Spanish).</li>
</ul>

<hr />

<h2 align="center" id="documentation"> Documentation </h2>

<ul>
  <li><a href="./docs/project-state.md">Project State</a></li>
  <li><a href="./docs/project-structure.md">Project Structure</a></li>
  <li><a href="./docs/build-iso.md">Build ISO Guide</a></li>
  <li><a href="./docs/build-wsl.md">Build WSL Guide</a></li>
  <li><a href="./docs/installation.md">Installation Guide</a></li>
  <li><a href="./docs/generations.md">Generations</a></li>
  <li><a href="./docs/x-repository.md">X Repository Guide</a></li>
  <li><a href="./docs/vm-testing.md">VM Testing</a></li>
  <li><a href="./ROADMAP.md">Roadmap</a></li>
  <li><a href="./CONTRIBUTING.md">Contributing</a> · <a href="./CODE_OF_CONDUCT.md">Code of Conduct</a> · <a href="./SECURITY.md">Security</a> · <a href="./SUPPORT.md">Support</a></li>
</ul>

<div align="center">
<h2>X</h2>
<a href="https://equislinux.github.io/web/">Website &amp; Docs</a> &middot; <a href="https://github.com/equislinux">GitHub</a>
</div>

- License: GPL-3.0 · Documentation: https://github.com/equislinux/wiki

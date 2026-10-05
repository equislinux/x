<h1 align="center"> X Linux </h1>

<div align="center">
  <p><b>X</b> is a custom Arch Linux spin focused on simplicity, clean branding, and reproducible builds.</p>
  <p>It ships its own package repository (<a href="https://github.com/xlnux/x-repo">x-repo</a>) so you can install X-specific packages directly with <code>pacman</code>.</p>
</div>

<blockquote>
  <p align="center"><b>Project status:</b> Under active development</p>
</blockquote>

<p align="center">
    <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue.svg">
    <img alt="Language" src="https://img.shields.io/badge/Language-Shell-89e051?logo=gnu-bash&logoColor=white">
    <img alt="Platform" src="https://img.shields.io/badge/Platform-Arch%20Linux-1793D1?logo=arch-linux&logoColor=white">
    <img alt="Status" src="https://img.shields.io/badge/Status-Active%20Development-2ea44f">
</p>

<hr />

<h2 align="center"> Table of Contents </h2>
<p align="center">
  <a href="#overview">Overview</a> •
  <a href="#project-status">Project Status</a> •
  <a href="#project-composition">Project Composition</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#related-repos">Related Repositories</a> •
  <a href="#related-documents">Related Documents</a> •
  <a href="#x">X</a>
</p>

<hr />

<h2 align="center" id="overview"> Overview </h2>

<p>X provides a minimal yet polished Arch-based system with its own identity. It is built with the standard <code>mkarchiso</code> workflow, layering a custom profile, branding assets, and post-install automation.</p>

<h3 align="center"> Key Features </h3>
<ul>
  <li><b>Custom branding</b> — Identity applied to <code>/etc/os-release</code>, GRUB, MOTD, and wallpapers.</li>
  <li><b>X package repository</b> — Dedicated <code>[x]</code> repo in <code>pacman.conf</code> for branding and tools.</li>
  <li><b>Script-based provisioning</b> — System and user setup driven by scripts instead of a graphical installer (Calamares removed).</li>
  <li><b>Post-install automation</b> — Scripts to apply branding and setup tasks after installation.</li>
  <li><b>WSL support</b> — Tools to build a WSL-importable root filesystem tarball.</li>
</ul>

<hr />

<h2 align="center" id="project-status"> Project Status </h2>

<ul>
  <li><b>Development stage:</b> Active.</li>
  <li><b>Build model:</b> Local <code>mkarchiso</code> flow for ISO and dedicated scripts for WSL rootfs.</li>
  <li><b>Automation:</b> Roadmap-to-issues synchronization is configured in GitHub Actions.</li>
  <li><b>Focus areas:</b> Package repository maturity, installer UX, documentation, and release pipeline hardening.</li>
</ul>

<p>Detailed status report: <a href="./docs/project-state.md">Project State</a></p>

<hr />

<h2 align="center" id="project-composition"> Project Composition </h2>

<ul>
  <li><code>airootfs/</code>: Root filesystem overlay (system config, branding, installer automation).</li>
  <li><code>profiledef.sh</code>: ArchISO profile metadata, boot modes, and file permissions.</li>
  <li><code>packages.x86_64</code>: Package manifest for ISO builds.</li>
  <li><code>pacman.conf</code>: Package manager configuration, including the <code>[x]</code> repository.</li>
  <li><code>xbuild.sh</code>: ISO build script.</li>
  <li><code>ROADMAP.md</code>: Project roadmap used as issue-sync source.</li>
</ul>

<p>Detailed structure reference: <a href="./docs/project-structure.md">Project Structure</a></p>

<hr />

<h2 align="center" id="quick-start"> Quick Start </h2>

<h3 align="center"> Build the ISO </h3>

<pre><code>sudo pacman -S archiso
./xbuild.sh</code></pre>

<p>Output: <code>./out/*.iso</code></p>

<h3 align="center"> Build for WSL </h3>

<p>The WSL rootfs is built in <a href="https://github.com/xlnux/wsl">xlnux/wsl</a> (rootfs builder + Windows importer) with provisioning in <a href="https://github.com/xlnux/wsl-scripts">xlnux/wsl-scripts</a>. Published rootfs release: <code>v0.1.0</code>. See <a href="./docs/build-wsl.md">Build WSL Guide</a>.</p>

<hr />

<h2 align="center" id="related-repos"> Related Repositories </h2>

<ul>
  <li><a href="https://github.com/xlnux/x">x:</a> scripts post install to set up xdev environment.</li>
  <li><a href="https://github.com/xlnux/x-repo">x-repo:</a> X package repository for x.</li>
  <li><a href="https://github.com/xfetch-cli/xfetch">xfetch:</a> official getter for system information created on rust for X but now running in any distro.</li>
  <li><a href="https://github.com/xlnux/xpm">xpm:</a> X package manager for x.</li>
  <li><a href="https://github.com/xlnux/xpkg">xpkg:</a> X packager for x developers.</li>
</ul>

<h2 align="center" id="related-documents"> Related Documents </h2>

<ul>
  <li><a href="./docs/project-state.md">Project State</a></li>
  <li><a href="./docs/project-structure.md">Project Structure</a></li>
  <li><a href="./docs/build-iso.md">Build ISO Guide</a></li>
  <li><a href="./docs/build-wsl.md">Build WSL Guide</a></li>
  <li><a href="./docs/x-repository.md">X Repository Guide</a></li>
  <li><a href="./docs/installation.md">Installation Guide</a></li>
  <li><a href="./ROADMAP.md">Roadmap</a></li>
  <li><a href="./CODE_OF_CONDUCT.md">Code of Conduct</a></li>
  <li><a href="./CONTRIBUTING.md">Contributions</a></li>
  <li><a href="./SECURITY.md">Security</a></li>
  <li><a href="./SUPPORT.md">Support</a></li>
</ul>


<div id="x" align="center">
<h2>X</h2>

<a href="https://xscriptor.io">X Web</a>
 & 
 <a href="https://github.com/xscriptor">X Github Profile</a>

</div>

- Documentation: https://github.com/xlnux/wiki

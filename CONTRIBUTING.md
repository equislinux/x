<h1 align="center"> Contributing to X Linux </h1>

<div align="center">
  <p>Thank you for considering contributing! To maintain the quality and reproducibility of the X Linux ecosystem, please follow these guidelines.</p>
</div>

<hr />

<h2 align="center"> Table of Contents </h2>
<p align="center">
  <a href="#how-to-contribute">How to Contribute</a> •
  <a href="#project-structure">Project Structure</a> •
  <a href="#rules">Rules</a>
</p>

<hr />

<h2 align="center" id="how-to-contribute"> How to Contribute </h2>

<ol>
  <li><b>Fork</b> the repository to your own GitHub account.</li>
  <li><b>Create a branch</b> for your feature, fix, or profile adjustment (<code>git checkout -b feat/new-package-support</code>).</li>
  <li><b>Commit</b> your changes with clear and descriptive messages, ensuring scripts remain executable.</li>
  <li><b>Push</b> to your branch and open a <b>Pull Request</b> against the main branch.</li>
</ol>

<h2 align="center" id="project-structure"> Project Structure </h2>

<ul>
  <li><b>airootfs/</b>: Root filesystem overlay where branding, hooks, and system configurations reside.</li>
  <li><b>Build Script (xbuild.sh)</b>: Tool for ISO image generation.</li>
  <li><b>pacman.conf & packages.x86_64</b>: Core configuration for repository management and package lists.</li>
</ul>

<h2 align="center" id="rules"> Rules </h2>

<ul>
  <li>Always respect the <b>Code of Conduct</b> in all interactions.</li>
  <li>Ensure any changes to <code>profiledef.sh</code> or <code>mkarchiso</code> configurations are tested for build success.</li>
  <li>Do not include sensitive data, personal SSH keys, or private API tokens in the <code>airootfs</code>.</li>
  <li>For reporting security vulnerabilities, please refer directly to our <a href="SECURITY.md"><b>SECURITY.md</b></a>.</li>
</ul>

<hr />

<div align="center">
  <p><i>By contributing, you agree that your code will be licensed under the project's respective licenses (MIT for build scripts and configuration).</i></p>
  <p><b>Thank you for helping us improve X Linux!</b></p>
</div>
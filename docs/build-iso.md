# Build ISO Guide

This guide explains how to build the X Linux ISO from this repository.

## Prerequisites

- Arch Linux (or compatible environment with ArchISO tooling).
- `sudo` access.
- Required package: `archiso`.

Install dependencies:

```bash
sudo pacman -S archiso
```

## Build Command

Run from the repository root:

```bash
./xbuild.sh
```

## What the Script Does

`xbuild.sh` performs the following:

1. Validates required files (`pacman.conf`, `profiledef.sh`).
2. Attempts to unmount stale mount points under `work/x86_64/airootfs`.
3. Removes previous `work/` and `out/` directories.
4. Runs `mkarchiso` with explicit config and output directories.
5. Verifies that an ISO was generated and reports artifact paths.

## Output

- ISO files are generated under `./out/`.
- A timestamped build log is generated in the repository root (for example, `build-YYYYMMDD-HHMM.log`).

## Troubleshooting

- If no ISO is generated, check the build log first.
- Common failure causes:
  - insufficient disk space;
  - errors in a live helper or pacman hook;
  - invalid profile configuration.

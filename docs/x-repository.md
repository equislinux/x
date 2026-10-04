# X Repository Guide

This guide describes how the custom X package repository is configured and consumed.

## Repository Configuration

The repository is declared in `pacman.conf`:

```ini
[x]
# Consumer side (live ISO / installed target): import + locally sign the
# project key shipped at /etc/pacman.d/x-repo.pub first.
SigLevel = Required
Server = https://xlnux.github.io/x-repo/repo/x86_64
```

The build host (`mkarchiso -C pacman.conf`) uses `SigLevel = Never` for `[x]`
because its keyring may not carry the project key.

## Usage in This Project

- Build scripts use `pacman.conf`, so the `[x]` repository is available during image/rootfs creation.
- The package manifest includes X packages such as `x-release`.
- The live/rootfs environment receives this repository configuration through copied config files.

## Add to an Existing Arch System

1. Append the `[x]` block to `/etc/pacman.conf`.
2. Refresh package databases and install X base package:

```bash
sudo pacman -Sy x-release
```

## Security Note

The published repository is signed with the project key. The live ISO and the
installed target use `SigLevel = Required` and trust the key (imported and
locally signed during build/install). The build host uses `Never` only because
`mkarchiso` may run on a host without the project key.

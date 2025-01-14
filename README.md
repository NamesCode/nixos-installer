# NixOS Installer

A Bash script to quickly install NixOS on my servers

## What's supported

### Boot systems

- UEFI
- ~BIOS~ NO SUPPORT YET

### Filesystems

- ZFS
    - Making vdevs
    - Raid options
    - Compression
    - Encryption
        - USB keydrive
        - password prompt
    - backup setup (There's a layout scheme for backups)

## Usage

Just run `sudo nix run --extra-experimental-features nix-command  --extra-experimental-features flakes github:namescode/nixos-installer`

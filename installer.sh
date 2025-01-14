#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Name <lasagna@garfunkle.space>
# SPDX-License-Identifier: MPL-2.0


# Exit on any kind of error
set -euo pipefail

error_handler() {
    echo "An error occurred on line $1."

    sudo swapoff "$swap_drive"

    # Unmount all mounted drives
    for drive in $selected_drives; do
      sudo umount "$drive"
    done

    sudo umount "$key_drive"

    case "$chosen_filesystem" in
      "ZFS")
        command sudo zpool destroy "$pool_name"
        ;;
      *)
        command echo "This should not occur" && return 1
        ;;
    esac
}

# Catches any kind of error and calls the error_handler function
trap 'error_handler $LINENO' ERR

# Checks if we're running as root
if [ "$USER" != "root" ]; then
  command echo "You need to be root to run this script. Run it again with sudo." && exit 1
fi


# Init

# Info
echo "For now, the script will just *assume* you have an internet connection. If you do not, *get one*."
echo "This script also will NOT work for bios systems yet"
echo "Nor will it work for systems with multiple drives. I need to add that."

# Creates the nixos-installer temp dir
mkdir -p /tmp/nixos-installer


# Logic

echo "What would you like to set as the device hostname?: "
read -r hostname

# Lets us find out what kind of /boot we need to make
uefi_or_bios() {
  echo "Are you installing on a UEFI or BIOS system? (u/uefi/b/bios): "
  read -r BOOTLOADER_TYPE

  case "$BOOTLOADER_TYPE" in
    [Uu][Ee][Ff][Ii]|[Uu])
      IS_UEFI=true
      ;;
    [Bb][Ii][Oo][Ss]|[Bb])
      IS_UEFI=false
      ;;
    *)
      command echo "That's not a valid option, try again" && uefi_or_bios
      ;;
  esac
}

uefi_or_bios

get_drives() {
  # Get the drives (excluding partitions) and their capacities
  drives=$(lsblk -d -o NAME,SIZE -n | awk '{print "/dev/" $1 " " $2}')

  # Use fzf to select drives
  selected_drives=$(echo "$drives" | fzf --multi \
    --header "Select (tab) all the drives you want to use. WARNING: They will be wiped." \
    --bind "enter:accept,space:toggle" --height 40%)

  remaining_drives="$(echo "$drives" | grep -vxFf <(echo "$selected_drives"))"

  # Display the selected drives
  if [ -z "$selected_drives" ]; then
      echo "No drives selected. You must select AT LEAST one."
      get_drives
  fi
}

get_drives

get_boot_drive() {
  boot_drive=$(echo "$selected_drives" | fzf --header "Select (tab) which drive you want as your boot drive." \
    --bind "enter:accept,space:toggle" --height 40%)

  if [ -z "$boot_drive" ]; then
      echo "No drive selected. You must select a drive."
      get_boot_drive
  fi
}

get_boot_drive

selected_drives=$(echo "$selected_drives" | awk '{print $1}')
boot_drive=$(echo "$boot_drive" | awk '{print $1}')

# Sets up the drives partition tables, partitions and the filesystem for the boot drive
for drive in "${selected_drives[@]}"; do
  if [[ "$drive" == "$boot_drive" ]]; then
    if [ "$IS_UEFI" = true ]; then
      # Wipes the drive and creates a new GPT table + a boot and swap partition
      echo -e "n\n\n\n+1G\nef00\nn\n\n\n+4G\n8200\nn\n\n\n\n\nw\ny\n" | sudo gdisk "$boot_drive" > /dev/null 2>> /tmp/nixos-installer/errors.log

      if [[ "${boot_drive:0-1}" =~ ^[0-9]+$ ]]; then
        filesystem_drives+=("$boot_drive""p3")
        swap_drive="$boot_drive""p2"
        boot_drive="$boot_drive""p1"
      else
        filesystem_drives+=("$boot_drive""3")
        swap_drive="$boot_drive""2"
        boot_drive="$boot_drive""1"
      fi

      # Formats the boot partition into fat32
      sudo mkfs.fat -F 32 -n boot "$boot_drive"

      # Formats the swap partition and swaps on it
      sudo mkswap -L swap "$swap_drive"
      sudo swapon "$swap_drive"
    else
      echo "BIOS NOT YET IMPLEMENTED"
      break
    fi
  else
    if [ "$IS_UEFI" = true ]; then
      # Wipes the drive and creates a new GPT table
      echo -e "n\n\n\n\n\nw\ny\n" | sudo gdisk "$drive" > /dev/null 2>> /tmp/nixos-installer/errors.log

      echo "Would've setup UEFI"
    else
      echo "BIOS NOT YET IMPLEMENTED"
      break
    fi

    filesystem_drives+=("$drive""1")
  fi
done


# Filesystem stuff

# Utility functions
encryption() {
  echo "Would you like to use a prompt or a USB with a keyfile? (p/prompt/k/key/n/none): "
  read -r prompt_or_usb

  case "$prompt_or_usb" in
    [Kk][Ee][Yy]|[Kk])
      key_drive="$(sudo blkid | grep 'LABEL="KEYDRIVE"' || true)"

      if [[ -z "$key_drive" ]]; then
        key_drive=$(echo "$remaining_drives" | fzf --header "Select which drive you want to use as the USB keyfile. (This drive will be wiped): " \
          --bind "enter:accept,space:toggle" --height 40%)
        key_drive=$(echo "$key_drive" | awk '{print $1}')

        echo -e "o\nw\n" | sudo fdisk "$key_drive"
        sudo mkfs.fat -F 32 -n KEYDRIVE "$key_drive"
      else
        key_drive=$(echo "$key_drive" | awk '{print $1}' | sed 's/.$//')
      fi

      mkdir -p /mnt
      mkdir -p /mnt/keydrive

      sudo mount "$key_drive" /mnt/keydrive

      echo "What would you like to call this key? (leave empty for hostname): "
      read -r key_stem

      if [ -z "$key_stem" ]; then
        key_stem="$hostname"
      fi

      echo "Now generating a 256-bit key at '/mnt/keydrive/""$key_stem"".key'. This key is stored as hexadecimal and it is recommended you print it out for safe keeping."
      openssl rand -hex 32 > /mnt/keydrive/"$key_stem".key

      options="$options ""-O encryption=on -O keyformat=hex -O keylocation=file:///mnt/keydrive/""$key_stem"".key"
      ;;
    [Pp][Rr][Oo][Mm][Pp][Tt]|[Pp])
      options="$options ""-O encryption=on -O keyformat=passphrase -O keylocation=prompt"
      ;;
    [Nn][Oo][Nn][Ee]|[Nn])
      command echo "Encryption disabled."
      ;;
    *)
      command echo "You can only choose between prompt, key or none. Try again." && encryption
      ;;
  esac
}

# Filesystem specific funtions
use_zfs() {
  options=""

  echo "Do you want to enable encryption? (y/n): "
  read -r enable_encryption

  if [ "$enable_encryption" = "y" ]; then
    encryption
  fi

  echo "What should the pool name be? (leave blank for 'hostname-pool'): "
  read -r pool_name
  if [[ -z "$pool_name" ]]; then
    pool_name=""$hostname"-pool"
  fi

  echo "Do you want to enable compression? (y/n): "
  read -r enable_compression

  if [ "$enable_compression" = "y" ]; then
    options="$options ""-O compression=on"
  fi

  options="$options ""-O mountpoint=legacy -O xattr=sa -O acltype=posixacl -o ashift=12"

  actions=()
  availabe_drives=${filesystem_drives[*]}
  while true; do
    action="$(echo -e "restart\nfinish\nstripe\nmirror\nraidz1\nraidz2" | fzf --header "Select (tab) all the drives you want to use for this vdev. WARNING: The capacity of the smallest one selected is the capacity of them all." \
      --bind "enter:accept,space:toggle" --height 40%)"

    if [ "$action" = "restart" ]; then
      actions=()
      availabe_drives=${filesystem_drives[*]}
      continue
    elif [ "$action" = "finish" ]; then
      break
    fi

    selected_drives="$(echo "${availabe_drives[*]}" | fzf --preview "lsblk {}" --multi \
      --header "Select (tab) all the drives you want to use for this vdev. WARNING: The capacity of the smallest one selected is the capacity of them all." \
      --bind "enter:accept,space:toggle" --height 40%)"

    for drive in $selected_drives; do
        available_drives=("${available_drives[@]/$drive}")  # Remove selected drive from available_drives array
    done

    if [ "$action" = "stripe" ]; then
      for drive in $selected_drives; do
        actions=("$drive" "${actions[@]}")
      done
    else
      actions+=("$action $(echo "$selected_drives" | tr '\n' ' ')")
    fi
  done

  sudo zpool create -f $options "$pool_name" $(echo "${actions[*]}" | tr '\n' ' ')

  sudo zfs create "$pool_name""/local"
  sudo zfs create "$pool_name""/local/nix"

  sudo zfs create "$pool_name""/backup"
  sudo zfs create "$pool_name""/backup/monthly"
  sudo zfs create "$pool_name""/backup/weekly"

  sudo zfs create "$pool_name""/backup/monthly/root"

  sudo zfs create -o "compression=off" "$pool_name""/backup/weekly/var"
  sudo zfs create "$pool_name""/backup/weekly/srv"
  sudo zfs create "$pool_name""/backup/weekly/home"
  sudo zfs create "$pool_name""/backup/weekly/root-user"

  mkdir -p /tmp/nixos-installer/mnt/
  sudo mount -t zfs "$pool_name""/backup/monthly/root" /tmp/nixos-installer/mnt

  mkdir -p /tmp/nixos-installer/mnt/var /tmp/nixos-installer/mnt/srv /tmp/nixos-installer/mnt/home /tmp/nixos-installer/mnt/root
  
  sudo mount -t zfs "$pool_name""/backup/weekly/var" /tmp/nixos-installer/mnt/var
  sudo mount -t zfs "$pool_name""/backup/weekly/srv" /tmp/nixos-installer/mnt/srv
  sudo mount -t zfs "$pool_name""/backup/weekly/home" /tmp/nixos-installer/mnt/home
  sudo mount -t zfs "$pool_name""/backup/weekly/root-user" /tmp/nixos-installer/mnt/root

  zpool status
}

# Get the chosen filesystem
chosen_filesystem=$(echo -e "ZFS\n" | fzf --header "Select (tab) which filesystem you want to use." \
    --bind "enter:accept,space:toggle" --height 40%)

case "$chosen_filesystem" in
  "ZFS")
    use_zfs
    ;;
  *)
    command echo "This should not occur" && return 1
    ;;
esac

# Make and mount boot
mkdir -p /tmp/nixos-installer/mnt/boot
sudo mount "$boot_drive" /tmp/nixos-installer/mnt/boot

nixos-generate-config --root /tmp/nixos-installer/mnt

if [ "$chosen_filesystem" = "ZFS" ]; then
  sed -i "12i   boot.supportedFilesystems = [ \"zfs\" ]; # Added by nixos-installer; it enables zfs kernel mod" /tmp/nixos-installer/mnt/etc/nixos/hardware-configuration.nix
  sed -i "21i   networking.hostId = \"""$(head -c4 /dev/urandom | od -A none -t x4 | xargs)""\"; # Added by nixos-installer; it sets the hostId as required by ZFS" /tmp/nixos-installer/mnt/etc/nixos/configuration.nix

  if [[ "$prompt_or_usb" =~ [Kk][Ee][Yy]|[Kk] ]]; then
    sed -i "12i \
      # Added by nixos-installer; it lets you decrypt using a USB to hold keyfiles\n\
      boot.initrd.postDeviceCommands = ''\n\
        # Prepare /mnt\n\
        mkdir -p /mnt\n\
        mkdir -p /mnt/keydrive\n\
        \n\
        # Mount keydrive\n\
        mount -L KEYDRIVE /mnt/keydrive\n\
      '';" /tmp/nixos-installer/mnt/etc/nixos/hardware-configuration.nix
  fi
fi

sed -i "21i   networking.hostName = \"""$hostname""\"; # Added by nixos-installer; it sets the hostname" /tmp/nixos-installer/mnt/etc/nixos/configuration.nix

nvim -O /tmp/nixos-installer/mnt/etc/nixos/{hardware-configuration,configuration}.nix

echo "You're all setup! Feel free to make some last minute changes and then run 'sudo nixos-install --root /tmp/nixos-installer/mnt'"

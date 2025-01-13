#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Name <lasagna@garfunkle.space>
# SPDX-License-Identifier: MPL-2.0


# Exit on any kind of error
set -euo pipefail

error_handler() {
    echo "An error occurred on line $1."
    # Cleanup or error handling code here
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
    if [[ "${boot_drive:0-1}" =~ ^[0-9]+$ ]]; then
      filesystem_drives+=("$boot_drive""p3")
      swap_drive="$boot_drive""p2"
      boot_drive="$boot_drive""p1"
    else
      filesystem_drives+=("$boot_drive""3")
      swap_drive="$boot_drive""2"
      boot_drive="$boot_drive""1"
    fi

    if [ "$IS_UEFI" = true ]; then
      # TODO: UNCOMMENT THESE WHEN DONE TESTING
      # Wipes the drive and replaces it with a new GPT table + a boot and swap partition
      # echo -e "n\n\n+1G\nef00\nn\n\n+4G\n8200\nn\n\n\n\nw\ny\n" | sudo gdisk "$boot_drive" > /dev/null 2>> /tmp/nixos-installer/errors.log
      # 
      # Formats the boot partition into fat32
      # sudo mkfs.fat -F 32 -n boot $boot_drive
      #
      # Formats the swap partition and swaps on it
      # sudo mkswap -L swap $swap_drive
      # sudo swapon $swap_drive

      echo "Would've setup UEFI"
    else
      echo "BIOS NOT YET IMPLEMENTED"
      break
    fi
  else
    if [ "$IS_UEFI" = true ]; then
      # TODO: UNCOMMENT THESE WHEN DONE TESTING
      # Wipes the drive and replaces it with a new GPT table
      # echo -e "n\n\n\n\nw\ny\n" | sudo gdisk "$drive" > /dev/null 2>> /tmp/nixos-installer/errors.log

      echo "Would've setup UEFI"
    else
      echo "BIOS NOT YET IMPLEMENTED"
      break
    fi

    filesystem_drives+=("$drive""1")
  fi
done


# Filesystem stuff

# Filesystem specific funtions
use_zfs() {
  echo "Do you want to enable encryption? (y/n): "
  read -r encryption

  if [ "$encryption" = "y" ]; then
    echo "do stuff"
  fi
}

# Get the chosen filesystem
chosen_filesystem=$(echo -e "ZFS\n" | fzf --header "Select (tab) which filesystem you want to use." \
    --bind "enter:accept,space:toggle" --height 40%)

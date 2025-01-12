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

# Info
echo "For now, the script will just *assume* you have an internet connection. If you do not, *get one*."
echo "This script also will NOT work for bios systems yet"
echo "Nor will it work for systems with multiple drives. I need to add that."

# Utility functions

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

if [ "$IS_UEFI" = true ]; then
  # echo -e "n\n\n+1G\nef00\nn\n\n+4G\n8200\nn\n\n\n\nw\ny\n" | sudo gdisk "$boot_drive" > /dev/null

  for drive in "${selected_drives[@]}"; do
    if [[ "$drive" == "$boot_drive" ]]; then
          # Skip the boot drive
          continue
    fi

    # Wipes the drive and replaces it with a new GPT table
    # echo -e "n\n\n\n\nw\ny\n" | sudo gdisk "$drive" > /dev/null
  done
else
  echo "BIOS NOT YET IMPLEMENTED"
fi


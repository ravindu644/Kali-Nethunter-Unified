#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
MODDIR=${0%/*}

# This script will be executed in late_start service mode

# Configure firmware path
if [ -f "/sys/module/firmware_class/parameters/path" ]; then
    current_path=$(cat /sys/module/firmware_class/parameters/path 2>/dev/null)
    new_path=""

    # Add /vendor/firmware if not present
    if [ -d "/vendor/firmware" ] && ! echo "$current_path" | grep -q "/vendor/firmware"; then
        new_path="/vendor/firmware"
    fi

    # Add chroot firmware path if exists
    if [ -L "${NHSYS}/kalifs" ]; then
        chroot_fw="$(readlink -f ${NHSYS}/kalifs)/lib/firmware"
        if [ -d "$chroot_fw" ] && ! echo "$current_path" | grep -q "$chroot_fw"; then
            [ -n "$new_path" ] && new_path="$new_path,$chroot_fw" || new_path="$chroot_fw"
        fi
    fi

    # Update firmware path if we have new entries
    if [ -n "$new_path" ]; then
        [ -n "$current_path" ] && final_path="$current_path,$new_path" || final_path="$new_path"
        echo "$final_path" > /sys/module/firmware_class/parameters/path 2>/dev/null
    fi
fi

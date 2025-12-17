#!/system/bin/sh

NHSYS=/data/local/nhsystem

detect_arch(){
    local arch=$(getprop ro.product.cpu.abi)
    case $arch in
        arm64*)
            export ARCH=arm64
            ;;
        armeabi*)
            export ARCH=arm
            ;;
        *) error "Unsupported architecture: ${arch}"
            ;;
    esac
    log "Detected architecture: ${ARCH}"
} && detect_arch

install_busybox(){

    echo "- Installing busybox..."

    if command -v busybox &> /dev/null; then
        echo "- Busybox is already installed"
        export BUSYBOX="$(which busybox)"

        [ -z "${BUSYBOX}" ] && error "Busybox is installed but \$BUSYBOX variable is empty. Something went wrong..." && exit 1

        return 0
    fi

    unzip -o "$ZIPFILE" 'busybox/*' -d "${TMPDIR}" >&2

    [ ! -d "${TMPDIR}/busybox" ] && error "Failed to extract busybox. Cannot continue..!"

    mkdir -p "${MODPATH}/system/bin"
    cp "${TMPDIR}/busybox/${ARCH}/busybox" "${MODPATH}/system/bin/busybox" && \
        chmod +x "${MODPATH}/system/bin/busybox" && \
        echo "- busybox installed successfully"

    # export the installed busybox path
    export BUSYBOX="${MODPATH}/system/bin/busybox"

    return 0
}

install_core(){
    echo "- Installing core files..."
    unzip -o "$ZIPFILE" 'system/*' -d "${MODPATH}" >&2
}

check_data_space(){
    local required_gb=10
    local free_kb=$(${BUSYBOX} df /data | ${BUSYBOX} tail -n1 | ${BUSYBOX} awk '{print $4}')
    local free_gb=$((free_kb / 1024 / 1024))

    if [ "$free_gb" -lt "$required_gb" ]; then
        echo "- Insufficient space on /data. Required: ${required_gb}GB, Available: ${free_gb}GB. Aborting..."
        exit 1
    fi

    echo "- /data partition has ${free_gb}GB free space"
    return 0
}

extract_rootfs(){
    echo "- Installing Kali rootfs..."

    if [ -d "${NHSYS}/kali-${ARCH}" ] && [ -n "$(ls -A "${NHSYS}/kali-${ARCH}" 2>/dev/null)" ]; then
        echo "- Kali rootfs is already installed. Skipping..."
        return 0
    fi

    find_rootfs(){
        unzip -l "$ZIPFILE" 2>/dev/null | grep -E '\.tar\.xz$' | head -1 | while read -r line; do
            # Extract filename from the last field (handles spaces correctly)
            echo "$line" | rev | cut -d' ' -f1 | rev
        done
    }

    rootfs_file=$(find_rootfs)

    if [ -z "$rootfs_file" ]; then
        echo "- No Kali rootfs found. Skipping..."
        return 0
    else
        echo "- Found Kali rootfs to be installed: ${rootfs_file}"
    fi

    mkdir -p "${NHSYS}/kali-${ARCH}"

    echo " - Extracting Kali rootfs (This may take up to 25 minutes)"

    if unzip -oq "${ZIPFILE}" "${rootfs_file}" -d "${TMPDIR}" && ${BUSYBOX} tar -xJf "${TMPDIR}/${rootfs_file}" -C "${NHSYS}/kali-${ARCH}" ; then
        ln -sf "${NHSYS}/kali-${ARCH}" "${NHSYS}/kalifs" || error "Failed to create symlink to ${NHSYS}/kalifs"
        echo "- Kali rootfs installed successfully"
    else
        echo "- Failed to install Kali rootfs. Skipping..."
        return 0
    fi
}

apply_nh_wallpaper(){
    echo "- Applying NetHunter wallpaper..."
    unzip -oq "${ZIPFILE}" 'wallpaper/wallpaper.png' -d "${TMPDIR}" >&2

    [ ! -f "${TMPDIR}/wallpaper/wallpaper.png" ] && echo "- Nethunter Wallpaper not found. Skipping..." && return 0

    cat "${TMPDIR}/wallpaper/wallpaper.png" > /data/system/users/0/wallpaper &>/dev/null && \
    echo '<?xml version="1.0" encoding="utf-8" standalone="yes" ?><wp width="1080" height="1920" name="wallpaper.png" />' > /data/system/users/0/wallpaper_info.xml
    chown system:system /data/system/users/0/wallpaper /data/system/users/0/wallpaper_info.xml && \
        chmod 0600 /data/system/users/0/wallpaper /data/system/users/0/wallpaper_info.xml && \
        chcon "u:object_r:wallpaper_file:s0" /data/system/users/0/wallpaper 2>/dev/null && \
        chcon "u:object_r:system_data_file:s0" /data/system/users/0/wallpaper_info.xml 2>/dev/null
    return 0
}

install_nh_apps(){
    echo "- Installing NetHunter apps..."
    unzip -oq "${ZIPFILE}" 'APKs/*' -d "${TMPDIR}" >&2

    if [ ! -d "${TMPDIR}/APKs" ] || [ -z "$(ls -A "${TMPDIR}/APKs" 2>/dev/null)" ]; then
        echo "- No NetHunter apps found. Skipping..."
        return 0
    fi

    if ! pm &>/dev/null; then
        echo "- pm command looks broken. Is devpts hooks properly wired up in your KernelSU kernel? Skipping..."
        return 0
    fi

    # remove previous installations
    pm uninstall com.offsec.nethunter &>/dev/null || true
    pm uninstall com.offsec.nethunter.kex &>/dev/null || true
    pm uninstall com.offsec.nhterm &>/dev/null || true
    pm uninstall com.offsec.nethunter.store &>/dev/null || true

    for apk in "${TMPDIR}/APKs"/*.apk; do
        echo "- Installing $(basename "$apk")..."
        if ! pm install -r "$apk"; then
            echo "  Failed to install $(basename "$apk")"
        fi
    done

    echo "- Granting permissions to NetHunter apps..."
    for x in ACCESS_BACKGROUND_LOCATION \
            ACCESS_COARSE_LOCATION \
            ACCESS_FINE_LOCATION \
            READ_EXTERNAL_STORAGE \
            WRITE_EXTERNAL_STORAGE \
            WRITE_SECURE_SETTINGS; do
    pm grant -g com.offsec.nethunter android.permission.$x &>/dev/null || true
    done

    return 0
}

final_touches(){
# this function has everything directly copied from the official installer

# Remove Osmosis BusyBox module
[ -d /data/adb/modules/busybox-ndk ] && {
  touch /data/adb/modules/busybox-ndk/disable
  touch /data/adb/modules/busybox-ndk/remove
}

# Remove Wi-Fi firmware modules
[ -d /data/adb/modules/wirelessFirmware ] && {
  touch /data/adb/modules/wirelessFirmware/disable
  touch /data/adb/modules/wirelessFirmware/remove
}

# Remove nano modules
[ -d /data/adb/modules/nano-ndk ] && {
  touch /data/adb/modules/nano-ndk/disable
  touch /data/adb/modules/nano-ndk/remove
}

# symlink kali scripts
mkdir -p "${MODPATH}/system/bin"
for link in bootkali bootkali_init bootkali_login bootkali_bash killkali; do
    ln -sf /data/data/com.offsec.nethunter/assets/scripts/${link} "${MODPATH}/system/bin/${link}" || true
done

# remove junk files and directories
for junk in ".git*" "placeholder" "README.md" "LICENSE"; do
    find "${MODPATH}" -name "${junk}" -delete || true
done

return 0
}

set_nh_permissions(){
    chown -R root:root "${MODPATH}/system" 2>/dev/null
    chmod -R 0755 "${MODPATH}/system" 2>/dev/null
    chcon -R u:object_r:system_file:s0 "${MODPATH}/system" 2>/dev/null
    return 0
}

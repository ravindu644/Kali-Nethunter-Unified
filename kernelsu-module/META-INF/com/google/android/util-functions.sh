#!/system/bin/sh

NHSYS=/data/local/nhsystem

# debug
[ -z "$ZIPFILE" ] && error "ZIPFILE is not set"
[ -z "$MODPATH" ] && error "MODPATH is not set"
[ -z "$TMPDIR" ] && error "TMPDIR is not set"

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
} && detect_arch

install_busybox(){

    echo "- Installing busybox..."

    if command -v busybox &> /dev/null; then
        echo "- Busybox is already installed"
        export BUSYBOX="$(which busybox)"

        [ -z "${BUSYBOX}" ] && error "Busybox is installed but \$BUSYBOX variable is empty. Something went wrong..."

        return 0
    fi

    unzip -qo "$ZIPFILE" 'busybox/*' -d "${TMPDIR}" 2>/dev/null

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
    unzip -qo "$ZIPFILE" 'system/*' -d "${MODPATH}" 2>/dev/null
}

check_data_space(){
    local required_gb=${required_gb:-10} free_gb avail_blocks block_size free_kb

    if command -v stat >/dev/null 2>&1; then
        avail_blocks=$(stat -f -c '%a' /data 2>/dev/null)
        block_size=$(stat -f -c '%S' /data 2>/dev/null)
        [ -n "$avail_blocks" ] && [ -n "$block_size" ] && free_gb=$((avail_blocks * block_size / 1024 / 1024 / 1024))
    fi

    [ -z "$free_gb" ] && free_kb=$(${BUSYBOX} df /data 2>/dev/null | ${BUSYBOX} tail -n1 | ${BUSYBOX} awk '{print $4}') && [ -n "$free_kb" ] && [ "$free_kb" -gt 0 ] 2>/dev/null && free_gb=$((free_kb / 1024 / 1024))

    [ -z "$free_gb" ] && echo "- Warning: Unable to determine free space on /data. Skipping space check..." && return 0
    [ "$free_gb" -lt "$required_gb" ] && echo "- Insufficient space on /data. Required: ${required_gb}GB, Available: ${free_gb}GB. Aborting..." && exit 1
    echo "- /data partition has ${free_gb}GB free space" && return 0
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

    # Try busybox tar first, fall back to system tar
    local TAR_CMD="${BUSYBOX} tar"
    command -v tar &>/dev/null && TAR_CMD="tar"

    if unzip -qo "${ZIPFILE}" "${rootfs_file}" -d "${TMPDIR}" 2>/dev/null && ${TAR_CMD} -xJf "${TMPDIR}/${rootfs_file}" -C "${NHSYS}/kali-${ARCH}" ; then
        ln -sf "${NHSYS}/kali-${ARCH}" "${NHSYS}/kalifs" || error "Failed to create symlink to ${NHSYS}/kalifs"
        echo "- Kali rootfs installed successfully"
    else
        echo "- Failed to install Kali rootfs. Skipping..."
        return 0
    fi
}

install_wireless_firmwares(){
    # Check if vendor/firmware folder exists in the zip
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "vendor/firmware/"; then
        echo "- Installing wireless firmware..."
        mkdir -p "${MODPATH}/system"
        unzip -qo "$ZIPFILE" "vendor/firmware/*" -d "${MODPATH}/system" 2>/dev/null
        return 0
    fi

    # Nothing to do
    return 0
}

apply_nh_wallpaper(){
    echo "- Applying NetHunter wallpaper..."

    # Extract wallpaper and ImageMagick binaries
    unzip -qo "${ZIPFILE}" "wallpaper/*" -d "${TMPDIR}" 2>/dev/null
    [ ! -f "${TMPDIR}/wallpaper/wallpaper.png" ] && echo "- NetHunter wallpaper not found. Skipping..." && return 0

    # Check if ImageMagick is available
    if [ ! -x "${TMPDIR}/wallpaper/${ARCH}/magick" ]; then
        echo "- ImageMagick not found. Skipping wallpaper..."
        return 0
    fi

    # Check if wm command has devpts issues (exit code 2 = broken)
    wm &>/dev/null
    if [ $? -eq 2 ]; then
        echo "- wm command looks broken. Is devpts hooks properly wired up in your KernelSU kernel? Skipping..."
        return 0
    fi

    # Get resolution as WIDTHxHEIGHT
    local res=$(wm size 2>/dev/null | grep "Physical size:" | cut -d' ' -f3)

    if [ -z "$res" ]; then
        echo "- Failed to detect display resolution. Skipping..."
        return 0
    fi

    # Parse width and height
    local width=$(echo "$res" | cut -d'x' -f1)
    local height=$(echo "$res" | cut -d'x' -f2)

    # Validate resolution
    if [ -z "$width" ] || [ -z "$height" ]; then
        echo "- Invalid resolution detected. Skipping..."
        return 0
    fi

    echo "- Detected resolution: ${width}x${height}"

    # Detect tablets by aspect ratio (tablets are typically < 1.7:1)
    # Calculate aspect ratio: height/width * 100 (to avoid floating point)
    local aspect_ratio=$((height * 100 / width))

    # If aspect ratio < 1.7 (i.e., 170), it's likely a tablet
    # Phones are typically 16:9 (1.78), 18:9 (2.0), 19.5:9 (2.17), etc.
    # Tablets are typically 4:3 (1.33) or 16:10 (1.6)
    if [ $aspect_ratio -lt 170 ]; then
        echo "- Tablet detected. Skipping wallpaper to avoid stretching..."
        return 0
    fi

    # Set up ImageMagick with library path
    chmod 755 -R "${TMPDIR}/wallpaper/${ARCH}"
    export LD_LIBRARY_PATH="${TMPDIR}/wallpaper/${ARCH}:${LD_LIBRARY_PATH}"
    local MAGICK="${TMPDIR}/wallpaper/${ARCH}/magick"

    # Resize wallpaper to match screen resolution
    echo "- Resizing wallpaper to ${width}x${height}..."
    if ! ${MAGICK} convert "${TMPDIR}/wallpaper/wallpaper.png" -resize "${width}x${height}^" -gravity center -extent "${width}x${height}" "${TMPDIR}/wallpaper/resized.png" 2>/dev/null; then
        echo "- Failed to resize wallpaper. Skipping..."
        return 0
    fi

    # Apply wallpaper
    echo "- Setting wallpaper..."
    cat "${TMPDIR}/wallpaper/resized.png" > /data/system/users/0/wallpaper 2>/dev/null || {
        echo "- Failed to set wallpaper"
        return 0
    }

    # Create wallpaper info XML with detected resolution
    echo "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><wp width=\"${width}\" height=\"${height}\" name=\"wallpaper.png\" />" > /data/system/users/0/wallpaper_info.xml

    # Set permissions and SELinux contexts
    chown system:system /data/system/users/0/wallpaper /data/system/users/0/wallpaper_info.xml 2>/dev/null
    chmod 0600 /data/system/users/0/wallpaper /data/system/users/0/wallpaper_info.xml 2>/dev/null
    chcon "u:object_r:wallpaper_file:s0" /data/system/users/0/wallpaper 2>/dev/null
    chcon "u:object_r:system_data_file:s0" /data/system/users/0/wallpaper_info.xml 2>/dev/null

    echo "- Wallpaper applied successfully!"
    return 0
}

install_nh_apps(){
    echo "- Installing NetHunter apps..."
    unzip -qo "${ZIPFILE}" 'APKs/*' -d "${TMPDIR}" 2>/dev/null

    # Ensure APK directory exists and contains at least one .apk file
    if [ ! -d "${TMPDIR}/APKs" ] || ! ls "${TMPDIR}/APKs"/*.apk >/dev/null 2>&1; then
        echo "- No NetHunter APK files found. Skipping..."
        return 0
    fi

    # Check if pm command has devpts issues (exit code 2 = broken)
    pm &>/dev/null
    if [ $? -eq 2 ]; then
        echo "- pm command looks broken. Is devpts hooks properly wired up in your KernelSU kernel? Skipping..."
        return 0
    fi

    # remove previous installations
    pm uninstall com.offsec.nethunter &>/dev/null || true
    pm uninstall com.offsec.nethunter.kex &>/dev/null || true
    pm uninstall com.offsec.nhterm &>/dev/null || true
    pm uninstall com.offsec.nethunter.store &>/dev/null || true

    for apk in "${TMPDIR}/APKs"/*.apk; do
        [ ! -f "$apk" ] && continue
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
    pm grant com.offsec.nethunter android.permission.$x &>/dev/null || true
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

# Setup userinit.d (NetHunter-specific)
if [ -d "${MODPATH}/system/etc/init.d" ]; then
    echo "- Setting up userinit.d scripts..."
    rm -rf /data/local/userinit.d 2>/dev/null || true
    mkdir -p "/data/local/userinit.d"
    [ -f "/data/local/userinit.sh" ] || echo "#!/system/bin/sh" > "/data/local/userinit.sh"
    chmod 0755 "/data/local/userinit.sh" 2>/dev/null || true
fi

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
    chcon -R u:object_r:vendor_firmware_file:s0 "${MODPATH}/system/vendor/firmware" 2>/dev/null
    return 0
}

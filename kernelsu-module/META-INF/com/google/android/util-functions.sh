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
        return 0
    fi

    unzip -o "$ZIPFILE" 'busybox/*' -d "${TMPDIR}" >&2

    [ ! -d "${TMPDIR}/busybox" ] && error "Failed to extract busybox. Cannot continue..!"

    mkdir -p "${MODPATH}/system/bin"
    cp "${TMPDIR}/busybox/${ARCH}/busybox" "${MODPATH}/system/bin/busybox" && \
        chmod +x "${MODPATH}/system/bin/busybox" && \
        echo "- busybox installed successfully"
    return 0
}

# export the installed busybox path
export BUSYBOX="${MODPATH}/system/bin/busybox"

install_core(){
    echo "- Installing core files..."
    unzip -o "$ZIPFILE" 'system/*' -d "${MODPATH}" >&2
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
    if ${BUSYBOX} tar -xJf "${TMPDIR}/${rootfs_file}" -C "${NHSYS}/kali-${ARCH}" ; then
        echo "- Kali rootfs installed successfully"
    else
        echo "- Failed to install Kali rootfs"
        return 1
    fi

    ln -sf "${NHSYS}/kali-${ARCH}" "${NHSYS}/kalifs" || error "Failed to create symlink to ${NHSYS}/kalifs"
    return 0
}

#!/system/bin/sh

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

install_core(){
    echo "- Installing core files..."
    unzip -o "$ZIPFILE" 'system/*' -d "${MODPATH}" >&2
}

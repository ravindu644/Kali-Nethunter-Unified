#!/bin/bash

# Copyright (c) 2025 ravindu644
# Automated script to convert Kali Nethunter Generic compatible with KernelSU

SCRIPT_DIR=$(readlink -f $(dirname $0))
DOWNLOAD_LINK="$1"

# Core functions
cd "${SCRIPT_DIR}"
rm -rf workspace && mkdir -p workspace

# logging functions
log() { echo "[INFO] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# print the usage if the download link is not provided
print_usage() {
    echo "Usage: $0 <download_link>"
    echo "Example: $0 https://kali.download/nethunter-images/kali-2025.4/kali-nethunter-2025.4-generic-arm64-full.zip"
    exit 1
}

# download the file
download_nh(){
    export FILENAME=$(basename "$DOWNLOAD_LINK")
    curl -L -o "${SCRIPT_DIR}/workspace/${FILENAME}" "${DOWNLOAD_LINK}" || error "Failed to download the file"
    log "Downloaded the file successfully to ${SCRIPT_DIR}/workspace/${FILENAME}"
    return 0
}

unzip_nh(){
    cd "${SCRIPT_DIR}/workspace"
    unzip "${FILENAME}" && rm "${FILENAME}" || error "Failed to unzip the file"
    log "Unzipped the file successfully to ${SCRIPT_DIR}/workspace"
    return 0
}

collect_info(){
    cd "${SCRIPT_DIR}/workspace"
    local rootfs="$(ls *.tar.xz 2>/dev/null || true)"

    if [ -z "$rootfs" ]; then
        error "No Kali rootfs found. Cannot continue !"
    fi
    log "Found Kali rootfs: $rootfs"

    # Search for all APK files and store their real paths in an array
    export APK_FILES=()
    while IFS= read -r -d '' apk; do
        APK_FILES+=("$(realpath "$apk")")
    done < <(find "${SCRIPT_DIR}/workspace" -name "*.apk" -type f -print0)

    # Error if no APK files found
    if [ ${#APK_FILES[@]} -eq 0 ]; then
        error "No APK files found in workspace"
    fi

    return 0

}

# Main execution
# check if download link is provided
if [ -z "$DOWNLOAD_LINK" ]; then
    print_usage
fi

download_nh
unzip_nh
collect_info

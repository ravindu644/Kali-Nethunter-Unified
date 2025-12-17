#!/bin/bash

# Copyright (c) 2025 ravindu644
# Automated script to convert Kali Nethunter Generic compatible with KernelSU

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
DOWNLOAD_LINK="$1"
WORKSPACE="${SCRIPT_DIR}/workspace"
MODULE_SRC="${SCRIPT_DIR}/kernelsu-module"
MODULE_TMP="${SCRIPT_DIR}/kernelsu-module.tmp"
REQUIRED_GB_DEFAULT=10

# Core functions
cd "${SCRIPT_DIR}"
rm -rf "${WORKSPACE}" && mkdir -p "${WORKSPACE}"

# logging functions
log() { echo "[INFO] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# print the usage if the download link is not provided
print_usage() {
    echo "Usage: $0 <download_link>"
    echo "Example: $0 https://kali.download/nethunter-images/kali-2025.4/kali-nethunter-2025.4-generic-arm64-full.zip"
    exit 1
}

check_requirements(){
    local deps=(curl unzip rsync zip)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep could not be found"
        fi
    done
} && check_requirements

# fetch the NetHunter zip (supports URL or local file)
fetch_nh(){
    if [[ "$DOWNLOAD_LINK" =~ ^https?:// ]]; then
        # Remote URL
        export FILENAME=$(basename "$DOWNLOAD_LINK")
        curl -L -o "${WORKSPACE}/${FILENAME}" "${DOWNLOAD_LINK}" || error "Failed to download the file"
        log "Downloaded the file successfully to ${WORKSPACE}/${FILENAME}"
    else
        # Local file
        if [ ! -f "$DOWNLOAD_LINK" ]; then
            error "Input file not found: $DOWNLOAD_LINK"
        fi
        export FILENAME=$(basename "$DOWNLOAD_LINK")
        cp "$DOWNLOAD_LINK" "${WORKSPACE}/${FILENAME}" || error "Failed to copy local file"
        log "Copied local file to ${WORKSPACE}/${FILENAME}"
    fi

    return 0
}

unzip_nh(){
    cd "${WORKSPACE}"
    unzip "${FILENAME}" && rm "${FILENAME}" || error "Failed to unzip the file"
    log "Unzipped the file successfully to ${WORKSPACE}"
    return 0
}

collect_info(){
    cd "${WORKSPACE}"
    local rootfs
    rootfs="$(ls *.tar.xz 2>/dev/null || true)"

    if [ -z "$rootfs" ]; then
        error "No Kali rootfs found. Cannot continue !"
    fi
    log "Found Kali rootfs: $rootfs"
    export ROOTFS_FILE="${WORKSPACE}/${rootfs}"

    # Detect edition (full/minimal/nano) from rootfs filename and set default required space
    local fs_size
    fs_size=$(basename "$rootfs" | awk -F[-.] '{print $2}')
    case "$fs_size" in
        minimal|nano)
            REQUIRED_GB_DEFAULT=4
            ;;
        *)
            REQUIRED_GB_DEFAULT=10
            ;;
    esac
    log "Using required space: ${REQUIRED_GB_DEFAULT}GB"

    # Read version info from original module.prop if present
    if [ -f "${WORKSPACE}/module.prop" ]; then
        export ORIG_VERSION
        export ORIG_VERSION_CODE
        ORIG_VERSION="$(grep -m1 '^version=' "${WORKSPACE}/module.prop" | cut -d'=' -f2- || true)"
        ORIG_VERSION_CODE="$(grep -m1 '^versionCode=' "${WORKSPACE}/module.prop" | cut -d'=' -f2- || true)"
        [ -n "${ORIG_VERSION}" ] && log "Original version: ${ORIG_VERSION}"
        [ -n "${ORIG_VERSION_CODE}" ] && log "Original versionCode: ${ORIG_VERSION_CODE}"
    else
        log "No module.prop found in workspace; keeping base module version info"
    fi

    # Search for all APK files and store their real paths in an array
    export APK_FILES=()
    while IFS= read -r -d '' apk; do
        APK_FILES+=("$(realpath "$apk")")
    done < <(find "${SCRIPT_DIR}/workspace" -name "*.apk" -type f -print0)

    # Log if no APK files found, but do not abort
    if [ ${#APK_FILES[@]} -eq 0 ]; then
        log "No APK files found in workspace. APK packaging will be skipped."
    else
        log "Found ${#APK_FILES[@]} APK file(s) in workspace"
    fi

    return 0

}

prepare_module_base(){
    [ -d "${MODULE_SRC}" ] || error "Base module directory not found: ${MODULE_SRC}"
    rm -rf "${MODULE_TMP}"
    log "Preparing temporary module at ${MODULE_TMP}"
    rsync -a "${MODULE_SRC}/" "${MODULE_TMP}/" || error "Failed to prepare temporary module directory"
    return 0
}

apply_rootfs_to_module(){
    [ -f "${ROOTFS_FILE}" ] || error "Rootfs file not found: ${ROOTFS_FILE}"
    cp "${ROOTFS_FILE}" "${MODULE_TMP}/" || error "Failed to copy rootfs into module"
    log "Copied rootfs to ${MODULE_TMP}/$(basename "${ROOTFS_FILE}")"
    return 0
}

copy_apks_to_module(){
    mkdir -p "${MODULE_TMP}/APKs"

    if [ ${#APK_FILES[@]} -eq 0 ]; then
        log "No APKs to copy into module. Skipping APK step."
        return 0
    fi

    # Clean any existing placeholders or old APKs
    rm -f "${MODULE_TMP}/APKs/"* 2>/dev/null || true

    for apk in "${APK_FILES[@]}"; do
        cp "$apk" "${MODULE_TMP}/APKs/" || error "Failed to copy APK: $apk"
    done
    log "Copied ${#APK_FILES[@]} APK file(s) into ${MODULE_TMP}/APKs"
    return 0
}

sync_system_overlay(){
    local SRC_SYS="${WORKSPACE}/system"
    local DEST_SYS="${MODULE_TMP}/system"

    if [ ! -d "${SRC_SYS}" ]; then
        log "No system overlay found in workspace. Skipping system sync."
        return 0
    fi

    mkdir -p "${DEST_SYS}"
    rsync -a "${SRC_SYS}/" "${DEST_SYS}/" || error "Failed to sync system overlay"
    log "Synchronized system overlay from workspace to module"
    return 0
}

cleanup_module_junk(){
    log "Cleaning up junk files from temporary module"
    local junk
    for junk in ".git*" "placeholder" "README*" "LICENSE"; do
        find "${MODULE_TMP}" -name "${junk}" -delete 2>/dev/null || true
    done
    return 0
}

update_required_space(){
    local MP="${MODULE_TMP}/module.prop"

    [ -f "${MP}" ] || {
        log "module.prop not found in temporary module; skipping required_gb update"
        return 0
    }

    [ -z "${REQUIRED_GB_DEFAULT}" ] && return 0

    if grep -q '^required_gb=' "${MP}"; then
        sed -i "s/^required_gb=.*/required_gb=${REQUIRED_GB_DEFAULT}/" "${MP}"
    else
        echo "required_gb=${REQUIRED_GB_DEFAULT}" >> "${MP}"
    fi

    log "Set required_gb=${REQUIRED_GB_DEFAULT} in module.prop"
    return 0
}

update_module_prop_version(){
    local MP="${MODULE_TMP}/module.prop"

    [ -f "${MP}" ] || {
        log "module.prop not found in temporary module; skipping version update"
        return 0
    }

    # Only update if original values are present
    if [ -n "${ORIG_VERSION}" ]; then
        if grep -q '^version=' "${MP}"; then
            sed -i "s/^version=.*/version=${ORIG_VERSION}/" "${MP}"
        else
            echo "version=${ORIG_VERSION}" >> "${MP}"
        fi
    fi

    if [ -n "${ORIG_VERSION_CODE}" ]; then
        if grep -q '^versionCode=' "${MP}"; then
            sed -i "s/^versionCode=.*/versionCode=${ORIG_VERSION_CODE}/" "${MP}"
        else
            echo "versionCode=${ORIG_VERSION_CODE}" >> "${MP}"
        fi
    fi

    log "Updated module.prop with original version information (if available)"
    return 0
}

build_unified_zip(){
    cd "${MODULE_TMP}" || error "Failed to cd into ${MODULE_TMP}"
    # Remove .zip extension from original filename before adding -unified.zip
    local BASE_NAME="${FILENAME%.zip}"
    local OUT_ZIP="${SCRIPT_DIR}/${BASE_NAME}-unified.zip"
    log "Creating unified zip: ${OUT_ZIP}"
    zip -r "${OUT_ZIP}" . >/dev/null || error "Failed to create unified zip"
    log "Unified zip created at: ${OUT_ZIP}"
    return 0
}

cleanup_temp_dirs(){
    log "Cleaning up temporary directories..."
    rm -rf "${WORKSPACE}" 2>/dev/null || true
    rm -rf "${MODULE_TMP}" 2>/dev/null || true
    log "Cleanup complete"
    return 0
}

# Main execution
# check if download link is provided
if [ -z "$DOWNLOAD_LINK" ]; then
    print_usage
fi

fetch_nh
unzip_nh
collect_info
prepare_module_base
apply_rootfs_to_module
copy_apks_to_module
sync_system_overlay
cleanup_module_junk
update_required_space
update_module_prop_version
build_unified_zip
cleanup_temp_dirs

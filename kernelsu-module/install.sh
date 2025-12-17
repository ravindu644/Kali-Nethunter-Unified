#!/system/bin/sh

# Copyright (c) 2025 ravindu644
# KernelSU Module Installer Script

# source our functions
unzip -o "$ZIPFILE" 'META-INF/*' -d $TMPDIR >&2
. "$TMPDIR/META-INF/com/google/android/util-functions.sh"
. "$TMPDIR/META-INF/com/google/android/update-binary"

print_modname(){
echo ""
echo "################################################"
echo "#                                              #"
echo "#  88      a8P         db        88        88  #"
echo "#  88    .88'         d88b       88        88  #"
echo "#  88   88'          d8''8b      88        88  #"
echo "#  88 d88           d8'  '8b     88        88  #"
echo "#  8888'88.        d8YaaaaY8b    88        88  #"
echo "#  88P   Y8b      d8''''''''8b   88        88  #"
echo "#  88     '88.   d8'        '8b  88        88  #"
echo "#  88       Y8b d8'          '8b 888888888 88  #"
echo "#                                              #"
echo "###  ############# NetHunter ###################"
print_module_info
}

on_install(){
    log "Installing module..."
    install_busybox
    install_core
    extract_rootfs
}

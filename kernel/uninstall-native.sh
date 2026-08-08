#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="$(uname -r)"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/alc298-book12"
BACKUP_DIR="/var/lib/alc298-book12-native-backup"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this uninstaller with sudo" >&2
    exit 1
fi

rm -f "$MODULE_DIR/snd-hda-codec-alc269.ko"
rmdir "$MODULE_DIR" 2>/dev/null || true

for target in \
    /etc/udev/rules.d/99-alc298-book12-init.rules \
    /etc/systemd/system/alc298-book12-init.service \
    /lib/systemd/system-sleep/alc298-book12-init; do
    backup_name="$(printf '%s' "$target" | tr / _)"
    if [ -e "$BACKUP_DIR/$backup_name" ] && [ ! -e "$target" ]; then
        mv "$BACKUP_DIR/$backup_name" "$target"
    fi
done
rmdir "$BACKUP_DIR" 2>/dev/null || true

depmod -a "$KERNEL_RELEASE"
systemctl daemon-reload
udevadm control --reload-rules

echo "Native module removed and userspace files restored."
echo "Reboot to load the distribution driver."

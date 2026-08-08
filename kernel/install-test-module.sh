#!/bin/bash
set -euo pipefail

CODEC_VENDOR_EXPECTED="0x10ec0298"
CODEC_SUBSYSTEM_EXPECTED="0x144dc14f"
KERNEL_RELEASE="$(uname -r)"
MODULE_SOURCE="${1:-}"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/alc298-book12"
MODULE_DEST="$MODULE_DIR/snd-hda-codec-alc269.ko"
BACKUP_DIR="/var/lib/alc298-book12-native-backup"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this installer with sudo" >&2
    exit 1
fi
if [ -z "$MODULE_SOURCE" ] || [ ! -f "$MODULE_SOURCE" ]; then
    echo "Usage: sudo $0 /path/to/snd-hda-codec-alc269.ko" >&2
    exit 1
fi

codec_found=false
for node in /sys/class/sound/hwC*D*; do
    [ -r "$node/vendor_id" ] || continue
    if [ "$(cat "$node/vendor_id")" = "$CODEC_VENDOR_EXPECTED" ] && \
       [ "$(cat "$node/subsystem_id")" = "$CODEC_SUBSYSTEM_EXPECTED" ]; then
        codec_found=true
        break
    fi
done
if ! $codec_found; then
    echo "ERROR: ALC298 subsystem $CODEC_SUBSYSTEM_EXPECTED was not found" >&2
    exit 1
fi

module_name="$(modinfo -F name "$MODULE_SOURCE")"
module_vermagic="$(modinfo -F vermagic "$MODULE_SOURCE")"
if [ "$module_name" != "snd_hda_codec_alc269" ]; then
    echo "ERROR: unexpected module name: $module_name" >&2
    exit 1
fi
case "$module_vermagic" in
    "$KERNEL_RELEASE "*) ;;
    *)
        echo "ERROR: module vermagic does not match $KERNEL_RELEASE" >&2
        echo "       $module_vermagic" >&2
        exit 1
        ;;
esac

install -d -m 755 "$MODULE_DIR" "$BACKUP_DIR"
install -m 644 "$MODULE_SOURCE" "$MODULE_DEST"

# The native driver must be the only component writing the vendor route.
for old_path in \
    /etc/udev/rules.d/99-alc298-book12-init.rules \
    /etc/systemd/system/alc298-book12-init.service \
    /lib/systemd/system-sleep/alc298-book12-init; do
    if [ -e "$old_path" ]; then
        backup_name="$(printf '%s' "$old_path" | tr / _)"
        mv "$old_path" "$BACKUP_DIR/$backup_name"
    fi
done

systemctl stop alc298-book12-init.service 2>/dev/null || true
systemctl daemon-reload
udevadm control --reload-rules
depmod -a "$KERNEL_RELEASE"

selected="$(modinfo -n snd_hda_codec_alc269)"
if [ "$(readlink -f "$selected")" != "$(readlink -f "$MODULE_DEST")" ]; then
    echo "ERROR: depmod selected an unexpected module: $selected" >&2
    exit 1
fi

echo "Native test module installed: $MODULE_DEST"
echo "The currently loaded driver is unchanged. Reboot to start the test."

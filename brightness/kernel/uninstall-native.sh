#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="${1:-$(uname -r)}"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/galaxybook12-amoled"
MODULE_DEST="$MODULE_DIR/i915.ko"
STATE_DIR="/var/lib/galaxybook12-amoled-native/$KERNEL_RELEASE"
SERVICE="galaxybook12-brightness.service"

case "$KERNEL_RELEASE" in
	"" | *[![:alnum:]._+-]*)
		echo "ERROR: invalid kernel release: $KERNEL_RELEASE" >&2
		exit 1
		;;
esac

rebuild_initramfs() {
	if command -v mkinitcpio >/dev/null 2>&1; then
		mkinitcpio -P
	elif command -v update-initramfs >/dev/null 2>&1; then
		update-initramfs -u -k "$KERNEL_RELEASE"
	elif command -v dracut >/dev/null 2>&1; then
		dracut --force --kver "$KERNEL_RELEASE"
	else
		echo "ERROR: no supported initramfs generator was found" >&2
		return 1
	fi
}

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this uninstaller with sudo" >&2
	exit 1
fi
if [ ! -d "/usr/lib/modules/$KERNEL_RELEASE" ]; then
	echo "ERROR: kernel modules for $KERNEL_RELEASE were not found" >&2
	exit 1
fi

rm -f "$MODULE_DEST"
if [ -f "$STATE_DIR/previous-i915.ko" ]; then
	install -d -m 755 "$MODULE_DIR"
	install -m 644 "$STATE_DIR/previous-i915.ko" "$MODULE_DEST"
fi
rmdir "$MODULE_DIR" 2>/dev/null || true

depmod -a "$KERNEL_RELEASE"
rebuild_initramfs

if [ -f "$STATE_DIR/service-enabled" ]; then
	systemctl enable "$SERVICE" >/dev/null 2>&1 || true
fi
rm -rf -- "$STATE_DIR"
rmdir /var/lib/galaxybook12-amoled-native 2>/dev/null || true

echo "Native AMOLED module removed for $KERNEL_RELEASE."
echo "The previous i915 module will be used after reboot."
echo "The userspace brightness service was re-enabled when appropriate."

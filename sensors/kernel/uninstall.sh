#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="${1:-$(uname -r)}"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/galaxybook12-sensor"
STATE_DIR="/var/lib/galaxybook12-sensor/$KERNEL_RELEASE"
LOAD_FILE="/etc/modules-load.d/galaxybook12-sensor.conf"
MODULES=(st_accel st_accel_i2c)

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

for module in "${MODULES[@]}"; do
	rm -f "$MODULE_DIR/$module.ko"
	if [ -f "$STATE_DIR/previous-$module.ko" ]; then
		install -d -m 755 "$MODULE_DIR"
		install -m 644 "$STATE_DIR/previous-$module.ko" "$MODULE_DIR/$module.ko"
	fi
done
rmdir "$MODULE_DIR" 2>/dev/null || true

if [ -f "$STATE_DIR/previous-modules-load.conf" ]; then
	install -m 644 "$STATE_DIR/previous-modules-load.conf" "$LOAD_FILE"
else
	rm -f "$LOAD_FILE"
fi

depmod -a "$KERNEL_RELEASE"
rebuild_initramfs
rm -rf -- "$STATE_DIR"
rmdir /var/lib/galaxybook12-sensor 2>/dev/null || true

echo "Galaxy Book 12 accelerometer modules removed for $KERNEL_RELEASE."
echo "The distribution modules will be used after reboot."


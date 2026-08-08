#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="$(uname -r)"
MODULE_SOURCE="${1:-}"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/galaxybook12-amoled"
MODULE_DEST="$MODULE_DIR/i915.ko"
STATE_DIR="/var/lib/galaxybook12-amoled-native/$KERNEL_RELEASE"
SERVICE="galaxybook12-brightness.service"

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

restore_failed_install() {
	rm -f "$MODULE_DEST"
	if [ -f "$STATE_DIR/previous-i915.ko" ]; then
		install -m 644 "$STATE_DIR/previous-i915.ko" "$MODULE_DEST"
	fi
	depmod -a "$KERNEL_RELEASE"
	if [ -f "$STATE_DIR/service-enabled" ]; then
		systemctl enable "$SERVICE" >/dev/null 2>&1 || true
	fi
	if [ -f "$STATE_DIR/service-active" ]; then
		systemctl start "$SERVICE" >/dev/null 2>&1 || true
	fi
}

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this installer with sudo" >&2
	exit 1
fi
if [ -z "$MODULE_SOURCE" ] || [ ! -f "$MODULE_SOURCE" ]; then
	echo "Usage: sudo $0 /path/to/i915.ko" >&2
	exit 1
fi
for command in depmod modinfo od systemctl; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "ERROR: missing command: $command" >&2
		exit 1
	fi
done

if [ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)" != \
	 "SAMSUNG ELECTRONICS CO., LTD." ] || \
   [ "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" != \
	 "Galaxy Book 12" ]; then
	echo "ERROR: this is not identified as a Samsung Galaxy Book 12" >&2
	exit 1
fi

panel_found=false
for edid in /sys/class/drm/card*-eDP-*/edid; do
	[ -r "$edid" ] || continue
	read -r vendor_hi vendor_lo product_lo product_hi _ \
		< <(od -An -tx1 -j8 -N4 "$edid")
	if [ "${vendor_hi:-}${vendor_lo:-}${product_lo:-}${product_hi:-}" = \
	     "4c8329a0" ]; then
		panel_found=true
		break
	fi
done
if ! $panel_found; then
	echo "ERROR: Samsung Display panel SDC a029 was not found" >&2
	exit 1
fi

if [ "$(modinfo -F name "$MODULE_SOURCE")" != "i915" ]; then
	echo "ERROR: the supplied file is not an i915 module" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$MODULE_SOURCE")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac

if [ -e "$STATE_DIR/installed" ]; then
	echo "ERROR: the native AMOLED module is already installed for $KERNEL_RELEASE" >&2
	echo "       uninstall it before installing another build" >&2
	exit 1
fi

install -d -m 755 "$MODULE_DIR" "$STATE_DIR"
if [ -f "$MODULE_DEST" ]; then
	install -m 644 "$MODULE_DEST" "$STATE_DIR/previous-i915.ko"
fi
if systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
	touch "$STATE_DIR/service-enabled"
fi
if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
	touch "$STATE_DIR/service-active"
fi
systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true

install -m 644 "$MODULE_SOURCE" "$MODULE_DEST"
depmod -a "$KERNEL_RELEASE"
selected="$(modinfo -n i915)"
if [ "$(readlink -f "$selected")" != "$(readlink -f "$MODULE_DEST")" ]; then
	echo "ERROR: depmod selected an unexpected module: $selected" >&2
	restore_failed_install
	exit 1
fi

if ! rebuild_initramfs; then
	echo "ERROR: initramfs rebuild failed; restoring the previous state" >&2
	restore_failed_install
	rebuild_initramfs || true
	exit 1
fi
touch "$STATE_DIR/installed"

echo "Native AMOLED module installed: $MODULE_DEST"
echo "The userspace brightness service has been disabled."
echo "Reboot to load the new i915 driver."

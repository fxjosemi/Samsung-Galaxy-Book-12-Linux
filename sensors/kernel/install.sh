#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="${KERNEL_RELEASE:-$(uname -r)}"
MODULE_SOURCE_DIR="${1:-}"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/galaxybook12-sensor"
STATE_DIR="/var/lib/galaxybook12-sensor/$KERNEL_RELEASE"
LOAD_FILE="/etc/modules-load.d/galaxybook12-sensor.conf"
MODULES=(st_accel st_accel_i2c)

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
	for module in "${MODULES[@]}"; do
		rm -f "$MODULE_DIR/$module.ko"
		if [ -f "$STATE_DIR/previous-$module.ko" ]; then
			install -m 644 "$STATE_DIR/previous-$module.ko" "$MODULE_DIR/$module.ko"
		fi
	done
	if [ -f "$STATE_DIR/previous-modules-load.conf" ]; then
		install -m 644 "$STATE_DIR/previous-modules-load.conf" "$LOAD_FILE"
	else
		rm -f "$LOAD_FILE"
	fi
	depmod -a "$KERNEL_RELEASE"
}

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this installer with sudo" >&2
	exit 1
fi
if [ -z "$MODULE_SOURCE_DIR" ] || [ ! -d "$MODULE_SOURCE_DIR" ]; then
	echo "Usage: sudo $0 /path/to/module-directory" >&2
	exit 1
fi
for command in depmod modinfo; do
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
if [ ! -d /sys/bus/acpi/devices/SAM0201:00 ]; then
	echo "ERROR: ACPI accelerometer SAM0201 was not found" >&2
	exit 1
fi

for module in "${MODULES[@]}"; do
	source_file="$MODULE_SOURCE_DIR/$module.ko"
	if [ ! -f "$source_file" ]; then
		echo "ERROR: missing module: $source_file" >&2
		exit 1
	fi
	if [ "$(modinfo -F name "$source_file")" != "$module" ]; then
		echo "ERROR: $source_file is not the expected module" >&2
		exit 1
	fi
	case "$(modinfo -F vermagic "$source_file")" in
		"$KERNEL_RELEASE "*) ;;
		*)
			echo "ERROR: $source_file does not match $KERNEL_RELEASE" >&2
			exit 1
			;;
	esac
done

install -d -m 755 "$MODULE_DIR" "$STATE_DIR"
for module in "${MODULES[@]}"; do
	if [ ! -e "$STATE_DIR/installed" ] && [ -f "$MODULE_DIR/$module.ko" ]; then
		install -m 644 "$MODULE_DIR/$module.ko" "$STATE_DIR/previous-$module.ko"
	fi
	install -m 644 "$MODULE_SOURCE_DIR/$module.ko" "$MODULE_DIR/$module.ko"
done
if [ ! -e "$STATE_DIR/installed" ] && [ -f "$LOAD_FILE" ]; then
	install -m 644 "$LOAD_FILE" "$STATE_DIR/previous-modules-load.conf"
fi
printf '%s\n' '# Samsung Galaxy Book 12 K2HH accelerometer' 'st_accel_i2c' > "$LOAD_FILE"

depmod -a "$KERNEL_RELEASE"
for module in "${MODULES[@]}"; do
	selected="$(modinfo -k "$KERNEL_RELEASE" -n "$module")"
	if [ "$(readlink -f "$selected")" != "$(readlink -f "$MODULE_DIR/$module.ko")" ]; then
		echo "ERROR: depmod selected an unexpected $module module: $selected" >&2
		restore_failed_install
		exit 1
	fi
done

if [ "${SKIP_INITRAMFS:-0}" != 1 ] && ! rebuild_initramfs; then
	echo "ERROR: initramfs rebuild failed; restoring the previous state" >&2
	restore_failed_install
	rebuild_initramfs || true
	exit 1
fi
touch "$STATE_DIR/installed"

echo "Galaxy Book 12 accelerometer modules installed for $KERNEL_RELEASE."
echo "Reboot, then check the IIO device and automatic screen rotation."

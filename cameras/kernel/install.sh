#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="$(uname -r)"
MODULE_SOURCE="${1:-}"
BRIDGE_SOURCE="${2:-${MODULE_SOURCE%/*}/ipu-bridge.ko}"
INT3472_SOURCE="${3:-${MODULE_SOURCE%/*}/intel_skl_int3472_discrete.ko}"
VCM_SOURCE="${4:-${MODULE_SOURCE%/*}/dw9806b.ko}"
FRONT_SOURCE="${5:-${MODULE_SOURCE%/*}/imx241.ko}"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/galaxybook12-camera"
MODULE_DEST="$MODULE_DIR/imx258.ko"
BRIDGE_DEST="$MODULE_DIR/ipu-bridge.ko"
INT3472_DEST="$MODULE_DIR/intel_skl_int3472_discrete.ko"
VCM_DEST="$MODULE_DIR/dw9806b.ko"
FRONT_DEST="$MODULE_DIR/imx241.ko"
STATE_DIR="/var/lib/galaxybook12-camera/$KERNEL_RELEASE"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this installer with sudo" >&2
	exit 1
fi
if [ -z "$MODULE_SOURCE" ] || [ ! -f "$MODULE_SOURCE" ] || \
   [ ! -f "$BRIDGE_SOURCE" ] || [ ! -f "$INT3472_SOURCE" ] || \
   [ ! -f "$VCM_SOURCE" ] || [ ! -f "$FRONT_SOURCE" ]; then
	echo "Usage: sudo $0 /path/to/imx258.ko [/path/to/ipu-bridge.ko] [/path/to/intel_skl_int3472_discrete.ko] [/path/to/dw9806b.ko] [/path/to/imx241.ko]" >&2
	exit 1
fi
for command in depmod modinfo modprobe; do
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
if [ ! -e /sys/bus/acpi/devices/SONY258A:00 ]; then
	echo "ERROR: rear Sony IMX258 sensor (SONY258A) was not found" >&2
	exit 1
fi
if [ ! -e /sys/bus/acpi/devices/INT347F:00 ]; then
	echo "ERROR: front Sony IMX241 sensor (INT347F) was not found" >&2
	exit 1
fi
if [ "$(modinfo -F name "$MODULE_SOURCE")" != "imx258" ]; then
	echo "ERROR: the supplied file is not an imx258 module" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$MODULE_SOURCE")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$FRONT_SOURCE")" != "imx241" ]; then
	echo "ERROR: the supplied front-camera file is not an imx241 module" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$FRONT_SOURCE")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: front-camera module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$BRIDGE_SOURCE")" != "ipu_bridge" ]; then
	echo "ERROR: the supplied bridge file is not an ipu_bridge module" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$BRIDGE_SOURCE")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: bridge module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$INT3472_SOURCE")" != "intel_skl_int3472_discrete" ]; then
	echo "ERROR: the supplied control-logic file is not an INT3472 discrete module" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$INT3472_SOURCE")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: INT3472 module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$VCM_SOURCE")" != "dw9806b" ]; then
	echo "ERROR: the supplied autofocus file is not a dw9806b module" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$VCM_SOURCE")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: autofocus module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac

install -d -m 755 "$MODULE_DIR" "$STATE_DIR"
if [ ! -e "$STATE_DIR/installed" ] && [ -f "$MODULE_DEST" ]; then
	install -m 644 "$MODULE_DEST" "$STATE_DIR/previous-imx258.ko"
fi
if [ ! -e "$STATE_DIR/installed" ] && [ -f "$BRIDGE_DEST" ]; then
	install -m 644 "$BRIDGE_DEST" "$STATE_DIR/previous-ipu-bridge.ko"
fi
if [ ! -e "$STATE_DIR/installed" ] && [ -f "$INT3472_DEST" ]; then
	install -m 644 "$INT3472_DEST" "$STATE_DIR/previous-int3472.ko"
fi
if [ ! -e "$STATE_DIR/installed" ] && [ -f "$VCM_DEST" ]; then
	install -m 644 "$VCM_DEST" "$STATE_DIR/previous-dw9806b.ko"
fi
if [ ! -e "$STATE_DIR/installed" ] && [ -f "$FRONT_DEST" ]; then
	install -m 644 "$FRONT_DEST" "$STATE_DIR/previous-imx241.ko"
fi
install -m 644 "$MODULE_SOURCE" "$MODULE_DEST"
install -m 644 "$BRIDGE_SOURCE" "$BRIDGE_DEST"
install -m 644 "$INT3472_SOURCE" "$INT3472_DEST"
install -m 644 "$VCM_SOURCE" "$VCM_DEST"
install -m 644 "$FRONT_SOURCE" "$FRONT_DEST"
depmod -a "$KERNEL_RELEASE"
selected="$(modinfo -n imx258)"
if [ "$(readlink -f "$selected")" != "$(readlink -f "$MODULE_DEST")" ]; then
	echo "ERROR: depmod selected an unexpected module: $selected" >&2
	exit 1
fi
selected_bridge="$(modinfo -n ipu_bridge)"
if [ "$(readlink -f "$selected_bridge")" != "$(readlink -f "$BRIDGE_DEST")" ]; then
	echo "ERROR: depmod selected an unexpected bridge: $selected_bridge" >&2
	exit 1
fi
selected_int3472="$(modinfo -n intel_skl_int3472_discrete)"
if [ "$(readlink -f "$selected_int3472")" != "$(readlink -f "$INT3472_DEST")" ]; then
	echo "ERROR: depmod selected an unexpected INT3472 module: $selected_int3472" >&2
	exit 1
fi
selected_vcm="$(modinfo -n dw9806b)"
if [ "$(readlink -f "$selected_vcm")" != "$(readlink -f "$VCM_DEST")" ]; then
	echo "ERROR: depmod selected an unexpected autofocus module: $selected_vcm" >&2
	exit 1
fi
selected_front="$(modinfo -n imx241)"
if [ "$(readlink -f "$selected_front")" != "$(readlink -f "$FRONT_DEST")" ]; then
	echo "ERROR: depmod selected an unexpected front-camera module: $selected_front" >&2
	exit 1
fi
touch "$STATE_DIR/installed"

echo "Camera modules installed: $MODULE_DEST, $FRONT_DEST, $VCM_DEST, $BRIDGE_DEST and $INT3472_DEST"
echo "Reboot is required so ACPI can rebuild the sensor/control-logic dependency."

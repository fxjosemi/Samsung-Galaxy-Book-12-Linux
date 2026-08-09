#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="$(uname -r)"
MODULE_DIR="/usr/lib/modules/$KERNEL_RELEASE/updates/galaxybook12-camera"
MODULE_DEST="$MODULE_DIR/imx258.ko"
BRIDGE_DEST="$MODULE_DIR/ipu-bridge.ko"
INT3472_DEST="$MODULE_DIR/intel_skl_int3472_discrete.ko"
VCM_DEST="$MODULE_DIR/dw9806b.ko"
FRONT_DEST="$MODULE_DIR/imx241.ko"
STATE_DIR="/var/lib/galaxybook12-camera/$KERNEL_RELEASE"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this uninstaller with sudo" >&2
	exit 1
fi
if [ ! -e "$STATE_DIR/installed" ]; then
	echo "ERROR: no Galaxy Book 12 camera override is recorded for $KERNEL_RELEASE" >&2
	exit 1
fi

modprobe -r imx258 2>/dev/null || true
modprobe -r imx241 2>/dev/null || true
modprobe -r dw9806b 2>/dev/null || true
modprobe -r ipu3_cio2 2>/dev/null || true
modprobe -r ipu_bridge 2>/dev/null || true
modprobe -r intel_skl_int3472_discrete 2>/dev/null || true
rm -f "$MODULE_DEST"
rm -f "$BRIDGE_DEST"
rm -f "$INT3472_DEST"
rm -f "$VCM_DEST"
rm -f "$FRONT_DEST"
if [ -f "$STATE_DIR/previous-imx258.ko" ]; then
	install -m 644 "$STATE_DIR/previous-imx258.ko" "$MODULE_DEST"
fi
if [ -f "$STATE_DIR/previous-ipu-bridge.ko" ]; then
	install -m 644 "$STATE_DIR/previous-ipu-bridge.ko" "$BRIDGE_DEST"
fi
if [ -f "$STATE_DIR/previous-int3472.ko" ]; then
	install -m 644 "$STATE_DIR/previous-int3472.ko" "$INT3472_DEST"
fi
if [ -f "$STATE_DIR/previous-dw9806b.ko" ]; then
	install -m 644 "$STATE_DIR/previous-dw9806b.ko" "$VCM_DEST"
fi
if [ -f "$STATE_DIR/previous-imx241.ko" ]; then
	install -m 644 "$STATE_DIR/previous-imx241.ko" "$FRONT_DEST"
fi
rmdir "$MODULE_DIR" 2>/dev/null || true
depmod -a "$KERNEL_RELEASE"
modprobe ipu3_cio2 2>/dev/null || true
modprobe imx258 2>/dev/null || true
modprobe imx241 2>/dev/null || true
rm -rf "$STATE_DIR"
rmdir /var/lib/galaxybook12-camera 2>/dev/null || true

echo "Galaxy Book 12 camera override removed."

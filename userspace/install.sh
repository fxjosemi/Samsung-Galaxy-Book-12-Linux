#!/bin/bash
set -euo pipefail

VENDOR_EXPECTED="SAMSUNG ELECTRONICS CO., LTD."
PRODUCT_EXPECTED="Galaxy Book 12"
CODEC_VENDOR_EXPECTED="0x10ec0298"
CODEC_SUBSYSTEM_EXPECTED="0x144dc14f"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: ejecute este instalador con sudo" >&2
    exit 1
fi

vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [ "$vendor" != "$VENDOR_EXPECTED" ] || [ "$product" != "$PRODUCT_EXPECTED" ]; then
    echo "ERROR: equipo no compatible: vendor='$vendor', product='$product'" >&2
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
    echo "ERROR: no se encontró ALC298 con SSID $CODEC_SUBSYSTEM_EXPECTED" >&2
    exit 1
fi

if ! command -v hda-verb >/dev/null 2>&1; then
    echo "ERROR: falta hda-verb; instale el paquete alsa-tools" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: falta python3" >&2
    exit 1
fi
if ! command -v systemctl >/dev/null 2>&1 || ! command -v udevadm >/dev/null 2>&1; then
    echo "ERROR: esta instalación requiere systemd y udev" >&2
    exit 1
fi

# Remove the experimental automatic jack router from development snapshots.
# It is unsafe to retain because the incomplete vendor route causes a large
# analog transient in connected headphones on this model.
systemctl disable --now alc298-book12-jack.service 2>/dev/null || true
rm -f /etc/systemd/system/alc298-book12-jack.service
rm -f /usr/local/libexec/alc298-book12-jack-monitor
rm -f /run/alc298-book12-jack-state

install -d -m 755 /usr/local/libexec
install -m 755 "$SCRIPT_DIR/alc298-book12-test.py" \
    /usr/local/libexec/alc298-book12-control
install -m 644 "$SCRIPT_DIR/alc298-book12-init.service" \
    /etc/systemd/system/alc298-book12-init.service
install -m 644 "$SCRIPT_DIR/99-alc298-book12-init.rules" \
    /etc/udev/rules.d/99-alc298-book12-init.rules
install -d -m 755 /lib/systemd/system-sleep
install -m 755 "$SCRIPT_DIR/alc298-book12-sleep.sh" \
    /lib/systemd/system-sleep/alc298-book12-init

systemctl disable alc298-book12-init.service 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed alc298-book12-jack.service 2>/dev/null || true
udevadm control --reload-rules

/usr/local/libexec/alc298-book12-control full --apply
echo "Fix instalado y amplificadores inicializados."

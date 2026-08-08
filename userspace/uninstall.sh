#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: ejecute este desinstalador con sudo" >&2
    exit 1
fi

systemctl stop alc298-book12-init.service 2>/dev/null || true
systemctl disable alc298-book12-init.service 2>/dev/null || true
systemctl disable --now alc298-book12-jack.service 2>/dev/null || true

rm -f /etc/udev/rules.d/99-alc298-book12-init.rules
rm -f /etc/systemd/system/alc298-book12-init.service
rm -f /etc/systemd/system/alc298-book12-jack.service
rm -f /lib/systemd/system-sleep/alc298-book12-init
rm -f /usr/local/libexec/alc298-book12-control
rm -f /usr/local/libexec/alc298-book12-jack-monitor
rm -f /run/alc298-book12-jack-state

systemctl daemon-reload
udevadm control --reload-rules

echo "Fix desinstalado. Un apagado completo restablecerá el estado del codec."

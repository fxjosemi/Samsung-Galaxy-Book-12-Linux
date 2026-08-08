#!/bin/bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf 'Run this uninstaller as root: sudo ./brightness/uninstall.sh\n' >&2
    exit 1
fi

systemctl disable --now galaxybook12-brightness.service 2>/dev/null || true
rm -f /etc/systemd/system/galaxybook12-brightness.service
rm -f /usr/local/sbin/galaxybook12-brightness
systemctl daemon-reload
printf 'AMOLED brightness service removed.\n'

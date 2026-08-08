#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf 'Run this installer as root: sudo ./brightness/install.sh\n' >&2
    exit 1
fi

for command in make cc install systemctl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$command" >&2
        exit 1
    fi
done

make -C "$SCRIPT_DIR"
"$SCRIPT_DIR/galaxybook12-brightness" check

install -Dm0755 "$SCRIPT_DIR/galaxybook12-brightness" \
    /usr/local/sbin/galaxybook12-brightness
install -Dm0644 "$SCRIPT_DIR/galaxybook12-brightness.service" \
    /etc/systemd/system/galaxybook12-brightness.service

systemctl daemon-reload
systemctl enable --now galaxybook12-brightness.service

printf 'AMOLED brightness service installed and started.\n'
printf 'Check it with: systemctl status galaxybook12-brightness.service\n'

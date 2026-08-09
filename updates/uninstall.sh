#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this uninstaller with sudo" >&2
	exit 1
fi

rm -f /etc/pacman.d/hooks/95-galaxybook12-kernel.hook
rm -f /usr/local/libexec/galaxybook12-rebuild-kernels
rm -f /etc/galaxybook12-update.conf
rm -rf -- /usr/local/src/galaxybook12-linux
rm -rf -- /var/lib/galaxybook12-update

echo "Galaxy Book 12 automatic update integration removed."

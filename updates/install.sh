#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_DEST="/usr/local/src/galaxybook12-linux"
CONFIG_DEST="/etc/galaxybook12-update.conf"
HOOK_DEST="/etc/pacman.d/hooks/95-galaxybook12-kernel.hook"
RUNNER_DEST="/usr/local/libexec/galaxybook12-rebuild-kernels"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this installer with sudo" >&2
	exit 1
fi
if ! command -v pacman >/dev/null 2>&1; then
	echo "ERROR: automatic update integration currently supports CachyOS/Arch only" >&2
	exit 1
fi
if [ "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" != "Galaxy Book 12" ]; then
	echo "ERROR: this is not identified as a Samsung Galaxy Book 12" >&2
	exit 1
fi

running_release="$(uname -r)"
pkgbase="$(cat "/usr/lib/modules/$running_release/pkgbase" 2>/dev/null || true)"
if [ -z "$pkgbase" ]; then
	echo "ERROR: cannot determine the package for kernel $running_release" >&2
	exit 1
fi

components=()
[ -e "/usr/lib/modules/$running_release/updates/alc298-book12/snd-hda-codec-alc269.ko" ] && components+=(audio)
[ -e "/usr/lib/modules/$running_release/updates/galaxybook12-amoled/i915.ko" ] && components+=(brightness)
[ -e "/usr/lib/modules/$running_release/updates/galaxybook12-camera/imx258.ko" ] && components+=(cameras)
[ -e "/usr/lib/modules/$running_release/updates/galaxybook12-sensor/st_accel_i2c.ko" ] && components+=(sensors)
if [ "${#components[@]}" -eq 0 ]; then
	echo "ERROR: install at least one native fix before enabling update integration" >&2
	exit 1
fi

staging="$(mktemp -d /usr/local/src/.galaxybook12-linux.XXXXXX)"
cleanup() { rm -rf -- "$staging"; }
trap cleanup EXIT
tar --exclude=.git --exclude='*/build' --exclude='*.ko' --exclude='*.o' \
	-cf - -C "$REPO_ROOT" . | tar -xf - -C "$staging"
rm -rf -- "$SOURCE_DEST"
mv "$staging" "$SOURCE_DEST"
trap - EXIT
chown -R root:root "$SOURCE_DEST"

install -D -m 755 "$SOURCE_DEST/updates/rebuild-kernels.sh" "$RUNNER_DEST"
install -D -m 644 "$SOURCE_DEST/updates/95-galaxybook12-kernel.hook" "$HOOK_DEST"
install -D -m 644 "$SOURCE_DEST/updates/galaxybook12-update.conf" "$CONFIG_DEST"
sed -i "s/^COMPONENTS=.*/COMPONENTS=\"${components[*]}\"/" "$CONFIG_DEST"
sed -i "s/^KERNEL_PACKAGES=.*/KERNEL_PACKAGES=\"$pkgbase\"/" "$CONFIG_DEST"

echo "Automatic rebuilding enabled for: ${components[*]}"
echo "Managed kernel package: $pkgbase"
echo "A separate installed kernel remains untouched as a recovery option."

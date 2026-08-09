#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_RELEASE="$(uname -r)"
JOBS="${JOBS:-2}"

if [ "$(id -u)" -eq 0 ]; then
	echo "ERROR: run ./install.sh all as your normal user; it will ask for sudo once" >&2
	exit 1
fi
if ! command -v pacman >/dev/null 2>&1 || ! grep -qi cachyos /etc/os-release; then
	echo "ERROR: the one-command installer currently supports CachyOS only" >&2
	exit 1
fi
if [ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)" != \
	 "SAMSUNG ELECTRONICS CO., LTD." ] || \
   [ "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" != \
	 "Galaxy Book 12" ]; then
	echo "ERROR: this is not identified as a Samsung Galaxy Book 12" >&2
	exit 1
fi
case "$JOBS" in
	"" | *[!0-9]* | 0) echo "ERROR: JOBS must be a positive integer" >&2; exit 1 ;;
esac

pkgbase="$(cat "/usr/lib/modules/$KERNEL_RELEASE/pkgbase" 2>/dev/null || true)"
if [ -z "$pkgbase" ]; then
	echo "ERROR: cannot determine the package for kernel $KERNEL_RELEASE" >&2
	exit 1
fi

echo "This installs every validated Galaxy Book 12 hardware fix for $KERNEL_RELEASE."
sudo -v
sudo pacman -S --needed --noconfirm \
	base-devel clang llvm curl git xz meson python-jinja python-ply python-yaml \
	libyuv iio-sensor-proxy libcamera-tools gst-plugin-libcamera \
	pipewire-libcamera "$pkgbase-headers"

echo "[1/6] Building kernel drivers (audio, AMOLED, cameras and sensor)..."
KERNEL_RELEASE="$KERNEL_RELEASE" JOBS="$JOBS" "$SCRIPT_DIR/kernel/build-module.sh"
KERNEL_RELEASE="$KERNEL_RELEASE" JOBS="$JOBS" "$SCRIPT_DIR/brightness/kernel/build-module.sh"
KERNEL_RELEASE="$KERNEL_RELEASE" JOBS="$JOBS" "$SCRIPT_DIR/cameras/kernel/build-module.sh"
KERNEL_RELEASE="$KERNEL_RELEASE" JOBS="$JOBS" "$SCRIPT_DIR/sensors/kernel/build-module.sh"

echo "[2/6] Installing kernel drivers..."
sudo env KERNEL_RELEASE="$KERNEL_RELEASE" \
	"$SCRIPT_DIR/kernel/install-native.sh" \
	"$SCRIPT_DIR/kernel/build/$KERNEL_RELEASE/snd-hda-codec-alc269.ko"
sudo env KERNEL_RELEASE="$KERNEL_RELEASE" SKIP_INITRAMFS=1 \
	"$SCRIPT_DIR/brightness/kernel/install-native.sh" \
	"$SCRIPT_DIR/brightness/kernel/build/$KERNEL_RELEASE/i915.ko"
sudo env KERNEL_RELEASE="$KERNEL_RELEASE" \
	"$SCRIPT_DIR/cameras/kernel/install.sh" \
	"$SCRIPT_DIR/cameras/kernel/build/$KERNEL_RELEASE/imx258.ko"
sudo env KERNEL_RELEASE="$KERNEL_RELEASE" SKIP_INITRAMFS=1 \
	"$SCRIPT_DIR/sensors/kernel/install.sh" \
	"$SCRIPT_DIR/sensors/kernel/build/$KERNEL_RELEASE"
sudo mkinitcpio -P

echo "[3/6] Building the matched libcamera and autofocus packages..."
installed_camera="$(pacman -Q libcamera 2>/dev/null | awk '{print $2}' || true)"
camera_target="0.7.2-3.9"
if [ -n "$installed_camera" ] && \
   [ "$(vercmp "$installed_camera" "$camera_target")" -gt 0 ]; then
	echo "NOTICE: libcamera $installed_camera is newer than validated $camera_target."
	echo "The installer will not downgrade it; the camera patch must be reviewed first."
else
	mapfile -t camera_packages < <(
		cd "$SCRIPT_DIR/cameras/libcamera"
		makepkg --packagelist
	)
	(
		cd "$SCRIPT_DIR/cameras/libcamera"
		makepkg --cleanbuild --noconfirm
	)
	if [ "${#camera_packages[@]}" -ne 2 ]; then
		echo "ERROR: expected the libcamera and libcamera-ipa packages" >&2
		exit 1
	fi
	sudo pacman -U --noconfirm "${camera_packages[@]}"
fi

echo "[4/6] Checking the GNOME rotation fix..."
installed_mutter="$(pacman -Q mutter 2>/dev/null | awk '{print $2}' || true)"
case "$installed_mutter" in
	50.4-1|50.4-1.1)
		JOBS="$JOBS" "$SCRIPT_DIR/sensors/mutter/build-arch-package.sh"
		mutter_package="$(find "$SCRIPT_DIR/sensors/mutter/build" -type f \
			-name 'mutter-50.4-1.2-x86_64.pkg.tar.zst' -print -quit)"
		if [ -z "$mutter_package" ]; then
			echo "ERROR: the patched Mutter package was not produced" >&2
			exit 1
		fi
		sudo pacman -U --noconfirm "$mutter_package"
		;;
	50.4-1.2) echo "Patched Mutter is already installed." ;;
	*)
		echo "NOTICE: Mutter $installed_mutter is not the validated 50.4 build."
		echo "The installer will not downgrade it; verify whether it already includes upstream commit 25e48d8b."
		;;
esac

echo "[5/6] Installing automatic kernel-update rebuilding..."
sudo "$SCRIPT_DIR/updates/install.sh"

echo "[6/6] Final checks..."
systemctl --user restart wireplumber.service 2>/dev/null || true
"$SCRIPT_DIR/status.sh"

echo
echo "Installation complete. Reboot once to activate all kernel drivers."
echo "Your other installed kernel family was deliberately left unmodified for recovery."

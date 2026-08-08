#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_NAME="0001-backends-monitor-manager-fix-auto-rotate.patch"
PATCH_FILE="$SCRIPT_DIR/patches/$PATCH_NAME"
ARCH_PACKAGE_REPO="https://gitlab.archlinux.org/archlinux/packaging/packages/mutter.git"
SUPPORTED_VERSION="50.4"
SUPPORTED_RELEASE="1"
PATCHED_RELEASE="1.2"
JOBS="${JOBS:-2}"
OUTPUT_DIR="$SCRIPT_DIR/build"

if [ "$(id -u)" -eq 0 ]; then
	echo "ERROR: run this build as a regular user, not as root" >&2
	exit 1
fi

for command in b2sum git makepkg sed; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "ERROR: missing command: $command" >&2
		exit 1
	fi
done

case "$JOBS" in
	"" | *[!0-9]* | 0)
		echo "ERROR: JOBS must be a positive integer" >&2
		exit 1
		;;
esac

work_dir="$(mktemp -d /tmp/gb12-mutter.XXXXXX)"
cleanup() {
	rm -rf -- "$work_dir"
}
trap cleanup EXIT

echo "Fetching the Arch Linux Mutter package recipe..."
git clone --depth=1 "$ARCH_PACKAGE_REPO" "$work_dir/pkg"

pkgbuild="$work_dir/pkg/PKGBUILD"
pkgver="$(sed -n 's/^pkgver=//p' "$pkgbuild")"
pkgrel="$(sed -n 's/^pkgrel=//p' "$pkgbuild")"
if [ "$pkgver" != "$SUPPORTED_VERSION" ] || \
   [ "$pkgrel" != "$SUPPORTED_RELEASE" ]; then
	echo "ERROR: this patch was validated for mutter $SUPPORTED_VERSION-$SUPPORTED_RELEASE" >&2
	echo "       the current Arch recipe is $pkgver-$pkgrel" >&2
	echo "       check whether the distribution already contains the upstream fix" >&2
	exit 1
fi

install -m 644 "$PATCH_FILE" "$work_dir/pkg/$PATCH_NAME"
patch_sum="$(b2sum "$PATCH_FILE" | cut -d' ' -f1)"

sed -i "s/^pkgrel=$SUPPORTED_RELEASE$/pkgrel=$PATCHED_RELEASE/" "$pkgbuild"
sed -i '/^license=(/i options=(!lto)' "$pkgbuild"
sed -i "/^source=(/a\\  \"$PATCH_NAME\"" "$pkgbuild"
sed -i "/^b2sums=(/a\\  '$patch_sum'" "$pkgbuild"
sed -i "/^  cd mutter$/a\\  git apply \"\$srcdir/$PATCH_NAME\"" "$pkgbuild"
sed -i 's/meson compile -C build$/meson compile -C build -j "${JOBS:-2}"/' "$pkgbuild"

echo "Building patched Mutter $SUPPORTED_VERSION-$PATCHED_RELEASE with $JOBS jobs..."
(
	cd "$work_dir/pkg"
	JOBS="$JOBS" makepkg --syncdeps --noconfirm
)

destination="$OUTPUT_DIR/$SUPPORTED_VERSION-$PATCHED_RELEASE"
mkdir -p "$destination"
find "$work_dir/pkg" -maxdepth 1 -type f -name '*.pkg.tar.zst' \
	-exec install -m 644 {} "$destination/" \;

echo "Packages written to: $destination"
echo "Install only the main package with:"
echo "  sudo pacman -U '$destination/mutter-$SUPPORTED_VERSION-$PATCHED_RELEASE-x86_64.pkg.tar.zst'"

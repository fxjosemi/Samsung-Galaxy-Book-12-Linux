#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="${KERNEL_RELEASE%%-*}"
HEADERS="/usr/lib/modules/$KERNEL_RELEASE/build"
PATCH_FILE="$SCRIPT_DIR/patches/0001-drm-i915-add-Galaxy-Book-12-AMOLED-backlight-support.patch"
SOURCE_TREE="${1:-}"
JOBS="${JOBS:-2}"

if [ ! -d "$HEADERS" ]; then
	echo "ERROR: headers for $KERNEL_RELEASE are not installed" >&2
	exit 1
fi
for command in make patch modinfo sed; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "ERROR: missing command: $command" >&2
		exit 1
	fi
done

if [ -z "$SOURCE_TREE" ]; then
	if ! command -v curl >/dev/null 2>&1; then
		echo "ERROR: curl is required to download the kernel source" >&2
		exit 1
	fi
	major="${KERNEL_VERSION%%.*}"
	cache_dir="$SCRIPT_DIR/build/source-$KERNEL_VERSION"
	local_archive="$SCRIPT_DIR/build/linux-$KERNEL_VERSION.tar.xz"
	shared_archive="$REPO_DIR/kernel/build/linux-$KERNEL_VERSION.tar.xz"
	source_url="https://cdn.kernel.org/pub/linux/kernel/v$major.x/linux-$KERNEL_VERSION.tar.xz"
	SOURCE_TREE="$cache_dir/linux-$KERNEL_VERSION"

	mkdir -p "$SCRIPT_DIR/build"
	if [ -f "$shared_archive" ]; then
		archive="$shared_archive"
	else
		archive="$local_archive"
	fi
	if [ ! -f "$archive" ]; then
		echo "Downloading Linux $KERNEL_VERSION source..."
		curl --fail --location --retry 3 --output "$archive" "$source_url"
	fi
	if [ ! -d "$SOURCE_TREE/drivers/gpu/drm/i915" ]; then
		mkdir -p "$cache_dir"
		tar -xJf "$archive" -C "$cache_dir" \
			"linux-$KERNEL_VERSION/drivers/gpu/drm/i915" \
			"linux-$KERNEL_VERSION/drivers/platform/x86/intel_ips.h"
	fi
fi

SOURCE_TREE="$(readlink -f "$SOURCE_TREE")"
if [ ! -f "$SOURCE_TREE/drivers/gpu/drm/i915/Makefile" ] || \
   [ ! -f "$SOURCE_TREE/drivers/platform/x86/intel_ips.h" ]; then
	echo "ERROR: not a usable Linux source tree: $SOURCE_TREE" >&2
	exit 1
fi

work_dir="$(mktemp -d /tmp/gb12-amoled-i915.XXXXXX)"
cleanup() {
	rm -rf -- "$work_dir"
}
trap cleanup EXIT

i915_dir="$work_dir/drivers/gpu/drm/i915"
mkdir -p "$work_dir/drivers/gpu/drm"
cp -a "$SOURCE_TREE/drivers/gpu/drm/i915" "$i915_dir"
cp "$SOURCE_TREE/drivers/platform/x86/intel_ips.h" "$work_dir/intel_ips.h"
patch -d "$work_dir" -p1 < "$PATCH_FILE"

# These paths are correct for an in-tree build but not for Kbuild's external
# module mode. They are adjusted only in the temporary build tree and are not
# part of the driver patch.
sed -i "s|^#define TRACE_INCLUDE_PATH ../../drivers/gpu/drm/i915$|#define TRACE_INCLUDE_PATH $i915_dir|" \
	"$i915_dir/i915_trace.h" "$i915_dir/intel_uncore_trace.h"
sed -i "s|^#define TRACE_INCLUDE_PATH ../../drivers/gpu/drm/i915/display$|#define TRACE_INCLUDE_PATH $i915_dir/display|" \
	"$i915_dir/display/intel_display_trace.h"
sed -i "s|^#define TRACE_INCLUDE_PATH ../../drivers/gpu/drm/i915/gvt$|#define TRACE_INCLUDE_PATH $i915_dir/gvt|" \
	"$i915_dir/gvt/trace.h"
sed -i "s|^#include \"../../../platform/x86/intel_ips.h\"$|#include \"$work_dir/intel_ips.h\"|" \
	"$i915_dir/gt/intel_rps.c"

make_args=()
if grep -qi clang /proc/version; then
	make_args+=(LLVM=1)
fi

echo "Building i915 for $KERNEL_RELEASE..."
# Module BTF is not needed for this override and makes final linking consume
# several gigabytes on low-memory tablets.
make -C "$HEADERS" M="$i915_dir" modules -j"$JOBS" W=1 \
	CONFIG_DEBUG_INFO_BTF_MODULES= "${make_args[@]}"

output_dir="$SCRIPT_DIR/build/$KERNEL_RELEASE"
output_module="$output_dir/i915.ko"
mkdir -p "$output_dir"
install -m 644 "$i915_dir/i915.ko" "$output_module"
if command -v llvm-strip >/dev/null 2>&1; then
	llvm-strip --strip-debug "$output_module"
elif command -v strip >/dev/null 2>&1; then
	strip --strip-debug "$output_module"
fi

if [ "$(modinfo -F name "$output_module")" != "i915" ]; then
	echo "ERROR: the resulting module has an unexpected name" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$output_module")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: the resulting module does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac

echo "Built module: $output_module"
echo "Install it with: sudo ./brightness/kernel/install-native.sh '$output_module'"

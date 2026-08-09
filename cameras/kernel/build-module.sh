#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="${KERNEL_RELEASE%%-*}"
HEADERS="/usr/lib/modules/$KERNEL_RELEASE/build"
PATCH_FILE="$SCRIPT_DIR/patches/0001-media-imx258-add-26MHz-clock-support.patch"
BRIDGE_PATCH_FILE="$SCRIPT_DIR/patches/0002-media-ipu-bridge-add-Galaxy-Book-12-IMX258.patch"
POWER_RAIL_PATCH_FILE="$SCRIPT_DIR/patches/0003-platform-int3472-map-Galaxy-Book-12-power-rails.patch"
POWER_SEQUENCE_PATCH_FILE="$SCRIPT_DIR/patches/0004-media-imx258-add-Galaxy-Book-12-power-sequence.patch"
ASYNC_PATCH_FILE="$SCRIPT_DIR/patches/0005-media-Galaxy-Book-12-defer-probe-and-skip-VCM.patch"
SOURCE_TREE="${1:-}"
JOBS="${JOBS:-2}"

if [ ! -d "$HEADERS" ]; then
	echo "ERROR: headers for $KERNEL_RELEASE are not installed" >&2
	exit 1
fi
if [ ! -f "$SCRIPT_DIR/dw9806b.c" ] || \
   [ ! -f "$SCRIPT_DIR/imx241.c" ] || \
   [ ! -f "$SCRIPT_DIR/imx241-regs.h" ]; then
	echo "ERROR: missing camera driver source" >&2
	exit 1
fi
for command in make patch modinfo; do
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
	if [ ! -f "$SOURCE_TREE/drivers/media/i2c/imx258.c" ] || \
	   [ ! -f "$SOURCE_TREE/drivers/media/pci/intel/ipu-bridge.c" ] || \
	   [ ! -f "$SOURCE_TREE/drivers/platform/x86/intel/int3472/discrete.c" ]; then
		mkdir -p "$cache_dir"
		tar -xJf "$archive" -C "$cache_dir" \
			"linux-$KERNEL_VERSION/drivers/media/i2c/imx258.c" \
			"linux-$KERNEL_VERSION/drivers/media/pci/intel/ipu-bridge.c" \
			"linux-$KERNEL_VERSION/drivers/platform/x86/intel/int3472/discrete.c" \
			"linux-$KERNEL_VERSION/drivers/platform/x86/intel/int3472/discrete_quirks.c" \
			"linux-$KERNEL_VERSION/drivers/platform/x86/intel/int3472/clk_and_regulator.c" \
			"linux-$KERNEL_VERSION/drivers/platform/x86/intel/int3472/led.c"
	fi
fi

SOURCE_TREE="$(readlink -f "$SOURCE_TREE")"
sensor_source="$SOURCE_TREE/drivers/media/i2c/imx258.c"
bridge_source="$SOURCE_TREE/drivers/media/pci/intel/ipu-bridge.c"
int3472_source_dir="$SOURCE_TREE/drivers/platform/x86/intel/int3472"
if [ ! -f "$sensor_source" ] || [ ! -f "$bridge_source" ] || \
   [ ! -f "$int3472_source_dir/discrete.c" ]; then
	echo "ERROR: not a usable Linux source tree: $SOURCE_TREE" >&2
	exit 1
fi

work_dir="$(mktemp -d /tmp/gb12-imx258.XXXXXX)"
cleanup() {
	rm -rf -- "$work_dir"
}
trap cleanup EXIT

work_media="$work_dir/drivers/media/i2c"
work_bridge="$work_dir/drivers/media/pci/intel"
work_int3472="$work_dir/drivers/platform/x86/intel/int3472"
mkdir -p "$work_media" "$work_bridge" "$work_int3472"
cp "$sensor_source" "$work_media/imx258.c"
cp "$SCRIPT_DIR/dw9806b.c" "$work_media/dw9806b.c"
cp "$SCRIPT_DIR/imx241.c" "$SCRIPT_DIR/imx241-regs.h" "$work_media/"
cp "$bridge_source" "$work_bridge/ipu-bridge.c"
cp "$int3472_source_dir/discrete.c" \
	"$int3472_source_dir/discrete_quirks.c" \
	"$int3472_source_dir/clk_and_regulator.c" \
	"$int3472_source_dir/led.c" "$work_int3472/"
patch -d "$work_dir" -p1 < "$PATCH_FILE"
patch -d "$work_dir" -p1 < "$BRIDGE_PATCH_FILE"
patch -d "$work_dir" -p1 < "$POWER_RAIL_PATCH_FILE"
patch -d "$work_dir" -p1 < "$POWER_SEQUENCE_PATCH_FILE"
patch -d "$work_dir" -p1 < "$ASYNC_PATCH_FILE"
printf '%s\n' 'obj-m += imx258.o' 'obj-m += imx241.o' 'obj-m += dw9806b.o' > "$work_media/Makefile"
printf '%s\n' \
	'obj-m += ipu_bridge.o' \
	'ipu_bridge-y := ipu-bridge.o' > "$work_bridge/Makefile"
printf '%s\n' \
	'obj-m += intel_skl_int3472_discrete.o' \
	'intel_skl_int3472_discrete-y := discrete.o discrete_quirks.o clk_and_regulator.o led.o' \
	> "$work_int3472/Makefile"

make_args=()
if grep -qi clang /proc/version; then
	make_args+=(LLVM=1)
fi

echo "Building Galaxy Book 12 IMX258 module for $KERNEL_RELEASE..."
make -C "$HEADERS" M="$work_media" modules -j"$JOBS" W=1 \
	CONFIG_DEBUG_INFO_BTF_MODULES= "${make_args[@]}"
make -C "$HEADERS" M="$work_bridge" modules -j"$JOBS" W=1 \
	CONFIG_DEBUG_INFO_BTF_MODULES= "${make_args[@]}"
make -C "$HEADERS" M="$work_int3472" modules -j"$JOBS" W=1 \
	CONFIG_DEBUG_INFO_BTF_MODULES= "${make_args[@]}"

output_dir="$SCRIPT_DIR/build/$KERNEL_RELEASE"
output_module="$output_dir/imx258.ko"
output_front="$output_dir/imx241.ko"
output_vcm="$output_dir/dw9806b.ko"
output_bridge="$output_dir/ipu-bridge.ko"
output_int3472="$output_dir/intel_skl_int3472_discrete.ko"
mkdir -p "$output_dir"
install -m 644 "$work_media/imx258.ko" "$output_module"
install -m 644 "$work_media/imx241.ko" "$output_front"
install -m 644 "$work_media/dw9806b.ko" "$output_vcm"
install -m 644 "$work_bridge/ipu_bridge.ko" "$output_bridge"
install -m 644 "$work_int3472/intel_skl_int3472_discrete.ko" "$output_int3472"
if command -v llvm-strip >/dev/null 2>&1; then
	llvm-strip --strip-debug "$output_module"
	llvm-strip --strip-debug "$output_front"
	llvm-strip --strip-debug "$output_vcm"
	llvm-strip --strip-debug "$output_bridge"
	llvm-strip --strip-debug "$output_int3472"
elif command -v strip >/dev/null 2>&1; then
	strip --strip-debug "$output_module"
	strip --strip-debug "$output_front"
	strip --strip-debug "$output_vcm"
	strip --strip-debug "$output_bridge"
	strip --strip-debug "$output_int3472"
fi

if [ "$(modinfo -F name "$output_module")" != "imx258" ]; then
	echo "ERROR: the resulting module has an unexpected name" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$output_module")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$output_front")" != "imx241" ]; then
	echo "ERROR: the resulting front-camera module has an unexpected name" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$output_front")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: front-camera module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$output_vcm")" != "dw9806b" ]; then
	echo "ERROR: the resulting autofocus module has an unexpected name" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$output_vcm")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: autofocus module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$output_bridge")" != "ipu_bridge" ]; then
	echo "ERROR: the resulting bridge module has an unexpected name" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$output_bridge")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: bridge module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac
if [ "$(modinfo -F name "$output_int3472")" != "intel_skl_int3472_discrete" ]; then
	echo "ERROR: the resulting INT3472 module has an unexpected name" >&2
	exit 1
fi
case "$(modinfo -F vermagic "$output_int3472")" in
	"$KERNEL_RELEASE "*) ;;
	*)
		echo "ERROR: INT3472 module vermagic does not match $KERNEL_RELEASE" >&2
		exit 1
		;;
esac

echo "Built modules: $output_module, $output_front, $output_vcm, $output_bridge and $output_int3472"
echo "Install it with: sudo ./cameras/kernel/install.sh '$output_module'"

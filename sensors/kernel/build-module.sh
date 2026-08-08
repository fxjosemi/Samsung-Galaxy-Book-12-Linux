#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="${KERNEL_RELEASE%%-*}"
HEADERS="/usr/lib/modules/$KERNEL_RELEASE/build"
PATCH_FILE="$SCRIPT_DIR/patches/0001-iio-st_accel-add-Samsung-K2HH-ACPI-support.patch"
SOURCE_TREE="${1:-}"
JOBS="${JOBS:-2}"

if [ ! -d "$HEADERS" ]; then
	echo "ERROR: headers for $KERNEL_RELEASE are not installed" >&2
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
	if [ ! -d "$SOURCE_TREE/drivers/iio/accel" ]; then
		mkdir -p "$cache_dir"
		tar -xJf "$archive" -C "$cache_dir" \
			"linux-$KERNEL_VERSION/drivers/iio/accel"
	fi
fi

SOURCE_TREE="$(readlink -f "$SOURCE_TREE")"
accel_source="$SOURCE_TREE/drivers/iio/accel"
for source in st_accel_core.c st_accel_buffer.c st_accel_i2c.c st_accel.h; do
	if [ ! -f "$accel_source/$source" ]; then
		echo "ERROR: not a usable Linux source tree: $SOURCE_TREE" >&2
		exit 1
	fi
done

work_dir="$(mktemp -d /tmp/gb12-st-accel.XXXXXX)"
cleanup() {
	rm -rf -- "$work_dir"
}
trap cleanup EXIT

work_accel="$work_dir/drivers/iio/accel"
mkdir -p "$work_accel"
for source in st_accel_core.c st_accel_buffer.c st_accel_i2c.c st_accel.h; do
	cp "$accel_source/$source" "$work_accel/$source"
done
patch -d "$work_dir" -p1 < "$PATCH_FILE"

printf '%s\n' \
	'obj-m += st_accel.o' \
	'st_accel-y := st_accel_core.o st_accel_buffer.o' \
	'obj-m += st_accel_i2c.o' > "$work_accel/Makefile"

make_args=()
if grep -qi clang /proc/version; then
	make_args+=(LLVM=1)
fi

echo "Building Galaxy Book 12 accelerometer modules for $KERNEL_RELEASE..."
make -C "$HEADERS" M="$work_accel" modules -j"$JOBS" W=1 \
	CONFIG_DEBUG_INFO_BTF_MODULES= "${make_args[@]}"

output_dir="$SCRIPT_DIR/build/$KERNEL_RELEASE"
mkdir -p "$output_dir"
for module in st_accel st_accel_i2c; do
	output_module="$output_dir/$module.ko"
	install -m 644 "$work_accel/$module.ko" "$output_module"
	if command -v llvm-strip >/dev/null 2>&1; then
		llvm-strip --strip-debug "$output_module"
	elif command -v strip >/dev/null 2>&1; then
		strip --strip-debug "$output_module"
	fi
	if [ "$(modinfo -F name "$output_module")" != "$module" ]; then
		echo "ERROR: $output_module has an unexpected module name" >&2
		exit 1
	fi
	case "$(modinfo -F vermagic "$output_module")" in
		"$KERNEL_RELEASE "*) ;;
		*)
			echo "ERROR: $output_module does not match $KERNEL_RELEASE" >&2
			exit 1
			;;
	esac
done

echo "Built modules in: $output_dir"
echo "Install them with: sudo ./sensors/kernel/install.sh '$output_dir'"

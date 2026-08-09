#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
KERNEL_RELEASE="${KERNEL_RELEASE:-$(uname -r)}"
KERNEL_VERSION="${KERNEL_RELEASE%%-*}"
HEADERS="/usr/lib/modules/$KERNEL_RELEASE/build"
PATCH_FILE="$SCRIPT_DIR/patches/0001-sound-hda-realtek-galaxy-book12.patch"
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
    archive="$SCRIPT_DIR/build/linux-$KERNEL_VERSION.tar.xz"
    source_url="https://cdn.kernel.org/pub/linux/kernel/v$major.x/linux-$KERNEL_VERSION.tar.xz"
    SOURCE_TREE="$cache_dir/linux-$KERNEL_VERSION"

    if [ ! -f "$archive" ]; then
        mkdir -p "$SCRIPT_DIR/build"
        echo "Downloading Linux $KERNEL_VERSION source..."
        curl --fail --location --retry 3 --output "$archive" "$source_url"
    fi
    if [ ! -d "$SOURCE_TREE/sound/hda/codecs/realtek" ]; then
        mkdir -p "$cache_dir"
        tar -xJf "$archive" -C "$cache_dir" \
            "linux-$KERNEL_VERSION/sound/hda/codecs" \
            "linux-$KERNEL_VERSION/sound/hda/common"
    fi
fi

SOURCE_TREE="$(readlink -f "$SOURCE_TREE")"
if [ ! -f "$SOURCE_TREE/sound/hda/codecs/realtek/alc269.c" ] || \
   [ ! -d "$SOURCE_TREE/sound/hda/common" ]; then
    echo "ERROR: not a usable Linux source tree: $SOURCE_TREE" >&2
    exit 1
fi

work_dir="$(mktemp -d /tmp/alc298-book12-build.XXXXXX)"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/sound/hda"
cp -a "$SOURCE_TREE/sound/hda/codecs" "$work_dir/sound/hda/"
cp -a "$SOURCE_TREE/sound/hda/common" "$work_dir/sound/hda/"
patch -d "$work_dir" -p1 < "$PATCH_FILE"

make_args=()
if grep -qi clang /proc/version; then
    make_args+=(LLVM=1)
fi

echo "Building for $KERNEL_RELEASE..."
make -C "$HEADERS" \
    M="$work_dir/sound/hda/codecs/realtek" \
    modules -j"$JOBS" W=1 "${make_args[@]}"

output_dir="$SCRIPT_DIR/build/$KERNEL_RELEASE"
output_module="$output_dir/snd-hda-codec-alc269.ko"
mkdir -p "$output_dir"
install -m 644 \
    "$work_dir/sound/hda/codecs/realtek/snd-hda-codec-alc269.ko" \
    "$output_module"

if [ "$(modinfo -F name "$output_module")" != "snd_hda_codec_alc269" ]; then
    echo "ERROR: the resulting module has an unexpected name" >&2
    exit 1
fi

echo "Built module: $output_module"
echo "Install it with: sudo ./kernel/install-native.sh '$output_module'"

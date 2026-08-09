#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
obs_version=32.2.1
build_root=$(mktemp -d /tmp/galaxybook12-obs.XXXXXX)
source_dir="$build_root/obs-studio"
build_dir="$build_root/build"
jobs=${JOBS:-2}

git clone --depth=1 --branch "$obs_version" \
  https://github.com/obsproject/obs-studio.git "$source_dir"
git -C "$source_dir" submodule update --init --depth=1 \
  plugins/obs-browser plugins/obs-websocket
git -C "$source_dir" apply \
  "$script_dir/0001-linux-pipewire-support-enumerated-camera-sizes.patch" \
  "$script_dir/0002-linux-pipewire-handle-contiguous-nv12.patch"

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_AJA=OFF \
  -DENABLE_BROWSER=OFF \
  -DENABLE_DECKLINK=OFF \
  -DENABLE_FRONTEND=OFF \
  -DENABLE_NEW_MPEGTS_OUTPUT=OFF \
  -DENABLE_NVENC=OFF \
  -DENABLE_SCRIPTING=OFF \
  -DENABLE_VLC=OFF \
  -DENABLE_VST=OFF \
  -DENABLE_WEBRTC=OFF \
  -DENABLE_WEBSOCKET=OFF

cmake --build "$build_dir" --target linux-pipewire -j "$jobs"

module="$build_dir/rundir/Release/lib/obs-plugins/linux-pipewire.so"
printf 'Built patched module: %s\n' "$module"

if [[ ${1:-} == --install ]]; then
  installed=/usr/lib/obs-plugins/linux-pipewire.so
  backup=/usr/lib/obs-plugins/linux-pipewire.so.gb12-original

  if [[ ! -e $backup ]]; then
    sudo cp -a "$installed" "$backup"
  fi
  sudo install -m755 "$module" "$installed"
  printf 'Installed patched module; original saved as: %s\n' "$backup"
fi

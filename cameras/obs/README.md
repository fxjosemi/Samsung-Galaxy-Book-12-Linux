# OBS PipeWire camera compatibility

OBS Studio 32.2.1 has two incompatibilities with the Galaxy Book 12 camera
stack. Its experimental PipeWire camera source does not parse enumerated frame
sizes, and its asynchronous video path does not split a contiguous NV12 buffer
into the Y and UV planes expected by libobs. The first issue can leave the
resolution uninitialized; the second produces a green frame followed by a
segmentation fault in `obs_source_output_video()`.

This directory contains the approved upstream enumerated-size fix from
[OBS PR #12509](https://github.com/obsproject/obs-studio/pull/12509) plus the
NV12 plane, offset and stride fix validated on the Galaxy Book 12 IPU3 rear
camera.

Install the build dependencies on Arch/CachyOS, then build and install only the
patched PipeWire module:

```bash
sudo pacman -S --needed base-devel cmake extra-cmake-modules git ninja
./cameras/obs/build-module.sh --install
```

The installer preserves the distribution module as
`/usr/lib/obs-plugins/linux-pipewire.so.gb12-original`. To roll back:

```bash
sudo install -m755 \
  /usr/lib/obs-plugins/linux-pipewire.so.gb12-original \
  /usr/lib/obs-plugins/linux-pipewire.so
```

The fix was tested with OBS 32.2.1, PipeWire 1.6.8 and the rear camera in NV12
at 3840x2160, 30 frames per second. Reapply it after an `obs-studio` package
upgrade until both changes are included upstream.

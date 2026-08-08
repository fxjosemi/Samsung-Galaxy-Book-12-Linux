# Native Realtek driver fix (experimental)

This directory contains the in-progress upstream-style fix for the shared
speaker/headphone output on the 2017 Samsung Galaxy Book 12.

The quirk is selected by the audio subsystem ID `144d:c14f`, rather than a
regional sales suffix. It therefore applies to Galaxy Book 12 Wi-Fi and LTE
variants that expose the same ALC298 audio hardware, including the SM-W720 and
SM-W727 families.

Known model codes include:

- SM-W720NZKAXAR, SM-W720NZKBPHE and SM-W720NZKBMX;
- SM-W727V / SM-W727VZKBVZW, SM-W727A, SM-W727P and SM-W727U.

If one of these variants reports a different codec subsystem ID, collect its
diagnostics before extending the match table. The vendor coefficient sequence
must not be enabled based only on the product name.

## Current implementation

`patches/0001-sound-hda-realtek-galaxy-book12.patch` adds an exact PCI quirk
to `sound/hda/codecs/realtek/alc269.c`. It:

- initializes the two internal amplifiers and the recovered vendor DSP table;
- listens to jack presence on mic pin `0x18`, which is the reliable insertion
  signal on this tablet;
- mutes shared output pin `0x17` while selecting the speaker or headphone
  vendor route;
- reapplies initialization and the current route after codec resume.

This first native test deliberately retains DAC `0x02` and mixer `0x0c` for
both routes. That is the path on which the recovered headphone coefficients
already produced correct, volume-controlled sound during hardware testing.
Moving the jack to DAC `0x03` / mixer `0x0d` remains a later experiment because
it would also require integrating DAC `0x03` with ALSA's playback volume.

## Build result on the test tablet

The patch has been compiled against Linux `7.1.6-1-cachyos` with Clang 22 and
`W=1`. The resulting module has matching vermagic. No live jack test has yet
been recorded for this native version.

The local build used:

```bash
make -C /usr/lib/modules/$(uname -r)/build \
  M=/path/to/linux-source/sound/hda/codecs/realtek \
  modules LLVM=1 W=1
```

## Reversible test installation

After building, install the patched module with its explicit path:

```bash
sudo ./kernel/install-test-module.sh \
  /path/to/snd-hda-codec-alc269.ko
```

The installer checks the codec IDs and module vermagic, places the module in
the kernel `updates` directory, and temporarily backs up the old userspace
initializer so it cannot overwrite the native route. Reboot is required.

To roll back:

```bash
sudo ./kernel/uninstall-test-module.sh
sudo reboot
```

Begin the first insertion test with playback stopped and the mixer at low
volume. Confirm that silence remains silence before starting audio.

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
- mirrors the front stream to headphone DAC `0x03` and switches pin `0x17`
  from speaker mixer `0x0c` to headphone mixer `0x0d`;
- keeps the DAC `0x02` and DAC `0x03` hardware volume values synchronized;
- disables pin `0x17` and EAPD whenever the analog PCM is closed, then restores
  them only while playback is open;
- reapplies initialization and the current route after codec resume.

During route changes the shared pin is muted and temporarily disabled before
its connection selector and pin mode change. When PipeWire suspends the sink,
the jack output remains electrically disabled. This sequencing is intended to
remove the insertion transient without adding a userspace delay.

## Build result on the test tablet

The first native version was tested on real hardware. It selected headphones
automatically and produced Windows-like audio, but retained a strong insertion
click and extremely faint left-to-right crosstalk because it still used speaker
DAC `0x02` and mixer `0x0c` for the jack.

The dedicated-DAC revision removed the crosstalk and otherwise worked
correctly, but the insertion click remained because pin `0x17` and EAPD stayed
enabled while ALSA reported the PCM as closed and PipeWire reported the sink as
suspended.

The idle-power revision was also tested. The insertion click remained with all
of the following conditions verified simultaneously: PCM closed, pin `0x17`
disabled, EAPD disabled, mic pin `0x18` at `VREF_HIZ`, and the codec runtime
suspended. Its pitch changed slightly during full codec suspension, but its
level did not materially improve.

The recovered Windows-derived repository contains only the five vendor route
writes used here and no additional depop sequence. Further blind changes to
undocumented coefficients are therefore not considered safe. The insertion
transient is retained as a known hardware limitation; automatic routing,
dedicated headphone DAC, channel separation and volume control work correctly.

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

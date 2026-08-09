# Native ALC298 fix

The patch in this directory adds a Realtek HDA quirk for Samsung subsystem
`144d:c14f`. It has been tested on a Galaxy Book 12 SM-W720 running Linux
7.1.6.

## Build and install

From the repository root:

```bash
./kernel/build-module.sh
sudo ./kernel/install-native.sh \
  "kernel/build/$(uname -r)/snd-hda-codec-alc269.ko"
sudo reboot
```

See [../INSTALL.md](../INSTALL.md) for dependencies, verification and removal.
After a manual installation, `sudo ./install.sh updates` enables automatic
rebuilding on CachyOS kernel updates; see
[the update guide](../updates/README.md).

## Driver changes

The quirk:

- initializes amplifier selectors `0x31` and `0x34`;
- restores the vendor DSP/routing coefficients at codec initialization;
- uses mic pin `0x18` for jack presence;
- routes speakers through DAC `0x02` / mixer `0x0c`;
- routes headphones through DAC `0x03` / mixer `0x0d`;
- mirrors the playback stream and hardware volume to DAC `0x03`;
- disables shared pin `0x17` and EAPD while playback is closed.

The patch applies to:

```text
sound/hda/codecs/realtek/alc269.c
sound/hda/codecs/realtek/realtek.h
```

## Test result

Speakers, automatic jack switching, stereo separation, volume control and
suspend/resume are working on the test machine.

Jack insertion still produces a short click. It was reproduced with PCM
closed, pin `0x17` disabled, EAPD disabled, mic bias at `VREF_HIZ`, and the
codec runtime-suspended. The original Windows-derived routing scripts contain
no additional depop sequence, so the click is documented rather than hidden by
untested coefficient writes.

# Samsung Galaxy Book 12 audio on Linux

This repository fixes the Realtek ALC298 audio found in the 2017 Samsung
Galaxy Book 12. It was developed and tested on an SM-W720 with audio subsystem
ID `144d:c14f`.

The native driver patch provides:

- working internal speakers;
- automatic switching between speakers and the 3.5 mm jack;
- separate speaker and headphone DAC paths;
- working stereo separation and volume control;
- correct routing after suspend and resume.

There is one known limitation: plugging in the jack produces a short click.
The click remains even when the codec output, EAPD and microphone bias are
disabled. Everything after insertion works normally.

## Supported hardware

The fix is matched by the codec IDs, not by the regional product suffix:

```text
Codec:      Realtek ALC298 (10ec:0298)
Subsystem:  Samsung 144d:c14f
```

This ID is used by the SM-W720 and SM-W727 Galaxy Book 12 family. The installer
refuses to continue if it does not find the exact codec and subsystem IDs.

## Installation

The native driver is the recommended option. Install the headers for the
kernel you are currently running, then build and install the module:

```bash
git clone https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux.git
cd Samsung-Galaxy-Book-12-Linux
./kernel/build-module.sh
sudo ./kernel/install-native.sh \
  "kernel/build/$(uname -r)/snd-hda-codec-alc269.ko"
sudo reboot
```

The build script downloads the matching kernel.org source when no source tree
is supplied. See [INSTALL.md](INSTALL.md) for dependencies, verification,
kernel updates and removal.

There is also an older speaker-only userspace workaround:

```bash
sudo ./install.sh
```

It is useful when building a kernel module is not possible, but it does not
switch the headphone route. Installing the native module automatically disables
this workaround so both implementations cannot write the codec at once.

## How it works

The firmware leaves two internal amplifiers uninitialized and describes the
shared output pin `0x17` only as a fixed speaker. The patch adds a quirk for
`144d:c14f`, initializes both amplifiers, uses mic pin `0x18` as the reliable
jack detector, and switches the shared output between:

```text
Speakers:    DAC 0x02 -> mixer 0x0c -> pin 0x17
Headphones:  DAC 0x03 -> mixer 0x0d -> pin 0x17
```

The amplifier and routing tables come from Aurélien Croc's GPL-2.0
[Windows/QEMU trace work](https://github.com/Teetoow/SamsungGalaxyBook12).
Technical notes are in [docs/hardware.md](docs/hardware.md).

## Contributing

Reports from other SM-W720 and SM-W727 variants are welcome. Include the output
of `userspace/collect-diagnostics.sh` and do not test vendor coefficient writes
on a different subsystem ID.

The project is licensed under GPL-2.0-only. See [LICENSE](LICENSE).

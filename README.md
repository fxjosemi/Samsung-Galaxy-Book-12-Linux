# Samsung Galaxy Book 12 ALC298 Linux audio

Linux audio support for the 2017 Samsung Galaxy Book 12 (SM-W720/SM-W727) with
the Realtek ALC298 codec.

The machine is identified by:

- DMI product: `Galaxy Book 12`
- codec vendor ID: `0x10ec0298`
- codec subsystem ID: `0x144dc14f`

Without a model-specific codec fixup, Linux leaves the codec-internal speaker
amplifiers uninitialized. The speakers are silent, and the combo jack does not
select the Windows vendor route even though its buttons and insertion switch
are reported by the kernel.

## Project status

The userspace workaround has been tested on the real hardware:

- both internal speaker channels work;
- the speaker amplifier is restored after suspend.

Automatic headphone routing is intentionally not installed. The recovered
vendor route produces a large analog transient in the headphones even with no
PCM playback. A safe fix needs native driver control of the separate Windows
headphone path (DAC `0x03` and mixer `0x0d`).

Tested environment:

- Samsung Galaxy Book 12 / SM-W720;
- board `SM-W720NZKBPHE`;
- ALC298 subsystem `144d:c14f`;
- CachyOS with Linux `7.1.6-1-cachyos`.

This repository contains the guarded, known-working userspace implementation
and an experimental native ALSA HDA quirk. The native work lives under
[`kernel/`](kernel/README.md) and is kept separate from the default installer
until its jack switching has passed hardware testing.

The native quirk matches audio subsystem `144d:c14f`, not a regional product
suffix. It is intended to cover Wi-Fi and LTE Galaxy Book 12 variants with the
same audio hardware. Known SM-W720 and SM-W727 sales codes are listed in the
native-driver documentation.

## Userspace installation

Install the runtime dependency:

```bash
# Arch Linux
sudo pacman -S alsa-tools

# Debian or Ubuntu
sudo apt install alsa-tools
```

Then install the fix from the repository root:

```bash
sudo ./install.sh
```

The installer refuses to write codec coefficients unless both the DMI product
and the exact ALC298 subsystem ID match. A hardware-specific udev rule starts
initialization only after that codec device exists.

To uninstall:

```bash
sudo ./uninstall.sh
```

After installation or a reboot, check the detected hardware and last
initialization result with:

```bash
./status.sh
```

## Hardware findings

- speaker pin: NID `0x17`;
- playback path: DAC `0x02` -> mixer `0x0c` -> pin `0x17`;
- left internal amplifier selector: COEF `0x22 = 0x31`;
- right internal amplifier selector: COEF `0x22 = 0x34`;
- vendor routing/DSP selector: COEF `0x22 = 0x1b`;
- combo-jack insertion is exposed as `SW_MICROPHONE_INSERT` by the
  `HDA Intel PCH Mic` input device.

The amplifier and DSP sequences are derived from Aurélien Croc's GPL-2.0
Windows/QEMU trace analysis for this exact model:
<https://github.com/Teetoow/SamsungGalaxyBook12>.

See [`docs/hardware.md`](docs/hardware.md) for the tested routes and codec
findings. The repeatable validation procedure is in
[`docs/testing.md`](docs/testing.md).

## Safety

Realtek vendor COEF registers are undocumented and hardware-specific. Do not
run this code on a different subsystem ID. Begin testing at low volume and stop
on distortion, imbalance, unexpected heat, or noise. A complete power-off
resets the codec and its internal amplifiers.

## License

GPL-2.0-only. See [`LICENSE`](LICENSE).

Contributions and reports from the exact hardware are welcome. Read
[`CONTRIBUTING.md`](CONTRIBUTING.md) before testing vendor COEF changes.

# Samsung Galaxy Book 12 on Linux

Compatibility fixes for the 2017 Samsung Galaxy Book 12 family. The project is
developed on an SM-W720 and is intended for the Wi-Fi and LTE variants that
share the same board hardware.

Each component has its own hardware checks, installer and removal procedure.
You can install only the fixes you need.

## Current fixes

### ALC298 audio

The native Realtek driver patch provides:

- working internal speakers;
- automatic switching between speakers and the 3.5 mm jack;
- separate speaker and headphone DAC paths;
- working stereo separation and volume control;
- correct routing after suspend and resume.

It matches codec `10ec:0298` with Samsung subsystem `144d:c14f`, rather than a
regional model suffix. A short click when inserting the jack remains as a known
hardware limitation.

Installation:

```bash
./kernel/build-module.sh
sudo ./kernel/install-native.sh \
  "kernel/build/$(uname -r)/snd-hda-codec-alc269.ko"
sudo reboot
```

See [INSTALL.md](INSTALL.md) for dependencies and kernel-update instructions.
The older speaker-only userspace fallback remains available through
`sudo ./install.sh`.

### AMOLED brightness

Linux exposes a brightness slider on this machine but does not program the
panel's private AMOLED controls. The brightness component follows the standard
`intel_backlight` slider and sends the corresponding calibrated values over the
internal eDP AUX channel.

It verifies the Galaxy Book 12 DMI identity, the internal eDP connector and the
Samsung Display `SDC a029` EDID before allowing any panel write. The full Linux
slider is mapped to the stable panel range 40–101 because lower panel values
are known to flicker.

Build and perform the read-only check:

```bash
make -C brightness
./brightness/galaxybook12-brightness check
```

Install the service:

```bash
sudo ./brightness/install.sh
```

The equivalent top-level command is `sudo ./install.sh brightness`.

More details and manual testing commands are in
[brightness/README.md](brightness/README.md).

## Supported family

The fixes are expected to cover the SM-W720 Wi-Fi and SM-W727 LTE families,
including regional and carrier suffixes, as long as the component-specific
hardware IDs match. Installers stop instead of forcing a fix onto unknown
hardware.

## How the audio fix works

The firmware leaves two internal amplifiers uninitialized and describes shared
output pin `0x17` only as a fixed speaker. The patch initializes both
amplifiers, uses mic pin `0x18` as the reliable jack detector and switches the
shared output between:

```text
Speakers:    DAC 0x02 -> mixer 0x0c -> pin 0x17
Headphones:  DAC 0x03 -> mixer 0x0d -> pin 0x17
```

The audio and display register research is based on Aurélien Croc's GPL-2.0
[Windows/QEMU trace work](https://github.com/Teetoow/SamsungGalaxyBook12).

## Contributing

Reports from other SM-W720 and SM-W727 variants are welcome. Include the exact
model, distribution, kernel version and the hardware IDs relevant to the
component being tested. Do not bypass the safety checks on unrelated hardware.

The project is licensed under GPL-2.0-only. See [LICENSE](LICENSE).

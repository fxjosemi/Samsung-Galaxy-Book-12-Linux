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
Samsung Display `SDC a029` EDID before allowing any panel write. By default the
full Linux slider is mapped to panel levels 10–101 with a short fade between
levels. The minimum was tested on the development SM-W720; the original
reverse-engineering work warned that some panels may flicker below 40.

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

A native `i915` implementation is also included. It reads the same factory
calibration inside the driver, exposes levels 10–101 directly and does not use
a service or fade. It has been tested on the development SM-W720 with Linux
7.1.6:

```bash
./brightness/kernel/build-module.sh
sudo ./brightness/kernel/install-native.sh \
  "brightness/kernel/build/$(uname -r)/i915.ko"
sudo reboot
```

Keep another kernel installed while testing the native graphics module. Its
installer preserves the distribution driver and provides a rollback script.

More details and manual testing commands are in
[brightness/README.md](brightness/README.md).

### Accelerometer and screen rotation

Samsung exposes the internal K2HH accelerometer as ACPI device `SAM0201`, but
the standard ST accelerometer driver does not match that ID. The sensor patch
binds it to the compatible LIS2HH12 implementation and reads the `ROTM` mount
matrix provided by the firmware. GNOME then receives all four orientations
through the normal IIO and `iio-sensor-proxy` interfaces.

Build and install the two small IIO modules:

```bash
./sensors/kernel/build-module.sh
sudo ./sensors/kernel/install.sh \
  "sensors/kernel/build/$(uname -r)"
sudo reboot
```

The complete implementation has been tested across a cold boot on the
development SM-W720 with Linux 7.1.6 and GNOME/Mutter 50.4: the panel follows
rotation and the firmware axis mapping is correct.  Mutter 50.4 also needs an
upstream session-start fix on this device; a reproducible native Arch/CachyOS
package is included.  See [sensors/README.md](sensors/README.md) for diagnosis,
installation and removal instructions.

### Cameras

The tablet has Intel IPU3, a rear Sony IMX258 (`SONY258A`) and a front Sony
IMX241 (`INT347F`). The rear sensor needs a 26 MHz clock table, an IPU bridge
entry, Samsung-specific power/reset handling and a DW9806B autofocus driver. A
native, reversible four-module override is included:

```bash
./cameras/kernel/build-module.sh
sudo ./cameras/kernel/install.sh \
  "cameras/kernel/build/$(uname -r)/imx258.ko"
sudo reboot
```

The front sensor is detected but does not yet have a mainline Linux driver.
See [cameras/README.md](cameras/README.md) for the verified hardware findings,
libcamera packages, status checks and current limitation.

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

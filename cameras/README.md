# Cameras

The Galaxy Book 12 uses Intel IPU3 with two MIPI sensors, not the IPU6/IPU7
stack used by later Galaxy Books:

| Position | Sensor | ACPI ID | Linux status |
|---|---|---|---|
| Rear | Sony IMX258, 13 MP, DW9806B AF | `SONY258A` | Supported by the native override below |
| Front | Sony IMX241, 5 MP | `INT347F` | Supported by this project's native V4L2 driver |

The IPU3 CIO2 and ImgU drivers and firmware are already present on the tested
SM-W720. The firmware compatibility gaps preventing both sensors from binding
are handled in one kernel override:

- upstream `imx258` lacks Samsung's 26 MHz clock configuration (the official
  tables use 650 and 321.75 MHz CSI-2 link frequencies);
- `ipu-bridge` does not list the `SONY258A` ACPI ID;
- Samsung uses the original Intel control-logic GPIO names `IO`, `Avdd` and
  `Core`, encoded as `0x0f`, `0x10` and `0x11`;
- the board requires its private camera-power ACPI method and a physical reset
  pulse around the standard IMX258 power sequence;
- the firmware advertises a DW9806B autofocus actuator, for which Linux 7.1
  has no driver; without one the V4L2 asynchronous graph cannot complete.

The build creates `imx258`, `imx241`, `dw9806b`, `ipu_bridge` and
`intel_skl_int3472_discrete` modules. The old GPIO meanings, IMX241 mode tables
and DW9806B register
sequence were verified in Samsung's official 2017 Windows driver rather than
inferred from pin order. The sensor rails map to `vif`, `vana` and `vdig`; the
separate `0x0e` line powers the autofocus actuator. The bridge publishes the
firmware's lens reference, and an early IMX258 probe defers until the IPU bridge
endpoint exists, avoiding an order-dependent boot failure.

## Native camera fix

Build the small native driver override for the running kernel:

```bash
./cameras/kernel/build-module.sh
```

Install the module path printed by the build, then reboot. A reboot is
mandatory because Linux constructs the ACPI dependency between `SONY258A` and
`INT3472:01` only during device enumeration:

```bash
sudo ./cameras/kernel/install.sh \
  "cameras/kernel/build/$(uname -r)/imx258.ko"
sudo reboot
```

Build and install the matched IPU3 userspace stack. The local package includes
the IMX241 sensor helper and signs the IPA with the matching libcamera key:

```bash
cd cameras/libcamera
makepkg --cleanbuild --noconfirm
sudo pacman -U ./libcamera-0.7.2-3.9-x86_64.pkg.tar.zst \
  ./libcamera-ipa-0.7.2-3.9-x86_64.pkg.tar.zst
sudo pacman -S libcamera-tools gst-plugin-libcamera pipewire-libcamera
systemctl --user restart wireplumber pipewire
```

Verify the sensor binding, media graph and libcamera enumeration:

```bash
./cameras/status.sh
cam -l
```

The status command reports `DW9806B bound` when the actuator is available. Its
V4L2 lens subdevice exposes the actuator's 10-bit `focus_absolute` control from
0 to 1023 so the useful per-module calibration range can be measured.

Remove the kernel override with:

```bash
sudo ./cameras/kernel/uninstall.sh
```

## OBS Studio

OBS Studio 32.2.1 does not correctly parse the discrete PipeWire resolution
list and assumes an invalid memory layout for contiguous NV12 camera buffers.
On IPU3 this appears as a green frame followed by a segmentation fault. The
project includes a patched `linux-pipewire.so` build that preserves the normal
libcamera processing and autofocus path. It has been validated with the rear
camera at 3840x2160 and 30 FPS. See [obs/README.md](obs/README.md).

## Front-camera driver

The firmware exposes `INT347F`, identified by Samsung's official Windows
package as Sony IMX241. Linux has no mainline IMX241 sensor driver, so this
project provides a dedicated GPL V4L2 driver rather than binding an unrelated
Sony sensor driver.

Static analysis followed by a live read has recovered the `0x0241` chip ID at
registers `0x0000`–`0x0001`, complete RAW10 tables for 2592x1944 and 1296x972 with the
tablet's 26 MHz clock, and the matching per-module AIQB calibration. Live ACPI
inspection also confirms two CSI-2 lanes and five DSC1 resources: reset, clock,
and the legacy `IO`, `Avdd` and `Core` rails (`0x0f`, `0x10`, `0x11`). The front
and rear controllers use the same private on/off UUIDs while maintaining
separate `FCAM`/`RCAM` state for the shared camera LED. The driver exposes both
recovered modes, powers the sensor only while it is in use, verifies chip ID
`0x0241`, and binds it to the ordinary IPU3 media graph as a RAW10 camera.

Its 360.966667 MHz CSI-2 link frequency and 144.386667 MPixel/s pixel rate are
derived from the official 26 MHz PLL registers (`833 / 15 / 10`) and the
two-lane RAW10 transport, rather than selected experimentally.

## Kernel updates and rollback

The modules are tied to the exact kernel release shown by `uname -r`. Rebuild,
reinstall and reboot after each kernel update. The installer verifies the DMI
identity, sensor ACPI ID, module names and `vermagic` before copying anything.
Rollback removes all five camera modules:

```bash
sudo ./cameras/kernel/uninstall.sh
sudo reboot
```

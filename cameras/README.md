# Cameras

The Galaxy Book 12 uses Intel IPU3 with two MIPI sensors, not the IPU6/IPU7
stack used by later Galaxy Books:

| Position | Sensor | ACPI ID | Linux status |
|---|---|---|---|
| Rear | Sony IMX258, 13 MP, DW9806B AF | `SONY258A` | Supported by the native four-module override below |
| Front | Sony IMX241, 5 MP | `INT347F` | No mainline Linux sensor driver |

The IPU3 CIO2 and ImgU drivers and firmware are already present on the tested
SM-W720. Four firmware compatibility gaps prevent the rear sensor from
binding:

- upstream `imx258` lacks Samsung's 26 MHz clock configuration;
- `ipu-bridge` does not list the `SONY258A` ACPI ID;
- Samsung uses the original Intel control-logic GPIO names `IO`, `Avdd` and
  `Core`, encoded as `0x0f`, `0x10` and `0x11`;
- the board requires its private camera-power ACPI method and a physical reset
  pulse around the standard IMX258 power sequence.
- the firmware advertises a DW9806B autofocus actuator, for which Linux 7.1
  has no driver; without one the V4L2 asynchronous graph cannot complete.

The build creates overrides for `imx258`, `dw9806b`, `ipu_bridge` and
`intel_skl_int3472_discrete`. The old GPIO meanings and DW9806B register
sequence were verified in Samsung's official 2017 Windows driver rather than
inferred from pin order. The sensor rails map to `vif`, `vana` and `vdig`; the
separate `0x0e` line powers the autofocus actuator. The bridge publishes the
firmware's lens reference, and an early IMX258 probe defers until the IPU bridge
endpoint exists, avoiding an order-dependent boot failure.

## Rear-camera fix

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

Install the IPU3 userspace stack. On Arch/CachyOS:

```bash
sudo pacman -S libcamera libcamera-ipa libcamera-tools \
  gst-plugin-libcamera pipewire-libcamera
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

## Front-camera limitation

The firmware exposes `INT347F`, identified by Samsung's Windows package and
contemporary Galaxy Book 12 specifications as Sony IMX241. Linux has no IMX241
sensor driver, register tables or libcamera tuning data. The generic IPU3
drivers cannot replace that sensor-specific layer. Binding an unrelated Sony
driver would risk invalid register writes, so this project deliberately does
not claim or force the front device.

Adding front-camera support requires a new GPL sensor driver based on public
IMX241 programming information or a legally redistributable register table,
plus libcamera tuning calibrated on this tablet.

## Kernel updates and rollback

The modules are tied to the exact kernel release shown by `uname -r`. Rebuild,
reinstall and reboot after each kernel update. The installer verifies the DMI
identity, sensor ACPI ID, module names and `vermagic` before copying anything.
Rollback removes all four overrides:

```bash
sudo ./cameras/kernel/uninstall.sh
sudo reboot
```

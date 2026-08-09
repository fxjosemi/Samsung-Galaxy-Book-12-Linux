# Accelerometer and automatic rotation

The Galaxy Book 12 contains a Samsung K2HH three-axis accelerometer.  Its ACPI
device uses ID `SAM0201`, which is not matched by the standard Linux ST
accelerometer driver.  Without that match there is no IIO device and desktop
environments cannot rotate the display automatically.

The kernel patch maps `SAM0201` to the compatible LIS2HH12 implementation and
reads the `ROTM` mount matrix supplied by Samsung firmware.  This avoids a
model-specific axis remapping in userspace.  It was tested on an SM-W720 with
Linux 7.1.6; the SM-W727 variants use the same board hardware.

This component enables the orientation sensor used for screen rotation.  It
does not add a separate angular-rate gyroscope; none is described by the ACPI
tables inspected on the development machine.

## Build

Install the matching kernel headers, compiler, `make`, `patch`, `curl` and
`xz`, then run from the repository root:

```bash
./sensors/kernel/build-module.sh
```

The script downloads the source version matching the running kernel when a
source tree is not supplied.  The result is written under:

```text
sensors/kernel/build/$(uname -r)/
```

## Install

Install both modules and reboot:

```bash
sudo ./sensors/kernel/install.sh \
  "sensors/kernel/build/$(uname -r)"
sudo reboot
```

The installer checks the Galaxy Book 12 DMI identity, the `SAM0201` ACPI
device, module names and kernel version.  It installs an override under
`updates`, runs `depmod` and rebuilds the initramfs.

Install `iio-sensor-proxy` if the desktop does not already provide it.  After
reboot, verify the sensor with:

```bash
cat /sys/bus/iio/devices/iio:device*/name
cat /sys/bus/iio/devices/iio:device*/mount_matrix
monitor-sensor
```

The name should be `lis2hh12`.  On the Galaxy Book 12, the firmware matrix is:

```text
0, -1, 0; -1, 0, 0; 0, 0, -1
```

GNOME on Wayland should then rotate the internal panel when rotation lock is
disabled and tablet mode is active.

### GNOME 50.4 does not rotate after login

Some GNOME 50.4 builds contain a Mutter lifecycle bug: the IIO sensor works,
but the compositor does not claim it when the session starts.  A live test may
rotate correctly and then stop working after a reboot.  This is separate from
the kernel driver and is fixed by an upstream Mutter change.

If `monitor-sensor` follows all four orientations but GNOME does not, see the
[native Mutter fix](mutter/README.md).  It patches the compositor itself and
does not require a startup script or background service.

## Kernel updates and removal

External modules are tied to one kernel release. The global installer enables
automatic CachyOS rebuilds; after a manual installation run
`sudo ./install.sh updates`. See [the update guide](../updates/README.md).

To remove the override:

```bash
sudo ./sensors/kernel/uninstall.sh
sudo reboot
```

Pass a kernel release to the removal script when cleaning an older installed
kernel.

## Development

The upstream-style sensor change is in `kernel/patches/`.  It adds the ACPI
match to `st_accel_i2c.c` and standard `ROTM` support to the shared ST
accelerometer core.  The latter is useful to other ACPI-described ST
accelerometers as well.  The independent GNOME session-start correction is in
`mutter/patches/` and comes from the official Mutter repository.

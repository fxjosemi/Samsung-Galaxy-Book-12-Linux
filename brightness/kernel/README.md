# Native AMOLED backlight driver

This patch adds Galaxy Book 12 AMOLED brightness control directly to `i915`.
It uses the panel's private eDP AUX protocol, reads the individual factory
calibration values and exposes levels 10–101 through the normal Linux
backlight interface. No background service or fade is used.

The driver activates only when both identifiers match:

- DMI vendor/product: `SAMSUNG ELECTRONICS CO., LTD.` / `Galaxy Book 12`;
- internal panel EDID: Samsung Display `SDC a029`.

That covers the SM-W720 and SM-W727 families without relying on a regional or
carrier model suffix. If panel initialization fails, `i915` falls back to its
original PWM backlight implementation.

## Current status

The first patch is based on Linux 7.1.6 and builds cleanly as a complete
`i915.ko` with Clang and `W=1`. It has booted successfully on the development
SM-W720: `i915` detects the AMOLED implementation, the standard slider exposes
levels 10–101 and changes the panel brightness correctly without the userspace
service.

The fixed-point conversion was compared against the original floating-point
implementation using the development panel's live calibration: all 2,178 bytes
were checked and the largest rounding difference was one register unit.

The userspace implementation remains the tested fallback. Keep a second kernel
installed until the native module has passed boot, brightness and suspend tests.

## Build

Install the compiler, kernel headers, `make`, `patch`, `curl`, `xz` and the
normal tools used to build external kernel modules. Then run from the repository
root:

```bash
./brightness/kernel/build-module.sh
```

An unpacked full Linux source tree can be supplied as the first argument. When
it is omitted, the script downloads the source version matching the running
kernel and extracts only the required directories.

The result is written to:

```text
brightness/kernel/build/$(uname -r)/i915.ko
```

## Install and reboot

```bash
sudo ./brightness/kernel/install-native.sh \
  "brightness/kernel/build/$(uname -r)/i915.ko"
sudo reboot
```

The installer verifies the computer, panel ID, module name and kernel version.
It places the module under `updates`, disables the userspace brightness service,
runs `depmod` and rebuilds the initramfs. It never unloads the active graphics
driver; the change starts only after reboot.

After reboot, check:

```bash
sudo dmesg | grep 'Galaxy Book 12 AMOLED backlight initialized'
cat /sys/class/backlight/intel_backlight/max_brightness
systemctl is-enabled galaxybook12-brightness.service
```

The maximum should be `101`, and the old service should be disabled. Test the
whole slider, suspend/resume and a cold boot before treating the module as
stable.

## Remove or recover

From the patched kernel:

```bash
sudo ./brightness/kernel/uninstall-native.sh
sudo reboot
```

If the graphical session cannot start, boot the other installed kernel or a
text console and pass the affected release explicitly:

```bash
sudo ./brightness/kernel/uninstall-native.sh 7.1.6-1-cachyos
sudo reboot
```

The distribution module is not overwritten. Removal deletes the override,
rebuilds the initramfs and re-enables the userspace service if it was enabled
before native installation.

## Development files

The upstream-style patch is under `patches/`. `tools/` contains the lookup-table
generator and the live calibration comparator used to validate the conversion
from floating point to kernel-safe fixed-point arithmetic.

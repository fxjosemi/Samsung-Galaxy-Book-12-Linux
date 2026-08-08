# Installation

These instructions install the native Realtek driver fix. Commands are run from
the repository root.

## 1. Check the hardware

The codec should report `0x10ec0298` and `0x144dc14f`:

```bash
cat /sys/class/sound/hwC*D*/vendor_id
cat /sys/class/sound/hwC*D*/subsystem_id
```

Do not force the patch onto a different subsystem ID. The coefficient tables
are specific to the Galaxy Book 12 board.

## 2. Install build dependencies

Arch Linux and derivatives:

```bash
sudo pacman -S --needed base-devel clang llvm curl xz
sudo pacman -S --needed linux-cachyos-headers
```

Replace the second package with the headers matching `uname -r`. For example,
an LTS installation normally needs `linux-cachyos-lts-headers` instead.

Debian and Ubuntu:

```bash
sudo apt install build-essential clang llvm curl xz-utils \
  linux-headers-"$(uname -r)" kmod patch
```

## 3. Build the module

The simple form downloads the kernel.org source matching the base version of
the running kernel:

```bash
./kernel/build-module.sh
```

The download is cached under `kernel/build/`. If you already have the exact
Linux source used by your distribution, pass it as the first argument:

```bash
./kernel/build-module.sh /path/to/linux-source
```

The resulting module is written to:

```text
kernel/build/<kernel-release>/snd-hda-codec-alc269.ko
```

## 4. Install and reboot

```bash
sudo ./kernel/install-native.sh \
  "kernel/build/$(uname -r)/snd-hda-codec-alc269.ko"
sudo reboot
```

The installer checks the hardware IDs and module version before changing
anything. It installs the module under the current kernel's `updates`
directory and backs up the older userspace initializer if present.

Unsigned external modules will not load when Secure Boot enforcement is
enabled. Disable Secure Boot or sign the module with a key trusted by your
system.

## 5. Verify the installation

After reboot, this command should point to `updates/alc298-book12`:

```bash
modinfo -n snd_hda_codec_alc269
```

Check the kernel log:

```bash
journalctl -k -b | grep -E 'ALC298|144d:c14f|snd_hda_codec_alc269'
```

Test speakers first at low volume. Then connect the jack and check left/right
channels separately. A short click during insertion is a known limitation.

## Kernel updates

The module is built for one exact kernel release. After booting a new kernel,
install its headers and repeat the build, install and reboot steps. The old
module remains confined to the old kernel directory.

## Removal

```bash
sudo ./kernel/uninstall-native.sh
sudo reboot
```

This removes the external module and restores any userspace files that the
native installer backed up.

## Speaker-only fallback

If the native module cannot be built, install `alsa-tools` and use:

```bash
sudo ./install.sh
```

Remove it with:

```bash
sudo ./uninstall.sh
```

This fallback initializes the internal speakers only. It intentionally does
not automate headphone routing.

## Other components

AMOLED brightness and the orientation sensor have separate instructions and
installers because neither requires the audio patch:

- [AMOLED brightness](brightness/README.md)
- [Accelerometer and automatic rotation](sensors/README.md)

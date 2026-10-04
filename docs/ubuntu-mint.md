# Ubuntu-based kernels (tested on Linux Mint 22.3)

This project targets CachyOS. This page records what was needed to build and
load the ALC298 audio module on an Ubuntu-based kernel. It is not a support
statement for other distributions.

Tested on: Samsung Galaxy Book 12, codec `10ec:0298`, subsystem `144d:c14f`,
Linux Mint 22.3, Ubuntu HWE kernel `7.0.0-34-generic`, Secure Boot enabled.

Results: both speakers OK, volume OK, cold boot OK, suspend/resume OK, jack OK.

## Why the vanilla kernel.org sources are not enough

Ubuntu patches `sound/hda` (including `alc269.c` and `hda_codec.h`). A module
built from vanilla kernel.org sources against the Ubuntu headers loaded but
crashed in `alc298_fixup_samsung_galaxy_book12` (page fault). Apply the Ubuntu
patches to the sources first.

## Procedure

Dependencies:

```bash
sudo apt install build-essential clang llvm curl xz-utils \
  linux-headers-"$(uname -r)" kmod patch git patchutils sbsigntool
```

Fetch the Ubuntu kernel source package without unpacking it (the full tree
needs several GB). This requires the source repositories to be enabled
(Linux Mint: Software Sources, optional repositories):

```bash
mkdir -p ~/ksrc && cd ~/ksrc
apt source --download-only linux-image-unsigned-"$(uname -r)"
```

Extract only the HDA code (adjust the archive name and the `linux-7.0` base
directory to your kernel) and apply the Ubuntu changes to it:

```bash
tar -xzf linux-hwe-7.0_7.0.0.orig.tar.gz \
  linux-7.0/sound/hda/codecs linux-7.0/sound/hda/common
cd linux-7.0
zcat ../linux-hwe-7.0_*.diff.gz \
  | filterdiff -p1 -i 'sound/hda/codecs/*' -i 'sound/hda/common/*' > ../ubuntu-hda.patch
patch -p1 --dry-run < ../ubuntu-hda.patch && patch -p1 < ../ubuntu-hda.patch
```

Build with that tree, from the root of this repository:

```bash
./kernel/build-module.sh ~/ksrc/linux-7.0
```

## Secure Boot

With Secure Boot enabled, sign both modules with a Machine Owner Key (keep the
private key out of the repository):

```bash
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der \
  -nodes -days 36500 -subj "/CN=Galaxy Book 12 module signing/"
chmod 600 MOK.priv
sudo mokutil --import MOK.der      # reboot and enroll the key in the MOK manager
for m in snd-hda-codec-alc269 snd-hda-codec-realtek-lib; do
  kmodsign sha256 MOK.priv MOK.der "kernel/build/$(uname -r)/$m.ko"
done
```

## Install

```bash
sudo ./kernel/install-native.sh "kernel/build/$(uname -r)/snd-hda-codec-alc269.ko"
sudo update-initramfs -u -k "$(uname -r)"
sudo reboot
```

`snd-hda-codec-realtek-lib.ko` is installed alongside `alc269`. Without it the
module fails with `disagrees about version of symbol alc_get_hp_pin`.

## Notes

- The modules are tied to the exact kernel version. After a kernel update,
  repeat the build, signing and installation. Keep a second kernel installed.
- Remove any leftover `options snd-hda-intel model=...` line in
  `/etc/modprobe.d/`. A forced model overrides the PCI SSID match and the
  fixup crashes. Confirm in `journalctl -k -b`: the line
  `ALC298: picked fixup ... for PCI SSID 144d:c14f` must not say
  `(model specified)`.

# Galaxy Book 12 IPU3 autofocus patch

This directory builds a matched `libcamera` and `libcamera-ipa` pair for the
Galaxy Book 12 rear IMX258 camera. They must be installed together because the
IPA signature is verified with a public key embedded in `libcamera`.

The patch changes the IPU3 autofocus implementation to:

- wait for the IPU3 pipeline after every lens movement;
- start with a bounded search in the useful middle range;
- stop after a sustained contrast drop confirms that the best coarse focus was
  passed, expanding toward 0 or 1023 only when the best result lies at a search
  boundary;
- search on both sides of the best coarse position during the fine pass;
- measure a fresh stable baseline after the final lens movement;
- debounce loss of focus before starting another scan; and
- avoid sending the same focus command to the DW9806B on every frame;
- advertise validated discrete viewfinder/video modes through `3840x2160`
- prevent an IPU3 BDS height underflow when WebRTC negotiates small widescreen modes such as `640x360`
  while retaining `1280x720` as the low-overhead default.

Build and install:

```sh
makepkg --cleanbuild --noconfirm
sudo pacman -U ./libcamera-0.7.2-3.6-x86_64.pkg.tar.zst \
  ./libcamera-ipa-0.7.2-3.6-x86_64.pkg.tar.zst
systemctl --user restart wireplumber
```

No reboot is required. To return to the repository packages:

```sh
sudo pacman -S libcamera libcamera-ipa
systemctl --user restart wireplumber
```

When Arch/CachyOS updates libcamera to a newer upstream version, refresh the
version and release in `PKGBUILD`, check whether the patch still applies, and
rebuild both packages together.

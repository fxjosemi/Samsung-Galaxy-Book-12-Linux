# AMOLED brightness

The Galaxy Book 12 exposes an `intel_backlight` slider, but changing it does
not program the AMOLED panel correctly. This component mirrors that slider to
the panel's private registers over the eDP AUX channel.

It only runs when all of these match:

- DMI product `Galaxy Book 12` from Samsung Electronics;
- a connected internal eDP display;
- Samsung Display EDID `SDC a029` (2160x1440);
- the Intel backlight sysfs interface.

The AUX device is discovered from sysfs instead of assuming that it is always
`/dev/drm_dp_aux0`.

## Build and check

The check is read-only and does not require root:

```bash
make -C brightness
./brightness/galaxybook12-brightness check
```

## Test once

Start with the current maximum brightness:

```bash
sudo ./brightness/galaxybook12-brightness set 101
```

Then try a lower stable value:

```bash
sudo ./brightness/galaxybook12-brightness set 70
```

The default service maps the complete desktop slider onto panel levels 10
through 101 and moves between levels with a short fade. Level 10 was visually
tested on the development SM-W720. The reference implementation warned about
visible flicker below 40, so individual panels should still be checked with a
camera and by eye.

```bash
sudo ./brightness/galaxybook12-brightness set 30
```

The watcher accepts a custom minimum as its second optional argument. For
example, `watch 3 20` maps the desktop slider to panel levels 20–101. Levels
1–9 remain available for manual experiments but are not enabled by default.

## Install

```bash
sudo ./brightness/install.sh
```

The systemd service follows `/sys/class/backlight/intel_backlight/brightness`
and reapplies the panel state after suspend or an AUX reset. Profile 3, the
adaptive AMOLED profile, is used by default.

To remove it:

```bash
sudo ./brightness/uninstall.sh
```

## Credits

The private panel protocol, calibration algorithm and register tables are
derived from Aurélien Croc's
[SamsungGalaxyBook12](https://github.com/Teetoow/SamsungGalaxyBook12) project,
commit `2e9bb798bcf31ce9fdb67f88d2ba616223c61fe3`. The original and modified code
are distributed under GPL-2.0-only.

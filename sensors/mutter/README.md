# GNOME automatic-rotation fix

The kernel modules in `../kernel/` expose the accelerometer correctly, but
GNOME 50.4 can still leave it unclaimed when the sensor appears during session
startup.  In that state `monitor-sensor` works while automatic rotation does
not, or rotation works during a live test and stops after reboot.

This directory contains the upstream Mutter fix for that lifecycle bug.  It
balances the orientation-tracking inhibit state and lets Mutter claim the
accelerometer normally.  It is a native compositor fix: it does not install a
background script or a separate service.

Upstream references:

- [GNOME Mutter issue #4931](https://gitlab.gnome.org/GNOME/mutter/-/work_items/4931)
- [GNOME Mutter merge request !4962](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/4962)
- [Upstream commit 25e48d8b](https://gitlab.gnome.org/GNOME/mutter/-/commit/25e48d8b3f0905fa38c07340e17b0f59938d44c2)

## Who needs this patch

Install the sensor kernel modules first and reboot.  This Mutter patch is only
needed when all of the following are true:

- the IIO device is present as `lis2hh12`;
- `monitor-sensor` reports orientation changes;
- GNOME does not rotate automatically after a fresh login;
- the installed Mutter version does not already contain the upstream commit.

The packaged build below is intentionally restricted to Mutter 50.4-1 on Arch
Linux and derivatives.  Do not downgrade a newer Mutter release to use it;
check first whether the upstream correction is already included.

## Arch Linux and CachyOS

Install the packaging tools and build dependencies.  `makepkg` will offer to
install any missing dependencies automatically:

```bash
sudo pacman -S --needed base-devel git
./sensors/mutter/build-arch-package.sh
```

The build uses two jobs by default to avoid excessive memory use.  Override it
only if the machine has enough RAM:

```bash
JOBS=4 ./sensors/mutter/build-arch-package.sh
```

Install only the resulting main `mutter` package, then reboot or log out:

```bash
sudo pacman -U sensors/mutter/build/50.4-1.2/mutter-50.4-1.2-x86_64.pkg.tar.zst
sudo reboot
```

The `mutter-devkit` and `mutter-docs` packages are not needed for rotation.

## Verify after login

With rotation lock disabled, rotate the tablet and check that the orientation
remains available without running `monitor-sensor`:

```bash
pacman -Q mutter
busctl get-property net.hadess.SensorProxy \
  /net/hadess/SensorProxy net.hadess.SensorProxy AccelerometerOrientation
busctl --user get-property org.gnome.Mutter.DisplayConfig \
  /org/gnome/Mutter/DisplayConfig \
  org.gnome.Mutter.DisplayConfig PanelOrientationManaged
```

The first property should contain an orientation rather than `undefined`, and
`PanelOrientationManaged` should be `true` while the device is in tablet mode.

## Revert

Reinstall the distribution package and restart the graphical session:

```bash
sudo pacman -S mutter
sudo reboot
```

Pacman normally also keeps the replaced package under `/var/cache/pacman/pkg/`,
which can be installed directly if the repository version is temporarily
unavailable.

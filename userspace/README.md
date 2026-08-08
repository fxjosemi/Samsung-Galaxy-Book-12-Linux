# Guarded userspace workaround

This directory contains the hardware-validated fallback while the native
kernel quirk is developed.

## Manual validation

Collect read-only information and inspect the codec:

```bash
./collect-diagnostics.sh
sudo ./alc298-book12-test.py status
```

Initialize the codec and select the speaker route:

```bash
sudo ./alc298-book12-test.py full --apply --verbose
speaker-test -D plughw:0,0 -c 2 -t wav -l 1
```

The two recovered routes can be selected explicitly for development:

```bash
sudo ./alc298-book12-test.py speakers --apply
sudo ./alc298-book12-test.py headphones --apply
```

Do not automate the headphone action. On the tested tablet it produces a
large analog/DC transient in the headphones even when playback is silent. The
safe installation below initializes and restores internal speakers only.

## Persistent installation

`sudo ./install.sh` installs:

- the guarded ALC298 control program;
- a udev-triggered initialization service that waits for the exact codec;
- suspend/resume restoration.

The Python and systemd components are not intended as the final upstream
solution. They are retained as a reference implementation and recovery path
for kernels that do not contain the native quirk.

# Hardware validation checklist

## Driver and hardware

```bash
modinfo -n snd_hda_codec_alc269
cat /sys/class/sound/hwC*D*/vendor_id
cat /sys/class/sound/hwC*D*/subsystem_id
```

The module path should contain `updates/alc298-book12`. Expected codec IDs are
`0x10ec0298` and `0x144dc14f`.

## Cold boot

After a full shutdown and power-on, run:

```bash
speaker-test -D plughw:0,0 -c 2 -t wav -l 1
```

Check left and right channels independently at low volume.

## Headphone jack

Connect the jack with playback stopped, then test left and right channels.
Verify that volume changes work and that unplugging returns playback to the
internal speakers. A short click at insertion is a known limitation.

## Suspend and resume

Suspend once, resume, and repeat both output tests. The codec initialization
and current route should be restored by the native driver.

## Kernel log

```bash
journalctl -k -b | grep -E 'ALC298|144d:c14f|snd_hda_codec_alc269'
```

Include this output, the exact model code and `uname -r` in bug reports.

## Userspace fallback

For the speaker-only fallback, use `./status.sh` after cold boot and resume.
Do not automate its `headphones` action; only the native driver prepares the
dedicated headphone DAC and mixer.

# Hardware validation checklist

## 1. Identity and installation

```bash
./status.sh
systemctl status alc298-book12-init.service
```

Expected identity is `Galaxy Book 12`, codec `0x10ec0298`, subsystem
`0x144dc14f`. The initialization unit is a udev-triggered oneshot and normally
shows `inactive (dead)` after completing; its last result must be `success`.

## 2. Cold boot

Perform a full shutdown, wait several seconds, then power on. After login:

```bash
./status.sh
speaker-test -D plughw:0,0 -c 2 -t wav -l 1
```

Verify the left and right channels independently at low volume.

## 3. Suspend and resume

Suspend once, resume, and repeat the stereo test. The system-sleep hook should
restore the amplifier state if the codec lost it.

## 4. Volume and stability

Check several normal volume levels. This repository does not install software
gain, a limiter, a virtual sink, or a custom PipeWire profile.

## 5. Headphone limitation

Automatic headphone routing is not part of the safe userspace installation.
Do not repeatedly run the experimental `headphones` action: the recovered
vendor table switches the physical output but leaves ALSA on the speaker DAC
and mixer, causing a large analog transient even without PCM playback.

Native driver work must switch to DAC `0x03` and mixer `0x0d` before the
headphone route can be considered ready for end users.

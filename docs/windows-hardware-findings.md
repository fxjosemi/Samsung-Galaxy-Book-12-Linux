# Windows findings: audio, cameras and useful sensors

Read-only investigation on the project Galaxy Book 12, 2026-09-20.
The user reports that Windows sounds louder/better than the current Linux stack.
No gain, amplifier register, camera or sensor setting was changed in Windows.
These findings are research inputs, not new validated Linux drivers.

## Audio: investigate the missing speaker processing first

The installed Realtek SST driver is **6.0.1.8261**, `oem29.inf`, installation
section `IntcAzAudModelMaxim`. The package explicitly assigns that section to
`INTELAUDIO\FUNC_01&VEN_10EC&DEV_0298&SUBSYS_144DC14F`.

Its `CusEffectSettingsMaxim.AddReg` section defines **226 binary parameters**
for `SSTPPCfg\{C75061F3-F2B2-4DCC-8F9F-82ABB4131E66}\SPK\EFX`.
The installed registry contains those 226 parameters plus `Enabled=1` and
`Position=1`. This establishes a configured speaker-processing profile; it
does not prove every parameter is used during playback or identify each one's
meaning. Other Dolby/DTS/Waves files in the package do not by themselves prove
those effects are active on this tablet.

The Linux patch initializes the amplifiers and routes the codec. It does not
implement this Windows SST effects profile. Missing processing is therefore a
plausible explanation for the audible difference, not a measured conclusion.

Next Linux steps:

1. Compare the same recording, output route and volume in both systems. Check
   ALSA mixer attenuation and PipeWire gain before changing amplifier settings.
2. Determine the Maxim parameter format and distinguish EQ, dynamics and any
   speaker-protection settings. Preserve the original settings as a reference.
3. Test a reversible speaker-only EQ/compressor/limiter chain in userspace if
   measurements justify it. Do not apply it to the headphone route.
4. Do not blindly increase codec coefficients, amplifier gain or set 150% volume:
   digital clipping and speaker excursion are different constraints, and a peak
   limiter alone is not equivalent to the vendor's speaker protection.

## Cameras: compatibility and tuning are separate tasks

The Windows package includes **11 CPF profiles**, a default AIQB and five
pipeline-configuration files. They cover several IMX241 module variants and
IMX258 still/video/4K profiles. A file named `HD120fpsVideo.cpf` is present;
that name does not establish an available Linux 120 FPS mode.

The checked rear CPF starts with `CPFF` and contains an `AIQB` block. Preserve
the full files and identify the actual fitted module before attempting tuning.
Do not assume Windows CPF/AIQB can be copied into the project's open libcamera
IPA: the current package does not provide such a conversion/import path.

Priorities after booting Linux:

- Verify both cameras using the existing native IPU3 drivers and libcamera.
- Compare exposure, white balance, noise and autofocus with Windows, at equal
  resolution and lighting; identify whether the problem is capture or tuning.
- For an application without libcamera/PipeWire support, test an optional
  `libcamerasrc -> videoconvert -> v4l2sink` bridge to a **v4l2loopback** device,
  initially at 720p. This exposes a virtual V4L2 webcam, not a physical USB/UVC
  device. It requires a working native capture pipeline and adds CPU/battery cost.
- Keep the bridge opt-in and stop it when unused. Prefer the existing PipeWire
  path for compatible applications.

References: [libcamera GStreamer setup](https://libcamera.org/getting-started.html),
[v4l2loopback](https://github.com/v4l2loopback/v4l2loopback),
[GStreamer v4l2sink](https://gstreamer.freedesktop.org/documentation/video4linux2/v4l2sink.html).

## Sensors: ambient light has the clearest everyday benefit

| Device | Verified Windows/ACPI facts | Next step |
|---|---|---|
| Ambient light | BH1733 ALS; `SAM0204`; `\_SB.PCI0.I2C5.ALS1`; I2C address `0x29`, 400 kHz | Recover conversion to lux, then expose IIO illuminance for automatic brightness |
| Grip/proximity | SX9310; `SAM0203`; `SAR1` on I2C5 at `0x28`; a second `SAR2` on I2C0 is conditional on `SMOD` | Establish actual grip behavior and preserve board configuration before enabling |
| Orientation | K2HH; `SAM0201` | Already supported by the project's rotation driver |
| Location | Broadcom 4752 enumerated in Windows | Lower priority; transport/firmware still to investigate |

ALS `_DSM` UUID `518808e9-2eb8-42d3-b5e3-b135f94343c9`, function 1, returns
236 bytes. The beginning is `80 13 81 d3 82 00 83 00 84 00 85 00 86 00 87 00`,
followed by tables and coefficients. Their complete semantics are unverified.
The installed `BH1733Als.dll` contains the string `Bh1730AlsDevice`, suggesting
a relationship worth testing against the [ROHM BH1730 documentation](https://www.rohm.com/products/sensors-mems/ambient-light-sensor-ics/digital-16bit-serial-output/bh1730fvc-product).
It is not sufficient evidence to bind an arbitrary related sensor driver.

The [upstream SX9310 driver](https://github.com/torvalds/linux/blob/master/drivers/iio/proximity/sx9310.c)
is a starting point for proximity support. Samsung's `_DSM` uses UUID
`7681541e-8827-4239-8d9d-36be7fe12542` and provides different register tables for
different board conditions. Preserve those settings; do not assume this sensor
is an optical face detector or a keyboard-cover detector.

## Preserved evidence

`windows-evidence-manifest.json` records source filenames, sizes and SHA-256
hashes, plus installed audio-profile metadata. It contains no binary drivers,
camera captures, serial numbers or machine-specific absolute paths.

Original camera profiles, sensor drivers, installed audio INF, full installed
Maxim parameter values and the ALS ACPI excerpt were copied to a separate local
private evidence directory. **Copy that directory off the Windows partition
before reinstalling** if it will be erased. Only this report and the manifest
are intended for GitHub. No new audio gain or sensor patch is validated yet.

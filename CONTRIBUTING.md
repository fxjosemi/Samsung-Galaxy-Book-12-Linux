# Contributing

This project writes undocumented Realtek codec coefficients and private AMOLED
panel registers. Hardware identity and reproducible observations are more
important than broad model-name matches.

## Before reporting a problem

Run:

```bash
./status.sh
./userspace/collect-diagnostics.sh
```

Attach the generated diagnostics directory as an archive after reviewing it.
Do not publish serial numbers or unrelated logs if you add any extra files.

Include:

- exact Samsung model and board name;
- codec vendor and subsystem IDs;
- distribution and kernel version;
- cold-boot and suspend/resume results;
- whether left and right speakers both work;
- whether the symptom occurs with playback silent.

For brightness reports, also include the output of:

```bash
./brightness/galaxybook12-brightness check
systemctl status galaxybook12-brightness.service
```

## Testing changes

Do not remove the vendor/subsystem checks to test another machine. Begin at low
volume and stop on distortion, imbalance, unexpected heat, smell, or a large
analog transient. A complete shutdown resets volatile codec state.

Follow [`docs/testing.md`](docs/testing.md) and report each result separately.
The native route is the supported jack implementation. The userspace
`headphones` action remains a manual diagnostic only.

Do not bypass the DMI, eDP or EDID checks in the brightness program. Stop the
service if the display flickers, shows incorrect colors or becomes unstable.
Test the full desktop slider, a cold boot and suspend/resume before reporting a
brightness change as successful.

## Patches

- Keep userspace changes GPL-2.0-only.
- Preserve attribution for the Windows/QEMU-derived tables.
- Run `bash -n` on shell scripts, compile-check Python files and build the
  brightness component with all compiler warnings enabled.
- Explain any COEF change and the exact hardware on which it was measured.
- Build native changes with `W=1` and test cold boot, resume, jack switching,
  channel separation and volume on physical hardware.

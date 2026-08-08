# Contributing

This project writes undocumented Realtek vendor coefficients. Hardware identity
and reproducible observations are more important than broad model-name matches.

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

## Testing changes

Do not remove the vendor/subsystem checks to test another machine. Begin at low
volume and stop on distortion, imbalance, unexpected heat, smell, or a large
analog transient. A complete shutdown resets volatile codec state.

Follow [`docs/testing.md`](docs/testing.md) and report each result separately.
Do not claim automatic headphone routing is safe on SM-W720: the currently
known incomplete route produces a large click in the headphones.

## Patches

- Keep userspace changes GPL-2.0-only.
- Preserve attribution for the Windows/QEMU-derived tables.
- Run `bash -n` on shell scripts and compile-check Python files.
- Explain any COEF change and the exact hardware on which it was measured.
- Keep native kernel work separate until it passes cold boot, resume, and jack
  switching tests on the physical tablet.

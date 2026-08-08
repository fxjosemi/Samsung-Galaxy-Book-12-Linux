# Changelog

## Unreleased

- Expand the project from an audio-only fix into a Galaxy Book 12 Linux
  compatibility repository.
- Add guarded AMOLED brightness control, eDP AUX discovery, a systemd service
  and suspend recovery.
- Add an exact-match ALC298 speaker amplifier initializer for Samsung
  Galaxy Book 12 (`144d:c14f`).
- Add udev-triggered startup and suspend/resume restoration.
- Add guarded diagnostics, status, install, and uninstall commands.
- Add a native Realtek driver patch with automatic speaker/headphone routing.
- Use the dedicated DAC `0x03` and mixer `0x0d` headphone path.
- Add native module build, install, verification, and rollback scripts.
- Document the remaining jack insertion click.

# Samsung preferred performance mode: experimental foundation

This component preserves the protocol recovered on Windows for continuing the
investigation after installing Linux. **It is not a validated performance fix.**
It is deliberately excluded from `install.sh all` and automatic startup.

## What is established

Book Settings 1.0.60.0 still contains "Modo de rendimiento preferido", and calls
`IsPerformanceModeSupported` / `SetPerformanceMode` in Samsung's firmware stack.
The installed SAFI 1.0.0.7 package implements the operation through IOCTL
`0x68921800`, with one 32-bit input and one 32-bit output. The kernel driver
passes the input to `\_SB.SAFI.SPRF` on ACPI device `SAM0701`.

The tablet's actual DSDT establishes this behavior:

- `SPRF(255)` returns 255 without changing the preference (capability query).
- Other inputs assign the root `ODV2` field, notify `\_SB.IETM` with event
  `0x88`, and return the input. Our tool only permits preference 0 or 1.
- EC event methods `_Q8B` and `_Q8C` also assign ODV2 to 1 and 0 and send the
  same notification. Their physical trigger has **not** been established.

This is a thermal-policy input, not a direct change to CPU frequency, PL1/PL2,
or the fan. A successful readback does not establish a performance improvement.
The relationship between the keyboard cover, the UI visibility check, and the
thermal policy still needs investigation. Do not label raw 0/1 as known Linux
balanced/performance profiles yet.

The upstream `samsung-galaxybook` driver does not match this tablet's `SAM0701`
interface. Do not force its newer-model commands onto this device.

## First steps on Linux

Python 3 is the only dependency for the passive inspection:

```bash
sudo python3 performance/gb12-performance.py status
```

For the query and optional short trial, install the distribution's `acpi_call`
module built for the running kernel (or its DKMS package and matching headers).
Its upstream interface is documented at
<https://github.com/nix-community/acpi_call>. Then:

```bash
sudo modprobe acpi_call
sudo python3 performance/gb12-performance.py probe
```

All ACPI access is blocked unless Samsung DMI identity, SAM0701 and the exact
reviewed DSDT SHA-256 match. A changed BIOS or DSDT requires another review;
there is intentionally no force switch. `status` reports a mismatch without
executing ACPI. No Windows files are needed by the Linux tool.

Once ready to measure Linux behavior, with the cover attached and the tablet
on a ventilated support, an explicit trial can request raw preference 1:

```bash
sudo python3 performance/gb12-performance.py trial 1 --seconds 30 --experimental
```

The original preference is read first, and restored after the trial, a failed
readback, Ctrl+C or SIGTERM. If already at 1, no change is made. The tool does
not override CPU/thermal limits or install persistence. SIGKILL, process crashes
or power loss cannot run cleanup; reboot before continuing if restoration is
not confirmed. Do not run other `acpi_call` clients during a probe/trial: the
module shares a response buffer, and the tool's lock only coordinates itself.
Firmware events may independently change ODV2 during a trial.

## Continue after installing Linux

1. Save `status` and `probe` output and the kernel version.
2. Check whether IETM/DPTF is enumerated and which Linux driver/thermal policy
   consumes its notifications. Check `thermald` status and logs where present.
3. Compare ODV2 with the cover attached/detached, on AC/battery, and after resume.
   Record observations; do not assume `_Q8B/_Q8C` mean cover connect/disconnect.
4. Measure a repeatable workload, package power, sustained frequency and
   temperatures with both preferences. Respect firmware thermal limits.
5. Only after showing an effect, decide whether a native `platform_profile`
   driver and desktop integration are appropriate. Check other BIOS revisions
   separately before widening the hardware match.

## Evidence and validation

Recovered 2026-09-20 on the project Galaxy Book 12, repository base `afbf52c`:

| Artifact | SHA-256 |
|---|---|
| DSDT (126076 bytes; OEM `SECCSD`, table `LH43STAR`) | `cee2c0bd469d8e2a9ad2ad15420483988c86768d15c0a7397eed684429dd1689` |
| Installed SafiDrv.sys | `69fd5ffd6a21aac3b507d6b5f7acf4fa3637c03d49009fa3dd8878fec7532440` |
| DriverStore Samsung.Firmware.dll | `d73f75e018834a815a22e4d4532e7260707a8ead7ecefa5153eb075f6a7fb1ce` |

In that driver, IOCTL dispatch at RVA `0x4725` calls the helper at `0x3a5c`;
the helper supplies ACPI method name `SPRF` (`0x46525053`) at RVA `0x3ab9`.
The DLL's MethodDef `0x06000012` queries support using input 255 and accepts
output 255; MethodDef `0x06000011` issues the requested preference.

Only static Windows/firmware analysis and mocked Python tests have been run.
No preference was changed on Windows. Linux ACPI execution, readback,
restoration and performance effects remain untested on hardware.

```bash
python3 -m unittest discover -s performance/tests -v
```

No proprietary binaries or full ACPI dumps are included in this repository.

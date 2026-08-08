# Hardware findings and tested codec state

## Identification

| Field | Value |
|---|---|
| Product | Samsung Galaxy Book 12 |
| Board/model family | SM-W720 / SM-W727 |
| Codec | Realtek ALC298 (`0x10ec0298`) |
| Codec subsystem | Samsung `0x144dc14f` |
| Speaker pin | NID `0x17` |
| Speaker DAC path | `0x02 -> 0x0c -> 0x17` |
| Headphone DAC path | `0x03 -> 0x0d -> 0x17` |
| Accelerometer ACPI ID | `SAM0201` |
| Accelerometer implementation | Samsung K2HH / LIS2HH12 compatible |
| Accelerometer I2C address | `0x1d` |

## Amplifier selectors

The codec-internal amplifier banks are selected through COEF index `0x22`:

- `0x31`: left amplifier;
- `0x34`: right amplifier;
- `0x1b`: vendor DSP and output routing register bank.

The full initialization tables are kept in
[`userspace/alc298-book12-test.py`](../userspace/alc298-book12-test.py). They
match the tables recovered from the Windows driver trace for this exact model.

## Tested output routes

All entries below are indirect register writes made after selecting bank
`0x1b`.

| Register | Internal speakers | Headphones |
|---|---:|---:|
| `0x07a` | `0x0400` | `0x0006` |
| `0x061` | `0xa000` | `0x8100` |
| `0x062` | `0x8400` | `0x0400` |
| `0x194` | `0x0240` | `0x0000` |
| `0x010` | `0x0000` | `0x4040` |

These values were tested audibly on the physical tablet.

Selecting the headphone table from userspace leaves ALSA on the speaker path
and is not suitable for automatic routing. The native quirk mirrors the front
stream to DAC `0x03`, selects mixer `0x0d`, and keeps its hardware volume in
sync with DAC `0x02`.

## Jack reporting

The firmware pin defaults do not expose a normal headphone output pin to the
generic HDA parser. NID `0x18` is presented as the external microphone jack,
and Linux reports insertion through an input device named `HDA Intel PCH Mic`
with switch code `SW_MICROPHONE_INSERT`.

The native driver attaches its route callback to this microphone jack event
instead of relying on generic headphone automute.

## Known insertion click

The jack produces a short click when inserted. It remains with PCM closed,
pin `0x17` disabled, EAPD disabled, mic bias at `VREF_HIZ`, and the codec
runtime-suspended. The original Windows-derived scripts do not contain another
depop sequence. No unverified coefficient workaround is included.

## Orientation sensor

ACPI describes the accelerometer at `\_SB.PCI0.I2C5.ACC1` with ID `SAM0201`.
The device responds as an LIS2HH12-compatible ST accelerometer and is exposed
by IIO as `lis2hh12` after adding the missing ACPI match.

The firmware `ROTM` method returns this mount matrix:

```text
 0 -1  0
-1  0  0
 0  0 -1
```

Reading that matrix in the driver produces the correct `normal`, `left-up`,
`right-up` and `bottom-up` orientations without a userspace model quirk.

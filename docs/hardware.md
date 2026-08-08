# Hardware findings and tested codec state

## Identification

| Field | Value |
|---|---|
| Product | Samsung Galaxy Book 12 |
| Board/model family | SM-W720 |
| Codec | Realtek ALC298 (`0x10ec0298`) |
| Codec subsystem | Samsung `0x144dc14f` |
| Speaker pin | NID `0x17` |
| Speaker DAC path | `0x02 -> 0x0c -> 0x17` |

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

However, selecting the headphone table while ALSA continues to use the
speaker playback path (`0x02 -> 0x0c`) causes a large analog transient in the
headphones, including when PCM playback is silent. Windows instead uses DAC
`0x03` through mixer `0x0d` for the headset. Automatic userspace routing is
therefore deliberately excluded from the installer. These values are retained
only as input for the future native driver fix.

## Jack reporting

The firmware pin defaults do not expose a normal headphone output pin to the
generic HDA parser. NID `0x18` is presented as the external microphone jack,
and Linux reports insertion through an input device named `HDA Intel PCH Mic`
with switch code `SW_MICROPHONE_INSERT`.

The native driver fix therefore needs to attach its vendor-route callback to
the detected microphone jack event instead of relying on generic headphone
automute, and it must switch the playback path to DAC `0x03` / mixer `0x0d`
before enabling the headphone vendor route.

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
| Camera ISP | Intel IPU3 ImgU `8086:1919` + CIO2 `8086:9d32` |
| Rear camera | Sony IMX258 (`SONY258A`), 13 MP, 26 MHz input clock |
| Front camera | Sony IMX241 (`INT347F`), 5 MP |

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

## Cameras

The active firmware devices and the original Samsung Windows driver identities
show two MIPI sensors. The kernel binds both IPU3 PCI functions and loads the
ImgU firmware. Rear-camera probe then stops at:

```text
imx258 i2c-SONY258A:00: input clock frequency of 26000000 not supported
```

The IMX258 data sheet permits a 6--27 MHz reference. The camera component adds
26 MHz PLL values while retaining the driver's established 1267/640 Mbps link
rates and adds `SONY258A` to the IPU bridge.

The board's `INT3472:01` control logic exposes six rear-camera GPIOs. Its live
ACPI `_DSM` values decode as reset, AF, IO, Avdd, Core and MCLK. Intel's 2017
Windows control-logic driver names the legacy function codes as follows:

| Function | GPIO type | Pin | Linux handling |
|---|---:|---:|---|
| Reset | `0x00` | `0x79` | IMX258 reset GPIO |
| Autofocus | `0x0e` | `0x2c` | DW9806B power GPIO |
| Sensor IO | `0x0f` | `0x2b` | `vif` regulator |
| Sensor analog | `0x10` | `0x2e` | `vana` regulator |
| Sensor core | `0x11` | `0x3d` | `vdig` regulator |
| Master clock | `0x0c` | `0x7b` | 26 MHz sensor clock |

Samsung also supplies private rear-camera on/off `_DSM` methods which manage a
shared rail and the camera indicator. The patched IMX258 driver calls them only
during the sensor's normal runtime power cycle and toggles reset in the proper
order. The front `INT347F` device is IMX241. The project driver claims that ACPI
ID, uses the matching `DSC1` runtime-power method and exposes the recovered
2592x1944 and 1296x972 RAW10 modes to IPU3.

The rear SSDB selects a Dongwoon DW9806B voice-coil autofocus actuator. Linux
7.1 provides `dw9807-vcm` but no compatible `dw9806b` module. The project adds
a separate DW9806B V4L2 lens driver using the initialization and 10-bit
position protocol recovered from Samsung's official W720 driver: position is
encoded in registers `0x03`/`0x04`, busy state is read from `0x05`, and the
startup values are programmed through `0x02`, `0x06` and `0x07`. A public
Samsung Galaxy J5 DW9806B configuration uses different SAC tuning and confirms
that these resonance values are module-specific. The official W720
fallback calibration is DAC 180 for panorama/infinity and 320 for macro, but
the per-module NVM can override it. Linux currently exposes the complete
10-bit DAC range 0–1023 so this unit's useful endpoints can be measured.
Opening the lens node does not power the camera, because PipeWire keeps that
node open while idle; register `0x02` detects and repairs initialization after
an actual sensor power cycle.

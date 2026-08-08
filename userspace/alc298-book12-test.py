#!/usr/bin/env python3
"""ALC298 amplifier probe/init tool for Samsung Galaxy Book 12 (SM-W720).

The amplifier tables are derived from the Windows/QEMU trace analysis by
Aurélien Croc (AP2C): https://github.com/Teetoow/SamsungGalaxyBook12

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License, version 2.
"""

import argparse
import fcntl
import os
from pathlib import Path
import re
import subprocess
import sys
import time

VENDOR_ID = "0x10ec0298"
SUBSYSTEM_ID = "0x144dc14f"
PRODUCT_NAME = "Galaxy Book 12"

AMP_LEFT = (
    (0x0B, 0x00), (0x0C, 0x00), (0x0D, 0x00), (0x1A, 0x00),
    (0x1B, 0x82), (0x1C, 0x00), (0x1D, 0x00), (0x1E, 0x00),
    (0x1F, 0x00), (0x20, 0xE2), (0x21, 0xC0), (0x22, 0x20),
    (0x23, 0x22), (0x24, 0x00), (0x26, 0x00), (0x27, 0xFF),
    (0x28, 0xFF), (0x29, 0xFF), (0x2A, 0xFC), (0x2B, 0x02),
    (0x2C, 0x48), (0x2D, 0x14), (0x2E, 0x02), (0x2F, 0x00),
    (0x30, 0x00), (0x31, 0x00), (0x32, 0x00), (0x33, 0x00),
    (0x34, 0x00), (0x35, 0x01), (0x36, 0x93), (0x37, 0x00),
    (0x38, 0x80), (0x39, 0x00), (0x3A, 0xF0),
)

AMP_RIGHT = (
    (0x0B, 0x00), (0x0C, 0x00), (0x0D, 0x00), (0x1A, 0x00),
    (0x1B, 0x82), (0x1C, 0x00), (0x1D, 0x00), (0x1E, 0x00),
    (0x1F, 0x00), (0x20, 0xE2), (0x21, 0xC0), (0x22, 0x20),
    (0x23, 0x22), (0x24, 0x04), (0x26, 0x00), (0x27, 0xFF),
    (0x28, 0xFF), (0x29, 0xFF), (0x2A, 0xCF), (0x2B, 0x02),
    (0x2C, 0x48), (0x2D, 0x34), (0x2E, 0x02), (0x2F, 0x00),
    (0x30, 0x00), (0x31, 0x00), (0x32, 0x00), (0x33, 0x00),
    (0x34, 0x00), (0x35, 0x01), (0x36, 0x93), (0x37, 0x00),
    (0x38, 0x80), (0x39, 0x00), (0x3A, 0xF0),
)

DSP_REGS = (
    (0x0C0, 0x2A86), (0x0C1, 0xCAAA), (0x0FA, 0x0001),
    (0x01C, 0xAFAF), (0x073, 0x0000), (0x074, 0x8000),
    (0x0A0, 0x0000), (0x070, 0x8020), (0x071, 0x1020),
    (0x080, 0x0000), (0x0FA, 0x0001), (0x02A, 0x2A8A),
    (0x061, 0xA100), (0x062, 0x8400), (0x026, 0x8080),
    (0x02F, 0x0000), (0x085, 0x5000), (0x01C, 0x2F2F),
    (0x190, 0x8430), (0x190, 0x8431), (0x194, 0x0240),
    (0x196, 0x3000), (0x07A, 0x0400), (0x063, 0xA23E),
    (0x063, 0xF23E), (0x111, 0xA602), (0x08E, 0x0068),
    (0x125, 0x0110), (0x091, 0x0E26), (0x125, 0x0410),
    (0x13A, 0x3030), (0x1DB, 0x0003), (0x161, 0x0041),
    (0x162, 0x040C), (0x160, 0xCEFF), (0x003, 0xC000),
    (0x198, 0x0000),
)

ROUTE_SPEAKERS = (
    (0x07A, 0x0400), (0x061, 0xA000), (0x062, 0x8400),
    (0x194, 0x0240), (0x010, 0x0000),
)

ROUTE_HEADPHONES = (
    (0x07A, 0x0006), (0x061, 0x8100), (0x062, 0x0400),
    (0x194, 0x0000), (0x010, 0x4040),
)


def read_text(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return "unknown"


def find_codec(force=False):
    product = read_text("/sys/class/dmi/id/product_name")
    matches = []
    for node in sorted(Path("/sys/class/sound").glob("hwC*D*")):
        vendor = read_text(node / "vendor_id")
        ssid = read_text(node / "subsystem_id")
        if vendor == VENDOR_ID and ssid == SUBSYSTEM_ID:
            matches.append(node)
    if not matches:
        raise SystemExit(f"No se encontró ALC298 {VENDOR_ID}/{SUBSYSTEM_ID}")
    if product != PRODUCT_NAME and not force:
        raise SystemExit(
            f"DMI inesperado: {product!r}; se esperaba {PRODUCT_NAME!r}. "
            "Use --force solo después de verificar la placa."
        )
    return Path("/dev/snd") / matches[0].name, product


class Codec:
    def __init__(self, device, verbose=False):
        self.device = str(device)
        self.verbose = verbose

    def verb(self, nid, verb, param):
        cmd = ["hda-verb", self.device, hex(nid), hex(verb), hex(param)]
        if self.verbose:
            print("+", " ".join(cmd), file=sys.stderr)
        result = subprocess.run(cmd, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        match = re.search(r"value\s*=\s*(0x[0-9a-fA-F]+)", result.stdout)
        if not match:
            raise RuntimeError(f"Respuesta inesperada de hda-verb: {result.stdout!r}")
        return int(match.group(1), 16)

    def set_coef(self, index, value):
        self.verb(0x20, 0x500 | ((index >> 8) & 0xFF), index & 0xFF)
        self.verb(0x20, 0x400 | ((value >> 8) & 0xFF), value & 0xFF)

    def get_coef(self, index):
        self.verb(0x20, 0x500 | ((index >> 8) & 0xFF), index & 0xFF)
        return self.verb(0x20, 0xC00, 0)

    def update_coef(self, index, set_mask=0, clear_mask=0):
        value = self.get_coef(index)
        self.set_coef(index, (value | set_mask) & ~clear_mask)

    def wait_ready(self, timeout=0.5):
        deadline = time.monotonic() + timeout
        while self.get_coef(0x26) & 0x4000:
            if time.monotonic() >= deadline:
                raise TimeoutError("El motor COEF no quedó listo (COEF 0x26 bit 0x4000)")
            time.sleep(0.001)

    def init_amp_register(self, amp, register, value, select=False):
        for _ in range(8):
            self.verb(0x00, 0xF00, 0x00)
        self.verb(0x06, 0x73E, 0x80)
        self.update_coef(0x26, set_mask=0x4000)
        if select:
            self.set_coef(0x22, amp)
        self.set_coef(0x23, register)
        self.set_coef(0x25, value)
        self.set_coef(0x26, 0xB010)
        for _ in range(8):
            self.verb(0x00, 0xF00, 0x00)
        self.verb(0x06, 0x73E, 0x00)
        self.update_coef(0x26, clear_mask=0x0010)
        actual = self.get_coef(0x26)
        if actual != 0xB000:
            raise RuntimeError(f"COEF 0x26 inesperado tras init: 0x{actual:04x}")

    def write_indirect(self, register, value):
        self.wait_ready()
        self.set_coef(0x23, register)
        self.set_coef(0x24, 0)
        self.set_coef(0x25, value)
        self.set_coef(0x26, 0xB013)


def print_status(codec, product):
    print(f"DMI product: {product}")
    print(f"Codec device: {codec.device}")
    print(f"Vendor/subsystem: {VENDOR_ID}/{SUBSYSTEM_ID}")
    print(f"Speaker pin 0x17 ctl:  0x{codec.verb(0x17, 0xF07, 0):02x}")
    print(f"Speaker pin 0x17 EAPD: 0x{codec.verb(0x17, 0xF0C, 0):02x}")
    print(f"Speaker pin 0x17 amp:  0x{codec.verb(0x17, 0xB00, 0):02x}")
    for index in (0x10, 0x22, 0x23, 0x24, 0x25, 0x26, 0x61, 0x62, 0x7A, 0x194):
        print(f"COEF 0x{index:03x}: 0x{codec.get_coef(index):04x}")


def initialize(codec):
    coef26 = codec.get_coef(0x26)
    if (coef26 & 0x3000) == 0:
        codec.set_coef(0x26, coef26 | 0x3000)
    for amp, table in ((0x31, AMP_LEFT), (0x34, AMP_RIGHT)):
        for number, (register, value) in enumerate(table):
            codec.init_amp_register(amp, register, value, select=(number == 0))
    codec.set_coef(0x22, 0x1B)
    for register, value in DSP_REGS:
        codec.write_indirect(register, value)


def set_route(codec, route):
    codec.set_coef(0x22, 0x1B)
    for register, value in route:
        codec.write_indirect(register, value)


def enable_speaker_pin(codec):
    codec.verb(0x17, 0x707, 0x40)
    codec.verb(0x17, 0x70C, 0x02)


def run_muted(codec, action):
    """Run vendor writes while the physical output amp is temporarily muted."""
    amp_value = codec.verb(0x17, 0xB00, 0)
    restore = 0xB080 if amp_value & 0x80 else 0xB000
    codec.verb(0x17, 0x300, 0xB080)
    time.sleep(0.04)
    try:
        action()
        time.sleep(0.06)
    finally:
        codec.verb(0x17, 0x300, restore)


def main():
    parser = argparse.ArgumentParser(
        description="Prueba controlada del amplificador ALC298 del Galaxy Book 12"
    )
    parser.add_argument("action", choices=("status", "init", "speakers", "headphones", "full"))
    parser.add_argument("--apply", action="store_true", help="autoriza escrituras COEF")
    parser.add_argument("--force", action="store_true", help="omite solo la comprobación DMI")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if not shutil_which("hda-verb"):
        raise SystemExit("Falta hda-verb (paquete alsa-tools)")
    device, product = find_codec(args.force)
    if os.geteuid() != 0:
        raise SystemExit("Ejecute con sudo; hwdep requiere root en esta configuración")
    lock = open("/run/lock/alc298-book12.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    codec = Codec(device, args.verbose)

    if args.action == "status":
        print_status(codec, product)
        return
    if not args.apply:
        raise SystemExit("Acción de escritura bloqueada: repita con --apply")
    def apply_action():
        if args.action in ("init", "full"):
            initialize(codec)
        if args.action in ("speakers", "full"):
            enable_speaker_pin(codec)
            set_route(codec, ROUTE_SPEAKERS)
        elif args.action == "headphones":
            set_route(codec, ROUTE_HEADPHONES)

    run_muted(codec, apply_action)
    print(f"Acción {args.action!r} completada en {device}")


def shutil_which(command):
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


if __name__ == "__main__":
    main()

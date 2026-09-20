#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Inspect and temporarily exercise the SM-W720 Samsung performance preference.

SPRF changes a DPTF input, not a CPU power limit. No performance gain is implied.
"""
import argparse
import contextlib
import hashlib
import os
from pathlib import Path
import re
import signal
import sys
import time

DSDT_HASH = "cee2c0bd469d8e2a9ad2ad15420483988c86768d15c0a7397eed684429dd1689"
SPRF = r"\_SB.SAFI.SPRF"
STATE = r"\ODV2"


def identity(root=Path("/sys")):
    def read(relative):
        try:
            return (root / relative).read_text().strip()
        except OSError:
            return "unavailable"

    dsdt = root / "firmware/acpi/tables/DSDT"
    digest = hashlib.sha256(dsdt.read_bytes()).hexdigest()
    return {
        "vendor": read("class/dmi/id/sys_vendor"),
        "product": read("class/dmi/id/product_name"),
        "bios": read("class/dmi/id/bios_version"),
        "safi": any((root / "bus/acpi/devices").glob("SAM0701:*")),
        "dsdt_sha256": digest,
        "reviewed_firmware": digest == DSDT_HASH,
    }


def require_reviewed(info):
    if (info["vendor"] != "SAMSUNG ELECTRONICS CO., LTD."
            or info["product"] != "Galaxy Book 12" or not info["safi"]
            or not info["reviewed_firmware"]):
        raise RuntimeError("Hardware/DSDT differs from the reviewed tablet; no ACPI calls made. "
                           "Review this firmware before adding support; there is no force option.")


def parse_integer(response):
    response = response.rstrip("\0\n ")
    if not re.fullmatch(r"0x[0-9a-fA-F]+", response):
        raise RuntimeError(f"ACPI did not return an integer: {response!r}")
    return int(response, 16)


class Acpi:
    def __init__(self, path=Path("/proc/acpi/call")):
        self.path = path

    def call(self, method, value=None):
        # Deliberately do not accept arbitrary methods or argument values.
        if not ((method == STATE and value is None)
                or (method == SPRF and value in (0, 1, 255))):
            raise ValueError("Unapproved ACPI request")
        command = method if value is None else f"{method} {value}"
        with self.path.open("w") as stream:
            stream.write(command)
        with self.path.open("r") as stream:
            return parse_integer(stream.read())


@contextlib.contextmanager
def exclusive_calls():
    import fcntl
    # Serializes this tool only. Other acpi_call clients must be stopped.
    fd = os.open("/run/lock/gb12-performance.lock",
                 os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def probe(acpi):
    if acpi.call(SPRF, 255) != 255:
        raise RuntimeError("Samsung capability query failed")
    value = acpi.call(STATE)
    if value not in (0, 1):
        raise RuntimeError(f"Unexpected ODV2 value {value}; refusing a trial")
    return value


def trial(acpi, requested, seconds, sleep=time.sleep):
    if requested not in (0, 1) or not 1 <= seconds <= 300:
        raise ValueError("Trial requires preference 0/1 and duration 1..300 seconds")
    previous = probe(acpi)
    print(f"Original ODV2: {previous}; trial preference: {requested}", flush=True)
    if previous == requested:
        print("Already at the requested preference; no state change made.")
        return
    try:
        # Restore even if the call was applied but its response could not be read.
        if acpi.call(SPRF, requested) != requested or acpi.call(STATE) != requested:
            raise RuntimeError("Firmware preference readback did not match")
        print(f"Preference accepted for {seconds}s; performance effect is UNVERIFIED.", flush=True)
        sleep(seconds)
    finally:
        if acpi.call(SPRF, previous) != previous or acpi.call(STATE) != previous:
            raise RuntimeError("RESTORE FAILED: stop testing and reboot before continuing")
        print(f"Restored original ODV2: {previous}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("status", help="Read identity/DSDT only; no ACPI calls")
    commands.add_parser("probe", help="Query SPRF support and read ODV2 without changing preference")
    test = commands.add_parser("trial", help="Temporarily request 0/1, then restore original value")
    test.add_argument("preference", type=int, choices=(0, 1))
    test.add_argument("--seconds", type=int, choices=range(1, 301), default=30, metavar="1..300")
    test.add_argument("--experimental", action="store_true", help="Explicitly enable the unvalidated trial")
    args = parser.parse_args()
    if args.action == "trial" and not args.experimental:
        parser.error("trial requires --experimental; the Linux thermal-policy effect is unvalidated")
    if sys.platform != "linux":
        parser.error("This command runs on Linux only")
    try:
        info = identity()
        for key, value in info.items():
            print(f"{key}: {value}")
        if args.action == "status":
            return 0
        require_reviewed(info)
        if os.geteuid() != 0:
            raise RuntimeError("Run probe/trial with sudo")
        if not Path("/proc/acpi/call").exists():
            raise RuntimeError("acpi_call is not loaded. Install it for this kernel, then sudo modprobe acpi_call")

        def interrupted(signum, frame):
            raise KeyboardInterrupt

        signal.signal(signal.SIGTERM, interrupted)
        with exclusive_calls():
            acpi = Acpi()
            if args.action == "probe":
                print(f"SPRF supported; ODV2 preference: {probe(acpi)}")
            else:
                trial(acpi, args.preference, args.seconds)
        return 0
    except KeyboardInterrupt:
        print("Interrupted; see restoration result above.", file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

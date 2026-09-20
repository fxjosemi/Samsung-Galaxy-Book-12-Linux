# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("performance", Path(__file__).parents[1] / "gb12-performance.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class Firmware:
    def __init__(self, value=0, fail_readback=False):
        self.value = value
        self.writes = []
        self.fail_readback = fail_readback

    def call(self, method, value=None):
        if method == p.STATE:
            if self.fail_readback and self.writes == [1]:
                raise RuntimeError("lost response")
            return self.value
        if value == 255:
            return 255
        self.writes.append(value)
        self.value = value
        return value


class Tests(unittest.TestCase):
    def test_rejects_unknown_firmware(self):
        info = dict(vendor="SAMSUNG ELECTRONICS CO., LTD.", product="Galaxy Book 12",
                    safi=True, reviewed_firmware=True)
        p.require_reviewed(info)
        for key, value in (("vendor", "other"), ("product", "other"),
                           ("safi", False), ("reviewed_firmware", False)):
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                p.require_reviewed({**info, key: value})

    def test_response_errors_are_not_success(self):
        self.assertEqual(p.parse_integer("0xff\0\n"), 255)
        for text in ("Error: AE_NOT_FOUND", "not called", "", "[0x1]", "0x1 garbage"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                p.parse_integer(text)

    def test_probe_does_not_write_preference(self):
        fw = Firmware()
        self.assertEqual(p.probe(fw), 0)
        self.assertEqual(fw.writes, [])

    def test_trial_restores_original(self):
        fw = Firmware()
        p.trial(fw, 1, 1, sleep=lambda _: None)
        self.assertEqual(fw.writes, [1, 0])
        self.assertEqual(fw.value, 0)

    def test_interrupt_restores_original(self):
        def interrupt(_):
            raise KeyboardInterrupt
        fw = Firmware()
        with self.assertRaises(KeyboardInterrupt):
            p.trial(fw, 1, 1, sleep=interrupt)
        self.assertEqual(fw.value, 0)

    def test_failed_readback_restores_original(self):
        fw = Firmware(fail_readback=True)
        with self.assertRaises(RuntimeError):
            p.trial(fw, 1, 1)
        self.assertEqual(fw.writes, [1, 0])

    def test_same_preference_does_not_write(self):
        fw = Firmware(1)
        p.trial(fw, 1, 1)
        self.assertEqual(fw.writes, [])

    def test_unknown_original_is_not_modified(self):
        fw = Firmware(7)
        with self.assertRaises(RuntimeError):
            p.trial(fw, 1, 1)
        self.assertEqual(fw.writes, [])

    def test_invalid_requests_never_reach_transport(self):
        for request, seconds in ((255, 30), (1, 0), (1, 301)):
            fw = Firmware()
            with self.assertRaises(ValueError):
                p.trial(fw, request, seconds)
            self.assertEqual(fw.writes, [])
        with self.assertRaises(ValueError):
            p.Acpi().call(r"\UNKNOWN", 1)


if __name__ == "__main__":
    unittest.main()

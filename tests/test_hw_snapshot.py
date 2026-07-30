#!/usr/bin/env python3
"""Unit tests for hw_test.py's pure snapshot helpers.

Regression guard for the slot-8 blind spot: sid_list_* have 9 entries and the
U64 "Tuneful Eight" fills slots 1..8, but read_snapshot/snapshots_equal used to
iterate range(8) and silently ignored the last one.

Run:  python tests/test_hw_snapshot.py
"""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import hw_test  # noqa: E402


def fake_memory(addrs, types):
    """Build a read_mem_byte stand-in over contiguous l/h/t arrays at 0/16/32."""
    lo = {0 + i: a & 0xFF for i, a in enumerate(addrs)}
    hi = {16 + i: (a >> 8) & 0xFF for i, a in enumerate(addrs)}
    tp = {32 + i: t for i, t in enumerate(types)}
    table = {**lo, **hi, **tp}
    return lambda addr: table[addr]


TUNEFUL_EIGHT = [0x0000, 0xD400, 0xD420, 0xD480, 0xD4A0,
                 0xD500, 0xD520, 0xD580, 0xD5A0]
EIGHT_TYPES = [0x00, 0x02, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x22]


class SnapshotTests(unittest.TestCase):
    def test_reads_all_nine_slots(self):
        with mock.patch.object(hw_test, "read_mem_byte",
                               fake_memory(TUNEFUL_EIGHT, EIGHT_TYPES)):
            snap = hw_test.read_snapshot(0, 16, 32)
        self.assertEqual(len(snap), 9)
        # Slot 8 is the one the old range(8) loop dropped.
        self.assertEqual(snap[8]["addr"], 0xD5A0)
        self.assertEqual(snap[8]["type"], 0x22)

    def test_slot8_difference_is_detected(self):
        """A change confined to slot 8 must make snapshots compare unequal."""
        with mock.patch.object(hw_test, "read_mem_byte",
                               fake_memory(TUNEFUL_EIGHT, EIGHT_TYPES)):
            baseline = hw_test.read_snapshot(0, 16, 32)

        drifted_types = list(EIGHT_TYPES)
        drifted_types[8] = 0xF0          # slot 8 lost / mis-typed
        with mock.patch.object(hw_test, "read_mem_byte",
                               fake_memory(TUNEFUL_EIGHT, drifted_types)):
            drifted = hw_test.read_snapshot(0, 16, 32)

        self.assertFalse(hw_test.snapshots_equal(baseline, drifted),
                         "slot-8 drift went unnoticed — the range(8) bug is back")

    def test_identical_snapshots_compare_equal(self):
        with mock.patch.object(hw_test, "read_mem_byte",
                               fake_memory(TUNEFUL_EIGHT, EIGHT_TYPES)):
            a = hw_test.read_snapshot(0, 16, 32)
            b = hw_test.read_snapshot(0, 16, 32)
        self.assertTrue(hw_test.snapshots_equal(a, b))

    def test_fmt_snapshot_lists_all_eight_sids(self):
        with mock.patch.object(hw_test, "read_mem_byte",
                               fake_memory(TUNEFUL_EIGHT, EIGHT_TYPES)):
            snap = hw_test.read_snapshot(0, 16, 32)
        text = hw_test.fmt_snapshot(snap)
        self.assertIn("D5A0", text, "slot 8 missing from the printed summary")
        self.assertEqual(text.count("$D"), 8, "expected all 8 SIDs listed")


if __name__ == "__main__":
    unittest.main(verbosity=2)

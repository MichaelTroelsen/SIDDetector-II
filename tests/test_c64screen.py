#!/usr/bin/env python3
"""Unit tests for the shared C64 screen-code decoder.

variant_smoke.py and hw_test.py used to each carry their own hand-rolled table.
They had drifted: one had `+` and `*` but not `( ) =`, the other the reverse, and
hw_test's docstring claimed it matched variant_smoke's. Anything unmapped became
'.', so differences inside the unmapped set were invisible in a golden diff.

Run:  python tests/test_c64screen.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import c64screen  # noqa: E402


class TableTests(unittest.TestCase):
    def test_letters(self):
        self.assertEqual(c64screen.decode_row(bytes([0x01, 0x1A])), "AZ")

    def test_digits(self):
        self.assertEqual(c64screen.decode_row(bytes(range(0x30, 0x3A))), "0123456789")

    def test_ascii_identical_range(self):
        """$20-$3F are byte-identical to ASCII; that is why the table is short."""
        for c in range(0x21, 0x40):
            self.assertEqual(c64screen.decode_row(bytes([c])), chr(c),
                             f"screencode ${c:02X} should decode to ASCII")

    def test_both_previously_divergent_sets_are_covered(self):
        # variant_smoke had these, hw_test did not:
        self.assertEqual(c64screen.decode_row(bytes([0x2B, 0x2A])), "+*")
        # hw_test had these, variant_smoke did not:
        self.assertEqual(c64screen.decode_row(bytes([0x28, 0x29, 0x3D])), "()=")

    def test_blank_codes(self):
        """Both $20 (space-filled screens) and $00 (untouched RAM) read blank."""
        self.assertEqual(c64screen.decode_row(bytes([0x00, 0x20, 0x00])), "")

    def test_unmapped_falls_back_to_dot(self):
        for c in (0x1C, 0x1E, 0x1F, 0x40, 0x7F, 0xA0, 0xFF):
            self.assertEqual(c64screen.decode_row(bytes([c, 0x01])), "." + "A",
                             f"${c:02X} should fall back to '.'")

    def test_trailing_blanks_stripped(self):
        self.assertEqual(c64screen.decode_row(bytes([0x01, 0x20, 0x20])), "A")

    def test_row_is_not_left_stripped(self):
        """Column alignment matters: leading blanks must survive."""
        self.assertEqual(c64screen.decode_row(bytes([0x20, 0x20, 0x01])), "  A")


class ScreenTests(unittest.TestCase):
    def test_decode_screen_splits_rows(self):
        raw = bytes([0x01] * 40 + [0x02] * 40)
        self.assertEqual(c64screen.decode_screen(raw), ["A" * 40, "B" * 40])

    def test_row_count_inferred(self):
        self.assertEqual(len(c64screen.decode_screen(bytes(1000))), 25)


class ConsumerAgreementTests(unittest.TestCase):
    def test_both_harnesses_decode_identically(self):
        """The whole point of the shared module."""
        import hw_test
        import variant_smoke
        row = bytes([0x08, 0x05, 0x0C, 0x0C, 0x0F, 0x20,
                     0x28, 0x34, 0x32, 0x30, 0x29, 0x3D, 0x2A, 0x2B])
        self.assertEqual(variant_smoke.decode(row), hw_test.decode_screen(row))
        self.assertEqual(variant_smoke.decode(row), "HELLO (420)=*+")


if __name__ == "__main__":
    unittest.main(verbosity=2)

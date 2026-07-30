#!/usr/bin/env python3
"""Unit tests for variant_smoke.py's screen decode / golden rendering.

Regression guard for the retry-star flake: siddetector appends '*' after
"6581 FOUND" / "8580 FOUND" when checkrealsid needed a bad-line retry. That
depends on raster timing and host load, so a byte-exact golden containing it
fails at random — observed on a full sweep as

    -golden  r06: 8580 SID...: 8580 FOUND
    +actual  r06: 8580 SID...: 8580 FOUND.

Run:  python tests/test_variant_render.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import variant_smoke as vs  # noqa: E402

# C64 screencodes for the uppercase/graphics set used by the result screen.
_ENC = {" ": 0x20, ".": 0x2E, ":": 0x3A, "/": 0x2F, "+": 0x2B, "-": 0x2D,
        "*": 0x2A}


def encode(text):
    """ASCII -> C64 screencodes, padded to a full 40-column row."""
    out = bytearray()
    for ch in text:
        if "A" <= ch <= "Z":
            out.append(ord(ch) - ord("A") + 1)
        elif "0" <= ch <= "9":
            out.append(ord(ch))
        else:
            out.append(_ENC[ch])
    return bytes(out).ljust(40, b"\x20")


def screen(rows):
    """Build a 1000-byte screen image from {row_index: text}."""
    raw = bytearray(b"\x20" * 1000)
    for r, text in rows.items():
        raw[r * 40:(r + 1) * 40] = encode(text)
    return bytes(raw)


class DecodeTests(unittest.TestCase):
    def test_star_decodes_as_star_not_dot(self):
        """'*' used to fall through to the '.' catch-all, making diffs cryptic."""
        self.assertEqual(vs.decode(encode("8580 FOUND*")), "8580 FOUND*")

    def test_ordinary_row_roundtrips(self):
        self.assertEqual(vs.decode(encode("8580 SID...: 8580 FOUND")),
                         "8580 SID...: 8580 FOUND")


class RetryStarTests(unittest.TestCase):
    def test_retry_and_clean_runs_render_identically(self):
        """The whole point: the golden must not depend on whether a retry fired."""
        clean = screen({6: "8580 SID...: 8580 FOUND"})
        retry = screen({6: "8580 SID...: 8580 FOUND*"})
        self.assertEqual(vs.render_golden(clean), vs.render_golden(retry),
                         "retry star leaked into the golden — the flake is back")

    def test_star_is_stripped_from_the_rendered_row(self):
        out = vs.render_golden(screen({6: "8580 SID...: 8580 FOUND*"}))
        self.assertIn("r06: 8580 SID...: 8580 FOUND\n", out)
        self.assertNotIn("*", out)

    def test_6581_row_also_normalised(self):
        clean = screen({5: "6581 SID...: 6581 FOUND"})
        retry = screen({5: "6581 SID...: 6581 FOUND*"})
        self.assertEqual(vs.render_golden(clean), vs.render_golden(retry))

    def test_non_star_content_is_untouched(self):
        """Stripping must not eat legitimate text."""
        row = "STEREO SID.: D420 ARMSID FOUND"
        out = vs.render_golden(screen({16: row}))
        self.assertIn(f"r16: {row}\n", out)


class GoldenShapeTests(unittest.TestCase):
    def test_golden_covers_the_expected_rows(self):
        """r00 (version banner) and r15 (decay animation) stay excluded."""
        self.assertNotIn(0, vs.GOLDEN_ROWS, "row 0 is the version banner")
        self.assertNotIn(15, vs.GOLDEN_ROWS, "row 15 animates")
        self.assertNotIn(24, vs.GOLDEN_ROWS, "row 24 is the static key legend")
        for r in (6, 16, 17):
            self.assertIn(r, vs.GOLDEN_ROWS)

    def test_every_golden_row_is_labelled(self):
        out = vs.render_golden(screen({}))
        self.assertEqual(len(out.splitlines()), len(vs.GOLDEN_ROWS))
        for line in out.splitlines():
            self.assertRegex(line, r"^r\d{2}: ")


if __name__ == "__main__":
    unittest.main(verbosity=2)

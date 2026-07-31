#!/usr/bin/env python3
"""Equivalence guard for the emulator decay classifier table (P3-5).

`checktypeandprint` (main screen) and `get_emu_page` (info page) used to be two
hand-written 6502 decision trees over the same (data1, data2, data3) decay
measurement.  They drifted apart once already -- P1-6, where the same signature
printed "UNKNOWNSID" on the main screen while the info page showed a confident
SwinSID Nano page.  Both are now driven from one table, `emu_class_tab`.

This test parses that table straight out of siddetector.asm and checks it still
reproduces the original decision trees exactly, for BOTH consumers.  The
reference trees below are transcribed from the pre-P3-5 source and must not be
"fixed" to match the table -- if they disagree, the table is what changed.

Exhaustiveness: the trees compare data3 only against $02 and zero, never
against anything else, so data3 in {0x00, 0x02, <any other>} covers its whole
behaviour.  data1 and data2 are compared against many values, so both are swept
over the full 0..255.  That makes 256 * 256 * 3 = 196,608 cases a complete
proof over the input space, not a sample.
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASM = os.path.join(ROOT, "siddetector.asm")

# Info page numbers, as named in the asm equates block.
IP_SWINU, IP_FPGA8580, IP_ULTI, IP_VICE, IP_HOXS, IP_UNKNOWN = 4, 6, 9, 10, 11, 16

# Sentinel for "checktypeandprint printed nothing at all" -- distinct from
# printing the UNKNOWNSID string, which is a different observable outcome.
NOTHING = "<no string printed>"


# --------------------------------------------------------------------------
# Reference: the two decision trees exactly as they were before P3-5.
# Transcribed from siddetector.asm at commit 0e3d056.
# --------------------------------------------------------------------------
def ref_checktypeandprint(d1, d2, d3):
    if d3 == 0x02:
        return "sunknown"                                    # + raw byte dump
    if 0x01 <= d1 <= 0x02 and d2 == 0x00:
        return "sunknown"
    if 0xDA <= d1 <= 0xF1 and d2 == 0x00:
        return "sULTIsid"
    if d2 == 0x19 and d3 == 0x00:
        return "shoxs"
    if d2 == 0x07 and d3 == 0x00:
        return "sResidfp6581d"
    if d1 == 0x05 and d2 == 0x00:
        return "sFast6581d"
    if d2 == 0x03 and d3 == 0x00:
        return "sResid6581d"
    if 0x16 <= d2 <= 0x18 and d3 == 0x00:
        return "sSwinsidU"
    if 0x05 <= d2 <= 0x06 and d3 == 0x00:
        return "sFPGAsid"
    if d2 == 0x98 and d3 == 0x00:
        return "sResid8580"
    if d2 == 0x01 and d3 == 0x00:
        return "sResid6581"
    if 0x02 <= d1 <= 0x04 and d2 == 0x00:
        return "sFastSid"
    return NOTHING


def ref_get_emu_page(d1, d2, d3):
    if d3 == 0x02:
        return IP_UNKNOWN
    if 0x01 <= d1 <= 0x02 and d2 == 0x00:
        return IP_UNKNOWN
    if 0xDA <= d1 <= 0xF1 and d2 == 0x00:
        return IP_ULTI
    if d2 == 0x19 and d3 == 0x00:
        return IP_HOXS
    if d2 == 0x07 and d3 == 0x00:
        return IP_VICE
    if d1 == 0x05 and d2 == 0x00:
        return IP_VICE
    if d2 == 0x03 and d3 == 0x00:
        return IP_VICE
    if 0x16 <= d2 <= 0x18 and d3 == 0x00:
        return IP_SWINU
    if 0x05 <= d2 <= 0x06 and d3 == 0x00:
        return IP_FPGA8580
    if d2 == 0x98 and d3 == 0x00:
        return IP_VICE
    if d2 == 0x01 and d3 == 0x00:
        return IP_VICE
    if 0x02 <= d1 <= 0x04 and d2 == 0x00:
        return IP_VICE
    return IP_UNKNOWN


# --------------------------------------------------------------------------
# Parse emu_class_tab out of the asm.
# --------------------------------------------------------------------------
def parse_table():
    with open(ASM, "r", encoding="utf-8", errors="replace") as fh:
        src = fh.read()

    body = re.search(
        r"^emu_class_tab:\s*$(.*?)^emu_class_tab_end:", src, re.S | re.M)
    if not body:
        raise AssertionError("emu_class_tab / emu_class_tab_end not found in siddetector.asm")

    consts = dict(re.findall(r"^\.const\s+(\w+)\s*=\s*(\S+)", src, re.M))

    def val(tok):
        tok = tok.strip()
        if tok in consts:
            return val(consts[tok])
        if tok.startswith("$"):
            return int(tok[1:], 16)
        return int(tok, 10)

    rows, pending = [], None
    for line in body.group(1).splitlines():
        line = re.sub(r"//.*", "", line).strip()
        if not line:
            continue
        if line.startswith(".byte"):
            parts = [p for p in line[len(".byte"):].split(",")]
            assert len(parts) == 4, f"expected 4 bytes per row, got: {line}"
            pending = [val(p) for p in parts]
        elif line.startswith(".word"):
            assert pending is not None, f".word without a preceding .byte: {line}"
            rows.append(tuple(pending) + (line[len(".word"):].strip(),))
            pending = None
    assert pending is None, "trailing .byte row with no .word string pointer"
    return rows


def table_match(rows, d1, d2, d3):
    """Mirror of emu_class_match: first row wins, or None."""
    for sel, lo, hi, page, string in rows:
        if sel == 0:
            pri, zero = d1, d2
        else:
            pri, zero = d2, d3
        if zero == 0 and lo <= pri <= hi:
            return page, string
    return None


class TestEmuClassifierTable(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = parse_table()

    def test_row_count(self):
        """EMUTAB_ROWS in the asm must match what is actually in the table."""
        with open(ASM, "r", encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        declared = int(re.search(r"^\.const\s+EMUTAB_ROWS\s*=\s*(\d+)", src, re.M).group(1))
        self.assertEqual(len(self.rows), declared,
                         "EMUTAB_ROWS disagrees with the number of rows in emu_class_tab")

    def test_first_match_wins_is_load_bearing(self):
        """Row order matters: data1=$02/data2=0 must be UNKNOWNSID, not FastSID.

        The UNKNOWNSID row ($01-$02) and the VICE FastSID row ($02-$04) overlap
        at exactly $02.  If the table is ever reordered or sorted, this is the
        case that silently changes meaning.
        """
        hit = table_match(self.rows, 0x02, 0x00, 0x00)
        self.assertIsNotNone(hit)
        self.assertEqual(hit[0], IP_UNKNOWN)
        self.assertEqual(hit[1], "sunknown")

    def test_exhaustive_equivalence(self):
        """Table reproduces BOTH original trees over the whole input space."""
        # data3 is only ever compared to $02 and to zero, so three
        # representatives cover it completely.  0x01 stands for "any other".
        checked = 0
        for d3 in (0x00, 0x02, 0x01):
            for d1 in range(256):
                for d2 in range(256):
                    checked += 1

                    if d3 == 0x02:
                        got_page, got_str = IP_UNKNOWN, "sunknown"
                    else:
                        hit = table_match(self.rows, d1, d2, d3)
                        if hit is None:
                            got_page, got_str = IP_UNKNOWN, NOTHING
                        else:
                            got_page, got_str = hit

                    want_page = ref_get_emu_page(d1, d2, d3)
                    if got_page != want_page:
                        self.fail(
                            f"get_emu_page mismatch at data1=${d1:02X} "
                            f"data2=${d2:02X} data3=${d3:02X}: "
                            f"table={got_page} reference={want_page}")

                    want_str = ref_checktypeandprint(d1, d2, d3)
                    if got_str != want_str:
                        self.fail(
                            f"checktypeandprint mismatch at data1=${d1:02X} "
                            f"data2=${d2:02X} data3=${d3:02X}: "
                            f"table={got_str} reference={want_str}")
        self.assertEqual(checked, 256 * 256 * 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)

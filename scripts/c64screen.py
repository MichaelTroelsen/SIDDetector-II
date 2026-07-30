#!/usr/bin/env python3
"""C64 screen-code decoding, shared by every harness that reads screen RAM.

There used to be two hand-rolled copies that had quietly diverged:

    variant_smoke.decode()   had  + and *   but not  ( ) =
    hw_test.decode_screen()  had  ( ) =     but not  + and *
                             ...and its docstring claimed it matched the other one.

Anything unmapped became '.', so a change within the unmapped set was invisible
in a golden diff, and a real '*' showed up as '.' in one place and nowhere in the
other. That is how the retry-star flake (CODE-REVIEW.md P0-4) managed to read as
`8580 FOUND.` instead of `8580 FOUND*`.

The table below is a superset of both, and it is built on a useful property
rather than an enumeration: **C64 screen codes $20-$3F are byte-identical to
ASCII** (space through '?'), so that whole range needs no mapping at all.
Letters live at $01-$1A, which is the only part that has to be shifted.

Unmapped codes still fall back to '.', but the set that reaches the fallback is
now just the graphics glyphs ($40-$7F), the reverse-video half ($80-$FF) and the
three oddballs $1C/$1E/$1F (British pound, up-arrow, left-arrow) which have no
sensible ASCII form.
"""

__all__ = ["decode_row", "decode_screen", "SCREEN_COLS", "SCREEN_ROWS"]

SCREEN_COLS = 40
SCREEN_ROWS = 25


def _decode_byte(c):
    if c == 0x00 or c == 0x20:
        # $00 is 'commercial at' in a real character ROM, but every screen this
        # repo dumps is either space-filled ($20) or untouched RAM ($00), so
        # treating both as blank is what makes rows compare sensibly.
        return " "
    if 0x01 <= c <= 0x1A:
        return chr(0x40 + c)            # $01..$1A -> 'A'..'Z'
    if c == 0x1B:
        return "["
    if c == 0x1D:
        return "]"
    if 0x21 <= c <= 0x3F:
        return chr(c)                   # ASCII-identical: ! " # $ ... < = > ?
    return "."


_TABLE = [_decode_byte(c) for c in range(256)]


def decode_row(row_bytes):
    """Decode one row of screen codes to text, right-stripped."""
    return "".join(_TABLE[b] for b in row_bytes).rstrip()


def decode_screen(raw, rows=None, cols=SCREEN_COLS):
    """Decode a screen image into a list of text rows.

    `raw` is screen RAM starting at the top-left cell. `rows` defaults to as many
    whole rows as `raw` holds.
    """
    if rows is None:
        rows = len(raw) // cols
    return [decode_row(raw[r * cols:(r + 1) * cols]) for r in range(rows)]


if __name__ == "__main__":
    # Show the mapping, so a future reader can eyeball it without reading code.
    for lo in range(0x00, 0x40, 0x10):
        cells = " ".join(f"{c:02X}={_TABLE[c]}" for c in range(lo, lo + 0x10))
        print(cells)

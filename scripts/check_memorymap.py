#!/usr/bin/env python3
"""Verify (or fix) docs/MEMORYMAP.md addresses match siddetector.sym.

Scans MEMORYMAP.md for table rows of the form:
    | $XXXX | `symname` | ... |

For each row, looks up `symname` in siddetector.sym (.label form) and
flags any mismatch. Used as a doc-drift guard.

  python scripts/check_memorymap.py           # verify, exit 1 on drift
  python scripts/check_memorymap.py --fix     # rewrite drifted addresses
  python scripts/check_memorymap.py --strict  # also fail on dead symbols

Exit code 0 if all addresses match (or --fix succeeded), 1 if drift
found in verify mode.

--strict additionally fails when a documented non-zero-page symbol no longer
exists in siddetector.sym at all. Without it, renaming or deleting a symbol
leaves MEMORYMAP.md pointing at a label that is gone while the guard still
reports success — the doc rots in exactly the way this script exists to catch.
Zero-page equates are always exempt: they are .const values that KickAssembler
never emits to the .sym file, so they are expected to be unresolvable.

The document's HEADER is checked too — its `**Version:**` and `**Build output:**`
lines. This used to be the guard's blind spot: only table rows were validated,
so the header sat at V1.4.44 and `code $2400-$594F` through several releases
while `--strict` reported success. Both lines are now derived from build
artifacts rather than maintained by hand — the version from the screen title in
siddetector.asm (the same string bump_version.sh treats as canonical), and the
segment extents from the <Block> START/END pairs in siddetector.dbg, which is
KickAssembler's own memory map and is rewritten on every build. Header drift
fails like address drift, and --fix rewrites it.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYM_PATH = ROOT / "siddetector.sym"
DBG_PATH = ROOT / "siddetector.dbg"
ASM_PATH = ROOT / "siddetector.asm"
DOC_PATH = ROOT / "docs" / "MEMORYMAP.md"

# Human names for each segment, keyed by its start address. A block whose start
# is not listed still gets reported, as "segment @ $XXXX" — silence would
# reintroduce exactly the blind spot this header check exists to close.
SEGMENT_NAMES = {
    0x0801: "BASIC stub",
    0x0A00: "TLR sid-detect2",
    0x1800: "Triangle Intro tune",
    0x2400: "code",
    0x5B00: "tlr_sweep",
    0x6000: "data",
    0x9200: "tracker",
    0xA000: "Delirious 9 tune",
    0xC020: "tune-mgmt",
    0xC300: "Q page",
}

NDASH = "–"


def load_symbols() -> dict[str, int]:
    """Parse `.label name=$XXXX` lines into {name: address_int}."""
    syms: dict[str, int] = {}
    pat = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$([0-9a-fA-F]+)")
    for line in SYM_PATH.read_text().splitlines():
        m = pat.match(line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    return syms


def doc_rows() -> list[tuple[int, str, int]]:
    """Yield (line_no, sym_name, doc_addr) for each parseable MEMORYMAP row."""
    pat = re.compile(r"^\|\s*\$([0-9A-Fa-f]{4})\b.*?\|\s*`([A-Za-z_][A-Za-z0-9_]*)`")
    rows: list[tuple[int, str, int]] = []
    for i, line in enumerate(DOC_PATH.read_text(encoding="utf-8").splitlines(), 1):
        m = pat.match(line)
        if m:
            rows.append((i, m.group(2), int(m.group(1), 16)))
    return rows


def blocks_from_dbg() -> list[tuple[int, int]]:
    """Extent of each <Block> in siddetector.dbg as (start, end).

    KickAssembler emits one line per emitted range; a block's extent is the
    lowest start and highest end across its lines. This is the same data the
    assembler prints as its "Memory Map".
    """
    text = DBG_PATH.read_text(encoding="utf-8", errors="replace")
    blocks: list[tuple[int, int]] = []
    for body in re.findall(r'<Block\b[^>]*>(.*?)</Block>', text, re.S):
        pairs = re.findall(r"\$([0-9a-fA-F]{4})\s*,\s*\$([0-9a-fA-F]{4})", body)
        if not pairs:
            continue
        starts = [int(a, 16) for a, _ in pairs]
        ends = [int(b, 16) for _, b in pairs]
        blocks.append((min(starts), max(ends)))
    return sorted(blocks)


def expected_build_line() -> str:
    parts = [
        f"{SEGMENT_NAMES.get(start, f'segment @ ${start:04X}')} "
        f"${start:04X}{NDASH}${end:04X}"
        for start, end in blocks_from_dbg()
    ]
    return "**Build output:** " + ", ".join(parts)


def expected_version_line() -> str | None:
    m = re.search(r"SIDDETECTOR (V\d+\.\d+\.\d+)",
                  ASM_PATH.read_text(encoding="utf-8", errors="replace"))
    return f"**Version:** {m.group(1)}" if m else None


def header_issues() -> list[tuple[int, str, str]]:
    """(line_no, current_text, expected_text) for stale header lines."""
    wanted = {"**Version:**": expected_version_line(),
              "**Build output:**": expected_build_line()}
    issues: list[tuple[int, str, str]] = []
    for i, line in enumerate(
            DOC_PATH.read_text(encoding="utf-8").splitlines(), 1):
        for prefix, expected in wanted.items():
            if expected and line.startswith(prefix):
                if line.rstrip() != expected:
                    issues.append((i, line.rstrip(), expected))
    return issues


def main() -> int:
    fix = "--fix" in sys.argv[1:]
    strict = "--strict" in sys.argv[1:]
    syms = load_symbols()
    rows = doc_rows()
    misses, drifts, ok = [], [], 0
    for line_no, name, doc_addr in rows:
        actual = syms.get(name)
        if actual is None:
            misses.append((line_no, name, doc_addr))
            continue
        if actual != doc_addr:
            drifts.append((line_no, name, doc_addr, actual))
            continue
        ok += 1

    if drifts:
        print(f"Address drift in {DOC_PATH.name}:")
        for line_no, name, doc_addr, actual in drifts:
            print(
                f"  line {line_no:>4}: `{name}` doc=${doc_addr:04X} "
                f"actual=${actual:04X}"
            )

    # Zero-page rows are .const equates KickAssembler never writes to the .sym
    # file, so "unresolved" is normal for them. A non-ZP row that resolves to
    # nothing is a real dead reference — the doc names a label that is gone.
    unresolved = [m for m in misses if not _is_zp_addr(m[2])]
    if unresolved:
        print(f"Symbols not found in {SYM_PATH.name} (non-ZP):")
        for line_no, name, doc_addr in unresolved:
            print(f"  line {line_no:>4}: `{name}` doc=${doc_addr:04X}")

    headers = header_issues()
    if headers:
        print(f"Stale header in {DOC_PATH.name}:")
        for line_no, current, expected in headers:
            print(f"  line {line_no:>4}: have {current}")
            print(f"             want {expected}")

    total = len(rows)
    print(
        f"\n{ok}/{total} matched, {len(drifts)} drift, "
        f"{len(misses)} unresolved ({len(unresolved)} non-ZP), "
        f"{len(headers)} header"
    )

    if fix and (drifts or headers):
        print(f"\nApplying --fix to {DOC_PATH}…")
        text = DOC_PATH.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        for line_no, name, doc_addr, actual in drifts:
            old = f"${doc_addr:04X}"
            new = f"${actual:04X}"
            # Patch only the first $XXXX field on the line (table address column).
            line = lines[line_no - 1]
            patched = re.sub(re.escape(old), new, line, count=1)
            if patched == line:
                # Try lowercase variant just in case.
                patched = re.sub(re.escape(old.lower()), new, line, count=1)
            lines[line_no - 1] = patched
        for line_no, _current, expected in headers:
            line = lines[line_no - 1]
            # Markdown uses trailing double-space as a hard line break — keep
            # whatever the line already ended with, including its newline.
            trailer = line[len(line.rstrip()):]
            lines[line_no - 1] = expected + trailer
        DOC_PATH.write_text("".join(lines), encoding="utf-8")
        if drifts:
            print(f"Rewrote {len(drifts)} address(es).")
        if headers:
            print(f"Rewrote {len(headers)} header line(s).")
        return 0

    if drifts or headers:
        return 1
    if strict and unresolved:
        print(
            f"\nFAIL (--strict): {len(unresolved)} documented non-ZP symbol(s) "
            f"no longer exist in {SYM_PATH.name}."
        )
        return 1
    return 0


def _is_zp_addr(addr: int) -> bool:
    return addr <= 0xFF


if __name__ == "__main__":
    sys.exit(main())

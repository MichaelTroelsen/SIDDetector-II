#!/usr/bin/env python3
"""Verify (or fix) docs/MEMORYMAP.md addresses match siddetector.sym.

Scans MEMORYMAP.md for table rows of the form:
    | $XXXX | `symname` | ... |

For each row, looks up `symname` in siddetector.sym (.label form) and
flags any mismatch. Used as a doc-drift guard.

  python scripts/check_memorymap.py        # verify, exit 1 on drift
  python scripts/check_memorymap.py --fix  # rewrite drifted addresses

Exit code 0 if all addresses match (or --fix succeeded), 1 if drift
found in verify mode.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYM_PATH = ROOT / "siddetector.sym"
DOC_PATH = ROOT / "docs" / "MEMORYMAP.md"


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


def main() -> int:
    fix = "--fix" in sys.argv[1:]
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
    if misses:
        # Symbols not in .sym are usually expected (constants, ZP equates not exported,
        # documentation-only references). Print them at lower priority.
        unresolved = [m for m in misses if not _is_zp_addr(m[2])]
        if unresolved:
            print(f"Symbols not found in {SYM_PATH.name} (non-ZP):")
            for line_no, name, doc_addr in unresolved:
                print(f"  line {line_no:>4}: `{name}` doc=${doc_addr:04X}")

    total = len(rows)
    print(
        f"\n{ok}/{total} matched, {len(drifts)} drift, "
        f"{len(misses)} unresolved"
    )

    if fix and drifts:
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
        DOC_PATH.write_text("".join(lines), encoding="utf-8")
        print(f"Rewrote {len(drifts)} address(es).")
        return 0

    return 1 if drifts else 0


def _is_zp_addr(addr: int) -> bool:
    return addr <= 0xFF


if __name__ == "__main__":
    sys.exit(main())

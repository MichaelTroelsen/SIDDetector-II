#!/usr/bin/env python3
"""End-to-end U64 8-SID regression test, non-destructive.

1. Snapshot the current U64 runtime config to bin/_u64_pretest_backup.json
   (gitignored — overwritten each run).
2. Read bin/tt8-ultimate.cfg (INI), convert to the JSON shape
   `c64u config set-multiple` expects.
3. Apply tt8 to the U64 (no save-to-flash; runtime only).
4. Boot siddetector.prg, wait for detection to settle.
5. Pause CPU, read sidnum_zp + sid_list, dump screen rows 16-23.
6. Restore the pre-test config from the snapshot, regardless of pass/fail.
7. Print pass/fail based on sidnum_zp >= 4 (behavioral U64 threshold)
   plus the slot addresses.
"""
import configparser
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
C64U = str(ROOT / "bin" / "c64u")
PRG = str(ROOT / "siddetector.prg")
CFG = ROOT / "bin" / "tt8-ultimate.cfg"
JSON_OUT = ROOT / "bin" / "tt8-ultimate.json"
BACKUP = ROOT / "bin" / "_u64_pretest_backup.json"
HOST = os.environ.get("C64U_HOST", "192.168.1.64")


def cfg_to_json() -> dict:
    """Parse the INI cfg, strip leading-whitespace from values, return dict."""
    parser = configparser.ConfigParser(strict=False)
    parser.optionxform = str  # preserve key case
    parser.read(CFG, encoding="utf-8")
    out: dict[str, dict[str, str]] = {}
    for section in parser.sections():
        items: dict[str, str] = {}
        for k, v in parser.items(section):
            items[k.strip()] = v.strip()
        out[section] = items
    return out


def c64u(*args: str, capture: bool = False, retries: int = 3) -> str:
    """Run c64u once. On HTTP timeout / connect-refused, sleep + retry up to
    `retries` times — applying the SID config can briefly take the U64's HTTP
    listener offline as it re-initialises hardware."""
    cmd = [C64U, "--host", HOST, *args]
    last_err = ""
    for attempt in range(retries + 1):
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
        last_err = (result.stderr or "") + (result.stdout or "")
        # Retry only on transient connection failures.
        transient = ("dial tcp" in last_err) or ("EOF" in last_err) or (
            "connection reset" in last_err
        )
        if not transient or attempt == retries:
            break
        wait = 2 + attempt * 2
        sys.stderr.write(f"  (attempt {attempt + 1}/{retries + 1}: connection issue; retrying in {wait}s)\n")
        time.sleep(wait)
    if not capture:
        sys.stderr.write(f"FAIL: {' '.join(cmd)}\n{last_err}\n")
    return result.stdout


def read_byte(addr: int) -> int:
    out = c64u("machine", "read-mem", f"{addr:04X}", "--length", "1", capture=True)
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(f"{addr:04X}:"):
            return int(line.split()[1], 16)
    raise RuntimeError(f"could not read ${addr:04X}: {out}")


def read_bytes(addr: int, length: int) -> bytes:
    out = c64u(
        "machine", "read-mem", f"{addr:04X}", "--length", str(length), capture=True
    )
    buf: list[int] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or ":" not in line[:6]:
            continue
        if line[:1] not in "0123456789ABCDEF":
            continue
        try:
            tokens = line.split()[1:]
        except IndexError:
            continue
        for tok in tokens:
            if len(tok) == 2 and all(c in "0123456789abcdefABCDEF" for c in tok):
                buf.append(int(tok, 16))
            else:
                break
    return bytes(buf[:length])


def is_u64_label_addr() -> int:
    """Look up `is_u64` in siddetector.sym at run time so the test survives
    address drift across builds."""
    sym_path = ROOT / "siddetector.sym"
    for line in sym_path.read_text().splitlines():
        if line.startswith(".label is_u64="):
            return int(line.split("$")[-1], 16)
    raise RuntimeError("is_u64 not found in siddetector.sym")


def main() -> int:
    # Snapshot only the categories tt8 modifies. `config export` (full dump)
    # currently fails when the U64 firmware returns malformed JSON for the
    # "SID Socket 1: ARMSID" section, so we go category-by-category and merge.
    print(f"=== Step 1: snapshot current U64 config -> {BACKUP.name} ===")
    snapshot_cats = ["Audio Mixer", "UltiSID Configuration", "SID Addressing"]
    snap: dict[str, dict[str, str]] = {}
    for cat in snapshot_cats:
        out = c64u("config", "show", cat, "--json", capture=True)
        try:
            parsed = json.loads(out)
        except json.JSONDecodeError:
            print(f"  WARNING: failed to parse category {cat!r}; skipping")
            continue
        if not isinstance(parsed, dict):
            print(f"  WARNING: category {cat!r} response not a dict; skipping")
            continue
        # `config show --json` returns {"<cat>": {...}, "errors": []} on success;
        # populated `errors` or `success: false` means a connection / API failure.
        errs = parsed.get("errors")
        if errs:
            print(f"  WARNING: category {cat!r} returned errors {errs!r}; skipping")
            continue
        if parsed.get("success") is False:
            print(f"  WARNING: category {cat!r} returned success=false; skipping")
            continue
        if cat not in parsed:
            print(f"  WARNING: category {cat!r} missing from response; skipping")
            continue
        snap[cat] = parsed[cat]
    if not snap:
        print("  ERROR: snapshot empty — refusing to apply tt8. Check U64 connectivity.")
        if BACKUP.exists():
            BACKUP.unlink()
        return 2
    BACKUP.write_text(json.dumps(snap, indent=2), encoding="utf-8")
    cats = ", ".join(snap.keys())
    print(f"  saved {BACKUP.stat().st_size} bytes ({cats})")

    print(f"\n=== Step 2: convert {CFG.name} -> JSON ===")
    settings = cfg_to_json()
    JSON_OUT.write_text(json.dumps(settings, indent=2), encoding="utf-8")
    sid_addressing = settings.get("SID Addressing", {})
    print(f"  UltiSID 1 Address: {sid_addressing.get('UltiSID 1 Address')}")
    print(f"  UltiSID 2 Address: {sid_addressing.get('UltiSID 2 Address')}")
    print(f"  UltiSID Range Split: {sid_addressing.get('UltiSID Range Split')}")

    rc = 1
    try:
        print(f"\n=== Step 3: apply tt8 config to U64 @ {HOST} ===")
        c64u("config", "set-multiple", str(JSON_OUT))
        # Applying SID-addressing changes briefly takes the U64's HTTP
        # listener offline; pause to let it come back before the run-prg call.
        time.sleep(3.0)

        print(f"\n=== Step 4: boot siddetector.prg + wait for detection ===")
        c64u("runners", "run-prg-upload", PRG)
        time.sleep(14)

        print(f"\n=== Step 5: pause + read state ===")
        c64u("machine", "pause")
        sidnum = read_byte(0x00F7)
        print(f"  sidnum_zp = ${sidnum:02X} ({sidnum})")

        sid_list_l = read_bytes(0x6009, 9)
        sid_list_h = read_bytes(0x6012, 9)
        sid_list_t = read_bytes(0x601B, 9)
        print(f"  sid_list_l: {' '.join(f'{b:02X}' for b in sid_list_l)}")
        print(f"  sid_list_h: {' '.join(f'{b:02X}' for b in sid_list_h)}")
        print(f"  sid_list_t: {' '.join(f'{b:02X}' for b in sid_list_t)}")
        print(f"  detected slots:")
        for i in range(1, 9):
            if sid_list_t[i] == 0 and sid_list_h[i] == 0:
                continue
            addr = (sid_list_h[i] << 8) | sid_list_l[i]
            print(f"    slot {i}: ${addr:04X}  type=${sid_list_t[i]:02X}")

        is_u64 = read_byte(is_u64_label_addr())
        print(f"  is_u64 = ${is_u64:02X}")

        print(f"\n=== Step 6: dump screen rows 16-23 ===")
        rows_raw = read_bytes(0x0680, 320)
        TBL = (
            "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
            " !\"#$%&'()*+,-./0123456789:;<=>?"
            "-ABCDEFGHIJKLMNOPQRSTUVWXYZ.....`"
        )
        def conv(c: int) -> str:
            c &= 0x7F
            return TBL[c] if c < len(TBL) else "?"

        for r in range(8):
            line = "".join(conv(b) for b in rows_raw[r * 40 : (r + 1) * 40])
            print(f"  row {16 + r}: |{line}|")

        c64u("machine", "resume")

        threshold = 4
        if sidnum >= threshold and is_u64 == 0x01:
            print(f"\nPASS: sidnum_zp = {sidnum} >= {threshold}, is_u64 = 1")
            rc = 0
        else:
            print(
                f"\nFAIL: sidnum_zp = {sidnum} (expected >= {threshold}), "
                f"is_u64 = {is_u64}"
            )
    finally:
        if BACKUP.exists() and BACKUP.stat().st_size >= 100:
            print(f"\n=== Step 7: restore pre-test config from {BACKUP.name} ===")
            c64u("config", "set-multiple", str(BACKUP))
            print("  restored.")
        else:
            print(
                f"\n=== Step 7: SKIPPED restore (snapshot at {BACKUP.name} "
                f"missing or too small)."
            )
    return rc


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""End-to-end U64 8-SID regression test.

1. Read bin/tt8-ultimate.cfg (INI), convert to the JSON shape
   `c64u config set-multiple` expects.
2. Apply the config to the live U64 (no save-to-flash; runtime only).
3. Boot siddetector.prg, wait for detection to settle.
4. Pause CPU, read sidnum_zp + sid_list, dump screen rows 16-23.
5. Print pass/fail based on sidnum_zp >= 4 (behavioral U64 threshold)
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


def c64u(*args: str, capture: bool = False) -> str:
    cmd = [C64U, "--host", HOST, *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if capture:
        return result.stdout
    if result.returncode != 0:
        sys.stderr.write(f"FAIL: {' '.join(cmd)}\n{result.stderr}\n{result.stdout}\n")
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


def main() -> int:
    print(f"=== Step 1: convert {CFG.name} -> JSON ===")
    settings = cfg_to_json()
    JSON_OUT.write_text(json.dumps(settings, indent=2), encoding="utf-8")
    sid_addressing = settings.get("SID Addressing", {})
    print(f"  UltiSID 1 Address: {sid_addressing.get('UltiSID 1 Address')}")
    print(f"  UltiSID 2 Address: {sid_addressing.get('UltiSID 2 Address')}")
    print(f"  UltiSID Range Split: {sid_addressing.get('UltiSID Range Split')}")

    print(f"\n=== Step 2: apply config to U64 @ {HOST} ===")
    c64u("config", "set-multiple", str(JSON_OUT))
    time.sleep(0.5)

    print(f"\n=== Step 3: boot siddetector.prg + wait for detection ===")
    c64u("runners", "run-prg-upload", PRG)
    time.sleep(14)

    print(f"\n=== Step 4: pause + read state ===")
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

    is_u64 = read_byte(0x592E)
    print(f"  is_u64 = ${is_u64:02X}")

    print(f"\n=== Step 5: dump screen rows 16-23 ===")
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

    print()
    threshold = 4
    if sidnum >= threshold and is_u64 == 0x01:
        print(f"PASS: sidnum_zp = {sidnum} >= {threshold}, is_u64 = 1")
        return 0
    print(f"FAIL: sidnum_zp = {sidnum} (expected >= {threshold}), is_u64 = {is_u64}")
    return 1


if __name__ == "__main__":
    sys.exit(main())

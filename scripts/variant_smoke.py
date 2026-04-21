#!/usr/bin/env python3
"""
variant_smoke.py — Detection regression test for every SidVariant personality.

Two modes:

  1. **Verify** (default):  launch the patched WinVICE 3.9 headless with
     `-sidvariant <name>`, autostart siddetector.prg, dump the screen through
     the VICE remote monitor, and compare it to a stored *golden* fingerprint
     in `tests/variant_goldens/<name>.txt`.  Any divergence fails the run.
     On top of the golden diff, the per-row substring check (kept from the
     earlier smoke-test version) still runs so mismatches are easy to spot.

  2. **Update** (`--update`): run every case but *write* the current screen
     as the new golden instead of comparing.  Use this after an intentional
     change to siddetector's UI or after extending a variant personality.

Usage:
    make test-variants
    python scripts/variant_smoke.py
    python scripts/variant_smoke.py sidfx armsid-d420    # subset by name
    python scripts/variant_smoke.py --update             # refresh goldens
"""
import os, re, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = os.path.join(ROOT, "siddetector.prg")
PORT = 6502
WAIT = 14.0
GOLDENS = os.path.join(ROOT, "tests", "variant_goldens")

# Rows included in the golden.  r00 (version banner) and r15 ($D418 decay
# animation) are intentionally excluded because they're dynamic / time-based.
# r24 (key legend) is static but stripped to keep goldens focused on
# detection results.
GOLDEN_ROWS = list(range(1, 15)) + list(range(16, 24))

# (variant name, CLI flags list, row index, expected substring on that row)
# Rows match siddetector.asm labels: r03 SWINSID, r04 FPGASID, r05 6581,
# r06 8580, r07 SIDKICK, r08 BACKSID, r09 KUNGFUSID, r10 PD SID, r12 SIDFX,
# r14 USID64, r16+ STEREO SID list.
CASES = [
    ("none",          ["-sidextra", "0"],                              6,  "8580 FOUND"),
    ("armsid-d420",   ["-sidextra", "1", "-sidvariant2", "armsid"],   17,  "ARMSID FOUND"),
    ("arm2sid-d420",  ["-sidextra", "1", "-sidvariant2", "arm2sid"],  17,  "ARMSID FOUND"),
    ("swinu",         ["-sidextra", "0", "-sidvariant",  "swinu"],     3,  "SWINSID ULTIMATE"),
    ("swinnano",      ["-sidextra", "0", "-sidvariant",  "swinnano"],  3,  "SWINSID NANO"),
    ("fpgasid8580",   ["-sidextra", "0", "-sidvariant",  "fpgasid8580"], 4, "FPGASID 8580"),
    ("fpgasid6581",   ["-sidextra", "0", "-sidvariant",  "fpgasid6581"], 4, "FPGASID 6581"),
    ("pdsid",         ["-sidextra", "0", "-sidvariant",  "pdsid"],    10,  "PD SID FOUND"),
    ("kungfusid-new", ["-sidextra", "0", "-sidvariant",  "kungfusid-new"], 9, "KUNGFUSID"),
    ("backsid",       ["-sidextra", "0", "-sidvariant",  "backsid"],   8,  "BACKSID FOUND"),
    ("usid64",        ["-sidextra", "0", "-sidvariant",  "usid64"],   14,  "USID64 FOUND"),
    ("sidfx",         ["-sidextra", "0", "-sidvariant",  "sidfx"],    12,  "SIDFX FOUND"),
    ("skpico-8580",   ["-sidextra", "0", "-sidvariant",  "skpico-8580"], 7, "SIDKICK"),
    ("skpico-6581",   ["-sidextra", "0", "-sidvariant",  "skpico-6581"], 7, "SIDKICK"),
]


def mon_connect(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.socket()
            s.connect(("127.0.0.1", PORT))
            return s
        except OSError:
            time.sleep(0.3)
    raise RuntimeError("VICE monitor never came up")


def recv_prompt(s, t=3):
    s.settimeout(1.5)
    buf = b""
    end = time.time() + t
    while time.time() < end:
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
            if re.search(rb"\(C:\$[0-9a-fA-F]{4}\)", buf):
                return buf
        except socket.timeout:
            continue
    return buf


def dump_screen(path):
    s = mon_connect()
    recv_prompt(s)
    s.sendall(f'save "{path}" 0 0400 07e7\n'.encode())
    recv_prompt(s)
    s.sendall(b"x\n")
    recv_prompt(s, t=2)
    s.close()
    with open(path, "rb") as f:
        return f.read()[2:]


def decode(row_bytes):
    def dec(c):
        if c in (0x20, 0x00): return " "
        if 0x01 <= c <= 0x1A: return chr(ord('A') + c - 1)
        if 0x30 <= c <= 0x39: return chr(c)
        if c == 0x2E: return "."
        if c == 0x3A: return ":"
        if c == 0x2F: return "/"
        if c == 0x2B: return "+"
        if c == 0x2D: return "-"
        return "."
    return "".join(dec(b) for b in row_bytes).rstrip()


def render_golden(raw):
    """Select + decode the stable subset of rows for the golden file."""
    lines = []
    for r in GOLDEN_ROWS:
        lines.append(f"r{r:02d}: " + decode(raw[r*40:(r+1)*40]))
    return "\n".join(lines) + "\n"


def compare_golden(name, current):
    """Return (ok, diff_text).  If no golden exists, record as missing."""
    path = os.path.join(GOLDENS, f"{name}.txt")
    if not os.path.isfile(path):
        return False, f"<no golden at {path} — run with --update to create>"
    with open(path, "r", encoding="utf-8") as f:
        want = f.read()
    if want == current:
        return True, ""
    # Minimal unified-diff-ish output: line-by-line
    out = []
    w_lines = want.splitlines()
    c_lines = current.splitlines()
    n = max(len(w_lines), len(c_lines))
    for i in range(n):
        w = w_lines[i] if i < len(w_lines) else "<eof>"
        c = c_lines[i] if i < len(c_lines) else "<eof>"
        if w != c:
            out.append(f"    -golden  {w}")
            out.append(f"    +actual  {c}")
    return False, "\n".join(out)


def run_case(name, args, row, expected, update):
    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    # `+sfxse` force-disables the SFX Sound Expander cartridge regardless of
    # what's in ~/.vice/vice.ini — otherwise a user that's run `make sfx`
    # once carries the SFXSoundExpander=1 setting and it perturbs the
    # golden diff (row 18 gets "DF40 SFX/FM FOUND").
    proc = subprocess.Popen(
        [VICE, "-autostart", PRG, "+sfxse",
         "-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{PORT}"] + args,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(WAIT)
        path = os.path.join(os.environ.get("TMP", "/tmp"), f"variant_{name}.bin")
        raw = dump_screen(path)
    finally:
        subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    row_text = decode(raw[row*40:(row+1)*40])
    substring_ok = expected in row_text
    golden_text = render_golden(raw)

    if update:
        os.makedirs(GOLDENS, exist_ok=True)
        with open(os.path.join(GOLDENS, f"{name}.txt"), "w", encoding="utf-8") as f:
            f.write(golden_text)
        status = "WROTE"
        detail = ""
    else:
        golden_ok, diff = compare_golden(name, golden_text)
        ok = substring_ok and golden_ok
        status = "PASS" if ok else "FAIL"
        detail = ""
        if not substring_ok:
            detail = f"  (row check: '{expected}' not in r{row:02d})"
        elif not golden_ok:
            detail = "  (golden diff:)\n" + diff

    print(f"  {status:5s} {name:14s}  r{row:02d}: {row_text}{detail}")
    return update or (substring_ok and golden_ok)


def main():
    args_iter = iter(sys.argv[1:])
    update = False
    selected_names = []
    for a in args_iter:
        if a == "--update":
            update = True
        else:
            selected_names.append(a)

    selected = [c for c in CASES if (not selected_names) or c[0] in selected_names]
    passes = 0
    for name, args, row, expected in selected:
        if run_case(name, args, row, expected, update):
            passes += 1
    total = len(selected)
    action = "WROTE" if update else "PASS"
    print(f"\nSidVariant smoke: {passes}/{total} {action}")
    return 0 if passes == total else 1


if __name__ == "__main__":
    sys.exit(main())

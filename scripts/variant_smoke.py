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
# 20 s wait — tri-SID configs (3× ResID) load slower than single-SID; 14 s
# used to be enough but triple-SID autostart can straddle that boundary.
WAIT = 20.0
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

    # -----------------------------------------------------------------------
    # Multi-SID scenarios.  `-sidextra N` enables SIDs #2..N+1.  The address
    # of each extra SID is set by Sid{2,3}AddressStart via -sid{2,3}address
    # (decimal, e.g. $D420 = 54304).  Default primary is plain 8580 ResID.
    # -----------------------------------------------------------------------

    # Secondary ARMSID at different addresses.
    ("stereo-D500-armsid",
        ["-sidextra", "1", "-sid2address", "54528",      # $D500
         "-sidvariant2", "armsid"],
        17, "ARMSID FOUND"),
    # ARMSID @ $DE00: siddetector's ARMSID scan explicitly skips $DE/$DF
    # expansion space (s_s_is_armsid `cmp #$DE / bcs s_s_arm_skip`).  The
    # chip is still detected via fiktivloop and shows up as generic 8580 —
    # matches real-hardware behaviour when ARMSID lives in cartridge space.
    ("stereo-DE00-armsid",
        ["-sidextra", "1", "-sid2address", "56832",      # $DE00
         "-sidvariant2", "armsid"],
        17, "DE00 8580"),

    # Secondary SwinSID U / FPGASID at non-default slots.
    ("stereo-D500-swinu",
        ["-sidextra", "1", "-sid2address", "54528",
         "-sidvariant2", "swinu"],
        17, "SWINSID ULTIMATE"),
    # FPGASID as *secondary* SID: the magic-cookie protocol ($81/$65 →
    # D419/D41A, read D41F=$3F/$00) only lives at primary $D400 addresses.
    # A FPGASID-personality on SID #2 never sees those writes and thus
    # falls through to checkrealsid, which detects it as a plain 8580.
    # Real FPGASID hardware is always the primary chip; this case stays
    # as a regression guard to make sure we haven't accidentally broken
    # the fall-through.
    ("stereo-D500-fpgasid8580",
        ["-sidextra", "1", "-sid2address", "54528",
         "-sidvariant2", "fpgasid8580"],
        17, "D500 8580"),

    # Triple-SID: 8580 @ D400 + ARMSID @ D420 + 8580 @ D500.
    # Expect: r17 ARMSID @ D420, r18 8580 @ D500.
    ("tri-D420-armsid+D500-8580",
        ["-sidextra", "2",
         "-sid2address", "54304",      # $D420
         "-sid3address", "54528",      # $D500
         "-sidvariant2", "armsid"],
        17, "ARMSID FOUND"),

    # Triple-SID: 8580 @ D400 + ARMSID @ D420 + 8580 @ DE00.
    # Classic "3-SID expander board" layout.
    ("tri-D420-armsid+DE00-8580",
        ["-sidextra", "2",
         "-sid2address", "54304",
         "-sid3address", "56832",      # $DE00
         "-sidvariant2", "armsid"],
        17, "ARMSID FOUND"),

    # Triple-SID mixed personalities: ARMSID @ D420 + FPGASID @ D500.
    ("tri-D420-armsid+D500-fpgasid",
        ["-sidextra", "2",
         "-sid2address", "54304",
         "-sid3address", "54528",
         "-sidvariant2", "armsid",
         "-sidvariant3", "fpgasid8580"],
        17, "ARMSID FOUND"),

    # Dual ARMSID — both secondary slots wear ARMSID.
    ("tri-D420-armsid+D500-armsid",
        ["-sidextra", "2",
         "-sid2address", "54304",
         "-sid3address", "54528",
         "-sidvariant2", "armsid",
         "-sidvariant3", "armsid"],
        17, "ARMSID FOUND"),

    # -----------------------------------------------------------------------
    # $DE00 — cartridge / stereo-expander space.  siddetector treats this
    # differently from D4xx-D7xx: the ARMSID / SwinSID-U DIS-echo scan is
    # explicitly skipped in DE/DF to avoid disturbing SIDFX and other I/O-2
    # cartridges.  Plain ResID chips at DE00 are still discovered by the
    # mirror-trick `fiktivloop` and reported via their real-SID dispatch.
    # -----------------------------------------------------------------------

    # Plain 8580 at DE00 — the most common "stereo expander cartridge"
    # layout.  Should be found by fiktivloop as a regular 8580.
    ("stereo-DE00-8580",
        ["-sidextra", "1", "-sid2address", "56832"],    # $DE00
        17, "DE00 8580"),

    # SwinSID Ultimate at DE00 — like ARMSID, SwinU uses the DIS protocol
    # which siddetector skips in DE/DF.  Expected fallback: 8580.
    ("stereo-DE00-swinu",
        ["-sidextra", "1", "-sid2address", "56832",
         "-sidvariant2", "swinu"],
        17, "DE00 8580"),

    # Triple-SID "Rad-expander" layout: plain 8580 at D400 + D500 + DE00.
    # All three identified as 8580 via fiktivloop and listed on r16-r18.
    ("tri-D500+DE00-plain-8580",
        ["-sidextra", "2",
         "-sid2address", "54528",       # $D500
         "-sid3address", "56832"],      # $DE00
        17, "D500 8580"),

    # (Dropped: "primary ARMSID + 8580 @ DE00" — in this layout VICE doesn't
    # route $D420-$D7FF to any chip, so accesses mirror back onto chip 0's
    # ARMSID, causing siddetector to *ghost-detect* ARMSID at $D420 via
    # its CS2-DIS mirror path.  On real hardware the same setup would
    # route those addresses into open bus and the ghost wouldn't appear.
    # Test left here as a comment to document the VICE-specific quirk.)

    # -----------------------------------------------------------------------
    # MIDI cartridges — codebase.c64.org/doku.php?id=base:c64_midi_interfaces
    # The patched WinVICE 3.9 (built with --enable-midi) emulates 5 cart
    # types via `-midi -miditype N`.  Per the reference + user constraint,
    # only ONE MIDI cart can be attached at a time.  All cases use the
    # default 8580 at $D400, so r06 still says "8580 FOUND"; the MIDI
    # detection lands on r11 (the NOSID line) at col 25.
    # Sequential and Namesoft share the polled-read fingerprint (only the
    # IRQ vs NMI line differs); siddetector reports both as SEQUENTIAL.
    # -----------------------------------------------------------------------
    ("midi-sequential",
        ["-sidextra", "0", "-midi", "-miditype", "0"],
        11, "SEQUENTIAL MIDI"),
    ("midi-passport",
        ["-sidextra", "0", "-midi", "-miditype", "1"],
        11, "PASSPORT MIDI"),
    ("midi-datel",
        ["-sidextra", "0", "-midi", "-miditype", "2"],
        11, "DATEL MIDI"),
    ("midi-namesoft",
        ["-sidextra", "0", "-midi", "-miditype", "3"],
        11, "SEQUENTIAL MIDI"),    # indistinguishable from Sequential
    ("midi-maplin",
        ["-sidextra", "0", "-midi", "-miditype", "4"],
        11, "MAPLIN MIDI"),
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


def _launch_and_capture(name, args):
    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    # `-default` resets every VICE resource to its default *before* per-test
    # flags are applied.  Without it, persistent settings written by
    # interactive `make stereo-*` / `make sfx` runs (Sid{2..8}AddressStart,
    # SFXSoundExpander, etc.) leak into ~/.vice/vice.ini and bias detection
    # — observed: stale Sid2AddressStart=$D420 rerouted skpico-8580's mirror
    # scan onto $D420 instead of $D460.  `-default` makes the harness
    # independent of whatever the user's local ini happens to hold.
    # `+sfxse` is kept as a belt-and-braces guard for SFX specifically.
    proc = subprocess.Popen(
        [VICE, "-default", "-autostart", PRG, "+sfxse",
         "-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{PORT}"] + args,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(WAIT)
        path = os.path.join(os.environ.get("TMP", "/tmp"), f"variant_{name}.bin")
        raw = dump_screen(path)
    finally:
        subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return raw


def run_case(name, args, row, expected, update):
    raw = _launch_and_capture(name, args)
    row_text = decode(raw[row*40:(row+1)*40])
    substring_ok = expected in row_text
    golden_text_first = render_golden(raw)
    golden_ok_first, _ = (True, "") if update else compare_golden(name, golden_text_first)
    # Up to 2 retries on timing flake — host-CPU variance or heavy tri-SID
    # load occasionally straddles the WAIT budget; also absorbs intermittent
    # VICE open-bus reads on $DF60 that look like SFX/FM to checkfmyam.
    retries = 0
    while not update and retries < 2 and (not substring_ok or not golden_ok_first):
        retries += 1
        raw = _launch_and_capture(name, args)
        row_text = decode(raw[row*40:(row+1)*40])
        substring_ok = expected in row_text
        golden_text_first = render_golden(raw)
        golden_ok_first, _ = compare_golden(name, golden_text_first)
    golden_text = golden_text_first

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

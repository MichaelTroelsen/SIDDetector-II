#!/usr/bin/env python3
"""
vice_coldboot_test.py — Stress test cold-boot D420 detection.

Launches WinVICE N times from scratch (fresh autostart each time), captures
the detection result, kills VICE, and repeats.  Reports hit-rate.

Usage:
    python scripts/vice_coldboot_test.py [n]       # default 10

Useful if the flakiness is specific to the first detection pass on a newly
booted VICE (where ResID and SID2 haven't been warmed up).
"""
import os, sys, time, socket, subprocess, re

HERE    = os.path.dirname(os.path.abspath(__file__))
ROOT    = os.path.dirname(HERE)
VICE    = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG     = os.path.join(ROOT, "siddetector.prg")
PORT    = 6502
WAIT    = 14.0
SHOT_DIR= os.environ.get("TMP", "/tmp")


def mon_connect(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.socket()
            s.connect(("127.0.0.1", PORT))
            return s
        except OSError:
            time.sleep(0.3)
    raise RuntimeError("monitor never came up")


def recv_prompt(s, timeout=5):
    s.settimeout(1.5)
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = s.recv(4096)
            if not chunk: break
            buf += chunk
            if re.search(rb"\(C:\$[0-9a-fA-F]{4}\)", buf):
                return buf.decode("latin-1", "replace")
        except socket.timeout:
            continue
    return buf.decode("latin-1", "replace")


def read_screen_rows():
    bin_path = os.path.join(SHOT_DIR, "_screen.bin")
    s = mon_connect()
    recv_prompt(s)
    s.sendall(f'save "{bin_path}" 0 0400 07e7\n'.encode()); recv_prompt(s)
    s.sendall(b"x\n"); recv_prompt(s, timeout=2)
    s.close()
    with open(bin_path, "rb") as f:
        raw = f.read()[2:]

    def dec(c):
        if c in (0x20, 0x00): return " "
        if 0x01 <= c <= 0x1A: return chr(ord('A') + c - 1)
        if 0x30 <= c <= 0x39: return chr(c)
        if c in (0x2E,0x3A,0x2F,0x2B,0x2D,0x28,0x29,0x24):
            return "?.:/+-()$"[(c - 0x24) % 10] if False else chr(c)
        return "."
    return ["".join(dec(raw[r*40 + c]) for c in range(40)).rstrip()
            for r in range(25)]


def read_dbg():
    """Read dbg_d420_* + sid_list."""
    bin_path = os.path.join(SHOT_DIR, "_dbg.bin")
    s = mon_connect()
    recv_prompt(s)
    s.sendall(f'save "{bin_path}" 0 5890 5895\n'.encode()); recv_prompt(s)
    # Also save sid_list (num_sids, sid_list_l/h/t — each is 8 or 9 bytes)
    sid_path = os.path.join(SHOT_DIR, "_sidlist.bin")
    s.sendall(f'save "{sid_path}" 0 6000 6020\n'.encode()); recv_prompt(s)
    # sidnum_zp at $F7 (ZP) holds the real count
    zp_path = os.path.join(SHOT_DIR, "_zp.bin")
    s.sendall(f'save "{zp_path}" 0 00F7 00F7\n'.encode()); recv_prompt(s)
    s.sendall(b"x\n"); recv_prompt(s, timeout=2)
    s.close()
    with open(bin_path, "rb") as f:
        raw = f.read()[2:]
    with open(sid_path, "rb") as f:
        sid = f.read()[2:]
    with open(zp_path, "rb") as f:
        num = f.read()[2]   # 2-byte PRG header + 1 byte data
    ll = list(sid[8:16])
    hh = list(sid[16:24])
    tt = list(sid[24:32])
    entries = [(hh[i]<<8)|ll[i] for i in range(1, num+1)] if num else []
    types   = [tt[i] for i in range(1, num+1)] if num else []
    return {
        "hits":       raw[0],
        "patched_lo": raw[1],
        "first_read": raw[2],
        "nz_read":    raw[3],
        "patched_hi": raw[4],
        "env3":       raw[5],
        "num_sids":   num,
        "entries":    entries,
        "types":      types,
    }


def run_once():
    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    p = subprocess.Popen(
        [VICE, "-autostart", PRG,
         "-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{PORT}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(WAIT)
    rows = read_screen_rows()
    dbg = read_dbg()
    d420 = any("D420" in r and "FOUND" in r for r in rows)
    return d420, rows, dbg


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    hits = misses = 0
    fails = []
    try:
        for i in range(1, n + 1):
            d420, rows, dbg = run_once()
            tag = "D420+" if d420 else "NO-D420"
            ents = ", ".join(f"${a:04X}=${t:02X}" for a,t in zip(dbg['entries'], dbg['types']))
            # fields: hits=stopsrealsid D420 entries; env3=s_s_add D420 hits;
            # nz_read=data1 at add (or A at stop); first_read=sidtype at add (or X at stop);
            # patched_hi=fll_try_real D420 hits
            dbgstr = (f"stop={dbg['hits']} s_s_add={dbg['env3']} "
                      f"fll_try={dbg['patched_hi']} "
                      f"data1=${dbg['nz_read']:02X} sidtype=${dbg['first_read']:02X} "
                      f"list[{dbg['num_sids']}]={ents}")
            print(f"run {i:02d}: {tag:8s} {dbgstr}")
            if d420: hits += 1
            else:
                misses += 1
                fails.append((i, rows))
        print(f"\nD420 hits {hits}/{n}  misses {misses}/{n}")
        if fails:
            print("\nFailure details:")
            for idx, rows in fails:
                print(f"  run {idx}:")
                for r, ln in enumerate(rows):
                    if ln and any(k in ln for k in ("FOUND","STEREO","D400","D420","SFX")):
                        print(f"    r{r:02d}: {ln}")
    finally:
        subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()

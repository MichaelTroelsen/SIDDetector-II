#!/usr/bin/env python3
"""Synthesize the post-detection state with 8 SIDs and re-render the screen
so we can confirm sidstereo_print + the static row layout handle a full
Tuneful Eight without truncation. Boots VICE, waits for detection to land
in kbdloop, freezes execution, pokes sidnum_zp=8 + sid_list slots 1..8 with
varied chip types, then JSRs printscreen + sidstereo_print and dumps the
screen RAM."""
import os, time, socket, subprocess, re

VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = r"C:/Users/mit/claude/c64server/siddetector2/siddetector.prg"
PORT = 6502

def sym(name):
    with open("siddetector.sym") as f:
        for line in f:
            m = re.match(rf"\.label\s+{re.escape(name)}\s*=\s*\$([0-9a-fA-F]+)", line)
            if m: return int(m.group(1), 16)
    raise KeyError(name)

NUM_SIDS    = sym("num_sids")
SID_L       = sym("sid_list_l")
SID_H       = sym("sid_list_h")
SID_T       = sym("sid_list_t")
SIDSTEREO   = sym("sidstereo_print")
PRINTSCREEN = sym("printscreen")
KBDLOOP     = sym("kbdloop")

# 8 synthetic SIDs across the canonical U64 Tuneful Eight layout.
# Type codes: $20 = ULTISID-8580-LO, $22 = ULTISID-6581. Mix to verify
# colour/text rendering for both branches.
SLOTS = [
    (0x00, 0xD4, 0x20),  # row 16
    (0x20, 0xD4, 0x22),  # row 17
    (0x00, 0xD5, 0x20),  # row 18
    (0x20, 0xD5, 0x22),  # row 19
    (0x00, 0xD6, 0x20),  # row 20
    (0x20, 0xD6, 0x22),  # row 21
    (0x00, 0xD7, 0x20),  # row 22
    (0x20, 0xD7, 0x22),  # row 23
]

def connect():
    for _ in range(60):
        try:
            s = socket.socket(); s.connect(("127.0.0.1", PORT)); return s
        except OSError:
            time.sleep(0.3)
    raise RuntimeError("no monitor")

def recv(s, t=3):
    s.settimeout(1.5); b=b""; end=time.time()+t
    while time.time() < end:
        try:
            c = s.recv(4096)
            if not c: break
            b += c
            if re.search(rb"\(C:\$[0-9a-fA-F]{4}\)", b): return b
        except socket.timeout:
            continue
    return b

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(0.5)
subprocess.Popen([VICE,"-autostart",PRG,"-remotemonitor","-remotemonitoraddress",f"127.0.0.1:{PORT}"],
                 stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(14)

s = connect(); recv(s)

# 1. Pause and poke sidnum_zp + sid_list arrays.
def poke(addr, b): s.sendall(f">${addr:04x} {b:02x}\n".encode()); recv(s)
poke(0x00F7, 0x08)   # sidnum_zp = 8
poke(NUM_SIDS, 0x08) # num_sids[0] = 8 (cosmetic; sidstereo_print uses sidnum_zp)
for i, (lo, hi, t) in enumerate(SLOTS, start=1):
    poke(SID_L + i, lo)
    poke(SID_H + i, hi)
    poke(SID_T + i, t)

# 2. Build a tiny stub at $0334 that re-paints the static screen and then
# calls sidstereo_print, then BRK. Set PC = $0334.
stub = bytes([
    0x20, PRINTSCREEN & 0xff, (PRINTSCREEN >> 8) & 0xff,   # JSR printscreen
    0x20, SIDSTEREO   & 0xff, (SIDSTEREO   >> 8) & 0xff,   # JSR sidstereo_print
    0x4c, KBDLOOP     & 0xff, (KBDLOOP     >> 8) & 0xff,   # JMP kbdloop (clean exit)
])
for i, b in enumerate(stub):
    poke(0x0334 + i, b)
s.sendall(b"r pc=$0334\n"); recv(s)
s.sendall(b"x\n"); recv(s, 1); s.close()
time.sleep(2.0)   # let printscreen + sidstereo_print + a couple of IRQs run

# 3. Re-attach, dump screen RAM 25×40.
s = connect(); recv(s)
scr_path = os.environ.get("TMP","/tmp") + "/eightsid_scr.bin"
s.sendall(f"save \"{scr_path}\" 0 0400 07e7\n".encode()); recv(s)
s.sendall(b"x\n"); recv(s,1); s.close()
time.sleep(0.3)

with open(scr_path,"rb") as f: data = f.read()
if len(data) >= 1002: data = data[2:1002]
TBL = (
    "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
    " !\"#$%&'()*+,-./0123456789:;<=>?"
    "-ABCDEFGHIJKLMNOPQRSTUVWXYZ.....`"
)
def conv(c):
    c &= 0x7f
    if c < len(TBL): return TBL[c]
    return '?'

print("+" + "-"*40 + "+")
for r in range(25):
    line = "".join(conv(b) for b in data[r*40:(r+1)*40])
    marker = "  <-- row" if 16 <= r <= 23 else ""
    print(f"|{line}|{marker} {r:2d}")
print("+" + "-"*40 + "+")

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

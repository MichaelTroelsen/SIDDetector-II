#!/usr/bin/env python3
"""Smoke test for tune-switch: enter tracker view, then poke cur_tune=1 +
JSR tune_select + JSR tracker_draw_chrome to verify the title row repaints
and the dispatch operands are patched to the Delirious play address."""
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

DO_SID_MUSIC = sym("do_sid_music")
TUNE_SELECT  = sym("tune_select")
DRAW_CHROME  = sym("tracker_draw_chrome")
IRQ_PLAY_JSR = sym("irq_play_jsr")
TPI_INIT_JSR = sym("tpi_init_jsr")

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

# 1. Enter tracker view (Triangle).
s = connect(); recv(s)
s.sendall(f"r pc=${DO_SID_MUSIC:x}\n".encode()); recv(s)
s.sendall(b"x\n"); recv(s, 1); s.close()
time.sleep(1.5)

# 2. Break, force cur_tune=1, JSR tune_select, JSR tracker_draw_chrome.
s = connect(); recv(s)
print("--- pre-switch IRQ play operand:")
s.sendall(f"m ${IRQ_PLAY_JSR:04x} ${IRQ_PLAY_JSR+2:04x}\n".encode()); print(recv(s).decode(errors='replace')[-100:])
print("--- pre-switch tpi init operand:")
s.sendall(f"m ${TPI_INIT_JSR:04x} ${TPI_INIT_JSR+2:04x}\n".encode()); print(recv(s).decode(errors='replace')[-100:])

# Poke cur_tune=1.
s.sendall(b">$00c0 01\n"); recv(s)
# JSR tune_select via PC manip + breakpoint at RTS site we want to come back.
# We'll just do it by setting PC to tune_select, letting it RTS into the stack,
# accept whatever happens. Cleaner: write a tiny stub at $0334 that does
# JSR tune_select, JSR draw_chrome, brk. Then PC=$0334.
stub = bytes([
    0x20, TUNE_SELECT & 0xff, (TUNE_SELECT >> 8) & 0xff,   # JSR tune_select
    0x20, DRAW_CHROME & 0xff, (DRAW_CHROME >> 8) & 0xff,   # JSR tracker_draw_chrome
    0x00,                                                  # BRK
])
for i, b in enumerate(stub):
    s.sendall(f">${0x0334+i:04x} {b:02x}\n".encode()); recv(s)
s.sendall(b"r pc=$0334\n"); recv(s)
s.sendall(b"x\n"); recv(s, 1); s.close()
time.sleep(0.8)

# 3. Inspect.
s = connect(); recv(s)
print("--- post-switch CUR_TUNE:")
s.sendall(b"m $00c0 $00c0\n"); print(recv(s).decode(errors='replace')[-80:])
print("--- post-switch IRQ play operand (expect 05 A0):")
s.sendall(f"m ${IRQ_PLAY_JSR:04x} ${IRQ_PLAY_JSR+2:04x}\n".encode()); print(recv(s).decode(errors='replace')[-100:])
print("--- post-switch tpi init operand (expect 00 A0):")
s.sendall(f"m ${TPI_INIT_JSR:04x} ${TPI_INIT_JSR+2:04x}\n".encode()); print(recv(s).decode(errors='replace')[-100:])
print("--- $A000 first bytes (expect Delirious code, A9 01 4C 8A A2 4C B9 A2):")
# Need BASIC ROM banked out to read RAM there. The IRQ already does that during
# play; we read after IRQ has run, so $01=$37 here. Use monitor's bank command.
s.sendall(b"bank ram\n"); recv(s)
s.sendall(b"m $a000 $a008\n"); print(recv(s).decode(errors='replace')[-120:])
s.sendall(b"bank cpu\n"); recv(s)

# Dump screen RAM.
import tempfile
scr_path = os.environ.get("TMP","/tmp") + "/scr.bin"
s.sendall(f"save \"{scr_path}\" 0 0400 07e7\n".encode()); recv(s)
s.sendall(b"x\n"); recv(s,1); s.close()
time.sleep(0.5)

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
print("+"+"-"*40+"+")
for r in range(25):
    line = "".join(conv(b) for b in data[r*40:(r+1)*40])
    print("|"+line+"|")
print("+"+"-"*40+"+")

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

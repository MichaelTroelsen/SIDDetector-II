#!/usr/bin/env python3
"""Smoke test for tracker view: autostart, wait for detection, goto do_sid_music,
wait a moment, dump screen RAM, decode to text."""
import os, time, socket, subprocess, re, sys

VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = r"C:/Users/mit/claude/c64server/siddetector2/siddetector.prg"
PORT = 6502
DO_SID_MUSIC = 0x2a63

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
time.sleep(14)   # wait for detection to settle on main screen

s = connect(); recv(s)
# Inspect PC before goto.
s.sendall(b"r\n"); r1 = recv(s); print("BEFORE:", r1.decode(errors='replace')[-200:])
# Set PC via `r pc=NNNN` then resume with `x`. Using `goto` alone has been flaky.
s.sendall(f"r pc=${DO_SID_MUSIC:x}\n".encode()); recv(s)
s.sendall(b"x\n"); recv(s, 1)
s.close()
time.sleep(2.5)   # let tracker screen render a few frames

s = connect(); recv(s)
# Check PC location after goto.
s.sendall(b"r\n"); r2 = recv(s); print("AFTER:", r2.decode(errors='replace')[-200:])
# Check shadow page for non-zero.
shadow_path = os.environ.get("TMP","/tmp") + "/shadow.bin"
s.sendall(f'save "{shadow_path}" 0 $c000 $c01f\n'.encode()); recv(s)
dump_path = os.environ.get("TMP","/tmp") + "/tracker_screen.bin"
s.sendall(f'save "{dump_path}" 0 $0400 $07e7\n'.encode()); recv(s)
shot_path = os.environ.get("TMP","/tmp") + "/tracker_screen.png"
s.sendall(f'screenshot "{shot_path}" 2\n'.encode()); recv(s)
s.sendall(b"x\n"); recv(s,1); s.close()

with open(shadow_path, "rb") as f:
    shadow = f.read()[2:]
print(f"Shadow $C000: {' '.join(f'{b:02X}' for b in shadow)}")

# Re-open monitor; read the undo table and other state.
s = connect(); recv(s)
undo_path = os.environ.get("TMP","/tmp") + "/undo.bin"
# trk_undo_count is symbol, but we need the address. Read the map.
with open("siddetector.sym") as f:
    for line in f:
        if "trk_undo_count" in line:
            addr = int(line.split("=$")[1].strip(), 16)
            break
    else:
        addr = None
if addr is not None:
    s.sendall(f'save "{undo_path}" 0 {addr:x} {addr+10:x}\n'.encode()); recv(s)
    with open(undo_path,"rb") as f:
        raw = f.read()[2:]
    print(f"undo_count+first 9 undo_lo: {' '.join(f'{b:02X}' for b in raw)}")
# Check zero page tracker state
s.sendall(b'save "' + (os.environ.get("TMP","/tmp")+'/zp.bin').encode() + b'" 0 $b0 $bf\n'); recv(s)
with open(os.environ.get("TMP","/tmp")+'/zp.bin','rb') as f:
    zp = f.read()[2:]
print(f"ZP $B0-$BF: {' '.join(f'{b:02X}' for b in zp)}")
s.sendall(b"x\n"); recv(s,1); s.close()

with open(dump_path, "rb") as f:
    raw = f.read()
# VICE's save command prepends a 2-byte load-address header.
screen = raw[2:2+1000] if len(raw) >= 1002 else raw

print(f"PNG screenshot: {shot_path}")
print(f"Screen RAM bytes: {len(screen)}")
print("+" + "-" * 40 + "+")
def sc_to_char(b):
    b = b & 0x7F
    if b == 0x00: return '@'
    if 0x01 <= b <= 0x1A: return chr(ord('A') + b - 1)
    if b == 0x1B: return '['
    if b == 0x1C: return '#'
    if b == 0x1D: return ']'
    if b == 0x1E: return '^'
    if b == 0x1F: return '<'
    if 0x20 <= b <= 0x3F: return chr(b)
    if b == 0x40: return ' '
    if 0x41 <= b <= 0x5A: return chr(ord('A') + b - 0x41)
    if b == 0x60: return ' '
    if b == 0x66: return '*'
    if b == 0x71: return 'o'
    if 0x61 <= b <= 0x7F: return '.'
    if 0xA0 == b: return '#'
    return '?'
for row in range(25):
    line = ''.join(sc_to_char(screen[row * 40 + col]) for col in range(40))
    print("|" + line + "|")
print("+" + "-" * 40 + "+")

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

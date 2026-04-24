#!/usr/bin/env python3
"""Enter tracker, let it run, jump to tracker_exit, verify we return to detection."""
import os, time, socket, subprocess, re

VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = r"C:/Users/mit/claude/c64server/siddetector2/siddetector.prg"
PORT = 6502
DO_SID_MUSIC = 0x2a61
TRACKER_EXIT = 0x932f

def connect():
    for _ in range(60):
        try:
            s=socket.socket(); s.connect(("127.0.0.1",PORT)); return s
        except OSError: time.sleep(0.3)
    raise RuntimeError

def recv(s,t=3):
    s.settimeout(1.5); b=b""; end=time.time()+t
    while time.time()<end:
        try:
            c=s.recv(4096)
            if not c: break
            b+=c
            if re.search(rb"\(C:\$[0-9a-fA-F]{4}\)",b): return b
        except socket.timeout: continue
    return b

TMP = os.environ["TMP"]

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(0.5)
subprocess.Popen([VICE,"-autostart",PRG,"-remotemonitor","-remotemonitoraddress",f"127.0.0.1:{PORT}"],
                 stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(14)

# Phase 1: enter tracker
s=connect(); recv(s)
s.sendall(f"goto ${DO_SID_MUSIC:x}\n".encode()); recv(s,1); s.close()
time.sleep(3)

# Phase 2: tracker should be running; snap screenshot
s=connect(); recv(s)
s.sendall(f'screenshot "{TMP}\\p2_tracker.png" 2\n'.encode()); recv(s)
# Now jump PC to tracker_exit
s.sendall(f"goto ${TRACKER_EXIT:x}\n".encode()); recv(s,1); s.close()
time.sleep(6)  # re-detection runs ~2s; wait a bit longer

# Phase 3: should be back on detection screen
s=connect(); recv(s)
s.sendall(f'screenshot "{TMP}\\p3_detection.png" 2\n'.encode()); recv(s)
# Dump row 0 to check banner
s.sendall(f'save "{TMP}\\p3_r0.bin" 0 $0400 $0427\n'.encode()); recv(s)
# Check sid_music_flag should be 0 again, trk_patched also 0
s.sendall(f'save "{TMP}\\p3_zp.bin" 0 $b0 $bf\n'.encode()); recv(s)
s.sendall(b"x\n"); recv(s,1); s.close()
subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def load(p):
    try:
        with open(p,"rb") as f: return f.read()[2:]
    except FileNotFoundError: return None

r0 = load(f"{TMP}\\p3_r0.bin")
zp = load(f"{TMP}\\p3_zp.bin")
print("Row 0 after exit:", ' '.join(f'{b:02X}' for b in r0) if r0 else 'missing')
print("ZP $B0-$BF:", zp.hex(' ') if zp else 'missing')
print("  $B0=music_flag  $B7=trk_patched (should both be 0 after exit + restart)")
print(f"Tracker shot: {TMP}\\p2_tracker.png")
print(f"Detection shot: {TMP}\\p3_detection.png")

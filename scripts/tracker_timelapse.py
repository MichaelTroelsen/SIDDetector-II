#!/usr/bin/env python3
"""Capture several screenshots over ~12 seconds of tracker playback to see
how V1/V2 bars animate across the tune."""
import os, time, socket, subprocess, re

VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = r"C:/Users/mit/claude/c64server/siddetector2/siddetector.prg"
PORT = 6502
DO_SID_MUSIC = 0x2a63

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

# Enter tracker
s=connect(); recv(s)
s.sendall(f"goto ${DO_SID_MUSIC:x}\n".encode()); recv(s,1); s.close()

# Sample every 1.5s for 12s
for i in range(8):
    time.sleep(1.5)
    s=connect(); recv(s)
    shot = f"{TMP}\\tl_{i}.png"
    s.sendall(f'screenshot "{shot}" 2\n'.encode()); recv(s)
    # Sample shadow CTRL bytes (voice 1-3 CTRL at $C004/$C00B/$C012)
    # Put into a single file
    s.sendall(f'save "{TMP}\\sh_{i}.bin" 0 $c004 $c012\n'.encode()); recv(s)
    s.sendall(f'save "{TMP}\\zp_{i}.bin" 0 $b3 $b6\n'.encode()); recv(s)
    s.sendall(b"x\n"); recv(s,1); s.close()

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print("  i  V1_CTRL V2_CTRL V3_CTRL  V1env V2env V1prev V2prev")
for i in range(8):
    try:
        with open(f"{TMP}\\sh_{i}.bin","rb") as f:
            sh = f.read()[2:]
        v1c, v2c, v3c = sh[0], sh[7], sh[14]
        with open(f"{TMP}\\zp_{i}.bin","rb") as f:
            zp = f.read()[2:]
        v1e, v2e, v1p, v2p = zp[0], zp[1], zp[2], zp[3]
        print(f"  {i}  {v1c:02X}      {v2c:02X}      {v3c:02X}       {v1e:02X}    {v2e:02X}    {v1p:02X}     {v2p:02X}")
    except FileNotFoundError:
        print(f"  {i}  missing")
print(f"Shots: {TMP}\\tl_0.png .. tl_7.png")

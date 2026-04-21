#!/usr/bin/env python3
"""Jump PC to do_restart via VICE monitor, screenshot mid-banner."""
import os, time, socket, subprocess, re

VICE=r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG=r"C:/Users/mit/claude/c64server/siddetector2/siddetector.prg"
PORT=6502
SHOT=os.environ.get("TMP","/tmp")

def connect():
    for _ in range(60):
        try:
            s=socket.socket();s.connect(("127.0.0.1",PORT));return s
        except OSError:time.sleep(0.3)
    raise RuntimeError("no mon")

def recv(s,t=3):
    s.settimeout(1.5);b=b"";end=time.time()+t
    while time.time()<end:
        try:
            c=s.recv(4096)
            if not c:break
            b+=c
            if re.search(rb"\(C:\$[0-9a-fA-F]{4}\)",b):return b
        except socket.timeout:continue
    return b

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(0.5)
subprocess.Popen([VICE,"-autostart",PRG,"-remotemonitor","-remotemonitoraddress",f"127.0.0.1:{PORT}"],
                 stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(14)

# Connect, set PC to do_restart ($2A91), run for ~1 s, then pause and screenshot.
s=connect();recv(s)
# VICE monitor: `goto <addr>` sets PC and continues execution.
s.sendall(b"goto 2a91\n")
# Monitor releases control; CPU running.  Don't wait for prompt.
s.close()
time.sleep(0.5)
s=connect();recv(s)
row24=os.path.join(SHOT,"row24.bin")
s.sendall(f'save "{row24}" 0 07c0 07ff\n'.encode());recv(s)
p=os.path.join(SHOT,"restart_direct.png")
s.sendall(f'screenshot "{p}" 2\n'.encode());recv(s)
s.sendall(b"x\n");recv(s,1);s.close()
with open(row24,"rb") as f:raw=f.read()[2:]
print(f"row 24 bytes: {' '.join(f'{b:02X}' for b in raw[:40])}")
print(f"$07FF DIAG byte: ${raw[-1]:02X}")
subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

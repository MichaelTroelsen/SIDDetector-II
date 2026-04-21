#!/usr/bin/env python3
"""Verify SPACE reaches VICE: read $07FF (incremented by do_restart) before/after SPACE."""
import os,time,socket,subprocess,re
import win32gui,win32con,pyautogui
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

def read_byte(addr):
    p=os.path.join(SHOT,"_b.bin")
    s=connect();recv(s)
    s.sendall(f'save "{p}" 0 {addr:04x} {addr:04x}\n'.encode());recv(s)
    s.sendall(b"x\n");recv(s,1);s.close()
    with open(p,"rb") as f:return f.read()[2]

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(0.5)
subprocess.Popen([VICE,"-autostart",PRG,"-remotemonitor","-remotemonitoraddress",f"127.0.0.1:{PORT}"],
                 stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(14)

b0=read_byte(0x07FF)
print(f"before SPACE: $07FF = ${b0:02X}")

hs=[]
def _cb(h,_):
    t=win32gui.GetWindowText(h)
    if "VICE" in t and "C64" in t:hs.append(h)
win32gui.EnumWindows(_cb,None)
print(f"found windows: {hs}")
try:win32gui.ShowWindow(hs[0],win32con.SW_SHOWNORMAL)
except:pass
r=win32gui.GetWindowRect(hs[0])
pyautogui.click((r[0]+r[2])//2,(r[1]+r[3])//2);time.sleep(0.6)
pyautogui.keyDown("space");time.sleep(0.3);pyautogui.keyUp("space")
# Sample row 24 at t=0.5, 1.0, 1.5, 2.5 to observe the banner cycle.
for tag, wait in [("t=0.5", 0.5), ("t=1.0", 0.5), ("t=1.5", 0.5), ("t=2.5", 1.0)]:
    time.sleep(wait)
    p=os.path.join(SHOT,f"_r24_{tag}.bin")
    s=connect();recv(s)
    s.sendall(f'save "{p}" 0 07c0 07e7\n'.encode());recv(s)
    s.sendall(b"x\n");recv(s,1);s.close()
    with open(p,"rb") as f:raw=f.read()[2:]
    print(f"{tag}: row24 = {' '.join(f'{b:02X}' for b in raw)}")
b1=read_byte(0x07FF)
print(f"after all: $07FF = ${b1:02X}")

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

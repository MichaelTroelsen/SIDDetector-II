#!/usr/bin/env python3
"""Launch VICE, press SPACE, screenshot 1s later to capture the restart banner."""
import os, sys, time, socket, subprocess, re
import win32gui, win32con, pyautogui
HERE=os.path.dirname(os.path.abspath(__file__));ROOT=os.path.dirname(HERE)
VICE=r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe";PRG=os.path.join(ROOT,"siddetector.prg")
PORT=6502;SHOT=os.environ.get("TMP","/tmp")

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

def shot(p):
    s=connect();recv(s)
    s.sendall(f'screenshot "{p}" 2\n'.encode());recv(s)
    s.sendall(b"x\n");recv(s,1);s.close()

subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(0.5)
subprocess.Popen([VICE,"-autostart",PRG,"-remotemonitor","-remotemonitoraddress",f"127.0.0.1:{PORT}"],
                 stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(14)  # let detection finish
# find VICE window and press SPACE
hs=[]
def cb(h,_):
    t=win32gui.GetWindowText(h)
    if "VICE" in t and "C64" in t:hs.append(h)
win32gui.EnumWindows(cb,None)
if not hs:sys.exit("no VICE win")
try:win32gui.ShowWindow(hs[0],win32con.SW_SHOWNORMAL)
except:pass
r=win32gui.GetWindowRect(hs[0])
pyautogui.click((r[0]+r[2])//2,(r[1]+r[3])//2);time.sleep(0.6)
pyautogui.keyDown("space");time.sleep(0.25);pyautogui.keyUp("space")
time.sleep(3.0)   # clearly inside the 10-s diag delay
shot(os.path.join(SHOT,"restart_t30.png"))
print("saved t3.0 shot")
subprocess.run(["taskkill","/F","/IM","x64sc.exe"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

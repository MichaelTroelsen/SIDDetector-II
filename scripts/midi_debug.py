#!/usr/bin/env python3
"""Quick diagnostic: launch siddetector with -midi, dump the screen at
several wait intervals to locate where startup is stalling."""
import os, re, socket, subprocess, sys, time

VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "siddetector.prg"))
PORT = 6502


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


def dump():
    s = socket.socket()
    s.connect(("127.0.0.1", PORT))
    recv_prompt(s)
    path = os.path.join(os.environ.get("TMP", "/tmp"), "midi_debug.bin")
    s.sendall(f'save "{path}" 0 0400 07e7\n'.encode())
    recv_prompt(s)
    s.sendall(b"x\n")
    recv_prompt(s, t=2)
    s.close()
    with open(path, "rb") as f:
        return f.read()[2:]


def dec_row(b):
    out = []
    for c in b:
        if c in (0x20, 0x00):
            out.append(" ")
        elif 0x01 <= c <= 0x1A:
            out.append(chr(ord("A") + c - 1))
        elif 0x30 <= c <= 0x39:
            out.append(chr(c))
        elif c == 0x2E:
            out.append(".")
        elif c == 0x3A:
            out.append(":")
        else:
            out.append(".")
    return "".join(out).rstrip()


def main():
    flags = sys.argv[1:] or ["-midi", "-miditype", "0"]
    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    proc = subprocess.Popen(
        [VICE, "-autostart", PRG, "+sfxse", "-sidextra", "0",
         "-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{PORT}"] + flags,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for wait in (5, 10, 20, 30, 45, 60):
            time.sleep(wait - (5 if wait == 5 else 5))  # delta from previous
            print(f"\n=== screen at t={wait}s ===")
            try:
                raw = dump()
                for r in (0, 6, 8, 9, 11):
                    print(f"  r{r:02d}: {dec_row(raw[r*40:(r+1)*40])}")
            except Exception as e:
                print(f"  (dump failed: {e})")
    finally:
        subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()

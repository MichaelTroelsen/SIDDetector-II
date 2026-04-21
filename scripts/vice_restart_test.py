#!/usr/bin/env python3
"""
vice_restart_test.py — Reproduce SFX/FM false-positive and D420 re-detection drift
under WinVICE. Launches x64sc, captures the screen after initial detection,
sends SPACE to trigger re-detection, captures again, then reads both screens
and reports what changed.

Usage:
    python scripts/vice_restart_test.py [restarts]

    restarts  number of SPACE restarts to perform (default 3).

Outputs PNG screenshots to /tmp/ and prints the decoded chip-status lines.
"""
import os, sys, time, socket, subprocess, re

import win32gui, win32con
import pyautogui

HERE   = os.path.dirname(os.path.abspath(__file__))
ROOT   = os.path.dirname(HERE)
VICE   = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG    = os.path.join(ROOT, "siddetector.prg")
PORT   = 6502
WAIT   = 14.0                      # seconds for autostart LOAD/RUN + detection
SHOT_DIR = os.environ.get("TMP", "/tmp")


def find_vice_window():
    handles = []
    def cb(hwnd, _):
        title = win32gui.GetWindowText(hwnd)
        if "VICE" in title and "C64" in title:
            handles.append(hwnd)
    win32gui.EnumWindows(cb, None)
    return handles[0] if handles else None


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


def mon_recv_prompt(s, timeout=5):
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


def mon_cmd(s, cmd):
    s.sendall((cmd + "\n").encode())
    return mon_recv_prompt(s)


def screenshot(path):
    """Pause CPU via monitor, take PNG, resume."""
    s = mon_connect()
    mon_recv_prompt(s)
    mon_cmd(s, f'screenshot "{path}" 2')
    mon_cmd(s, "x")          # exit monitor (resume)
    s.close()


def read_bytes(addr_hex, length):
    """Read a small block of memory from a running VICE via the monitor.
    Returns a bytes object."""
    bin_path = os.path.join(SHOT_DIR, f"_probe_{addr_hex}.bin")
    end_hex = f"{int(addr_hex, 16) + length - 1:04x}"
    s = mon_connect()
    mon_recv_prompt(s)
    mon_cmd(s, f'save "{bin_path}" 0 {addr_hex} {end_hex}')
    mon_cmd(s, "x")
    s.close()
    with open(bin_path, "rb") as f:
        return f.read()[2:]


def screen_text(png_path):
    """Dump the siddetector screen RAM to a file and decode it.
    Returns a list of 25 40-char rows (trailing spaces stripped)."""
    bin_path = png_path.replace(".png", ".bin")
    s = mon_connect()
    mon_recv_prompt(s)
    # Save uses unquoted format: save "path" device startaddr endaddr
    # File format: 2-byte load addr + raw bytes. We only want the raw bytes.
    mon_cmd(s, f'save "{bin_path}" 0 0400 07e7')
    mon_cmd(s, "x")
    s.close()
    with open(bin_path, "rb") as f:
        raw = f.read()
    data = raw[2:]  # strip PRG load-addr header
    # Decode C64 screen codes (uppercase/graphic): 0=@ 1-26=A-Z 27=[ 28=£ 29=] 30=↑ 31=← 32=space …
    # Simple table covering rows the app uses (letters, digits, punctuation).
    def decode(c):
        if c == 0x20 or c == 0x00: return " "
        if 0x01 <= c <= 0x1A: return chr(ord('A') + c - 1)
        if 0x30 <= c <= 0x39: return chr(c)           # digits
        if c == 0x2E: return "."
        if c == 0x3A: return ":"
        if c == 0x2F: return "/"
        if c == 0x2B: return "+"
        if c == 0x2D: return "-"
        if c == 0x28: return "("
        if c == 0x29: return ")"
        if c == 0x24: return "$"
        if c == 0x21: return "!"
        if c == 0x3F: return "?"
        if c == 0x3D: return "="
        return "."
    rows = []
    for r in range(25):
        s_ = "".join(decode(data[r*40 + c]) for c in range(40))
        rows.append(s_.rstrip())
    return rows


def send_space(hwnd):
    """Bring VICE window to the front and press SPACE.
    Uses a ShowWindow + click trick because SetForegroundWindow alone is
    blocked by Windows focus rules when the current console has focus."""
    try:
        win32gui.ShowWindow(hwnd, win32con.SW_SHOWNORMAL)
    except Exception:
        pass
    # Move + click inside the VICE window to force focus
    rect = win32gui.GetWindowRect(hwnd)
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    pyautogui.click(cx, cy)
    time.sleep(0.4)
    pyautogui.press("space")
    time.sleep(0.2)


def launch_vice(extra_args=None):
    # Kill any stragglers first
    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    args = [VICE, "-autostart", PRG,
            "-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{PORT}"]
    if extra_args:
        args.extend(extra_args)
    p = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(WAIT)
    return p


def dump_status(tag, rows):
    """Print lines that contain detection results."""
    print(f"\n== {tag} ==")
    for r, line in enumerate(rows):
        if not line: continue
        # Focus on rows that show detection results
        if any(k in line for k in (
                "FOUND", "NOSID", "UNKNOWN", "DECAY",
                "STEREO", "DF40", "DF50", "ARMSID", "SFX")):
            print(f"  r{r:02d}: {line}")


def main():
    restarts = 3
    extra = []
    quiet = False
    for a in sys.argv[1:]:
        if a.isdigit():
            restarts = int(a)
        elif a == "--sfx":
            extra += ["-sfxse", "-sfxsetype", "3812"]
        elif a == "--nostereo":
            extra += ["-sidextra", "0"]
        elif a == "--quiet":
            quiet = True
    shots = []
    proc = launch_vice(extra)
    d420_hits = 0; d420_misses = 0; sfx_hits = 0
    def check(label, rows):
        has_d420 = any("D420" in ln and "FOUND" in ln for ln in rows)
        has_sfx  = any("SFX/FM" in ln and "FOUND" in ln for ln in rows)
        if not quiet:
            tag = ("D420+" if has_d420 else "NO-D420 ") + ("SFX!" if has_sfx else "ok")
            print(f"  {label:18s} {tag}")
        return has_d420, has_sfx

    try:
        png = os.path.join(SHOT_DIR, "sid_run0.png")
        screenshot(png); shots.append(png)
        rows0 = screen_text(png)
        if not quiet: dump_status("initial run", rows0)
        d, s = check("initial run", rows0)
        if d: d420_hits += 1
        else: d420_misses += 1
        if s: sfx_hits += 1

        hwnd = find_vice_window()
        if not hwnd:
            print("!! could not find VICE window; SPACE won't reach CIA")
            return 2

        for i in range(1, restarts + 1):
            send_space(hwnd)
            time.sleep(WAIT)
            png = os.path.join(SHOT_DIR, f"sid_run{i}.png")
            screenshot(png); shots.append(png)
            rows = screen_text(png)
            if not quiet: dump_status(f"after SPACE #{i}", rows)
            d, s = check(f"SPACE #{i}", rows)
            if d: d420_hits += 1
            else: d420_misses += 1
            if s: sfx_hits += 1

        total = d420_hits + d420_misses
        print(f"\nSUMMARY: D420 detected {d420_hits}/{total}  "
              f"missed {d420_misses}/{total}  "
              f"SFX false-positives {sfx_hits}/{total}")

    finally:
        subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print("\nScreenshots:", ", ".join(shots))
    return 0


if __name__ == "__main__":
    sys.exit(main())

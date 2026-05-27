"""Dump main screen RAM at $0400-$07E7 after siddetector autostart, with no jump."""
import os, re, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG = os.path.join(ROOT, "siddetector.prg")
DETECT_WAIT = 22.0

def free_port():
    s = socket.socket(); s.bind(("", 0)); p = s.getsockname()[1]; s.close(); return p

def recv_until_prompt(sock, timeout=10):
    sock.settimeout(2.0); buf = b""; deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk: break
            buf += chunk
            if re.search(rb"\(C:\$[0-9a-fA-F]{4}\)", buf):
                return buf.decode("latin-1", errors="replace")
        except socket.timeout: continue
    return buf.decode("latin-1", errors="replace")

def mon_connect(port):
    for _ in range(30):
        try:
            s = socket.socket(); s.connect(("127.0.0.1", port))
            recv_until_prompt(s, timeout=5); return s
        except OSError: time.sleep(0.3)
    raise RuntimeError("monitor connect failed")

def decode(row):
    out = []
    for c in row:
        if c in (0x20, 0x00): out.append(" ")
        elif 0x01 <= c <= 0x1A: out.append(chr(0x40 + c))
        elif 0x30 <= c <= 0x39: out.append(chr(c))
        elif c == 0x2E: out.append(".")
        elif c == 0x3A: out.append(":")
        elif c == 0x2F: out.append("/")
        elif c == 0x2B: out.append("+")
        elif c == 0x2D: out.append("-")
        elif c == 0x28: out.append("(")
        elif c == 0x29: out.append(")")
        elif c == 0x3D: out.append("=")
        else: out.append(".")
    return "".join(out).rstrip()

port = free_port()
dump_path = os.path.join(ROOT, "tests", "main_screen_dump.bin")
if os.path.exists(dump_path): os.remove(dump_path)
subprocess.run(["taskkill", "//F", "//IM", "x64sc.exe"], capture_output=True)
cmd = [VICE, "-autostart", PRG, "-remotemonitor",
       "-remotemonitoraddress", f"ip4://127.0.0.1:{port}", "+confirmonexit"]
print(f"Launching VICE (port {port}) …")
proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    print(f"Waiting {DETECT_WAIT}s …")
    time.sleep(DETECT_WAIT)
    s = mon_connect(port)
    s.sendall(f'save "{dump_path}" 0 0400 07e7\n'.encode())
    recv_until_prompt(s)
    s.sendall(b'quit\n')
    try: recv_until_prompt(s, timeout=2)
    except Exception: pass
    s.close()
    time.sleep(1.0)
    with open(dump_path, "rb") as f: raw = f.read()[2:]
    print("\n--- MAIN SCREEN (rows 0-24) ---")
    for r in range(25):
        print(f"r{r:02d}: {decode(raw[r*40:(r+1)*40])}")
finally:
    subprocess.run(["taskkill", "//F", "//IM", "x64sc.exe"], capture_output=True)
    try: proc.wait(timeout=2)
    except Exception: pass

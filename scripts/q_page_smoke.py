#!/usr/bin/env python3
"""
q_page_smoke.py — Launch siddetector under WinVICE, wait for detection, press Q,
dump the Q-page screen, decode rows, and print.  One-off verification that the
$C300 Q-page paint actually lands in screen RAM as designed.

Usage:
    python scripts/q_page_smoke.py [--variant NAME]
"""
import argparse, os, re, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG = os.path.join(ROOT, "siddetector.prg")
DETECT_WAIT = 22.0  # wait for siddetector to finish detection (matches variant_smoke)
PAINT_WAIT = 10.0   # wait for Q-page paint (decay measurement is slow)

def free_port():
    s = socket.socket()
    s.bind(("", 0))
    p = s.getsockname()[1]
    s.close()
    return p

def recv_until_prompt(sock, timeout=10):
    sock.settimeout(2.0)
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk: break
            buf += chunk
            if re.search(rb'\(C:\$[0-9a-fA-F]{4}\)', buf):
                return buf.decode("latin-1", errors="replace")
        except socket.timeout:
            continue
    return buf.decode("latin-1", errors="replace")

def mon_connect(port):
    for _ in range(30):
        try:
            s = socket.socket()
            s.connect(("127.0.0.1", port))
            recv_until_prompt(s, timeout=5)
            return s
        except OSError:
            time.sleep(0.3)
    raise RuntimeError("could not connect to VICE remote monitor")

def decode(row_bytes):
    out = []
    for c in row_bytes:
        if c in (0x20, 0x00): out.append(" ")
        elif 0x01 <= c <= 0x1A: out.append(chr(ord('A') + c - 1))
        elif 0x30 <= c <= 0x39: out.append(chr(c))
        elif c == 0x2E: out.append(".")
        elif c == 0x3A: out.append(":")
        elif c == 0x2F: out.append("/")
        elif c == 0x2B: out.append("+")
        elif c == 0x2D: out.append("-")
        elif c == 0x28: out.append("(")
        elif c == 0x29: out.append(")")
        elif c == 0x3D: out.append("=")
        elif c == 0x21: out.append("!")
        elif c == 0x3F: out.append("?")
        elif c == 0x2C: out.append(",")
        else: out.append(".")
    return "".join(out).rstrip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="",
                    help="-sidvariant personality (empty = stock 8580)")
    args = ap.parse_args()

    port = free_port()
    dump_path = os.path.join(ROOT, "tests", "q_page_dump.bin")
    if os.path.exists(dump_path):
        os.remove(dump_path)

    subprocess.run(["taskkill", "//F", "//IM", "x64sc.exe"],
                   shell=False, capture_output=True)

    cmd = [VICE,
           "-autostart", PRG,
           "-remotemonitor",
           "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
           "+confirmonexit"]
    if args.variant:
        cmd += ["-sidvariant", args.variant]
    print(f"Launching VICE (variant={args.variant or 'stock-8580'}, port {port}) …")
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        print(f"Waiting {DETECT_WAIT}s for detection to complete …")
        time.sleep(DETECT_WAIT)

        # siddetector polls CIA1 directly (bypasses KERNAL keyboard buffer),
        # so keybuf won't work.  Instead, set PC = quality_entry from the
        # monitor and resume — sidnum_zp / sid_list have already been
        # populated by the now-paused detection flow, which is exactly the
        # state Q-press would invoke quality_entry in.
        s = mon_connect(port)
        # PC state before — sanity check
        s.sendall(b'r\n')
        before = recv_until_prompt(s, timeout=2)
        print("--- registers BEFORE jump ---")
        for line in before.splitlines():
            if line.strip().startswith((".", "(C:")):
                print("   ", line.strip())
        # Dump screen RAM BEFORE the jump
        pre_dump = os.path.join(ROOT, "tests", "q_page_pre_dump.bin")
        if os.path.exists(pre_dump):
            os.remove(pre_dump)
        s.sendall(f'save "{pre_dump}" 0 0400 07e7\n'.encode())
        recv_until_prompt(s, timeout=2)
        # Sanity check: dump sidnum_zp ($F7) and sid_list_l/h/t ($6009/$6012/$601b)
        s.sendall(b'm f7 f7\n')
        out = recv_until_prompt(s, timeout=2)
        print("--- sidnum_zp ---")
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith(">C:"):
                print("   ", stripped)
        s.sendall(b'm 6000 6024\n')
        out = recv_until_prompt(s, timeout=2)
        print("--- num_sids + sid_list_l/h/t ($6000-$6024) ---")
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith(">C:"):
                print("   ", stripped)
        # Set PC = $c300 and resume.
        s.sendall(b'r pc=c300\n')
        recv_until_prompt(s, timeout=2)
        s.sendall(b'x\n')           # exit monitor, resume CPU
        recv_until_prompt(s, timeout=2)
        s.close()

        print(f"Q sent. Waiting {PAINT_WAIT}s for paint …")
        time.sleep(PAINT_WAIT)

        # Dump screen RAM + state
        s = mon_connect(port)
        # state inspection
        for cmd, label in [(b'r\n', 'PC after'),
                           (b'm f7 f7\n', '$F7 (sidnum_zp)'),
                           (b'm 6009 6024\n', 'sid_list l/h/t'),
                           (b'm aa ac\n', 'tmp2/tmp1/tmp'),
                           (b'm f9 fa\n', 'sptr_zp')]:
            s.sendall(cmd)
            out = recv_until_prompt(s, timeout=2)
            print(f"--- {label} ---")
            for line in out.splitlines():
                stripped = line.strip()
                if stripped and not stripped.startswith("(C:"):
                    print("   ", stripped)
        s.sendall(f'save "{dump_path}" 0 0400 07e7\n'.encode())
        recv_until_prompt(s)
        s.sendall(b'quit\n')
        try: recv_until_prompt(s, timeout=2)
        except Exception: pass
        s.close()

        time.sleep(1.0)
        with open(dump_path, "rb") as f:
            raw = f.read()[2:]      # strip the 2-byte PRG header

        print("\n--- Q PAGE SCREEN (rows 0-24) ---")
        for r in range(25):
            print(f"r{r:02d}: {decode(raw[r*40:(r+1)*40])}")
    finally:
        subprocess.run(["taskkill", "//F", "//IM", "x64sc.exe"],
                       shell=False, capture_output=True)
        try: proc.wait(timeout=2)
        except Exception: pass

if __name__ == "__main__":
    main()

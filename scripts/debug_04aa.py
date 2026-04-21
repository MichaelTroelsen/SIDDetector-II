#!/usr/bin/env python3
"""
debug_04aa.py — Catch the instruction that writes the corrupt value to $04AA.

Sets a store watchpoint on $04AA, runs the program through two runs
(via dbg_autorestart), and logs every write with its PC.

Expected:
  - Several writes from printscreen (template dot $2E) each run
  - The corrupt write ($02) happens somewhere after readkey2 on run2

Usage:
    python3 scripts/debug_04aa.py [port]   (default: 56633)
"""

import socket, sys, time, re, subprocess, os

HOST = "127.0.0.1"
TIMEOUT = 120
VICE = "C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = "siddetector.prg"
MAX_FIRES = 200  # stop after this many watchpoint fires to avoid runaway

def recv_until_prompt(sock, timeout=30):
    sock.settimeout(1.5)
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            if re.search(rb'\(C:\$[0-9a-fA-F]{4}\)', buf):
                return buf.decode("latin-1", errors="replace")
        except socket.timeout:
            pass
    return buf.decode("latin-1", errors="replace")

def send(sock, cmd):
    sock.sendall((cmd + "\n").encode())

def read_mem_byte(sock, addr):
    send(sock, f"m {addr:04x} {addr:04x}")
    resp = recv_until_prompt(sock, timeout=10)
    # format: ">C:04aa  2e  ..."
    m = re.search(r'C:0*4aa\s+([0-9a-fA-F]{2})', resp, re.IGNORECASE)
    return int(m.group(1), 16) if m else None

def extract_pc(text):
    pcs = re.findall(r'\(C:\$([0-9a-fA-F]{4})\)', text)
    return pcs[-1].upper() if pcs else None

def connect(port, retries=80):
    for _ in range(retries):
        try:
            s = socket.socket()
            s.connect((HOST, port))
            return s
        except (ConnectionRefusedError, OSError):
            s.close()
            time.sleep(0.5)
    return None

def load_sym(vs_file):
    labels = {}
    try:
        with open(vs_file) as f:
            for line in f:
                m = re.match(r'al C:([0-9a-fA-F]+) \.(\w+)', line)
                if m:
                    labels[m.group(2)] = int(m.group(1), 16)
    except FileNotFoundError:
        pass
    return labels

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 56633

    labels = load_sym("siddetector.vs")
    readkey2 = labels.get("readkey2", 0)
    printscreen = labels.get("printscreen", 0)
    print(f"Symbol addresses: readkey2=${readkey2:04x}  printscreen=${printscreen:04x}")

    os.system("taskkill /F /IM x64sc.exe >NUL 2>&1")
    time.sleep(0.8)

    print(f"\nLaunching VICE (remote monitor port {port})...")
    proc = subprocess.Popen([
        VICE, "-autostart", PRG,
        "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
        "+confirmonexit", "-sfxse", "-sfxsetype", "3812",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    sock = connect(port)
    if not sock:
        print("ERROR: could not connect")
        proc.terminate()
        sys.exit(1)

    recv_until_prompt(sock, timeout=15)

    # Conditional watchpoint: only fire when value being stored is NOT $2E (not dot)
    # i.e. when A != $2e at time of store
    send(sock, "watch store 04aa cond (A != $2e)")
    resp = recv_until_prompt(sock, timeout=5)
    print(f"Watchpoint response: {resp.strip()}")
    print("Watchpoint set on stores to $04AA (cond A!=$2e). Running...\n")

    fires = []
    for i in range(MAX_FIRES):
        send(sock, "go")
        resp = recv_until_prompt(sock, timeout=TIMEOUT)
        # Get actual registers to find true PC
        send(sock, "r")
        reg_resp = recv_until_prompt(sock, timeout=5)
        # Parse "ADDR:$XXXX" or "  PC   SR  AC  XR  YR  SP\n$XXXX ..."
        pc_match = re.search(r'PC\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s*\n\s*\$([0-9a-fA-F]{4})', reg_resp)
        if not pc_match:
            pc_match = re.search(r'\$([0-9a-fA-F]{4})\s+[0-9a-fA-F]{2}\s+[0-9a-fA-F]{2}', reg_resp)
        reg_pc = pc_match.group(1).upper() if pc_match else None

        val = read_mem_byte(sock, 0x04AA)

        prompt_pc = extract_pc(resp)
        val_str = f"${val:02x}" if val is not None else "??"
        note = ""
        if val == 0x02:
            note = "  *** BUG: 'B' written! ***"
        fires.append((reg_pc or prompt_pc, val))

        # On first 3 fires print raw data for analysis
        if i < 3:
            print(f"  [{i+1:2d}] prompt_PC=${prompt_pc}  reg_PC=${reg_pc}  $04AA->{val_str}{note}")
            print(f"       regs: {reg_resp.strip()[:120]}")
        else:
            print(f"  [{i+1:2d}] reg_PC=${reg_pc}  $04AA->{val_str}{note}")

        if val == 0x02:
            print(f"\n  CULPRIT reg_PC=${reg_pc}. Disassembly:")
            if reg_pc:
                base = int(reg_pc, 16)
                send(sock, f"d {max(0,base-6):04x} {base+6:04x}")
                dis = recv_until_prompt(sock, timeout=5)
                print(dis)
            break
    else:
        print(f"\nReached {MAX_FIRES} watchpoint fires without seeing $02. Last 5:")
        for pc, val in fires[-5:]:
            print(f"  PC=${pc}  value=${val:02x}" if val is not None else f"  PC=${pc}  value=??")

    send(sock, "quit")
    sock.close()
    try:
        proc.terminate()
    except:
        pass

if __name__ == "__main__":
    main()

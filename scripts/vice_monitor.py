#!/usr/bin/env python3
"""
vice_monitor.py — Connect to VICE remote monitor, run test_suite, save result.

Usage:
    python3 scripts/vice_monitor.py <td_spin_addr> <output_file> <port>

  td_spin_addr  : hex address of td_spin label (from test_suite.vs), e.g. "0bd7"
  output_file   : path to write the result byte
  port          : TCP port VICE remote monitor is listening on

Connects to VICE remote monitor on localhost:<port>.
Sets a numeric breakpoint at td_spin_addr, resumes execution, waits for it
to fire (verifying PC matches), then saves $07E8 (pass_count copy in
off-screen RAM) to output_file and quits.

Exit codes:
  0 — success (result file written)
  1 — connection failed / timeout / VICE error
"""

import socket
import sys
import time
import re

HOST = "127.0.0.1"
TIMEOUT = 120  # seconds to wait for td_spin breakpoint

def recv_until_prompt(sock, timeout=TIMEOUT):
    """Read from socket until we see a monitor prompt '(C:$xxxx)'."""
    sock.settimeout(2.0)
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            text = buf.decode("latin-1", errors="replace")
            if re.search(r'\(C:\$[0-9a-fA-F]{4}\)', text):
                return text
        except socket.timeout:
            continue
    return buf.decode("latin-1", errors="replace")

def extract_pc(text):
    """Return the PC address from the last monitor prompt in text, or None."""
    m = re.findall(r'\(C:\$([0-9a-fA-F]{4})\)', text)
    return m[-1].lower() if m else None

def send(sock, cmd):
    sock.sendall((cmd + "\n").encode())

def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <td_spin_addr> <output_file> <port>",
              file=sys.stderr)
        sys.exit(1)

    # Normalise to 4 hex digits for comparison with monitor prompt (C:$XXXX)
    td_spin_addr = sys.argv[1].lower().zfill(4)
    output_file = sys.argv[2]
    PORT = int(sys.argv[3])

    # Connect with retries — VICE may take up to 30 seconds to start and bind
    sock = None
    for attempt in range(120):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect((HOST, PORT))
            break
        except (ConnectionRefusedError, OSError):
            sock.close()
            sock = None
            time.sleep(0.5)

    if sock is None:
        print("ERROR: could not connect to VICE remote monitor", file=sys.stderr)
        sys.exit(1)

    try:
        # Drain the initial banner (may arrive late; that's OK)
        recv_until_prompt(sock, timeout=10)

        # Set a numeric breakpoint — avoids loadsym CWD issues on Linux
        send(sock, f"break ${td_spin_addr}")
        recv_until_prompt(sock, timeout=5)

        # Resume execution and wait for td_spin.
        # Guard against the "shifted buffer" race (banner arrives late so the
        # go-response contains an earlier prompt instead of the breakpoint hit):
        # keep going until PC == td_spin_addr.
        for _ in range(20):
            send(sock, "go")
            resp = recv_until_prompt(sock, timeout=TIMEOUT)
            pc = extract_pc(resp)
            if pc is None:
                print("ERROR: timed out waiting for td_spin breakpoint",
                      file=sys.stderr)
                sys.exit(1)
            if pc == td_spin_addr:
                break  # breakpoint fired at the right address
            # Wrong address — a timing shift or early breakpoint; keep going
        else:
            print(f"ERROR: never reached td_spin (${td_spin_addr})",
                  file=sys.stderr)
            sys.exit(1)

        # Save pass_count copy from off-screen scratch RAM ($07E8)
        save_cmd = f'save "{output_file}" 0 07e8 07e8'
        send(sock, save_cmd)
        recv_until_prompt(sock, timeout=5)

        send(sock, "quit")
        sock.close()

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()

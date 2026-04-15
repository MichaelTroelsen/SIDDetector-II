#!/usr/bin/env python3
"""
vice_monitor.py — Connect to VICE remote monitor, run test_suite, save result.

Usage:
    python3 scripts/vice_monitor.py <pass_count_addr> <output_file> <port>

  pass_count_addr  : hex address of pass_count (from test_suite.vs)
  output_file      : path to write the result byte
  port             : TCP port VICE remote monitor is listening on

Connects to VICE remote monitor on localhost:<port>.
Sets a breakpoint at td_spin, resumes execution, waits for the breakpoint,
then saves $07E8 (pass_count copy in off-screen RAM) to output_file and quits.

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
    """Read from socket until we see a monitor prompt line like '(C:$xxxx)'."""
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
            # VICE monitor prompt looks like: (C:$080d)  or  (C:$0000)
            if re.search(r'\(C:\$[0-9a-fA-F]{4}\)', text):
                return text
        except socket.timeout:
            continue
    return buf.decode("latin-1", errors="replace")

def send(sock, cmd):
    sock.sendall((cmd + "\n").encode())

def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <pass_count_addr> <output_file> <port>", file=sys.stderr)
        sys.exit(1)

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
        print("ERROR: could not connect to VICE remote monitor on localhost:6510", file=sys.stderr)
        sys.exit(1)

    try:
        # Initial banner / prompt
        recv_until_prompt(sock, timeout=10)

        # Load symbols and set breakpoint
        send(sock, "loadsym tests/test_suite.vs")
        recv_until_prompt(sock, timeout=5)

        send(sock, "break td_spin")
        recv_until_prompt(sock, timeout=5)

        # Start execution; wait for td_spin breakpoint (test runs to completion)
        send(sock, "go")
        resp = recv_until_prompt(sock, timeout=TIMEOUT)
        if "(C:$" not in resp:
            print("ERROR: timed out waiting for td_spin breakpoint", file=sys.stderr)
            sys.exit(1)

        # Save pass_count copy from off-screen scratch RAM
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

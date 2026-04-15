#!/usr/bin/env python3
"""
take_screenshot.py — Connect to VICE remote monitor after detection completes
and save a screenshot.

Usage:
    python3 scripts/take_screenshot.py <output_png> <port> [wait_seconds]

  output_png    : path to write the screenshot
  port          : TCP port VICE remote monitor is listening on
  wait_seconds  : seconds to wait before connecting (default: 8)
                  used to let detection complete before pausing the CPU
"""

import socket
import sys
import time
import re

HOST = "127.0.0.1"

def recv_until_prompt(sock, timeout=10):
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

def send(sock, cmd):
    sock.sendall((cmd + "\n").encode())

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <output_png> <port> [wait_seconds]",
              file=sys.stderr)
        sys.exit(1)

    output_png = sys.argv[1]
    PORT = int(sys.argv[2])
    wait_sec = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0

    print(f"Waiting {wait_sec}s for detection to complete...")
    time.sleep(wait_sec)

    # Connect with retries
    sock = None
    for attempt in range(60):
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
        # Drain the banner (connection pauses the CPU)
        resp = recv_until_prompt(sock, timeout=10)
        print(f"Connected. CPU paused at: {resp[-30:].strip()!r}")

        # Take screenshot directly — screen RAM is already drawn
        send(sock, f'screenshot PNG "{output_png}"')
        resp = recv_until_prompt(sock, timeout=5)
        print(f"Screenshot response: {resp.strip()!r}")

        send(sock, "quit")
        sock.close()
        print("Done.")

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()

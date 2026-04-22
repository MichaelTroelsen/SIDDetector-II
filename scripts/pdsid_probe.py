#!/usr/bin/env python3
"""
pdsid_probe.py — dumps detector state after PDsid-proxy detection.
Saves $0000..$DFFF to a tmp .prg and extracts the bytes of interest.
"""
import os, socket, subprocess, sys, time, re, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VICE = r"C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe"
PRG  = os.path.join(ROOT, "siddetector.prg")
PORT = 6502
WAIT = 20.0


def connect(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.socket()
            s.connect(("127.0.0.1", PORT))
            return s
        except OSError:
            time.sleep(0.3)
    raise RuntimeError("monitor never opened")


def recv_until_prompt(s, t=3):
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


def cmd(s, line, t=3):
    s.sendall((line + "\n").encode())
    return recv_until_prompt(s, t=t).decode(errors="replace")


def dump(path, start, end):
    s = connect()
    recv_until_prompt(s)
    s.sendall(f'save "{path}" 0 {start:04x} {end:04x}\n'.encode())
    recv_until_prompt(s, t=3)
    s.sendall(b"x\n")
    recv_until_prompt(s, t=2)
    s.close()
    with open(path, "rb") as f:
        return f.read()[2:]   # strip 2-byte PRG load addr


def main():
    proc = subprocess.Popen(
        [VICE, "-remotemonitor", "-remotemonitoraddress", "ip4://127.0.0.1:6502",
         "-warp", "-sidextra", "0", "-sidvariant", "pdsid",
         "-autostart", PRG],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        # wait for autostart + detection + IRQ loop
        time.sleep(WAIT)
        tmpdir = tempfile.mkdtemp()

        # Resolve is_u64 address from the live .sym — kickass shifts it per build.
        is_u64_addr = 0x58A9
        sym = os.path.join(ROOT, "siddetector.sym")
        if os.path.isfile(sym):
            with open(sym) as f:
                for ln in f:
                    if "is_u64" in ln and "=$" in ln:
                        is_u64_addr = int(ln.split("=$")[1].strip(), 16)
                        break

        low = dump(os.path.join(tmpdir, "zp.prg"), 0x0000, 0x00FF)
        lo2 = dump(os.path.join(tmpdir, "body.prg"), 0x5800, 0x60FF)
        iomem = dump(os.path.join(tmpdir, "io2.prg"), 0xDF00, 0xDF1F)

        is_u64 = lo2[is_u64_addr - 0x5800]
        sidnum = low[0xF7]
        sid_list_l = lo2[0x6008 - 0x5800 : 0x6008 - 0x5800 + 8]
        sid_list_h = lo2[0x6010 - 0x5800 : 0x6010 - 0x5800 + 8]
        sid_list_t = lo2[0x6018 - 0x5800 : 0x6018 - 0x5800 + 8]

        print(f"is_u64           = ${is_u64:02X}")
        print(f"sidnum_zp        = ${sidnum:02X}  ({sidnum})")
        print(f"sid_list_l[0..7] = {' '.join(f'${b:02X}' for b in sid_list_l)}")
        print(f"sid_list_h[0..7] = {' '.join(f'${b:02X}' for b in sid_list_h)}")
        print(f"sid_list_t[0..7] = {' '.join(f'${b:02X}' for b in sid_list_t)}")
        print(f"$DF00..$DF1F     = {' '.join(f'{b:02X}' for b in iomem)}")

        # $6008..$607F — shows the overflowed entries that sidnum=$20 claims exist.
        print("\n--- $6008 sid_list_l / $6010 sid_list_h / $6018 sid_list_t / $6020 uci_resp:")
        for off in range(0x6008, 0x6080, 0x10):
            row = lo2[off - 0x5800 : off - 0x5800 + 0x10]
            print(f"${off:04X}: {' '.join(f'{b:02X}' for b in row)}")
    finally:
        try: proc.terminate()
        except Exception: pass
        try: proc.wait(timeout=3)
        except Exception:
            try: proc.kill()
            except Exception: pass


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
read_uci_resp.py - Deploy siddetector, wait for detection, read uci_resp bytes.
Shows the raw UCI GET_HWINFO response so we can verify the filter-curve type
byte offsets (Frame1 type at [5], Frame2 type at [10]).
"""

import subprocess, sys, time, re, argparse
from pathlib import Path

ROOT      = Path(__file__).resolve().parent.parent
C64U      = str(ROOT / 'bin' / 'c64u')
U64REMOTE = str(ROOT / 'bin' / 'u64remote.exe')
PRG_FILE  = ROOT / 'siddetector.prg'

UCI_RESP_ADDR = 0x5320   # fixed: after num_sids($5300,8) + sid_list_l/h/t(8 each)

def c64u(*args):
    return subprocess.run([C64U, 'machine'] + list(args),
                          capture_output=True, text=True).stdout

def read_mem_byte(addr):
    out = c64u('read-mem', f'{addr:04X}')
    m = re.search(rf'{addr:04X}:\s+([0-9A-Fa-f]{{2}})', out, re.IGNORECASE)
    if not m:
        raise RuntimeError(f"No byte at ${addr:04X}:\n{out}")
    return int(m.group(1), 16)

def deploy(ip, wait_secs):
    print(f"Deploying {PRG_FILE.name} to {ip} ...")
    subprocess.run([U64REMOTE, f'--host={ip}', '--prg', str(PRG_FILE)],
                   capture_output=True)
    print(f"Waiting {wait_secs}s for cold-boot detection ...")
    time.sleep(wait_secs)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ip',   default='192.168.1.64')
    ap.add_argument('--wait', type=float, default=9.0)
    args = ap.parse_args()

    deploy(args.ip, args.wait)

    # Read 22 bytes of uci_resp
    print()
    print(f"uci_resp @ ${UCI_RESP_ADDR:04X}")
    raw = [read_mem_byte(UCI_RESP_ADDR + i) for i in range(22)]
    hex_str = ' '.join(f'{b:02X}' for b in raw)
    print(f"  raw bytes: {hex_str}")

    count = raw[0]
    print(f"  [0]  count = {count}")

    curve_names = {0:'8580 LO', 1:'8580 HI', 2:'6581', 3:'6581 ALT',
                   4:'U2 LO', 5:'U2 MID', 6:'U2 HI'}

    for fn in range(1, min(count + 1, 5)):
        base = 1 + (fn - 1) * 5
        lo, hi = raw[base], raw[base + 1]
        sec_hi, sec_lo = raw[base + 2], raw[base + 3]
        t = raw[base + 4]
        curve = curve_names.get(t, f'UNKNOWN(${t:02X})')
        print(f"  [{base}..{base+4}] Frame{fn}: addr=${hi:02X}{lo:02X}  sec=${sec_hi:02X}{sec_lo:02X}  type=${t:02X} = {curve}")

    print(f"  [21] status = ${raw[21]:02X}")

if __name__ == '__main__':
    main()

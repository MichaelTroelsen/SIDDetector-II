#!/usr/bin/env python3
"""
read_uci_live.py - Navigate to debug page 2, then read uci_resp bytes.
Debug page 2 issues a fresh GET_HWINFO UCI call when displayed,
so this captures the live query result.
"""

import subprocess, sys, time, re, argparse
from pathlib import Path

ROOT      = Path(__file__).resolve().parent.parent
C64U      = str(ROOT / 'bin' / 'c64u')
U64REMOTE = str(ROOT / 'bin' / 'u64remote.exe')
VS_FILE   = ROOT / 'siddetector.vs'
PRG_FILE  = ROOT / 'siddetector.prg'

UCI_RESP_ADDR = 0x5320
KBDLOOP_ORIG  = 'A97F8D'

def c64u(*args):
    return subprocess.run([C64U, 'machine'] + list(args),
                          capture_output=True, text=True).stdout

def pause():   subprocess.run([C64U, 'machine', 'pause'],  capture_output=True)
def resume():  subprocess.run([C64U, 'machine', 'resume'], capture_output=True)

def read_mem_byte(addr):
    out = c64u('read-mem', f'{addr:04X}')
    m = re.search(rf'{addr:04X}:\s+([0-9A-Fa-f]{{2}})', out, re.IGNORECASE)
    if not m:
        raise RuntimeError(f"No byte at ${addr:04X}:\n{out}")
    return int(m.group(1), 16)

def write_mem(addr, hexdata):
    subprocess.run([C64U, 'machine', 'write-mem', f'{addr:04X}', hexdata],
                   capture_output=True)

def sym(name):
    text = VS_FILE.read_text(errors='replace')
    m = re.search(rf'C:([0-9A-Fa-f]+)\s+\.{re.escape(name)}\b', text)
    if not m:
        raise RuntimeError(f"Symbol '{name}' not found in {VS_FILE.name}")
    return int(m.group(1), 16)

def jmp_to(patch_addr, target_addr, settle=0.5, orig=KBDLOOP_ORIG):
    lo = target_addr & 0xFF
    hi = (target_addr >> 8) & 0xFF
    pause()
    write_mem(patch_addr, f'4C{lo:02X}{hi:02X}')
    resume()
    time.sleep(settle)
    pause()
    write_mem(patch_addr, orig)
    resume()

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

    KBDLOOP        = sym('kbdloop')
    DEBUG_ENTRY    = sym('debug_entry')
    DBG_KBDLOOP    = sym('dbg_kbdloop') if 'dbg_kbdloop' in VS_FILE.read_text(errors='replace') else None
    DEBUG_ENTRY_P2 = sym('debug_entry_p2')
    DBG2_KBDLOOP   = sym('dbg2_kbdloop')
    START          = sym('start') if 'start' in VS_FILE.read_text(errors='replace') else 0x2400

    print(f"\nNavigating to debug page 1 ...")
    jmp_to(KBDLOOP, DEBUG_ENTRY, settle=1.0)

    dbg1_loop = DBG_KBDLOOP if DBG_KBDLOOP else DEBUG_ENTRY  # fallback
    print(f"Navigating to debug page 2 (UCI live query runs now) ...")
    jmp_to(dbg1_loop, DEBUG_ENTRY_P2, settle=2.0)  # wait 2s for UCI query

    # Read uci_resp (22 bytes)
    raw = [read_mem_byte(UCI_RESP_ADDR + i) for i in range(23)]
    hex_str = ' '.join(f'{b:02X}' for b in raw)

    print()
    print(f"uci_resp @ ${UCI_RESP_ADDR:04X} (captured after debug page 2 live query):")
    print(f"  raw: {hex_str}")

    count = raw[0]
    print(f"  [0] count = {count}")

    curve_names = {0:'8580 LO', 1:'8580 HI', 2:'6581', 3:'6581 ALT',
                   4:'U2 LO',   5:'U2 MID',  6:'U2 HI'}

    for fn in range(1, min(count + 1, 5)):
        base = 1 + (fn - 1) * 5
        lo, hi = raw[base], raw[base + 1]
        sec_hi, sec_lo = raw[base + 2], raw[base + 3]
        t = raw[base + 4]
        curve = curve_names.get(t, f'UNKNOWN(${t:02X})')
        print(f"  [{base}..{base+4}] Frame{fn}: ${hi:02X}{lo:02X}  sec=${sec_hi:02X}{sec_lo:02X}  T=${t:02X} = {curve}")

    print(f"  [21] trailing= ${raw[21]:02X}")
    print(f"  [22] status = ${raw[22]:02X}")

    # Exit debug page 2 back to main
    print("\nExiting debug page 2 ...")
    jmp_to(DBG2_KBDLOOP, START)

if __name__ == '__main__':
    main()

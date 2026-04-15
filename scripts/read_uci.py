#!/usr/bin/env python
"""Read uci_resp and sid_list from running C64 after siddetector completes detection."""
import subprocess, sys, time, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
C64U     = str(ROOT / 'bin' / 'c64u')
VS_FILE  = ROOT / 'siddetector.vs'
U64REMOTE = str(ROOT / 'bin' / 'u64remote.exe')
IP = '192.168.1.64'

def c64u(*args):
    r = subprocess.run([C64U, 'machine'] + list(args), capture_output=True, text=True)
    return r.stdout

def read_byte(addr):
    out = c64u('read-mem', f'{addr:04X}')
    m = re.search(rf'{addr:04X}:\s+([0-9A-Fa-f]{{2}})', out, re.IGNORECASE)
    return int(m.group(1), 16) if m else -1

def sym(name):
    t = VS_FILE.read_text(errors='replace')
    m = re.search(rf'C:([0-9A-Fa-f]+)\s+\.{re.escape(name)}\b', t)
    return int(m.group(1), 16) if m else None

print('Deploying siddetector.prg ...')
subprocess.run([U64REMOTE, IP, 'run', str(ROOT / 'siddetector.prg')], capture_output=True)
print('Waiting 12s for detection ...')
time.sleep(12)

uci_addr = sym('uci_resp')
sl_addr  = sym('sid_list_l')
sh_addr  = sym('sid_list_h')
st_addr  = sym('sid_list_t')

print(f'uci_resp  @ ${uci_addr:04X}')
resp = [read_byte(uci_addr + i) for i in range(8)]
print(f'uci_resp bytes: {" ".join(f"{b:02X}" for b in resp)}')
print()

count = read_byte(0xF7)   # sidnum_zp
print(f'sidnum_zp (F7) = {count}')
for i in range(1, min(count + 1, 9)):
    l = read_byte(sl_addr + i)
    h = read_byte(sh_addr + i)
    t = read_byte(st_addr + i)
    print(f'  SID[{i}]: ${h:02X}{l:02X}  type=${t:02X}')

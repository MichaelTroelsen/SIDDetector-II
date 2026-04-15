#!/usr/bin/env python3
"""
hw_test.py - Automated hardware smoke test for siddetector on real C64 via U64.

Strategy:
  - All keypresses use the JMP-patch method: pause CPU, write JMP <handler> at the
    relevant kbdloop address, resume, wait 0.3 s (fires once), pause, restore original
    bytes, resume.  This avoids CIA1 row-order conflicts (DDRB injection would trigger
    I before R/P, Q before T, etc.).
  - Sub-screen exits also use JMP patches on the sub-screen's own kbdloop address,
    jumping to 'start' ($2400) which re-runs full detection.
  - P (music toggle) is special: it returns to the main kbdloop without restarting
    detection, so it can be toggled on/off in-place.

Usage:
  python scripts/hw_test.py [--ip <addr>] [--wait <secs>] [--scenario <path.cfg>]

  --ip        U64 IP address (default 192.168.1.64)
  --wait      seconds to wait for detection after each restart (default 9)
  --scenario  path to a scenario .cfg file with expected detection values
              (see tests/hw/scenarios/*.cfg for examples)

Without --scenario: smoke test only -- verifies detection is stable across
  all restarts and screen navigations (result must match cold-boot baseline).

With --scenario: additionally verifies that the detected chip types and
  addresses match the expected values defined in the scenario file.
"""

import subprocess, sys, time, re, argparse, configparser
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ROOT        = Path(__file__).resolve().parent.parent
C64U        = str(ROOT / 'bin' / 'c64u')
U64REMOTE   = str(ROOT / 'bin' / 'u64remote.exe')
VS_FILE     = ROOT / 'siddetector.vs'
PRG_FILE    = ROOT / 'siddetector.prg'

KBDLOOP_ORIG = 'A97F8D'   # lda #$7F; sta $DC00 -- first 3 bytes of every kbdloop

# Chip type code names (for readable output)
CHIP_NAMES = {
    0x01: '6581',           0x02: '8580',
    0x04: 'SwinSID-U',      0x05: 'ARMSID/ARM2SID',
    0x06: 'FPGASID-8580',   0x07: 'FPGASID-6581',
    0x08: 'SwinSID-Nano',   0x09: 'PD-SID',
    0x0A: 'BackSID',        0x0B: 'SIDKick-pico-8580',
    0x0C: 'KungFuSID',      0x0D: 'uSID64',
    0x0E: 'SIDKick-pico-6581',
    0x10: 'SecondSID',
    0x20: 'ULTISID-8580',    0x21: 'ULTISID-8580',
    0x22: 'ULTISID-6581',    0x23: 'ULTISID-6581',
    0x24: 'ULTISID-8580',   0x25: 'ULTISID-8580',
    0x26: 'ULTISID-8580',   0x30: 'SIDFX',
    0xF0: 'Unknown/NoSID',  0x00: '(empty)',
}

def chip_name(code):
    return CHIP_NAMES.get(code, f'?${code:02X}')

# ---------------------------------------------------------------------------
# Hardware primitives
# ---------------------------------------------------------------------------

def c64u(*args):
    result = subprocess.run([C64U, 'machine'] + list(args),
                            capture_output=True, text=True)
    return result.stdout

def pause():
    subprocess.run([C64U, 'machine', 'pause'],  capture_output=True)

def resume():
    subprocess.run([C64U, 'machine', 'resume'], capture_output=True)

def write_mem(addr, hexdata):
    subprocess.run([C64U, 'machine', 'write-mem', f'{addr:04X}', hexdata],
                   capture_output=True)

def read_mem_byte(addr):
    out = c64u('read-mem', f'{addr:04X}')
    pat = rf'{addr:04X}:\s+([0-9A-Fa-f]{{2}})'
    m = re.search(pat, out, re.IGNORECASE)
    if not m:
        raise RuntimeError(f"Could not read byte at ${addr:04X}:\n{out}")
    return int(m.group(1), 16)

# ---------------------------------------------------------------------------
# Symbol resolution
# ---------------------------------------------------------------------------

def sym(name):
    text = VS_FILE.read_text(errors='replace')
    m = re.search(rf'C:([0-9A-Fa-f]+)\s+\.{re.escape(name)}\b', text)
    if not m:
        raise RuntimeError(f"Symbol '{name}' not found in {VS_FILE.name}")
    return int(m.group(1), 16)

# ---------------------------------------------------------------------------
# JMP-patch keypress
# ---------------------------------------------------------------------------

def jmp_to(patch_addr, target_addr, settle_secs=0.3, orig_bytes=None):
    """Patch patch_addr with JMP target_addr, let it fire once, restore.

    orig_bytes: hex string of 3 bytes to restore (default: read from patch_addr
    while paused, so the correct opcode is always restored regardless of which
    kbdloop variant is being patched).
    """
    lo = target_addr & 0xFF
    hi = (target_addr >> 8) & 0xFF
    pause()
    if orig_bytes is None:
        b0 = read_mem_byte(patch_addr)
        b1 = read_mem_byte(patch_addr + 1)
        b2 = read_mem_byte(patch_addr + 2)
        orig_bytes = f'{b0:02X}{b1:02X}{b2:02X}'
    write_mem(patch_addr, f'4C{lo:02X}{hi:02X}')
    resume()
    time.sleep(settle_secs)
    pause()
    write_mem(patch_addr, orig_bytes)
    resume()

# ---------------------------------------------------------------------------
# Detection snapshot  (slot = {addr, type})
# ---------------------------------------------------------------------------

def read_snapshot(sid_list_l, sid_list_h, sid_list_t):
    """
    Return list of 8 dicts: {addr: int (16-bit), type: int (8-bit)}.
    Slot 0 is unused by siddetector; slots 1-7 hold detected SIDs.
    """
    return [
        {
            'addr': (read_mem_byte(sid_list_h + i) << 8) | read_mem_byte(sid_list_l + i),
            'type': read_mem_byte(sid_list_t + i),
        }
        for i in range(8)
    ]

def fmt_slot(s):
    if s['type'] == 0 and s['addr'] == 0:
        return '(empty)'
    return f"${s['addr']:04X} {chip_name(s['type'])}(${s['type']:02X})"

def fmt_snapshot(snap):
    active = [(i, s) for i, s in enumerate(snap) if i > 0 and s['type'] != 0]
    if not active:
        return '(none)'
    return '  '.join(f"[{i}]{fmt_slot(s)}" for i, s in active)

def snapshots_equal(a, b):
    return all(a[i]['addr'] == b[i]['addr'] and a[i]['type'] == b[i]['type']
               for i in range(8))

# ---------------------------------------------------------------------------
# Scenario loading
# ---------------------------------------------------------------------------

def load_scenario(path):
    """
    Parse a .cfg scenario file.  Returns a dict:
      {
        'name': str,
        'detect_wait': float,          # overrides --wait if present
        'slots': {                     # 1-based slot index -> expected values
            1: {'addr': 0xD400, 'type': 0x06},
            2: {'addr': 0xD420, 'type': 0x07},
            ...
        }
      }
    """
    cfg = configparser.ConfigParser(inline_comment_prefixes=(';', '#'))
    cfg.read(path)

    scenario = {
        'name':         cfg.get('scenario', 'name',         fallback=Path(path).stem),
        'detect_wait':  cfg.getfloat('scenario', 'detect_wait', fallback=None),
        'slots':        {},
    }

    exp = cfg['expect'] if 'expect' in cfg else {}
    for key, val in exp.items():
        val = val.strip()
        m = re.match(r'^slot(\d+)_(addr|type)$', key)
        if not m:
            continue
        n, field = int(m.group(1)), m.group(2)
        if n not in scenario['slots']:
            scenario['slots'][n] = {}
        scenario['slots'][n][field] = int(val.lstrip('$'), 16)

    return scenario

def verify_scenario(label, snap, scenario, results_list):
    """
    Check that each expected slot in the scenario matches the snapshot.
    Records PASS/FAIL into results_list.
    """
    all_ok = True
    for n, exp in sorted(scenario['slots'].items()):
        got = snap[n]
        ok_addr = ('addr' not in exp) or (got['addr'] == exp['addr'])
        ok_type = ('type' not in exp) or (got['type'] == exp['type'])
        ok = ok_addr and ok_type

        exp_str = f"${exp.get('addr', 0):04X} {chip_name(exp.get('type', 0))}(${exp.get('type', 0):02X})"
        got_str = fmt_slot(got)
        detail  = f"slot{n}: expected {exp_str}  got {got_str}"

        marker = 'PASS' if ok else 'FAIL'
        print(f"    [{marker}] {label} slot{n} - {detail if not ok else got_str}")
        results_list.append((f"{label} slot{n}", ok, detail if not ok else ''))
        if not ok:
            all_ok = False
    return all_ok

# ---------------------------------------------------------------------------
# Main test sequence
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description='siddetector hardware smoke test')
    parser.add_argument('--ip',       default='192.168.1.64',
                        help='U64 IP address')
    parser.add_argument('--wait',     type=float, default=9.0,
                        help='seconds to wait for detection after restart')
    parser.add_argument('--scenario', default=None,
                        help='path to scenario .cfg file with expected chip/address values')
    args = parser.parse_args()

    scenario = None
    if args.scenario:
        scenario = load_scenario(args.scenario)
        print(f"Scenario: {scenario['name']}")
        if scenario['detect_wait'] is not None:
            args.wait = scenario['detect_wait']

    DETECT_WAIT = args.wait

    print(f"{'='*60}")
    print(f"  siddetector hardware smoke test - {datetime.now():%Y-%m-%d %H:%M:%S}")
    print(f"  U64: {args.ip}   detect_wait: {DETECT_WAIT}s")
    if scenario:
        print(f"  Scenario: {scenario['name']}")
        for n, exp in sorted(scenario['slots'].items()):
            print(f"    slot{n}: ${exp.get('addr', 0):04X}  "
                  f"{chip_name(exp.get('type', 0))}(${exp.get('type', 0):02X})")
    print(f"{'='*60}\n")

    # Load symbol addresses
    print("Loading symbols from siddetector.vs ...")
    KBDLOOP        = sym('kbdloop')
    DO_RESTART     = sym('do_restart')
    START          = sym('start')
    INFO_ENTRY     = sym('info_entry')
    INFO_KBDLOOP   = sym('info_kbdloop')
    DEBUG_ENTRY    = sym('debug_entry')
    DBG_KBDLOOP    = sym('dbg_kbdloop')
    DEBUG_ENTRY_P2 = sym('debug_entry_p2')
    DBG2_KBDLOOP   = sym('dbg2_kbdloop')
    README_ENTRY   = sym('readme_entry')
    README_KBDLOOP = sym('readme_kbdloop')
    SND_ENTRY      = sym('sound_test_entry')
    SND_KBDLOOP    = sym('snd_kbdloop')
    DO_MUSIC       = sym('do_sid_music')
    SID_LIST_L     = sym('sid_list_l')
    SID_LIST_H     = sym('sid_list_h')
    SID_LIST_T     = sym('sid_list_t')
    print(f"  kbdloop    = ${KBDLOOP:04X}   do_restart = ${DO_RESTART:04X}")
    print(f"  sid_list   = L:${SID_LIST_L:04X} H:${SID_LIST_H:04X} T:${SID_LIST_T:04X}")
    print()

    # Deploy
    print(f"Deploying {PRG_FILE.name} to {args.ip} ...")
    subprocess.run([U64REMOTE, args.ip, 'run', str(PRG_FILE)])
    print(f"Waiting {DETECT_WAIT}s for cold-boot detection ...")
    time.sleep(DETECT_WAIT)

    baseline = read_snapshot(SID_LIST_L, SID_LIST_H, SID_LIST_T)
    print(f"\nBaseline: {fmt_snapshot(baseline)}\n")

    # ---------------------------------------------------------
    results = []   # list of (label, passed, detail)

    def record(label, passed, detail=''):
        marker = 'PASS' if passed else 'FAIL'
        print(f"  [{marker}] {label}" + (f" - {detail}" if detail else ''))
        results.append((label, passed, detail))

    def check_stable(label, snap):
        """Verify snap == baseline (detection is stable)."""
        ok = snapshots_equal(snap, baseline)
        if not ok:
            diff = [f"slot{i}: expected {fmt_slot(baseline[i])} got {fmt_slot(snap[i])}"
                    for i in range(8)
                    if baseline[i]['addr'] != snap[i]['addr'] or
                       baseline[i]['type'] != snap[i]['type']]
            record(label + ' (stable)', False, '; '.join(diff))
        else:
            record(label + ' (stable)', True)
        return ok

    def restart_and_verify(label, extra_wait=0):
        """Press SPACE, wait for redetection, verify stable + scenario."""
        jmp_to(KBDLOOP, DO_RESTART)
        time.sleep(DETECT_WAIT + extra_wait)
        snap = read_snapshot(SID_LIST_L, SID_LIST_H, SID_LIST_T)
        check_stable(label, snap)
        if scenario:
            verify_scenario(label, snap, scenario, results)

    def enter_screen_and_return(label, entry_addr, screen_kbdloop, extra_wait=0):
        """Enter a sub-screen, wait 1s, exit via JMP start, verify on return.
        extra_wait: additional seconds added to DETECT_WAIT (use for screens that
        take time to exit, e.g. the sound test which plays for ~6s before
        the snd_kbdloop patch fires)."""
        print(f"\n  >> entering {label} screen ...")
        jmp_to(KBDLOOP, entry_addr)
        time.sleep(1)
        print(f"  << exiting {label} screen ...")
        jmp_to(screen_kbdloop, START)
        time.sleep(DETECT_WAIT + extra_wait)
        snap = read_snapshot(SID_LIST_L, SID_LIST_H, SID_LIST_T)
        check_stable(f"{label} return", snap)
        if scenario:
            verify_scenario(f"{label} return", snap, scenario, results)

    # ---------------------------------------------------------
    # COLD BOOT: scenario verification
    # ---------------------------------------------------------
    if scenario:
        print("--- CHECK: cold boot vs scenario ---")
        verify_scenario("cold boot", baseline, scenario, results)

    # ---------------------------------------------------------
    # TEST 1: SPACE restart x3
    # ---------------------------------------------------------
    print("\n--- TEST: SPACE restart x3 ---")
    for i in range(1, 4):
        restart_and_verify(f"SPACE restart #{i}")

    # ---------------------------------------------------------
    # TEST 2: Info screen (I key)
    # ---------------------------------------------------------
    print("\n--- TEST: I - info screen ---")
    enter_screen_and_return("info", INFO_ENTRY, INFO_KBDLOOP)

    # ---------------------------------------------------------
    # TEST 3: Debug screen page 1 (D key)
    # ---------------------------------------------------------
    print("\n--- TEST: D - debug screen page 1 ---")
    enter_screen_and_return("debug", DEBUG_ENTRY, DBG_KBDLOOP)

    # ---------------------------------------------------------
    # TEST 4: Debug screen page 2 (D→D navigation) + UCI content check
    # ---------------------------------------------------------
    print("\n--- TEST: D->D - debug screen page 2 ---")
    print("  >> entering debug page 1 ...")
    jmp_to(KBDLOOP, DEBUG_ENTRY)
    time.sleep(1)
    print("  >> navigating to debug page 2 ...")
    jmp_to(DBG_KBDLOOP, DEBUG_ENTRY_P2)
    time.sleep(2)   # extra second for UCI query to complete

    # If U64 detected: verify UCI response populated correctly
    UCI_RESP = sym('uci_resp')
    IS_U64   = sym('is_u64')
    is_u64   = read_mem_byte(IS_U64) != 0
    if is_u64:
        uci_count  = read_mem_byte(UCI_RESP)
        uci_status = read_mem_byte(UCI_RESP + 22)
        print(f"  UCI: count={uci_count}  status=${uci_status:02X}")
        # Only expect UCI count >= 1 when ULTISID ($20-$27) appears in the baseline.
        # When SIDFX external hardware is present (detected as $30 or as 6581/8580 if
        # DETECTSIDFX failed), U64 UCI defers to the cartridge and returns count=0.
        ultisid_types = set(range(0x20, 0x28))
        has_ultisid = any(s['type'] in ultisid_types for s in baseline)
        if not has_ultisid:
            print(f"  UCI: no ULTISID in baseline — count=0 expected (external/real SID)")
        else:
            record("debug p2 UCI count >= 1", uci_count >= 1,
                   f"got count={uci_count}" if uci_count < 1 else '')
        record("debug p2 UCI status not dirty (not $30)", uci_status != 0x30,
               f"got status=${uci_status:02X} (dirty FIFO - unread bytes remain)" if uci_status == 0x30 else '')
        if uci_count >= 1:
            f1_hi = read_mem_byte(UCI_RESP + 2)
            in_range = 0xD4 <= f1_hi <= 0xDF
            record(f"debug p2 UCI F1 hi=${f1_hi:02X} in $D4-$DF",
                   in_range, f"got ${f1_hi:02X}" if not in_range else '')

    print("  << exiting debug page 2 ...")
    jmp_to(DBG2_KBDLOOP, START)
    time.sleep(DETECT_WAIT)
    snap = read_snapshot(SID_LIST_L, SID_LIST_H, SID_LIST_T)
    check_stable("debug page 2 return", snap)
    if scenario:
        verify_scenario("debug page 2 return", snap, scenario, results)

    # ---------------------------------------------------------
    # TEST 6: README screen (R key)
    # ---------------------------------------------------------
    print("\n--- TEST: R - readme screen ---")
    enter_screen_and_return("readme", README_ENTRY, README_KBDLOOP)

    # ---------------------------------------------------------
    # TEST 7: Sound test screen (T key)
    # ---------------------------------------------------------
    print("\n--- TEST: T - sound test screen ---")
    # Sound test plays for ~6s; patch fires only when snd_kbdloop is reached.
    # From patch at t=1: ~5s remaining sound test + ~7s detection = ~12s total.
    # extra_wait=7 gives 9+7=16s wait from patch — 4s margin.
    enter_screen_and_return("sound test", SND_ENTRY, SND_KBDLOOP, extra_wait=7)

    # ---------------------------------------------------------
    # TEST 8: Music toggle (P key - returns to kbdloop, no restart)
    # ---------------------------------------------------------
    print("\n--- TEST: P - music toggle ---")
    print("  >> P: start music ...")
    jmp_to(KBDLOOP, DO_MUSIC)
    time.sleep(1)
    print("  >> P: stop music ...")
    jmp_to(KBDLOOP, DO_MUSIC)
    time.sleep(1)
    snap = read_snapshot(SID_LIST_L, SID_LIST_H, SID_LIST_T)
    check_stable("P music toggle (no restart)", snap)
    if scenario:
        verify_scenario("P music toggle", snap, scenario, results)

    # ---------------------------------------------------------
    # Summary
    # ---------------------------------------------------------
    total  = len(results)
    passed = sum(1 for _, ok, _ in results if ok)
    failed = total - passed

    print(f"\n{'='*60}")
    print(f"  RESULTS  {passed}/{total} passed   {failed} failed")
    print(f"{'='*60}")
    for label, ok, detail in results:
        marker = 'PASS' if ok else 'FAIL'
        print(f"  [{marker}] {label}" + (f"\n         {detail}" if detail and not ok else ''))

    # Write timestamped report
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    scen_tag = f"_{Path(args.scenario).stem}" if args.scenario else ''
    report_path = ROOT / 'tests' / f'hw_test_result{scen_tag}_{ts}.txt'
    with open(report_path, 'w') as f:
        f.write(f"siddetector hardware smoke test\n")
        f.write(f"Run: {datetime.now():%Y-%m-%d %H:%M:%S}   U64: {args.ip}\n")
        if scenario:
            f.write(f"Scenario: {scenario['name']}\n")
        f.write(f"Baseline: {fmt_snapshot(baseline)}\n\n")
        for label, ok, detail in results:
            f.write(f"[{'PASS' if ok else 'FAIL'}] {label}\n")
            if detail:
                f.write(f"       {detail}\n")
        f.write(f"\n{passed}/{total} passed   {failed} failed\n")
    print(f"\nReport: {report_path.relative_to(ROOT)}\n")

    return 0 if failed == 0 else 1


if __name__ == '__main__':
    sys.exit(main())

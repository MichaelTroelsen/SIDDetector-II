# SID Detector — Debug & Development Notes

## Current status

Program is stable and working. All known crash bugs are resolved.

| Version | Key changes |
|---------|-------------|
| V1.4.44  | TT8 8-SID HARDWARE TEST |
| V1.4.43  | TYPE FIX + DRAIN CAP + MEMMAP |
| V1.4.42  | U64 BEHAVIORAL THRESHOLD 4 |
| V1.4.41  | TUNEFUL 8 BANNER ON NOSID ROW |
| V1.4.40  | U64 BEHAVIORAL DETECT |
| V1.4.39  | BAR + BANNER ON ROW 24 |
| V1.4.38  | RESTART BAR ROW 23->24 |
| V1.4.37  | U64 8-SID FINGERPRINT SCAN |
| V1.4.36  | U64 8-SID TUNEFUL EIGHT |
| V1.4.35  | TRACKER 2ND TUNE + PROG BAR |
| V1.4.33  | SID TRACKER VIEW (P KEY) |
| V1.4.32  | SKIP PDSID D4XX MIRRORS |
| V1.4.31  | FIX SID_LIST OVERFLOW |
| V1.4.30  | TEST MATRIX HTML DIAGRAM |
| V1.4.29  | FIX DISPLAY GAPS |
| V1.4.28  | SIDVARIANT PROXY IN VICE 3.9 |
| V1.4.27  | release: docs reorg into docs/ + hardware-only probe verification matrix (P01–P05) + stale version-string fix |
| V1.4.26  | feat: ip_fmyam info page + fix SIDFX wording + unreachable pages |
| V1.4.25  | fix: info page header/footer lost after cycling through pages |
| V1.4.24  | fix: info page scroll stops before running into trailing blanks |
| V1.4.23  | fix: readme scroll — 23-line unbreakable V1.4.xx block; version list trimmed to last 5 |
| V1.4.22  | refactor: remove dead $DE00 SFX probe + debug vars; OPL moved to standard $DF40/$DF50/$DF60 |
| V1.4.21  | docs: bump version + update README/TODO/teststatus |
| V1.4.20  | rename: FM-YAM label → SFX/FM (covers both chips) |
| V1.4.19  | fix: FM-YAM detect robustly via upper-bits-clear status check (`(status & $E0) == 0`) |
| V1.4.18  | fix: eliminate FM-YAM/SFX false positives when hardware removed |
| V1.4.17  | fix: FM-YAM detection on real hardware |
| V1.4.00–V1.4.16 | feat: SFX/FM-YAM detection + sound test overhaul (bundled commit — 3 FM instruments: flute/organ/bell; SID pulse-width fix; OPL global init per XeNTaX edlib) |
| V1.3.100 | fix: SFX display cursor bug + detection overhaul |
| V1.3.99  | fix: SFX false positive — pre-check $DE00 & $3F == 0 before timer test |
| V1.3.98  | fix: SFX false positive — require $C0 (both IRQ+T1_FLAG) not just bit7 |
| V1.3.88–V1.3.97 | feat: CBM SFX Sound Expander detection at DE00 (bundled commit) |
| V1.3.87  | feat: FM-YAM OPL2 detection + SKpico FM T31/T32 |
| V1.3.86  | feat: SIDKick-pico FM Sound Expander detection |
| V1.3.85  | feat: ARM2SID SFX mode display + T28/T29 unit tests |
| V1.3.84  | bump: ARMSID+SIDFX D420 bus contamination fix |
| V1.3.83  | bump: SIDKick Pico D420 SIDFX detection via D41D echo |
| V1.3.82  | bump: checkrealsid retry confidence indicator (`*` suffix on main screen) |
| V1.3.81  | bump: multi-SID full melody sound test (snd_patch_page self-modifies 31× `sta $D4xx`) |
| V1.3.80  | bump: ARMSID stereo D5xx fix + 27 unit test suite |
| V1.3.79  | bump: info screen, readme screen, stereo fixes |
| V1.3.78  | bump: debug page 1 version string |
| V1.3.77  | initial commit (SID Detector II V1.3.77) — rebuilt repository baseline |
| V1.3.72  | docs: MixSID test coverage; SIDFX+ARMSID/PICO D420 TODOs; C41/C42 resolved as covered by C34f/C34g |
| V1.3.71  | MixSID ARMSID+8580: read D41B ACK in s_s_arm_call_real fixes 8580 re-detection after restart/screen-exit |
| V1.3.45  | fix dpf_lk_lp $AB1E register bug (A=lo,Y=hi): debug page 2 no longer hangs on UltiSID entries; UltiSID main screen shows "8580 INT"/"6581 INT" |
| V1.3.44  | remove jsr dbg_uci_query from dbg_uci_act (startup data already populated); fix jmp_to() dynamic orig_bytes restore |
| V1.3.43  | swap DATA_ACC before DF1F read: uci_resp+22 now shows post-reset status (should be 00); update test check |
| V1.3.42  | drain FIFO fully before reading status: add discard loop after 22-byte buffer fill; test checks status != dollar30 |
| V1.3.41  | debug p2 smoke test: verify UCI count/status/F1-addr on U64; add dbg_print_frame sid_list lookup for 6581/8580 curve name |
| V1.3.40  | dbg_print_frame: add INT/EXT suffix to GET_HWINFO T byte; clarify checkrealsid is primary UltiSID 6581/8580 detection |
| V1.3.39  | Remove dbg_uci_curvename — GET_HWINFO T byte is hardware presence code not filter curve; no UCI command exists to read filter curves |
| V1.3.30  | debug pg2: UltiSID filter curve scan; remove FOUND from ULTISID strings |
| V1.3.29  | ULTISID 7 filter curve variants via UCI type byte (8580 LO/HI, 6581, 6581 ALT, U2 LO/MID/HI) |
| V1.3.28  | fix debug page 2 heading (PETSCII); UltiSID on main screen; filter curve via UCI |
| V1.3.26  | (no description provided) |
| V1.3.25  | (no description provided) |
| V1.3.24  | fix UltiSID detection: lo=$00 filter prevents mirror false-positives (D640/D680); skip $FF in poll (open bus); fix D500 restart; guard overflow |
| V1.3.23  | fix uci_c2_add freq hi write for reliable UltiSID restart detection; fix debug page 2 title overwrite |
| V1.3.22  | real 8580 detection: SEI + 3-attempt retry in checkrealsid guards against VIC bad-line DMA steal interference; secondary SID type codes use SIDKick-pico codes (0B/0E) instead of generic 6581/8580 |
| V1.3.21  | shorten SIDKick-pico display strings to prevent line wrap |
| V1.3.20  | SIDKick-pico primary model detection: use auto-detect trigger instead of config-page-0 read to avoid poisoning secondary SID detection |
| V1.3.19  | SIDKick-pico secondary model type via primary config mode (config[8]=CFG_SID2_TYPE): 6581 or 8580 |
| V1.3.18  | SIDKick-pico secondary model: firmware does not expose model register at secondary slot; stays as type 0B |
| V1.3.17  | Fix SIDKick-pico dual SID secondary lost on restart; add fll_preclear for stale LFSR; add SIDKick-pico stereo scenario |
| V1.3.16  | --dry-run |
| V1.3.15  | SIDKick-pico dual SID: skip Check2 to fix secondary lost on restart |
| V1.3.14  | FPGASID: restore SID2 type detection via config mode |
| V1.3.13  | FPGASID restart fix: skip Check2 noise test that corrupts D43B |
| V1.3.12  | FPGASID restart fix: remove SID2 config access that corrupts D43B |
| V1.3.11  | Fix FPGASID D420 lost on restart: reset SID2 voice 3 oscillator in start via test-bit cycle; also restore SID2 type read via 82/65 config |
| V1.3.10  | Fix D420 persistent detection after restart: write D41E=$80 in SID2 config before exit to clear SID2 revision mode state |
| V1.3.09  | Fix FPGASID D420 restart detection; show secondary SID addresses and types; add FPGASID CPLD/FPGA revision display |
| V1.3.08  | fix SPACE restart: clear D41E identify bit; D420 FPGASID now found on restart |
| V1.3.07  | FPGASID: read CPLD/FPGA revision; show on debug screen and info page |
| V1.3.06  | fix: screen title width (zero-pad patch numbers to keep title 40 chars) |
| V1.3.5  | docs: add ARM2SID stereo map detection notes; V1.3.01/V1.3.02 changelog entries |
| V1.3.4  | fix: ARM2SID stereo scan now uses hardware map — eliminates false positives and restart inconsistency |
| V1.3.02 | stereo SID dispatch fixes, real SID type in secondary slots |
| V1.3.01 | begin stereo SID detection phase — ARM2SID slots queried via armsid_get_version |
| V1.2.19  | CI fix: VICE remote monitor replaces broken moncommands; BackSID stereo false-positive fix + spinner animation |
| V1.2.18  | CI fix: remote monitor + dynamic port replaces broken moncommands; BackSID stereo false-positive fix + spinner animation |
| V1.2.16  | D420/D500 mirror false positive fix for real SID stereo detection |
| V1.2.8  | Add SIDKick-pico detection via config mode VERSION_STR readback |
| V1.2.7  | Add BackSID detection via D41C echo protocol |
| V1.2.6  | Add PDsid detection: write P/D to D41D/D41E, read S from D41E (data1=$09); stereo scan and info page wired in |
| V1.2.5  | Fix stereo SID scan: skip D4xx and DE/DF in ARMSID pass to prevent false SwinsidU detections at primary SID mirrors |
| V1.2.4  | Info page system (press I), white heading / yellow content, CRSR LEFT/RIGHT navigation |
| V1.2.3  | SIDKick rename, PD SID rename |
| V1.2.2  | 3 new SID types: SIDKick, PD SID, BackSID; stereo DE00–DFFF support |

---

## Fixed crashes (historical)

### Fix 1 — Missing register saves in IRQ handler (`32e40f8`)

**File:** `siddetector.asm` — `IRQ:` label

The IRQ handler jumped to `$EA7E` (KERNAL finish-IRQ) without first pushing A/X/Y.
`$EA7E` does three PLAs then RTI — without the pushes, it consumed the hardware-pushed
P/PCL/PCH bytes, and RTI jumped to garbage → random PC → crash.

Fix: add `pha / txa / pha / tya / pha` at the top of the IRQ handler.

### Fix 2 — Incorrect VIC IRQ acknowledge (`a4f86c8`)

**File:** `siddetector.asm` line ~494

`inc $D019` was used to acknowledge the raster IRQ. `$D019` is write-1-to-clear:
`inc` reads $01, adds 1 → writes $02, which clears the wrong bit and leaves the raster
flag set → IRQ re-fires immediately → infinite re-entry → hang.

Fix: `lda #$01 / sta $D019`.

### Fix 3 — Info page black screen

`show_info_page` called `$E544` (clear screen), `$E50C` (cursor PLOT), and `$AB1E`
(string print) after our custom IRQ vector was installed. These KERNAL routines
conflicted with the modified ZP state, producing a black screen.

Fix: replaced all three with direct hardware writes:
- Screen RAM clear: fill `$0400–$07FF` and color RAM `$D800–$DBFF` directly
- Cursor position: write `$D1`/`$D2` (screen line ptr), `$D3` (col), `$D6` (row) directly
- String print: `$FFD2` loop via ZP `$FE`/`$FF` pointer

---

## Info page system

Press **I** on the main detection screen to enter the info page for the detected chip.

| Key | Action |
|-----|--------|
| CRSR LEFT (SHIFT+RIGHT) | previous page |
| CRSR RIGHT | next page |
| SPACE | return to main screen |

Pages 0–15 map to: NO SID, 6581, 8580, ARMSID, SWINSID U, SWINSID NANO,
FPGA 8580, FPGA 6581, SIDFX, ULTISID, VICE, HOXS64, SIDKICK, PD SID, BACKSID, UNKNOWN.

Color scheme: white heading (first line), yellow content, white nav hint (row 24).

---

## How to debug with VICE monitor

```bash
make debug
# or manually:
x64sc -autostart siddetector.prg -moncommands tests/debug.mon
```

Breakpoints in `tests/debug.mon`:
- `start` — program entry / spacebar restart
- `end` — after primary detection, before stereo scan
- `readkey2` — IRQ vector install
- `IRQ` — every raster interrupt
- `SPACEBARPROMPT` — keyboard poll loop
- `calcandloop`, `funny_print` — decay fingerprint phase

VICE monitor commands:
```
r                    — show registers (PC, SP, A, X, Y, P)
mem $0100 $0110      — dump stack
mem $d019            — VIC interrupt status
mem $1e00 $1e20      — sid_list / num_sids result tables
g                    — continue to next breakpoint
x                    — exit monitor (run freely)
```

---

## Unit tests

```bash
make test_suite      # 23 tests — all should pass ($17 at $0600)
make test            # arithmetic tests only
make test_dispatch   # dispatch logic tests only
```

Test suite covers: machine type dispatch, SIDFX, Swinsid/ARMSID/ARM2SID,
FPGASID, real SID 6581/8580, second SID, no sound, ArithmeticMean.

Hardware-specific tests (real SID decay, ARMSID echo, FPGASID magic cookie)
cannot run in VICE and require physical hardware.

---

## Memory map

| Range | Contents |
|-------|----------|
| `$0801–$080C` | BASIC stub (SYS 2061) |
| `$080D–$1D9E` | Main code |
| `$1E00–$1E24` | Result tables: `num_sids`, `sid_list_l/h/t`, `sid_map` |
| `$1E25–$38CF` | Screen data, info page text, string labels, colour table |

Note: data section was moved from `$1D00` to `$1E00` in V1.2.4 to make room
for the info page code.

---

## MCP C64 debugger

`mcp-c64` is configured and active. Tools available:
- `mcp__mcp-c64__assemble_program` — assemble a `.asm` file
- `mcp__mcp-c64__run_program` — launch a `.prg` in VICE

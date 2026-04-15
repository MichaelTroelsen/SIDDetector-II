# SID Detector TODO

## New chips to detect

- [x] **KungFuSID** — Detected via D41D echo: write $A5, read back. Old firmware returns $A5 (register echo); new firmware returns $5A (FW_UPDATE_START_ACK). Both accepted. Detection placed after all other hardware checks (position 5b). `data1=$0C`.
- [x] **SIDKick-pico** — Detected via config mode VERSION_STR: write $FF to D41F, $E0 to D41E, skip 20 bytes from D41D, read 'S'/$53 + 'K'/$4B (data1=$0B)
- [x] **BackSID** — Detected via register echo: write $42 to D41C, $B5 to D41D, $1D to D41E, read D41F; if D41F==$42 → BackSID (data1=$0A)
- [x] **PD SID** — Detected via register echo: write 'P' to D41D, 'D' to D41E, read 'S' from D41E (data1=$09)

## Features

### SID test sounds
- [x] Play a short test tone on each detected SID so the user can hear it is working
- [x] Use a simple triangle-wave note (voice 1, fixed frequency) per SID address
- [x] Optionally allow pressing a key to cycle through all detected SIDs

### Per-chip information pages
- [x] After detection, add an info screen for each detected chip (press a key to step through)
- [x] Show chip name, variant, known quirks, audio quality rating, and firmware/upgrade info
- [x] Include "where to buy" pointer (see CHIPS.md) on-screen where space allows

## Bugs to fix

### Multiple SID / stereo detection errors
- [x] **Unknown SID at D400 not written into `sid_list` tables** — fixed: after sidstereostart, if sidnum_zp==0, D400 is added as type $F0; sidstereo_print now shows "UNKNOWN SID FOUND" for $F0
- [x] **FPGASID stereo address not scanned** — fixed: removed `fiktivloop` (noise-mirror, wrong method for FPGASID) and `jsr s_s_l3` (premature return) from `s_s_lfpgasid`/`s_s_lfpgasid_2`; outer loop now continues scanning all addresses with `checkfpgasid`
- [x] **SIDFX stereo capability not reported** — fixed: pre-populated D400 in `end_pre_d400` block ($30 case) + added `sidFXf` dispatch in `sidstereo_print`; stereo row now shows "D400 SIDFX FOUND"
- [x] **Swinsid Nano (NOPAD variant) indistinguishable** — no reliable discriminant found; accepted as limitation
- [x] **NOSID+U2+ indistinguishable from SwinSID Nano** — exhaustively probed 10+ discriminants (D41B, D41C, D419/D41A, D41F, freq variation, waveform, interrupt context, monotone counting, write-to-read). All overlap. U2+ FPGA generates bus noise at ~44 kHz identical to SwinSID Nano oscillator. Accepted limitation; documented in FINDINGS.md.
- [x] **D400+D500 mixed Swinsid/real-SID** — fixed: at D5xx–D7xx in sidtype=$05 stereo scan, DIS echo (`sfx_probe_dis_echo`) is now tried before `checkrealsid` when primary is a real SID ($01/$02). Returns type $04 (SwinSID U) or $05 (ARMSID) instead of misidentifying as 6581/8580. Guard prevents triggering when ARMSID is primary (snoops all writes). *(teststatus #21 — needs hw verification)*
- [x] **D400+D500 mixed ARMSID/real-SID** — fixed V1.3.73: jmp s_s_l3 in s_s_add for sidtype=$05 exits ARMSID scan early, preventing U64/ULTISID false entries from D5xx-DFxx scan; 8580@D400 + ARMSID@D420 hw_test 10/10 *(teststatus C09 — 🟢)*
- [x] **Stereo ARMSID / SwinSID U detection skipped** — fixed V1.3.80: `s_s_arm_call_real` now allows `data4=$05` (ARMSID primary) to reach `sfx_probe_dis_echo` for D5xx+ candidates. `sfx_probe_dis_echo` reads from `candidate+$1B` (not D41B), so D400 ARMSID snooping the DIS writes does not corrupt the result. The cleanup writes and existing `s_s_skip_dis: lda $D41B` ACK handle residual tristate. *(requires hardware with dual ARMSID/SwinSID U config to verify — teststatus: add C50+)*
- [x] **SwinSID Ultimate fiktivloop false positive (D500)** — AVR OSC3 returns 0 with noise enabled; `checksecondsid` falsely detected D500 as a second SID. Fixed: skip `fiktivloop` for `data4=$04` (SwinSID U is always single-slot). Same pattern as SIDFX skip at `end_skip_fiktiv`.
- [x] Fix FC3 cartridge false-positive C128 detection — merged check128_unknown into check128_c128 path; $D0FE open-bus ($FF) now overrides false C128/TC64 detect from FC3
- [x] **Info page CRSR LEFT/RIGHT navigation broken** — fixed by adding B (prev) and M (next) key aliases; VICE `gtk3_sym_da.vkm` does not reliably map PC cursor keys to CIA row-0 bit-2, but B/M work correctly in VICE

## Testing

### Covered by test suite (tests/test_suite.asm — 27 tests)
- [x] Machine type dispatch: C64 / C128 / TC64 (T01–T03)
- [x] SIDFX dispatch: found / not found (T04–T05)
- [x] Swinsid Ultimate dispatch: data1=$04 (T06)
- [x] ARM2SID dispatch: data1=$05, data2=$4F, data3=$53 (T07)
- [x] ARMSID dispatch: data1=$05, data2=$4F, data3≠$53 (T08)
- [x] ARMSID no-match cases: data2 wrong / data1 wrong (T09–T10)
- [x] FPGASID 8580 dispatch: data1=$06 (T11)
- [x] FPGASID 6581 dispatch: data1=$07 (T12)
- [x] FPGASID no-match: data1=$F0 (T13)
- [x] Real SID 6581 dispatch: data1=$01 (T14)
- [x] Real SID 8580 dispatch: data1=$02 (T15)
- [x] Real SID no-match: data1=$F0 (T16)
- [x] Second SID dispatch: data1=$10 (T17)
- [x] No sound dispatch: data1=$F0 (T18)
- [x] ArithmeticMean: [10,20,30]=20, [5×6]=5, [100,50,75,25]=62, empty=0 (T19–T22)
- [x] FPGASID stereo: data1=$06 at $D500 → recorded in sid_list (T23)
- [x] PDsid dispatch: data1=$09 (T24)
- [x] BackSID dispatch: data1=$0A (T25)
- [x] SIDKick-pico dispatch: data1=$0B (T26)
- [x] KungFuSID dispatch: data1=$0C (T27)

### Not yet testable in VICE (require real hardware)
- [ ] `Checkarmsid` hardware probe — SID register echo depends on chip model
- [ ] `checkfpgasid` magic-cookie config — only works on real FPGASID
- [ ] `checkrealsid` OSC3 readback — sawtooth decay is hardware-specific
- [ ] `checksecondsid` noise mirror — $D41B randomness is hardware-specific
- [ ] `calcandloop` decay timing — emulator timing differs from hardware by design
- [ ] Add tests for new chips (PICOSid, BackBit SID, Public Domain SID) once detection method is known

### MixSID hardware combination tests (require physical chip swaps)
- [x] **C06** — ARMSID@D400 + 6581@D420: confirmed V1.3.74: fallback Checkarmsid at D400 handles ARMSID@CS1 correctly; 6581 at D420 found via sidstereostart s_s_arm_call_real; hw_test 10/10 *(teststatus C06 — 🟢)*
- [ ] **C01–C04** — real SID + real SID combos at D420 (6581/8580 × 6581/8580): different detection path (not ARMSID); low priority, expected to work
- [x] **C08** — 6581@D400 + ARMSID@D420: fixed V1.3.74: single CS2-DIS window in step2_armsid (pre-clean voice3+D41F, enter CS2-DIS once, checkrealsid inside window, dispatch BEFORE cleanup to avoid false uSID64 via U64 FPGA); hw_test 10/10 *(teststatus C08 — 🟢)*
- [x] **C09** — 8580@D400 + ARMSID@D420: fixed V1.3.73 *(teststatus C09 — 🟢)*
- [ ] **C10–C20** — misc MixSID combos (FPGASID, SwinSID Nano, SIDKick Pico, KungFuSID as primary or secondary at D420): untested, various code paths

### SIDFX secondary detection for ARMSID and SIDKick Pico at D420 (LFT slot)
- [x] **SIDFX + ARMSID at D420** (SW1=LFT): ARMSID firmware does not activate DIS detection from CS2 slot — DIS writes to D43F/D43E/D43D produce no echo at D43B or D41B (confirmed hw: 8580@D400 + ARMSID@D420). ARMSID only responds to DIS via CS1. SIDFX reports ARMSID (8580-mode) as 8580 — same as real 8580, undetectable. WONTFIX: falls back to SIDFX-reported type. V1.3.84 guards prevent false positives.
- [x] **SIDFX + SIDKick Pico at D420** (SW1=LFT): SIDKick Pico cannot be specifically identified at D420 via CS2. D41D echo test was SIDFX write-buffer artifact (SIDFX caches unmapped reg writes, returns them for any chip). DIS probe (D43B) is contaminated when primary is ARMSID (CS-agnostic bus drive). Fixed V1.3.84: removed D41D echo; added ARMSID-primary guard for DIS at D420; falls back to SIDFX-reported type. WONTFIX for specific PICO identification at D420.

## Other improvements

- [x] **Skip $D418 decay scan when hardware SID detected** — removed from scope: decay scan still runs but result is overridden by hardware detection; no user-visible benefit in skipping it
- [x] **ARMSID2 detection** — second generation distinguished from ARMSID
- [~] **Save results to disk** — WONTFIX: niche use case, 1541 not always present
- [x] **REU / GeoRAM conflict handling** — accepted limitation: documented as known false positive; no fix planned since DE00/DF00 conflict is environment-specific and rare
- [x] **ULTISID detection improvement** — WONTFIX: U64 firmware registers not publicly documented; current $D418 decay fingerprint detection is sufficient
- [x] **ULTISID main screen display** — V1.3.45: shows "8580 INT"/"6581 INT" instead of filter curve names (teststatus #15/#16 fixed)
- [x] **D418 decay table accuracy** — timing constants re-measured and updated
- [x] **Colour-coded results** — `colorize_rows` routine implemented and called after detection; reads col 13 of each row and writes green (found) / red (not found) / yellow (info) to $D800 colour RAM; boundary correctly updated to `cpx #$0E` when KUNGFUSID row was added

## Other known bugs

- None currently tracked

## In-app content improvements

- [x] **Info screen** — added revision quirks (6581: combined waveforms, DC offset, OSC3/ENV3; 8580: voice-3 disconnect, combined waveform note); firmware link for ARMSID; detection method added to SIDKick-pico, BackSID, PD SID; PD SID description rewritten to reflect specific product
- [x] **Readme screen** — added PDsid to chip list; expanded detection chain with steps 3A/3B/3C (PDsid/BackSID/SIDKick-pico) and 7A (KungFuSID); fixed README_LINES=55→74 / README_MAX_SCROLL=34→53 (version history was unreachable); bumped to V1.3.79
- [x] **Main screen** — V1.3.83: `retry_zp` ($B2) tracks how many attempts `checkrealsid` needed; a `*` is appended after "6581 FOUND"/"8580 FOUND" on the main screen if any retries were required (VIC bad-line DMA steal)
- [x] **Sound test** — T-key test shows "NOW TESTING: D4xx" before each SID; all detected SIDs play the full 3-voice melody (snd_patch_page self-modifies all 31 sta $D4xx in st_soundtest to any SID page). per-SID volume adjustment not implemented (low value).
- [x] **Debug screen** — show siddetector version string on page 1 so it is visible without the README screen

## GitHub repository improvements

- [x] **Fix repository** — screenshot added to README; landing page now shows detection result screen
- [x] **Releases** — v1.3.77–v1.3.82 tagged and released on GitHub (MichaelTroelsen/SIDDetector-II)
- [x] **GitHub README** — updated to v1.3.82; Known issues updated with V1.3.83 retry indicator
- [x] **CI** — removed; use `make ci` locally (Ubuntu VICE too many ROM/autostart quirks)

## Stereo config error cases (wrong result reported)

- D400: 6581   D500: Swinsid  — **fixed V1.3.79** (`s_s_arm_call_real` tries `sfx_probe_dis_echo` when primary is real SID $01/$02; SwinSID U echoes 'S' at D51B → detected correctly)
- D400: Swinsid D500: 6581   — **fixed V1.3.02** (`fiktivloop` now calls `checkrealsid` on candidate; 6581/8580 correctly identified in secondary slot)
- D400: Swinsid DE00: 6581   — **fixed V1.3.02** (same fix)
- D400: armsid  D500: 8580   — **fixed V1.3.02** (same fix)
- D400: armsid  DE00: 8580   — **fixed V1.3.02** (same fix)

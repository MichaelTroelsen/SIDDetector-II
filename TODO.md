# SID Detector TODO

## New chips to detect

- [x] **8-SID "Tuneful Eight" (U64)** — V1.4.36 lifted the slot cap; V1.4.37
      added the write-coupling scan that actually detects all 8 slots in the
      first place. Verified on the user's U64 hardware (3/3 consecutive runs
      → 8 SIDs at `D400 D420 D480 D4A0 D500 D520 D580 D5A0`). Per-iteration
      flow: silence primary D400 voice 3, snapshot every already-found
      slot's OSC3, write saw+gate to candidate's voice 3, reject if primary
      or any found slot's OSC3 changed (write-mirror). Drops the `is_u64`
      gate because U64 configs that disable UCI return `$DF1F = $FF` yet
      still have multi-SID hardware; uses direct `checkrealsid` for chip
      typing because `uci_type_for_addr` hangs in its FIFO drain loop when
      UCI is unresponsive.
- [ ] **EMUSID (new)** — Planned chip family (TBD vendor / protocol).
      Add detection stub + TODO.md placeholder once the magic-cookie
      spec is published; wire it through `sidstereo_print` + info page.
- [x] **CBM SFX Sound Expander + FM-YAM (shared chip)** — V1.4.06+: detected at standard `$DF40/$DF50/$DF60` (XeNTaX reference) via `checkfmyam`. Both products use Yamaha OPL family (YM3526 / YM3812) with identical port decoding; one detection path covers both. V1.4.09: T1 started with IRQ masked (`$04=$41`) + RST on exit to avoid OPL-/IRQ CPU storm that was hanging real hardware. V1.4.19: detection uses `(status & $E0) == 0` on two reads — real OPL drives status into `$00-$1F` range; open bus has high bits set (`$FF, $D1, $C5`). V1.4.20: screen label neutralized to `DF40 SFX/FM FOUND`. V1.4.22: legacy `checksfxexpander` at `$DE00` removed entirely (had been disabled in V1.4.18 due to bus-noise false positives); `opl_write_reg` simplified to a single jmp to `cfm_write_reg`; dead vars `sfxexp_detected`/`sfx_port_mode`/`opl_tmp_reg/val`/`dse_s2b/6b/2b_b` removed. Verified on U64 with FM-YAM installed/removed and CBM SFX Sound Expander — see teststatus rows 41-44.
- [x] **OPL sound test** — V1.4.13+: Sound test (T) plays the same 7-note C-major arpeggio (`C E G C G E C`) across 3 octaves per instrument, matching SID's 3-voice pattern. Three FM instruments: Flute (pure sine, no FM), Organ (FM sustained w/ feedback), Bell (FM percussive). Global OPL init sequence (`$01=$20`, `$08=$00`, `$BD=$C0`) per XeNTaX edlib player. V1.4.14: SID pulse width table reorder fix — pulse was silent after waveform reorder. V1.4.15: three FM instruments added.
- [x] **KungFuSID** — Detected via D41D echo: write $A5, read back. Old firmware returns $A5 (register echo); new firmware returns $5A (FW_UPDATE_START_ACK). Both accepted. Detection placed after all other hardware checks (position 5b). `data1=$0C`.
- [x] **SIDKick-pico** — Detected via config mode VERSION_STR: write $FF to D41F, $E0 to D41E, skip 20 bytes from D41D, read 'S'/$53 + 'K'/$4B (data1=$0B)
- [x] **BackSID** — Detected via register echo: write $42 to D41C, $B5 to D41D, $1D to D41E, read D41F; if D41F==$42 → BackSID (data1=$0A)
- [x] **PD SID** — Detected via register echo: write 'P' to D41D, 'D' to D41E, read 'S' from D41E (data1=$09)

## Features

### Quality (Q) info page — combined sidcheck + $D418 decay
- [ ] **`Q` key → dedicated "Quality Fingerprint" page.** Combines two
      orthogonal accuracy fingerprints into one screen:
      - **sidcheck** (Wonderland XIII / Censor Designs) — combined-waveform
        OSC3 readback after specific timed $D40E/F/D412 sequences. Produces
        a 0–5 grade per detected SID slot ("AWFUL/BAD/GOOD/BEST"). Lifted
        from `vice-emu-code-r46118-testprogs-SID/sidcheck/sidcheck.asm`;
        rebased to drive `sptr_zp` so it can run against each entry in
        `sid_list`.
      - **$D418 decay** — existing `calcandloop` decay-rate measurement,
        currently shown only on row 15 of the main screen when no chip was
        identified (`data4=$F0`). On the Q page, surface it for *every*
        detected slot so the user can compare implementations side-by-side
        (real 8580 vs ARMSID vs FPGASID vs SwinSID emulators, etc).
      - Layout: one row per detected SID — `D400  QUALITY 4/5 (BEST 8580)  D418=N15`
      - Tradeoffs: needs raster-sync (sei + $d011/$d012 wait); writes to
        voice 3 ($D40E/F/D411/D412/D40F) so must restore quiet state
        ($D??12=0) at end of each slot probe. Per-family interpretation
        table not calibrated for v1 — ship raw grade, future revision
        builds per-chip expected-grade reference.
      - Source notes: see `vice-emu-code-r46118-testprogs-SID/sidcheck/`
        in `~/Downloads` (memory: `vice_sid_testprogs.md`).

### SID test sounds
- [x] Play a short test tone on each detected SID so the user can hear it is working
- [x] Use a simple triangle-wave note (voice 1, fixed frequency) per SID address
- [x] Optionally allow pressing a key to cycle through all detected SIDs

### Second tune + tune-select in tracker view
- [x] **Embed `bin/Delirious_9_tune.sid` (Troelsen / Fun Fun, Genesis Project
      1990) as a second tune in the tracker view, selected with keys 1 / 2.**
      Resolved V1.4.34 via option 1 (SIDwinder offline relocation): tune
      relocated to `$A000-$B39B` and embedded directly in the .prg as a
      separate segment. New tune-management code lives in a fresh `$C020`
      segment (above the tracker shadow at `$C000-$C01F`). `tune_select`
      patches IRQ play / init JSR operands, tracker_patch_once scan range,
      and the title row pointer. `tracker_poll_keys` now handles `1` / `2`
      and calls `tune_switch` which stops IRQ play, silences SID, unpatches
      old player, repatches new range, re-inits, redraws chrome. BASIC ROM
      is banked out (`$01=$36`) only inside the IRQ play call and around
      tune_player_init / tracker_patch_once — the rest of the program keeps
      `$01=$37` so `$AB1E` (BASIC STROUT) still works. PRG grew from
      ~33 KB to ~46 KB (8 KB zero-pad to $A000 + 5 KB tune + ~256 B in
      $C020 segment).

### SID music playback (P key) — visual animation
- [x] **VU meters / waveform display while SID music plays.** Implemented as
      a dedicated "SID TRACKER VIEW" screen (P enters, SPACE / P / Q exits via
      `jmp start`). Design:
      - Player's `STA $D4xx` writes are redirected via binary patch to
        shadow RAM at `$C000-$C01F`; raster IRQ copies shadow -> real SID
        each frame after `jsr $1806`. Lets the render path read voice
        FREQ / PW / CTRL / ADSR (regs otherwise write-only).
      - Per-voice columns show NOTE name (96-entry PAL note table lookup),
        waveform letters (TRI/SAW/PUL/NOI/---), gate +/-, ADSR and FREQ hex.
      - VU bar per voice: voice 3 uses real `$D41C` ENV3; voices 1-2 use a
        software envelope follower that tracks gate edges and ramps per
        AD/SR nybbles.
      - 40-column live OSC3 scope plotted across 8 rows at bottom.
      - Tracker code lives at `$9200` (below BASIC ROM) so it stays CPU-
        visible without bank switching. Footprint ~3.5 KB code+data.

### Per-chip information pages
- [x] After detection, add an info screen for each detected chip (press a key to step through)
- [x] Show chip name, variant, known quirks, audio quality rating, and firmware/upgrade info
- [x] Include "where to buy" pointer (see docs/CHIPS.md) on-screen where space allows

## Bugs to fix

### Multiple SID / stereo detection errors
- [x] **Unknown SID at D400 not written into `sid_list` tables** — fixed: after sidstereostart, if sidnum_zp==0, D400 is added as type $F0; sidstereo_print now shows "UNKNOWN SID FOUND" for $F0
- [x] **FPGASID stereo address not scanned** — fixed: removed `fiktivloop` (noise-mirror, wrong method for FPGASID) and `jsr s_s_l3` (premature return) from `s_s_lfpgasid`/`s_s_lfpgasid_2`; outer loop now continues scanning all addresses with `checkfpgasid`
- [x] **SIDFX stereo capability not reported** — fixed: pre-populated D400 in `end_pre_d400` block ($30 case) + added `sidFXf` dispatch in `sidstereo_print`; stereo row now shows "D400 SIDFX FOUND"
- [x] **Swinsid Nano (NOPAD variant) indistinguishable** — no reliable discriminant found; accepted as limitation
- [x] **NOSID+U2+ indistinguishable from SwinSID Nano** — exhaustively probed 10+ discriminants (D41B, D41C, D419/D41A, D41F, freq variation, waveform, interrupt context, monotone counting, write-to-read). All overlap. U2+ FPGA generates bus noise at ~44 kHz identical to SwinSID Nano oscillator. Accepted limitation; documented in docs/FINDINGS.md.
- [x] **D400+D500 mixed Swinsid/real-SID** — fixed: at D5xx–D7xx in sidtype=$05 stereo scan, DIS echo (`sfx_probe_dis_echo`) is now tried before `checkrealsid` when primary is a real SID ($01/$02). Returns type $04 (SwinSID U) or $05 (ARMSID) instead of misidentifying as 6581/8580. Guard prevents triggering when ARMSID is primary (snoops all writes). *(teststatus #21 — needs hw verification)*
- [x] **D400+D500 mixed ARMSID/real-SID** — fixed V1.3.73: jmp s_s_l3 in s_s_add for sidtype=$05 exits ARMSID scan early, preventing U64/ULTISID false entries from D5xx-DFxx scan; 8580@D400 + ARMSID@D420 hw_test 10/10 *(teststatus C09 — 🟢)*
- [x] **Stereo ARMSID / SwinSID U detection skipped** — fixed V1.3.80: `s_s_arm_call_real` now allows `data4=$05` (ARMSID primary) to reach `sfx_probe_dis_echo` for D5xx+ candidates. `sfx_probe_dis_echo` reads from `candidate+$1B` (not D41B), so D400 ARMSID snooping the DIS writes does not corrupt the result. The cleanup writes and existing `s_s_skip_dis: lda $D41B` ACK handle residual tristate. *(requires hardware with dual ARMSID/SwinSID U config to verify — teststatus: add C50+)*
- [x] **SwinSID Ultimate fiktivloop false positive (D500)** — AVR OSC3 returns 0 with noise enabled; `checksecondsid` falsely detected D500 as a second SID. Fixed: skip `fiktivloop` for `data4=$04` (SwinSID U is always single-slot). Same pattern as SIDFX skip at `end_skip_fiktiv`.
- [x] Fix FC3 cartridge false-positive C128 detection — merged check128_unknown into check128_c128 path; $D0FE open-bus ($FF) now overrides false C128/TC64 detect from FC3
- [x] **Info page CRSR LEFT/RIGHT navigation broken** — fixed by adding B (prev) and M (next) key aliases; VICE `gtk3_sym_da.vkm` does not reliably map PC cursor keys to CIA row-0 bit-2, but B/M work correctly in VICE

## Testing

### Covered by test suite (tests/test_suite.asm — 34 tests)
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
- [x] ARM2SID SFX-only: emul_mode=$01 (T28)
- [x] ARM2SID SFX+SID: emul_mode=$02 (T29)
- [x] SKpico FM Sound Expander: skpico_fm=$04 (T30) / $05 (T31)
- [x] FM-YAM OPL2: fmyam_detected=$01 (T32)
- [x] CBM SFX dispatch: flag=$00 → none (T33) / flag=$01 → found (T34) — dispatch-logic tests only (uses a fake flag var since V1.4.22 removed the live `sfxexp_detected` + `$DE00` probe)

### Not yet testable in VICE (require real hardware)
- [x] `Checkarmsid` hardware probe — user-confirmed 2026-04-19 / V1.4.27; see P01 in docs/teststatus.md
- [x] `checkfpgasid` magic-cookie config — user-confirmed 2026-04-19 / V1.4.27; see P02 in docs/teststatus.md
- [x] `checkrealsid` OSC3 readback — user-confirmed 2026-04-19 / V1.4.27; see P03 in docs/teststatus.md
- [x] `checksecondsid` noise mirror — user-confirmed 2026-04-19 / V1.4.27; see P04 in docs/teststatus.md
- [x] `calcandloop` decay timing — user-confirmed 2026-04-19 / V1.4.27; see P05 in docs/teststatus.md
- [x] **PICOSid / BackBit SID / Public Domain SID** — detection implemented (SIDKick-pico config-mode, BackSID unlock protocol, PD SID echo); VICE unit tests T24–T27 added

### MixSID hardware combination tests (require physical chip swaps)
- [x] **C06** — ARMSID@D400 + 6581@D420: confirmed V1.3.74: fallback Checkarmsid at D400 handles ARMSID@CS1 correctly; 6581 at D420 found via sidstereostart s_s_arm_call_real; hw_test 10/10 *(teststatus C06 — 🟢)*
- [x] **C01–C04** — real SID + real SID combos at D420 (6581/8580 × 6581/8580): verified on hardware
- [x] **C08** — 6581@D400 + ARMSID@D420: fixed V1.3.74: single CS2-DIS window in step2_armsid (pre-clean voice3+D41F, enter CS2-DIS once, checkrealsid inside window, dispatch BEFORE cleanup to avoid false uSID64 via U64 FPGA); hw_test 10/10 *(teststatus C08 — 🟢)*
- [x] **C09** — 8580@D400 + ARMSID@D420: fixed V1.3.73 *(teststatus C09 — 🟢)*

### SIDFX secondary detection for ARMSID and SIDKick Pico at D420 (LFT slot)
- [x] **SIDFX + ARMSID at D420** (SW1=LFT): ARMSID firmware does not activate DIS detection from CS2 slot — DIS writes to D43F/D43E/D43D produce no echo at D43B or D41B (confirmed hw: 8580@D400 + ARMSID@D420). ARMSID only responds to DIS via CS1. SIDFX reports ARMSID (8580-mode) as 8580 — same as real 8580, undetectable. WONTFIX: falls back to SIDFX-reported type. V1.3.84 guards prevent false positives.
- [x] **SIDFX + SIDKick Pico at D420** (SW1=LFT): SIDKick Pico cannot be specifically identified at D420 via CS2. D41D echo test was SIDFX write-buffer artifact (SIDFX caches unmapped reg writes, returns them for any chip). DIS probe (D43B) is contaminated when primary is ARMSID (CS-agnostic bus drive). Fixed V1.3.84: removed D41D echo; added ARMSID-primary guard for DIS at D420; falls back to SIDFX-reported type. WONTFIX for specific PICO identification at D420.

## ARMSID2 SFX capability

ARMSID2 (second generation) includes built-in SFX Sound Expander emulation (Yamaha OPL2 / YM3812).
`armsid_emul_mode` is already read in `armsid_get_version` ('m','m' command → D41B bits[1:0]):
  - 0 = SID only (standard)
  - 1 = SFX only (OPL2, no SID)
  - 2 = SFX + SID (both simultaneously)

The value is shown on the debug screen ("SID"/"SFX"/"BOT") but not surfaced elsewhere.

- [x] **Main screen** — V1.3.85: when ARM2SID emul_mode≥1, "FOUND" replaced by "+SFX " (same width); mode=1 (SFX only) suppresses SID type field; mode=2 shows "+SFX " + SID type
- [x] **Info page** — V1.3.85: `arm2sid_print_extra` shows "MODE: SID", "MODE: SFX", or "MODE: SID+SFX" (ARM2SID only)
- [x] **Stereo rows** — V1.3.85: ARM2SID SFX- slots (DF00/DF20) omit SID type (`print_map_name` shows "SFX-"; `tmp_zp==$03` guard skips `print_sid_type_4`)

## Other improvements

- [x] **Skip $D418 decay scan when hardware SID detected** — removed from scope: decay scan still runs but result is overridden by hardware detection; no user-visible benefit in skipping it
- [x] **ARMSID2 detection** — second generation distinguished from ARMSID
- [~] **Save results to disk** — WONTFIX: niche use case, 1541 not always present
- [x] **REU / GeoRAM conflict handling** — mostly moot since V1.4.06 moved OPL detection to the standard `$DF40/$DF50/$DF60` XeNTaX ports (REU lives at `$DF00-$DF0F`, so no overlap). The `$DE00` legacy probe that could have conflicted with IO1 cartridges was removed entirely in V1.4.22.
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
- [x] **Photos of chips and boards** — 19 hardware photos added to `pictures/` (commit e645031): HEIC originals + JPEG web-ready previews in `pictures/jpeg/`. Cover bare C64/C128/U64/C64-Reloaded boards, 6581/8580 chip reference, ARMSID/ARM2SID, FPGASID, SwinSID Nano/Ultimate, SIDKick Pico, BackSID, PDSID, uSID64, FM-YAM + CBM SFX rig, and probe/test rigs. Selected photos embedded in README.md (Hardware test rig section) and docs/STORY.md §4, §6, §7, §10, §18.

## Stereo config error cases (wrong result reported)

- D400: 6581   D500: Swinsid  — **fixed V1.3.79** (`s_s_arm_call_real` tries `sfx_probe_dis_echo` when primary is real SID $01/$02; SwinSID U echoes 'S' at D51B → detected correctly)
- D400: Swinsid D500: 6581   — **fixed V1.3.02** (`fiktivloop` now calls `checkrealsid` on candidate; 6581/8580 correctly identified in secondary slot)
- D400: Swinsid DE00: 6581   — **fixed V1.3.02** (same fix)
- D400: armsid  D500: 8580   — **fixed V1.3.02** (same fix)
- D400: armsid  DE00: 8580   — **fixed V1.3.02** (same fix)

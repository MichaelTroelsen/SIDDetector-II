# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SID Detector is a Commodore 64 diagnostic utility written in 6502 assembly that identifies 24+ variants of SID (Sound Interface Device) chips and emulators. Reference release: https://csdb.dk/release/?id=176909

## Build

```bash
make             # assemble siddetector.asm → siddetector.prg using KickAssembler
make run         # launch detector in the patched WinVICE 3.9
make run-armsid  # launch with ARMSID personality at D400  (see Makefile for full list)
make ci          # host tests + unit tests (46 cases) + MEMORYMAP.md drift check
make ci-full     # the above + golden-diff sweep across all 30 variant cases
make python_tests # host-side Python tests only (no emulator, <1 s)
make clean       # remove siddetector.prg
```

**Tools:**
- **KickAssembler** (`C:/debugger/kickasm/KickAss.jar`, requires Java).
- **Patched WinVICE 3.9** with the `-sidvariant` personality layer at `C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe`. Source, build recipe and usage: `docs/VICE_PROXY_BUILD.md`, `docs/VICE_PROXY_USAGE.md`, `docs/ARMSID_PROXY_PLAN.md`. **All VICE-based tests must use this binary** — the stock VICE doesn't know `-sidvariant`.
- **Tool paths live in ONE place: `toolpaths.env`.** The Makefile `include`s it,
  `scripts/ci_test.sh` sources it, and `scripts/toolpaths.py` parses it for the
  Python harnesses. Do not re-hard-code a path in a script — they were previously
  copy-pasted into 17 files and drifted. A wrong path fails with one clear message
  naming that file.

**Shared harness modules** (all in `scripts/`, import them rather than
re-implementing):
- `toolpaths.py` — tool locations; `vice()` / `kickass_jar()` validate at point of use.
- `c64screen.py` — C64 screen-code decoding. Note `$20-$3F` are byte-identical to
  ASCII, so only `$01-$1A` (letters) need shifting.
- `viceproc.py` — `terminate(proc)` stops only the VICE this script started.
  **Never** use `taskkill /F /IM x64sc.exe`; it kills the user's interactive session.

**Host tests** (`make python_tests`, no emulator needed): `tests/test_hw_snapshot.py`,
`tests/test_variant_render.py`, `tests/test_c64screen.py`,
`tests/test_emu_classifier.py` (parses `emu_class_tab` out of the asm and proves
it still reproduces the two decision trees it replaced, over the whole input
space — edit that table and this is what catches you).

**Gotchas that cost real debugging time** (see `CODE-REVIEW.md`):
- VICE **monitor** reads of SID registers disagree with CPU reads — the monitor
  peeks I/O without clocking ResID. Debug SID reads with a `tests/probe_*.asm`
  program that records them, never with monitor `m`.
- A screen dump pauses the machine and perturbs detection; `variant_smoke.py`'s
  `MIN_WAIT` must stay past the end of the chain (22 s).
- OSC3 keeps residue after a voice is silenced — "non-zero" does not mean "mirror".
  Both stereo mirror tests therefore baseline the candidate while nothing drives
  it and look for a *change* (V1.5.08, P0-5).
- **Do not add or move instructions between "start the reference oscillator" and
  "first read of the candidate"** in `s_s_arm_chk` / `s_s_arm_mir_test`. In a
  single-SID config every `$D4xx` address mirrors `$D400` and ~20 extra cycles in
  that window was measured to change *which* mirror the scan reports
  (`$D420` → `$D460`) — wrong on a real FPGASID, whose SID2 genuinely is at
  `$D420`. Two earlier attempts at the P0-5 fix were reverted for exactly this.

**Source syntax:** The `.asm` file uses KickAssembler syntax (converted from the original ACME source in `siddetector.asm.acme.bak`). Key differences from ACME: `.byte`/`.word`/`.text` directives, `//` comments, `.const` for symbol equates, lowercase mnemonics only, labels require `:`, and `#'x'` for char literals.

## Architecture

The program executes a sequential detection chain at startup, testing SID registers and measuring timing characteristics to classify the hardware:

### Detection Chain (in order)

1. **`DETECTSIDFX`** — Tests for SIDFX external hardware
2. **`Checkarmsid`** — Identifies ARMSID chip (uses timing hacks due to bus behavior)
3. **Swinsid detection** — Identifies Swinsid Ultimate emulator
4. **`checkfpgasid`** — FPGA-based SID (6581 or 8580 variant)
5. **`checkusid64`** — uSID64 detection via D41F config register two-read stability test
6. **`checkrealsid`** — Real 6581/8580 chip identification (sub-revisions R2, R3, R4, R4AR)
7. **`checksecondsid`** — Scans for additional SIDs at D500/D600/D700/DE00/DF00 (stereo configs)
8. **`checkkungfusid`** — KungFuSID via D41D echo/ACK
9. **`checkswinsidnano`** — SwinSID Nano via dual-frequency oscillator test (D41B)
10. **`checkfmyam`** — Yamaha OPL2 FM expansion (CBM SFX Sound Expander / FM-YAM) at $DF40/$DF50/$DF60 (V1.4.x)
11. **`checkmidi`** — C64 MIDI cartridges (Sequential/Namesoft/DATEL/Passport/Maplin) via 6850 ACIA reset signature (V1.4.45)
12. **`tlr_sweep`** — family-agnostic baseline scan (TLR `sid-detect2`); runs only when no primary chip identified (`data4=$00`); finds get type `$11`, deduped against family-specific results (V1.5.01)

Emulator detection (VICE ResID/FastSID, HOXS64, Frodo, YACE64, EMU64) runs as a fallback when no hardware SID is identified.

**Screens:** the result screen offers I (per-chip info), Q (Quality Fingerprint — sidcheck grade + $D418 decay per slot, V1.5.02), D (debug), R (readme), T (sound test), P (tracker view), L (TLR detector), SPACE (restart).

### Key Techniques

- **`calcandloop` / `ArithMean`** — Measures the $D418 (volume) register decay characteristic over multiple samples; the decay rate distinguishes chip types
- **Provisional typing, refined in place (V1.5.06)** — `u64_fingerprint_scan`
  runs before the family sweeps (their writes would clobber the per-slot OSC3
  fingerprints it needs) but it can only prove "an independent SID lives here",
  not which one. It therefore records the type its own `checkrealsid` measured
  plus a per-slot `sid_prov` flag; `s_s_dup_lp` and `fll_dup_lp` (via
  `fll_refine`) then overwrite that type **in place** instead of skipping the
  address as a duplicate. On a U64, `ufs_chk_u64` converts the provisional
  entries to the ULTISID curve codes, because there nothing downstream can refine
  them. **Both mirror checks must skip a list entry at the candidate's own
  address** — otherwise a provisionally-typed slot tests itself and always looks
  like a mirror.
- **Self-modifying code** — SID register addresses (e.g., `cas_d418`, `cas_d41D`–`cas_d41F`) are patched at runtime to handle D400/D500 mirroring in FPGA implementations
- **`checkpalntsc`** — PAL vs NTSC detection affects timing loops throughout
- **`check128`** — Detects C64 vs C128 to adjust behavior

### Memory Layout

| Address | Contents |
|---------|----------|
| `$0801` | BASIC stub (`SYS 9216` → `$2400`) |
| `$1800` / `$A000` | Embedded SID tunes (Triangle Intro / Delirious 9) |
| `$0A00` | Embedded TLR `sid-detect2` (copied to `$0801` on **L**) |
| `$2400` | Main program — `start:` + all detection routines (`~$5A99`) |
| `$5B00` | `tlr_sweep` baseline scan (V1.5.01) |
| `$6000` | Detection tables (`num_sids`, `sid_list_l/h/t`, `sid_map`) + screen/string/colour data |
| `$9200` | SID Tracker View code (V1.4.33) |
| `$C000`/`$C020` | Tracker shadow SID + tune-selector segment |
| `$C300` | Quality Fingerprint page code + tables (V1.5.02) |

Zero-page `$A2–$AF`, `$B0–$C2`, and `$F6–$FF` hold working variables and detection state (`$C1/$C2` = Q-page patch pointer `qc_pt_ptr`).

### Detected SID Types

Real chips (6581 R2/R3/R4/R4AR, 8580), FPGASID, ARMSID/ARM2SID, Swinsid Nano/Ultimate/Micro, SIDKick-pico (8580/6581), KungFuSID, BackSID, PD SID, uSID64, ULTISID (U64), SIDFX; FM expansion (CBM SFX Sound Expander / FM-YAM); MIDI cartridges (Sequential/Namesoft/DATEL/Passport/Maplin); emulators VICE ResID/FastSID, HOXS64, Frodo, YACE64, EMU64; plus UNKNOWNSID and No Sound fallbacks. The chip-type→name mapping is centralised in `sid_type_index` + `sid_code_to_slot`, shared by the debug page (`sidname_long_*`) and the Q page (`sidname_short_*`).

## SidVariant proxy (headless testing in WinVICE)

The repo ships a fork of VICE 3.9 (at `../vice-sidvariant/`) with a
`-sidvariant <name>` flag that makes any emulated SID slot wear a
chip-family personality — ARMSID, ARM2SID, SwinSID U/Nano, FPGASID,
PDsid, KungFuSID, BackSID, SIDKick-pico, SIDFX, uSID64. The personality
only intercepts the chip's detection magic-cookie protocol; ResID still
synthesises audio.

This lets CI exercise every chip family without hardware:
- `make run-<variant>` / `make stereo-<variant>` — one-shot interactive launch.
- `make test-variants` — 30-case headless sweep, pass/fail per variant.
- `make ci-full` — unit tests + variant golden diff; pre-PR gate.
- `tests/variant_goldens/*.txt` — reference screen dumps per variant.
- `patches/vice-sidvariant-v1.patch` — the source diff against pristine VICE 3.9.

Full plan in `docs/ARMSID_PROXY_PLAN.md`; build recipe in
`docs/VICE_PROXY_BUILD.md`; catalogue of variants + make targets in
`docs/VICE_PROXY_USAGE.md`.

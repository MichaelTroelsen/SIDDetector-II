# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SID Detector is a Commodore 64 diagnostic utility written in 6502 assembly that identifies 24+ variants of SID (Sound Interface Device) chips and emulators. Reference release: https://csdb.dk/release/?id=176909

## Build

```bash
make             # assemble siddetector.asm → siddetector.prg using KickAssembler
make run         # launch detector in the patched WinVICE 3.9
make run-armsid  # launch with ARMSID personality at D400  (see Makefile for full list)
make ci          # unit tests (43 cases) + MEMORYMAP.md drift check
make ci-full     # unit tests + golden-diff sweep across all 14 variants
make clean       # remove siddetector.prg
```

**Tools:**
- **KickAssembler** (`C:/debugger/kickasm/KickAss.jar`, requires Java).
- **Patched WinVICE 3.9** with the `-sidvariant` personality layer at `C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe`. Source, build recipe and usage: `docs/VICE_PROXY_BUILD.md`, `docs/VICE_PROXY_USAGE.md`, `docs/ARMSID_PROXY_PLAN.md`. **All VICE-based tests must use this binary** — the stock VICE doesn't know `-sidvariant`.
- Paths are set at the top of the `Makefile`.

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
- `make test-variants` — 14-case headless sweep, pass/fail per variant.
- `make ci-full` — unit tests + variant golden diff; pre-PR gate.
- `tests/variant_goldens/*.txt` — reference screen dumps per variant.
- `patches/vice-sidvariant-v1.patch` — the source diff against pristine VICE 3.9.

Full plan in `docs/ARMSID_PROXY_PLAN.md`; build recipe in
`docs/VICE_PROXY_BUILD.md`; catalogue of variants + make targets in
`docs/VICE_PROXY_USAGE.md`.

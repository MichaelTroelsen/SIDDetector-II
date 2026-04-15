# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SID Detector is a Commodore 64 diagnostic utility written in 6502 assembly that identifies 24+ variants of SID (Sound Interface Device) chips and emulators. Reference release: https://csdb.dk/release/?id=176909

## Build

```bash
make          # assemble siddetector.asm → siddetector.prg using KickAssembler
make run      # build and launch in WinVICE (x64sc)
make clean    # remove siddetector.prg
```

**Tools:** KickAssembler (`C:/debugger/kickasm/KickAss.jar`, requires Java) and WinVICE (`C:/winvice/bin/x64sc.exe`). Paths are set at the top of the `Makefile`.

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

Emulator detection (VICE ResID/FastSID, HOXS64, Frodo, YACE64, EMU64) runs as a fallback when no hardware SID is identified.

### Key Techniques

- **`calcandloop` / `ArithMean`** — Measures the $D418 (volume) register decay characteristic over multiple samples; the decay rate distinguishes chip types
- **Self-modifying code** — SID register addresses (e.g., `cas_d418`, `cas_d41D`–`cas_d41F`) are patched at runtime to handle D400/D500 mirroring in FPGA implementations
- **`checkpalntsc`** — PAL vs NTSC detection affects timing loops throughout
- **`check128`** — Detects C64 vs C128 to adjust behavior

### Memory Layout

| Address | Contents |
|---------|----------|
| `$0801` | BASIC stub + main code |
| `$1D00` | Detection result tables: `num_sids`, `sid_list_l/h/t`, `sid_map` |

Zero-page `$A2–$AF` and `$F6–$FF` hold working variables and detection state.

### Detected SID Types

Real chips (6581 R2/R3/R4/R4AR, 8580), FPGASID, ARMSID, Swinsid Nano, Swinsid Ultimate, uSID64, ULTISID (U64), SIDFX, and emulators: VICE ResID, VICE FastSID, HOXS64, Frodo, YACE64, EMU64, plus UNKNOWNSID and No Sound fallbacks.

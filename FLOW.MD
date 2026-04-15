# SID Detector — Detection Flow Architecture

## Overview

The program is a single-pass detection chain executed at startup. Each step probes the SID
hardware in a specific way and, if the chip is identified, jumps to `end` (skipping the remaining
steps). If no hardware SID is found, the program falls through to the emulator-identification
stage (`calcandloop`).

---

## 1. Entry and Initialization (`start`, `$2400`)

```
SYS 9216  →  start ($2400)
             │
             ├─ Silence SID  (D418=0, D404/D40B/D411 gate-off)
             ├─ Switch to uppercase charset  (D018=$15)
             ├─ Zero sid_list tables  (8 slots × 3 arrays at $1D00)
             ├─ jsr printscreen          — draw static 40×25 UI to $0400
             ├─ jsr checkpalntsc         — NMI vector patch + raster check
             │     → $02A6 = 1 (PAL) or 0 (NTSC)
             └─ jsr check128             — probe $D030 / $D0FE
                   → za7 ($A7) = $FF (C64) | $FC (C128) | other (TC64)
```

Both results are printed to screen before the detection chain begins.
All subsequent timing loops use the PAL/NTSC flag.

---

## 2. Detection Chain (sequential, first match wins)

Each detector writes its result code into **`data1` ($A4)** and returns.
The calling code checks `data1`; a match jumps to `end`, a miss falls through to the next step.

```
┌──────────────────────────────────────────────────────────────────────┐
│  ibegin:  spin on raster $FF, busy-wait ~1300 µs for SIDFX init     │
└──────────────────────────────────────────────────────────────────────┘
         │
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 1 — DETECTSIDFX                                             ║
║  Method:  SCI serial handshake via D41E/D41F pins                 ║
║  Write:   $80 $50 $4E $50 ("PNP" sequence)                        ║
║  Read:    4 vendor/product ID bytes                               ║
║  Match:   bytes == $45 $4C $12 $58                                ║
║  Result:  data1 = $30 (SIDFX found) | $31 (not found)            ║
║  data4:   $30 saved here so stereo scan knows SIDFX is present    ║
╚════════════════════════════════════════════════════════════════════╝
         │ $30? ──► print "SIDFX" on row 12 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 2 — Checkarmsid  (+ armsid_get_version)                    ║
║  Method:  Write "DIS" (PETSCII $44,$49,$53) to D41F/D41E/D41D    ║
║           Self-modifying code patches SID base address at runtime ║
║           (avoids bus-behaviour corruption)                       ║
║  Wait:    2× loop1sek delay (~2 s) for ARMSID echo to settle     ║
║  Read:    D41B (OSC3 read-back register)                          ║
║  Match:   'S' ($53) → Swinsid Ultimate  data1=$04                ║
║           'N' ($4E) → ARMSID family     data1=$05                ║
║  Sub-check (ARMSID only):                                         ║
║    jsr armsid_get_version → armsid_major/minor                   ║
║    major=$03 → ARM2SID   (print "ARM2SID Vx.xx")                 ║
║    major≠$03 → ARMSID    (print "ARMSID  Vx.xx")                 ║
╚════════════════════════════════════════════════════════════════════╝
         │ $04? ──► print "SWINSID ULTIMATE" on row 3 ──► jmp end
         │ $05? ──► print "ARMSID/ARM2SID"   on row 2 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 3 — checkpdsid                                             ║
║  Method:  Write 'P'=$50 → D41D,  'D'=$44 → D41E                 ║
║  Read:    D41E                                                    ║
║  Match:   reads 'S'=$53 → PDsid confirmed                        ║
║  Result:  data1 = $09 (found) | $F0 (not found)                  ║
╚════════════════════════════════════════════════════════════════════╝
         │ $09? ──► print "PD SID" on row 10 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 3b — checkbacksid                                           ║
║  Method:  Write D41B=$02, D41C=$01, D41D=$B5, D41E=$1D           ║
║           Poll D41F up to 15× (every ~42 ms, re-writing D41B)    ║
║  Match:   D41F response matches BackSID handshake                 ║
║  Result:  data1 = $0A (found) | $F0 (not found)                  ║
╚════════════════════════════════════════════════════════════════════╝
         │ $0A? ──► print "BACKSID" on row 8 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 3c — checkskpico  (SIDKick-pico)                           ║
║  Method:  Write $FF → D41F (enter config mode)                   ║
║           Write $E0 → D41E (VERSION_STR pointer)                 ║
║  Read:    D41D byte[0] and byte[1]                               ║
║  Match:   byte[0]='S'/$53, byte[1]='K'/$4B                       ║
║  Result:  data1 = $0B (found) | $F0 (not found)                  ║
╚════════════════════════════════════════════════════════════════════╝
         │ $0B? ──► print "SIDKICK-PICO" on row 7 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 4 — checkfpgasid                                            ║
║  Method:  Write magic cookie $81 → D419,  $65 → D41A             ║
║           Set bit 7 of D41E (identify mode)                      ║
║  Read:    D419 (expect $1D), D41A (expect $F5) → magic $F51D     ║
║           D41F: $3F → 8580 mode,  $00 → 6581 mode               ║
║  Result:  data1 = $06 (FPGA 8580) | $07 (FPGA 6581) | $F0       ║
║  Cleanup: write $00 → D419/D41A to exit config mode              ║
╚════════════════════════════════════════════════════════════════════╝
         │ $06? ──► print "FPGASID 8580" on row 4 ──► jmp end
         │ $07? ──► print "FPGASID 6581" on row 4 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 5 — checkrealsid                                            ║
║  Method:  Sawtooth waveform fingerprint on voice 3               ║
║    1. Write $48 → D412/D40F  (gate + sawtooth setup)             ║
║    2. Right-shift → activate sawtooth                            ║
║    3. Read D41B (OSC3) four times, checking expected sequences:  ║
║         read1 AND $FE must be $00                                ║
║         read2 must be $03  (all real SIDs)                       ║
║         read3 must be < $07                                      ║
║         read4 == $08 → 6581,  read4 < $08 → 8580                ║
║  Result:  data1 = $01 (6581) | $02 (8580) | $F0                  ║
║  Cleanup: write $00 → D412/D40F, read D41B to clear state        ║
╚════════════════════════════════════════════════════════════════════╝
         │ $01? ──► print "6581 SID" on row 5 ──► jmp end
         │ $02? ──► print "8580 SID" on row 6 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 6 — checksecondsid  (noise mirror trick)                   ║
║  Method:  Enable noise waveform on voice 3 at D400               ║
║           Walk $D400..$DFxx in $20 steps                         ║
║           A real SID at an offset generates non-zero D41B reads  ║
║           A mirror of the primary always reads $00               ║
║  Result:  data1 = $10 (independent second SID slot found)        ║
╚════════════════════════════════════════════════════════════════════╝
         │ $10? ──► print "UNKNOWN SID" on row 11 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 7 — checkkungfusid                                          ║
║  Method:  Write $A5 → D41D, read D41D back                       ║
║  Match:   D41D == $A5 (old FW echo) OR $5A (FW_UPDATE_START_ACK) ║
║  Result:  A = $0C (found) | $F0 (not found)                      ║
╚════════════════════════════════════════════════════════════════════╝
         │ $0C? ──► print "KUNGFUSID" on row 9 ──► jmp end
         │ else fall-through
         ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 8 — checkswinsidnano  (last-resort hardware check)          ║
║  Method:  Enable noise waveform on voice 3                       ║
║           Read D41B; Swinsid Nano returns non-zero                ║
║           An empty/open-bus socket always reads $00              ║
║  Result:  data1 = $08 (found) | $F0 (not found)                  ║
╚════════════════════════════════════════════════════════════════════╝
         │ $08? ──► print "SWINSID NANO" on row 3 ──► jmp end
         │ else fall-through
         ▼
        nosound: print "NO SID FOUND" on row 11  ──► fall through to end
```

---

## 3. Post-Detection: Multi-SID Stereo Scan (`end`)

After the primary chip is identified, the program scans **all** SID address slots
($D400–$DFxx in $20 steps) looking for additional chips in a stereo configuration.

```
end:
 ├─ Save data1 → data4  (primary chip type; keep if $F0 = unknown)
 ├─ Pre-populate sid_list[1] = D400 for detected chip type
 │
 ├─ sidstereostart (BackSID family,     sidtype=$0A)
 │     Skips D4xx mirrors; BackSID only at D400, pre-populated, skip scan
 │
 ├─ sidstereostart (ARMSID/SwinsidU,    sidtype=$05)
 │     Scans D5xx–D7xx only (D4xx = primary mirror, DE/DF = false-positive risk)
 │     Mirror test: write $AA→D41D, $55→scan_addr:D41D; if D41D changed → mirror
 │     For each independent slot: jsr Checkarmsid, record in sid_list
 │
 ├─ sidstereostart (FPGASID family,     sidtype=$06)
 │     (scan skipped — FPGA mirrors across all D4xx-D7xx; stereo not supported)
 │
 ├─ sidstereostart (PDsid family,       sidtype=$09)
 │     Calls checkpdsid at each slot
 │
 ├─ sidstereostart (SIDKick-pico,       sidtype=$0B)
 │     Mirrors D4xx-D7xx; pre-populated, scan skipped
 │
 ├─ fiktivloop_d400                    (real SID family)
 │     Sets up D400 as scan base → fiktivloop
 │     Skips D400 (primary) and D420-D7xx mirrors
 │     Finds real independent second SIDs (DE00/DF00, stereo cartridges)
 │
 └─ If sidnum_zp==0: record D400 as unknown ($F0) so display is not blank
```

Results are stored in:

| Table         | Address  | Contents                           |
|---------------|----------|------------------------------------|
| `num_sids`    | `$1D00`  | Count of SIDs found (0–7)          |
| `sid_list_h`  | `$1D01+` | High byte of SID address ($D4/$D5…)|
| `sid_list_l`  | `$1D09+` | Low byte of SID address ($00/$20…) |
| `sid_list_t`  | `$1D11+` | Chip type code for each slot       |

---

## 4. Emulator Identification via D418 Decay (`calcandloop`)

When no hardware SID is found at the register-echo level, `checkrealsid` still returns
`$F0`. The program then runs a timing fingerprint to distinguish software emulators.

```
calcandloop:
 │
 ├─ 6 iterations of calc_start:
 │     sei                     (interrupts off — precise timing required)
 │     Write $1F → D418        (master volume = 31)
 │     Loop: INC $07E8/$07E9/$07EA  (24-bit cycle counter)
 │           Read D418; loop while ≠ 0
 │     Record 3-byte count in ArrayPtr1/2/3[iteration]
 │     cli                     (interrupts re-enabled between samples)
 │
 ├─ ArithmeticMean over ArrayPtr1/2/3 → averaged data1/data2/data3
 │
 └─ checktypeandprint: compare data1/data2/data3 against lookup table
```

### Emulator Fingerprint Table

| data3 | data2 range | data1 range | Identified as              |
|-------|-------------|-------------|----------------------------|
| $02   | any         | any         | Unknown / unclassified     |
| $00   | $00         | $01–$02     | Swinsid Nano               |
| $00   | $00         | $DA–$F1     | ULTIsid (Ultimate 64)      |
| $00   | $19         | $00         | HOXS64                     |
| $00   | $07         | $00         | VICE ResID-FP 6581         |
| $00   | $00         | $05         | VICE FastSID 6581          |
| $00   | $03         | $00         | VICE ResID 6581            |
| $00   | $16–$18     | $00         | Swinsid Ultimate           |
| $00   | $05–$06     | $00         | FPGASID                    |
| $00   | $98         | $00         | VICE ResID 8580            |
| $00   | $01         | $00         | VICE ResID 6581 (alt)      |
| any   | $00–$04     | any         | VICE FastSID               |
| —     | —           | —           | Unknown SID / No SID       |

---

## 5. IRQ Loop and Keyboard Handler

After printing results, a raster IRQ is installed and the program enters its interactive loop.

```
readkey2:
 ├─ Reset SP = $FF  (calcandloop used TXS/TSX; SP may be ~6)
 ├─ Install IRQ vector at $0314/$0315 → our handler
 ├─ Set VIC raster IRQ at line 0
 ├─ Disable CIA1 timers (VIC raster only)
 └─ cli  (interrupts enabled)

IRQ handler (every frame ~50/60 Hz):
 ├─ COLWASH colour animation (if colwash_flag=1)
 └─ SID music player call at $1806 (if sid_music_flag=1)

kbdloop (direct CIA1 matrix scan):
 ├─ SPACE  → jmp start  (full re-detection)
 ├─ Q      → RTS / quit
 ├─ I      → info sub-screen for detected chip
 ├─ D      → debug page (register dump)
 ├─ R      → readme/help page
 ├─ T      → sound test page
 └─ P      → toggle SID music (Triangle Intro, $1800)
```

---

## 6. Data Flow Summary

```
                     ┌─────────────────────────────┐
                     │        data1 ($A4)           │
                     │   Primary detection result   │
                     │  $01=6581  $02=8580          │
                     │  $04=SwinsidU  $05=ARMSID    │
                     │  $06=FPGA8580  $07=FPGA6581  │
                     │  $08=SwinNano  $09=PDsid     │
                     │  $0A=BackSID   $0B=SKpico    │
                     │  $0C=KungFu   $10=2nd SID    │
                     │  $30=SIDFX    $F0=unknown    │
                     └──────────────┬──────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            ▼                       ▼                       ▼
     data4 ($1D00 area)      sid_list tables          data2/data3 ($A5/$A6)
     Chip type saved          ($1D00–$1D1F)           Decay sub-bytes for
     for info page            Stereo scan              emulator discrimination
     and colour coding        results                 (ArithmeticMean output)
```

---

## 7. Memory Map

| Range          | Contents                                          |
|----------------|---------------------------------------------------|
| `$0801–$080C`  | BASIC stub: `SYS 9216`                            |
| `$080D–$17FF`  | (gap — unused; may contain BASIC variables)       |
| `$1800–$2387`  | Triangle Intro SID music module (embedded binary) |
| `$2400–$xxxx`  | Main program code and all subroutines             |
| `$1D00`        | `num_sids` — count of detected SIDs               |
| `$1D01–$1D08`  | `sid_list_h` — SID page high bytes                |
| `$1D09–$1D10`  | `sid_list_l` — SID page low bytes                 |
| `$1D11–$1D18`  | `sid_list_t` — chip type codes                    |
| `$A2–$B1`      | Zero-page: detection scratch registers            |
| `$F6–$FF`      | Zero-page: scan state (counters, pointers)        |
| `$07E8–$07EA`  | Off-screen RAM: 24-bit cycle counter for decay    |
| `$D400`        | Primary SID register page                        |

---

## 8. Key Design Patterns

**Self-modifying code** — `Checkarmsid`, `checkfpgasid`, `checkrealsid` all patch their own
`STA`/`LDA` absolute address bytes at runtime so the same routine works on any SID page
($D400, $D500, …) passed in via `sptr_zp:sptr_zp+1`.

**Register-echo protocol** — ARMSID, ARM2SID, PDsid, SIDKick-pico, and BackSID all implement
firmware-defined handshakes: the detector writes a known sequence to write-only SID registers
and reads back a response from normally-readable registers (D41B–D41F).

**Timing sensitivity** — ARMSID detection requires two ~1 s waits. SIDFX requires a ~1300 µs
post-power-on delay. The D418 decay measurement runs with interrupts disabled (`SEI`) to
eliminate jitter. All timing loops scale with the PAL/NTSC flag.

**Mirror detection** — The stereo scan uses a write-$AA/$55-and-compare trick to distinguish
an independent second chip from a mirror of the primary SID, preventing false positives.

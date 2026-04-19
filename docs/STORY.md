# Identifying Every SID Chip in Existence — Inside SID Detector

*A technical deep-dive for C64 sceners, SID musicians, and hardware developers*
*By funfun/Triangle 3532 · Version V1.3.70 · April 2026*

---

## Executive Summary

The SID chip — the Sound Interface Device in every Commodore 64 — no longer exists as a single thing. Today a musician or scener might be running their tunes on a 1984 MOS 6581 R4, an ARM Cortex-M4 clone from the Czech Republic, an FPGA recreation from Germany, a RP2040-based replacement, or a chip embedded inside an Ultimate 64 board. Software that adapts to the chip it runs on — different filter curves, different volume routines, different digi-playback tricks — needs to know what it is talking to.

**SID Detector** is a Commodore 64 tool that identifies 24+ SID variants from 6502 assembly at runtime. This document is the engineering story behind it: how each chip exposes (or hides) its identity, what machine-code techniques pull that identity out, how the detection chain was built and refined, and what we learned testing against real hardware.

The short version of the lessons:
- Modern SID replacements communicate their identity through undocumented register echo behaviour — the same voice-3 address space that real chips use for oscillator and envelope output
- Open-bus (empty socket, NOSID) is not quiet; it generates misleading noise that looks like oscillator activity
- Temporal profiling — measuring how activity *changes over time* rather than whether it exists — is the most robust discriminant
- Self-modifying code is not a dirty trick on the 6502; it is the standard solution for parameterising absolute addressing across multiple SID slot addresses at runtime
- Hardware-in-the-loop testing with a real C64, automated keypress injection, and symbol-resolved memory reads is the only way to be confident a probe works

---

## Table of Contents

1. [The Problem: A Fragmented SID Ecosystem](#1-the-problem)
2. [The SID Address Map — What We Have to Work With](#2-the-sid-address-map)
3. [Detection Taxonomy — Six Ways a Chip Reveals Itself](#3-detection-taxonomy)
4. [Real SID: OSC3 Readback and Sub-Revision Fingerprinting](#4-real-sid)
5. [D418 Volume Decay — Emulator Fingerprinting](#5-d418-decay)
6. [DIS Echo Protocol — ARMSID, ARM2SID, SwinSID Ultimate](#6-dis-echo)
7. [FPGASID: Magic Cookie Config Mode](#7-fpgasid)
8. [uSID64: Two-Read Stability Test](#8-usid64)
9. [BackSID: Reverse-Engineered Unlock-and-Poll Protocol](#9-backsid)
10. [SIDKick Pico: Config Mode with Manual String Pointer](#10-sidkick-pico)
11. [KungFuSID: ACK-Based Identification](#11-kungfusid)
12. [SwinSID Nano: The Oscillator Speed Test and the NOSID Trap](#12-swinsid-nano)
13. [SIDFX: SCI Serial Handshake and Secondary Chip Probing](#13-sidfx)
14. [PD SID and uSID64: Simpler Echo Tests](#14-pdsid-and-usid64)
15. [Stereo SID Detection: Scanning Secondary Slots](#15-stereo)
16. [Self-Modifying Code — The Right Tool for Multi-Slot Probing](#16-self-modifying-code)
17. [The NOSID Problem — When Empty is Louder than Expected](#17-nosid)
18. [Hardware Testing Methodology](#18-hardware-testing)
19. [SIDFX Secondary Probing — New Territory (V1.3.x)](#19-sidfx-secondary)
20. [Detection Chain Order — Why Sequence Matters](#20-detection-order)
21. [Results Summary](#21-results)
22. [Known Limitations](#22-limitations)
23. [FM Expansion Detection — CBM SFX Sound Expander & FM-YAM (V1.4.x)](#23-fm-expansion-detection--cbm-sfx-sound-expander--fm-yam-v14x)

---

## 1. The Problem

The SID chip (MOS 6581, later 8580) was the heart of the C64's audio system from 1982 until Commodore stopped manufacturing. Once the original chips ran out, the scene faced a problem: ageing silicon is failing, prices are climbing, and nobody is making new ones. Since around 2012, a small industry of replacement chips has grown up — FPGA implementations, ARM Cortex-M microcontroller emulations, AVR-based clones, and even the Ultimate 64 board which bakes SID emulation directly into its FPGA fabric.

Each replacement has slightly different audio characteristics. Some emulate the 6581 filter's nonlinearity. Some add digital audio playback tricks. Some support both 6581 and 8580 modes automatically. And critically: some behave differently for certain demo and game techniques that rely on specific undocumented hardware behaviour.

**SID-aware software benefits from knowing what it's running on.** A player that works around the 8580's different filter cutoﬀ characteristics should behave differently on an FPGASID in 6581 mode. A digi-player that uses volume register tricks needs to know whether D418 behaves as a real chip, an ARM emulator, or an emulator with a non-zero cycle-accurate delay. A test suite needs to verify its timing assumptions against real hardware before declaring a tune correct.

SID Detector solves this by running a sequence of hardware probes that identify, from within running C64 6502 code, which chip (or emulator) is installed — including chip sub-revision (6581 R2, R3, R4, R4AR), stereo configurations, and what kind of chip is inside hardware cartridges like SIDFX.

---

## 2. The SID Address Map — What We Have to Work With

The SID occupies 32 bytes from `$D400` to `$D41F` in the C64 memory map. Twenty-five of those bytes are write-only registers (voices, envelope, filters, volume). The remaining five are read-only outputs from the hardware:

| Address | Name | Read content |
|---------|------|-------------|
| `$D419` | POT X | Paddle/mouse X axis (8-bit) |
| `$D41A` | POT Y | Paddle/mouse Y axis (8-bit) |
| `$D41B` | OSC3 | Voice 3 oscillator MSB (8 bits of 23-bit accumulator) |
| `$D41C` | ENV3 | Voice 3 envelope value (8-bit) |
| `$D41D`–`$D41F` | (unofficial) | Normally write-only; used as echo registers by clone chips |

The five addresses `$D41B`–`$D41F` are the most important for detection. On a real SID:

- `$D41B` and `$D41C` return live hardware state from the voice-3 oscillator and envelope generator
- `$D41D`, `$D41E`, `$D41F` are write-only; reads return the last data seen on the bus (open-collector bus float)

On modern replacements, the situation is different. Because the clone chips are microcontrollers or FPGAs running in software, they typically store every SID write into a register array in RAM. Reads from addresses that are nominally write-only on real hardware come back from that RAM. This is not intentional documentation — it is an artefact of how ARM and AVR microcontrollers implement memory-mapped I/O. **Most clone chips inadvertently expose their identity through D41B–D41F echo behaviour that real chips do not produce.**

The detection chain exploits this systematically.

---

## 3. Detection Taxonomy — Six Ways a Chip Reveals Itself

Before diving into specific chips, here is the taxonomy of techniques used:

### 3.1 Oscillator Output Readback
Read `$D41B` (OSC3) and/or `$D41C` (ENV3) after setting voice-3 to a known waveform and frequency. Real SIDs produce predictable values; emulators and empty sockets produce either wrong values or nothing at all.

### 3.2 Volume Register Decay (D418 Fingerprinting)
Set `$D418` (master volume) to `$1F` and time how long it takes to decay to zero. Different emulator cores have different decay rates because their internal cycle-counting implementations differ. Real hardware decays with the analogue filter; emulators decay with integer math.

### 3.3 Echo-Based Identification
Write a known sequence to `$D41D`–`$D41F` (nominally write-only), then read back from `$D41B`–`$D41D`. Clone chips whose microcontroller implementations store writes in a RAM array echo the written values back. The specific echo pattern distinguishes the chip family. This is the most widely applicable technique.

### 3.4 Magic Cookie Config Mode
Write a specific multi-byte "unlock sequence" to SID registers. The chip responds by entering a documentation mode where readable registers expose identification data. Used by FPGASID (`$81/$65` cookie to `D419/D41A`) and SIDKick Pico (`$FF` to `D41F`).

### 3.5 SCI Protocol Communication
The SIDFX cartridge implements a full serial state machine over the `D41E/D41F` pins. A PNP (Plug-and-Play) login packet is exchanged; the chip responds with a vendor/product ID. This is the most elaborate protocol in the codebase.

### 3.6 Temporal Profiling
Rather than asking "does this value match?", ask "is the change rate increasing or decreasing over time?" Useful for discriminating the SwinSID Nano's continuously-running AVR oscillator from an empty SID socket where bus noise decays toward silence.

---

## 4. Real SID: OSC3 Readback and Sub-Revision Fingerprinting

The original MOS 6581 and CSG/MOS 8580 are identified using voice 3's hardware oscillator output.

**What makes this work:** The SID's three oscillators are free-running hardware circuits. When you enable voice 3 with a sawtooth waveform and read D41B, you get the upper 8 bits of the 23-bit phase accumulator. The value depends on the oscillator's frequency, the gate bit state, and timing. Clone chips that emulate this in software often produce slightly different values, and certain emulators do not implement it at all.

**The test (`checkrealsid`):**

```asm
// 1. Arm voice 3 with gate bit set
lda #$48
crs_d412:  sta $D412           // voice 3 control: gate=1, waveform=sawtooth
crs_d40f:  sta $D40F           // voice 3 freq lo = $48

// 2. Shift right to activate sawtooth waveform (gate still set)
lsr
crs_d412_1: sta $D412          // now $24: sawtooth with gate bit set

// 3. First OSC3 read
crs_d41b: lda $D41B            // read oscillator output
tax
and #$FE
bne unknownSid                 // non-zero non-one → not real SID

// 4. Second read confirms we have a real SID (not a bus float)
crs_d41b_1: lda $D41B
cmp #$03                       // real chips return $03 here
```

The `and #$FE; bne unknownSid` gate is critical: it accepts only values `$00` or `$01`. An empty socket returns bus float (typically `$D4` — the high byte of the `lda $D41B` opcode bytes remaining on the data bus), which fails this check. An ARM emulator that hasn't set up its sawtooth correctly may return a value outside this range.

**Sub-revision identification:** After confirming a real SID, the detector compares the D41B readback sequence against lookup tables `MODE6581` and `MODE8580`. The filter circuit in 6581 revisions was manufactured with varying resistor tolerances, causing each revision to have a slightly different characteristic. The lookup table maps the readback value to one of: 6581 R2, R3, R4, R4AR, or 8580.

This technique was originally published by Gideon Zweijtzer in the 1541 Ultimate detection code and forms the foundation that all other detection steps are built around.

---

## 5. D418 Volume Decay — Emulator Fingerprinting

When no hardware chip is identified (no real SID, no clone), the detector falls back to emulator fingerprinting via the volume register.

**The principle:** Write `$1F` to `$D418` (volume register, master volume). In a hardware SID, this register affects the analogue output stage and does not produce a readable echo. In an emulator, the register is implemented as a software variable. Some emulators update D418 on every cycle (cycle-accurate), others on every sample (batch processing), and others round the decay timer differently. The time it takes for D418 to read back as `$00` — or more accurately, for a decay timer in the emulator to count down — differs between implementations.

**The measurement (`calcandloop`):**

```asm
// Set up voice 1 as a timing reference: gate-on sawtooth
// Sample D418 decay 6 times (NumberInts = $06)
// Average with ArithmeticMean (16-bit accumulator)
// Compare against MODE6581/MODE8580/MODEUNKN tables
```

Six samples are taken and averaged to reduce noise. The averaged decay count is compared against a table of known values:

| Emulator | Approximate decay count |
|----------|------------------------|
| VICE ResID 6581 | specific value A |
| VICE ResID 8580 | specific value B |
| VICE FastSID | specific value C |
| HOXS64 | specific value D |
| Frodo | specific value E |
| YACE64 | specific value F |
| EMU64 | specific value G |

Each emulator's SID core makes slightly different choices about how to model the analogue circuit. Those choices produce measurably different decay rates that are stable across runs of the same emulator version.

This technique identifies emulators only — real hardware chips and all the modern replacements are identified before this step is reached.

---

## 6. DIS Echo Protocol — ARMSID, ARM2SID, SwinSID Ultimate

The most important technique for identifying modern replacements is the DIS echo test. It exploits a property that is common to most ARM- and AVR-based SID replacements.

**The background:** Microcontroller-based SID clones store every write to a SID register into a RAM array. When the C64 code reads from a nominally write-only address (D41D–D41F), the microcontroller returns the last value stored in that RAM array slot — the value that was most recently written to that address. Real SID chips do not do this; the D41D–D41F addresses on a real SID have no readback path.

**The sequence:** Write the ASCII string `"DIS"` to voice-3 registers in reverse order (because `D41D` through `D41F` are the three bytes):

```asm
// Write 'D'=$44 to D41F, 'I'=$49 to D41E, 'S'=$53 to D41D
cas_d418: lda #$00             // zero D418 first (important: not $D400+offset,
          sta $D418            // avoid bus conflicts on ARMSID's self-read)
          lda #$44             // 'D'
cas_d41f: sta $D41F
          lda #$49             // 'I'
cas_d41e: sta $D41E
          lda #$53             // 'S'
cas_d41d: sta $D41D
          jsr loop1sek         // ~1.8ms wait
          jsr loop1sek

// Read back — the key register is D41B
cas_d41B: lda $D41B            // 'S'=$53 → SwinSID Ultimate; 'N'=$4E → ARMSID family
```

Wait — we wrote `"DIS"` but read back from `$D41B`, not `$D41D`. Why?

This is the key insight. ARMSID and SwinSID Ultimate don't just echo the last write to each address — they *rotate* or *shift* the written bytes through internal registers. The `"DIS"` sequence, after propagating through the ARMSID firmware, appears shifted one register position downward: the `'S'` (written to D41D) shows up at D41B. `'I'` (D41E) shows up at D41C. `'D'` (D41F) shows up at D41D. The specific echo position is a firmware implementation detail of each chip.

**Discrimination between ARMSID and SwinSID Ultimate:**

| D41B readback | Chip |
|--------------|------|
| `'S'` = `$53` | SwinSID Ultimate |
| `'N'` = `$4E` | ARMSID or ARM2SID |

**Discrimination between ARMSID and ARM2SID:**

```asm
cas_d41C: lda $D41C            // 'O'=$4F for both
cas_d41d7: lda $D41D           // 'R'=$53 → ARM2SID; other → ARMSID
...
ldx data3
cpx #$53                       // 'R'
bne armsidlo                   // plain ARMSID
// ARM2SID confirmed
```

ARM2SID is the stereo successor to ARMSID. It puts `'R'` (the fourth letter of "DSISR" — the reverse-shifted sequence) at D41D. ARMSID puts something else there. This single-byte check is all that separates the two.

**ARM2SID also exposes its configuration map.** Via the "dis" config-mode entry sequence (lowercase `d`, `i`, `s` to D41F, D41E, D41D), the chip returns a nibble-packed map of all eight possible SID slot addresses:

```
armsid_map_l  [3:0] = Slot 0 (D400), [7:4] = Slot 1 (D420)
armsid_map_l2 [3:0] = Slot 2 (D500), [7:4] = Slot 3 (D520)
armsid_map_h  [3:0] = Slot 4 (DE00), [7:4] = Slot 5 (DE20)
armsid_map_h2 [3:0] = Slot 6 (DF00), [7:4] = Slot 7 (DF20)
```

Nibble values: `0` = none, `1` = left SID, `2` = right SID, `3` = SFX expander, `4` = SID3. This is used by `arm2sid_populate_sid_list` to build the stereo SID list directly without scanning, making it the most reliable stereo detection in the codebase.

**Why `loop1sek` matters:** The ARM processor in ARMSID runs at 100 MHz — approximately 100 times faster than the C64's 1 MHz 6510. But ARM firmware processes C64 bus transactions asynchronously. If the C64 reads D41B *immediately* after the write, the ARM may not have processed the `"DIS"` sequence yet. The two `loop1sek` delays (each ~1785 cycles ≈ 1.8 ms) give the ARM firmware time to propagate the write through its register array.

---

## 7. FPGASID: Magic Cookie Config Mode

FPGASID takes a more explicit approach to self-identification. It responds to a specific two-byte "magic cookie" that no real SID write sequence would produce in normal use.

**The unlock sequence:**

```asm
lda #$81
cfs_D419: sta $D419            // magic byte 1 to POT-X address
lda #$65
cfs_D41A: sta $D41A            // magic byte 2 to POT-Y address
lda #%10000000
cfs_D41E: sta $D41E            // set bit 7 → enter identify mode
```

After these three writes, FPGASID exposes its device ID in D419:D41A:

```asm
cfs_D419_1: lda $D419
cmp #$1D                       // must be $1D (device ID low byte)
bne fpgasidf_nosound
cfs_D41A_1: lda $D41A
cmp #$F5                       // must be $F5 (device ID high byte = $F51D)
bne fpgasidf_nosound
```

The 16-bit value `$F51D` is FPGASID's unique identifier. A real SID cannot produce a stable, predictable value at D419/D41A from a write-triggered config sequence — POT-X and POT-Y are sampled from hardware capacitor charge-time circuits.

**6581 vs 8580 mode determination:**

```asm
cfs_D41F: lda $D41F
cmp #$3F                       // $3F = 8580 emulation mode
bne cfs_6581
lda #$06; jmp cfs_save         // data1=$06: FPGASID 8580
cfs_6581:
lda #$07; jmp cfs_save         // data1=$07: FPGASID 6581
```

D41F returns `$3F` for 8580 mode, `$00` for 6581 mode. The detector always exits config mode by writing `$00` to D419 and D41A.

---

## 8. uSID64: Two-Read Stability Test

The uSID64 is an STM32-based SID replacement. Like other microcontroller implementations, it stores register writes in RAM. But its detection is more nuanced because the identifying register (D41F) is also the address that a floating NOSID bus can produce misleading values on.

**The protocol:** Write the config unlock sequence `$F0 $10 $63 $00 $FF` to D41F (five successive writes to the same address). A uSID64 stores these and responds by holding a stable value in D41F that lies in the range `$E0`–`$FC`.

```asm
// Write unlock sequence
lda #$F0; sta $D41F
lda #$10; sta $D41F
lda #$63; sta $D41F
lda #$00; sta $D41F
lda #$FF; sta $D41F

// Read twice with a ~3ms gap
jsr rp_delay                   // ~3ms
lda $D41F                      // first read
// ... store first read ...
jsr rp_delay
lda $D41F                      // second read

// Acceptance criteria:
// Both in $E0-$FC range
// |read2 - read1| <= $02
```

**Why two reads?** An empty SID socket (NOSID) also exhibits a D41F value that drifts into the `$E0`–`$FE` range — because the last write was `$FF`, and the floating bus decays toward that value. But a decaying bus is not stable: two reads a few milliseconds apart will differ by more than `$02`. A real uSID64 holds its register value steady (it is being driven by an active microcontroller). The two-read stability check discriminates between "bus decaying towards `$FF`" and "chip holding a config register value".

---

## 9. BackSID: Reverse-Engineered Unlock-and-Poll Protocol

BackSID is manufactured by BackBit and presents the greatest detection challenge of any chip in the codebase: **there is no published identification interface.** The chip is intentionally designed to be transparent — it looks exactly like a real 6581 or 8580 to software. BackBit's official firmware utility `backsid.prg` does have a detection routine, but it is provided as a binary without documentation.

**Reverse engineering from the binary:** The `backsid.prg` binary was disassembled. The detection subroutine at `$0B17` revealed the following protocol:

```
$0B17: STX $D41B       ; write $02 to D41B (slot identifier)
$0B1A: STA $D41C       ; write test value to D41C
$0B1F: LDA #$B5 : STA $D41D   ; unlock key 1
$0B24: LDA #$1D : STA $D41E   ; unlock key 2
; poll loop:
$0B07: STX $D41B       ; re-arm echo request
$0B0A: LDA $A2 : ADC #$02     ; wait 2 jiffies (~40ms)
$0B13: LDA $D41F       ; read echo
; if $D41F == test_value: BackSID confirmed
; loop for up to ~2.4 seconds (121 jiffies)
```

**The unlock sequence:**
1. Write `$02` to D41B (this is the "slot identifier" — `$02` means "primary SID slot")
2. Write a test value (`$01` in our implementation) to D41C
3. Write `$B5` to D41D (unlock key 1)
4. Write `$1D` to D41E (unlock key 2)
5. Re-arm by writing `$02` to D41B on every poll
6. Read D41F — if it echoes back the test value from D41C, BackSID is present

**Why polling?** BackSID's ARM processor needs time to process the unlock sequence and arm the echo — possibly from a few milliseconds to over a second depending on startup state. BackBit's original code polls for up to 2.4 seconds. Our implementation polls 15 times at ~42ms intervals (~630ms total), which is sufficient because the C64 program's ~200ms startup code already elapses before the detection step is reached.

**Re-arm on every poll is mandatory.** Each write of `$02` to D41B re-arms the echo request for that poll cycle. Omitting it causes the echo to never appear.

**Pre-check:** Before the unlock sequence, D41F is read. If it already reads `$01` before any writes, it is a bus-float artefact (the NOSID bus can float to `$01` from previous register activity), not a real BackSID echo. The pre-check exits early in this case.

**Our `checkbacksid` implementation:**

```asm
checkbacksid:
    stx x_zp                    // save caller X (poll loop uses X as counter)
    sty y_zp
    pha
    // Self-modify D41C..D41F addresses for multi-slot scanning
    lda sptr_zp+1
    sta cbs_d41C+2              // hi byte of all absolute address operands
    sta cbs_d41D+2
    sta cbs_d41E+2
    sta cbs_d41F+2
    sta cbs_pre+2
    lda sptr_zp
    clc; adc #$1C
    sta cbs_d41C+1
    adc #$01; sta cbs_d41D+1
    adc #$01; sta cbs_d41E+1
    adc #$01; sta cbs_d41F+1
    sta cbs_pre+1
    // Pre-check: D41F before unlock — $01 = NOSID bus float
cbs_pre:    lda $D41F
            cmp #$01
            beq cbs_notfound
    // Unlock
    lda #$02
    ldy #$1B
    sta (sptr_zp),y             // D41B via indirect-indexed (works for any SID slot)
    lda #$01
cbs_d41C:   sta $D41C
    lda #$B5
cbs_d41D:   sta $D41D
    lda #$1D
cbs_d41E:   sta $D41E
    // Poll loop
    ldx #15
cbs_poll:
    lda #$02
    ldy #$1B
    sta (sptr_zp),y             // re-arm on each poll
    lda #$0E
    jsr rp_delay                // ~42ms; preserves X via stack
cbs_d41F:   lda $D41F
    sta backsid_d41f            // save for debug display
    cmp #$01
    beq cbs_found
    dex
    bne cbs_poll
cbs_notfound: lda #$F0; sta data1; jmp cbs_done
cbs_found:    lda #$0A; sta data1
cbs_done:
    ldx x_zp; ldy y_zp; pla
    rts
```

**The `(sptr_zp),y` trick for D41B:** The original implementation hardcoded `sta $D41B` (D400 address). When BackSID was later detected in a SIDFX secondary slot at D500, `$D51B` was needed instead. Rather than adding a full self-modification block for D41B (which would require two more address patches), D41B access uses 6502 indirect-indexed addressing: `ldy #$1B; sta (sptr_zp),y`. This writes to `(sptr_zp) + $1B`, which equals the correct D41B address for any SID slot. Since `rp_delay` clobbers Y (uses it as inner loop counter), `ldy #$1B` is re-issued before each write.

**BackSID hardware limitation:** The BackSID unlock protocol works *once per power cycle*. After cold-boot detection, a soft restart (SPACE key) does not power-cycle the chip, so the unlock protocol does not succeed again. On restart, BackSID falls back to displaying as 8580 (the SIDFX-reported chip type). This is a hardware property, not a software bug. The primary use case — power on, run detector, know your chip — works correctly.

---

## 10. SIDKick Pico: Config Mode with Manual String Pointer

SIDKick Pico is based on the Raspberry Pi Pico (RP2040 dual-core processor). It exposes its identity via a config mode that the detector enters by writing `$FF` to D41F (the uppermost voice-3 register).

**The protocol:**

```asm
sfx_skp_f:  lda #$FF
            sta $D41F           // enter config mode

// D41E is a manual pointer register — write the byte offset you want to read
// D41D is the data register — read the byte at VERSION_STR[offset]
sfx_skp_e1: lda #$E0            // request byte 0 of VERSION_STR
            sta $D41E
sfx_skp_ds: lda $D41D           // read byte 0 → must be 'S' = $53
            cmp #$53
            bne sfx_skp_miss
sfx_skp_e2: lda #$E1            // request byte 1 of VERSION_STR
            sta $D41E
sfx_skp_ds2: lda $D41D          // read byte 1 → must be 'K' = $4B
            cmp #$4B
            bne sfx_skp_miss
```

The full VERSION_STR for firmware v0.22 DAC64 is `SK\x10\x09\x03\x0F0.22/DAC64` — but detecting `'S'` and `'K'` at positions 0 and 1 is sufficient for positive identification.

**No auto-increment:** Unlike some protocols, D41E is not an auto-incrementing pointer. The firmware re-reads the same byte until D41E is explicitly changed. This means each byte access requires writing the next offset to D41E first.

**Exit:** After detection (pass or fail), write `$00` to D41E (volume register) to exit config mode cleanly.

**6581 vs 8580 discrimination (in SIDFX context):** After SIDKick Pico is confirmed in a SIDFX secondary slot, `buf_zp` (which holds the SIDFX-reported chip type byte) is checked:

```asm
lda buf_zp
cmp #$01                        // $01 = 6581 mode reported by SIDFX
bne sfx_skp_s2_8580
lda #$0E                        // SIDKick Pico 6581
bne sfx_pop_s2_save
sfx_skp_s2_8580:
lda #$0B                        // SIDKick Pico 8580 (or UNKN → default 8580)
```

---

## 11. KungFuSID: ACK-Based Identification

KungFuSID is identified by writing a magic byte and checking whether the chip acknowledges it. The magic value `$A5` is used because it is the firmware-update trigger — writing `$A5` to D41D on KungFuSID initiates firmware update mode on old firmware versions.

**Two firmware generations, two detection paths:**

```asm
lda #$A5
cks_d41D: sta $D41D             // write magic byte
jsr rp_delay                    // ~6ms for ARM to process
cks_d41D_read: lda $D41D        // read back

cmp #$5A                        // new firmware: $A5→$5A byte-swap ACK
beq kungfusid_found
cmp #$A5                        // old firmware: echoes back the write value
beq kungfusid_found
```

Old-firmware KungFuSID implements a `kff_read_handler` that returns `SID[register_addr]` for every address — it stores all writes in a RAM array and returns them on read. Writing `$A5` stores it; reading back returns `$A5`.

New-firmware KungFuSID performs a byte-swap: `$A5` → `$5A`. This is the acknowledgement that the firmware-update mode write was received. The detector accepts both forms.

Real SID chips, ARMSID, FPGASID, and SIDKick Pico all produce values other than `$A5` or `$5A` at D41D after this sequence — confirming KungFuSID is identified cleanly.

---

## 12. SwinSID Nano: The Oscillator Speed Test and the NOSID Trap

SwinSID Nano is the most difficult chip to detect reliably. It has no echo protocol and no magic cookie. It is identified entirely by the behaviour of its AVR oscillator, which is exactly the behaviour that an empty SID socket can accidentally mimic under certain conditions.

**The physical principle:** SwinSID Nano uses an Atmel AVR microcontroller running a software LFSR (linear feedback shift register) to emulate the SID voice oscillators. The LFSR advances at roughly 44 kHz (the AVR's effective audio sample rate). Reading D41B from a SwinSID Nano gives the current LFSR state, which changes approximately once every 22 µs.

On a real 6581 or 8580, the oscillator advances every C64 clock cycle (≈1 µs). Reading D41B 8 times in rapid succession (at roughly 19 cycles apart = 19 µs) will catch 7 of the 7 consecutive pairs changing — the oscillator moves faster than the read interval.

On SwinSID Nano, the oscillator moves slower than the read interval (22 µs vs 19 µs). Some reads catch the same LFSR value; the change count per 8-read window is typically 3–6, not always 7.

**The NOSID trap:** An empty SID socket on a C64 with an active bus (recent register writes, or an Ultimate II+ cartridge present) produces a floating bus that retains capacitive charge from previous bus activity. This produces values that change on successive reads — exactly what we are trying to measure. After recent activity, a NOSID bus can produce change counts of 4–7, identical to SwinSID Nano.

**The discriminant — temporal profiling:** The key difference is what happens over *time*:
- SwinSID Nano's AVR oscillator is continuously running; the change rate does not decrease
- NOSID bus noise settles toward silence as the capacitive charge dissipates

```
Hardware          cnt_12ms    cnt_62ms    Trend
SwinSID Nano      2–3         4–7         ↑ (increasing)
NOSID (fresh)     2–3         0–1         ↓ (decreasing)
NOSID (warmed)    4–7         4–7         → (high noise floor — looks like SwinSID!)
```

**The current algorithm (V1.2.32+):**

**Step 0.25 — Real SID pre-check:** Run `checkrealsid` first (it only writes to D412/D40F, never D41F, so it cannot interfere with any subsequent probe). If a real 6581 or 8580 is confirmed, skip SwinSID Nano entirely. This eliminates the real-SID false positive without touching the SwinSID Nano logic.

**Stage 1 — 3-retry change-count gate (noise waveform, freq=$FFFF):** Set voice 3 to maximum frequency noise waveform, read D41B 8 times. Count consecutive differing pairs. Retry up to 3 times.
- **All 3 attempts: cnt = 7** → guaranteed real-SID LFSR speed → reject (bne checkswinsidnano)
- **Any attempt: cnt < 7** → ambiguous → proceed to Stage 2

The 3-retry rule: P(all 3 fail for SwinSID Nano) ≈ (0.4)³ ≈ 6% false-negative rate (acceptable). P(real SID passes Stage 1) ≈ 0 after the Step 0.25 pre-check.

**Stage 2 — Activity confirmation at 62ms:** After a 50ms wait, count changes in another 8-read window. Require cnt ≥ 3.
- SwinSID Nano oscillator: still running → passes
- Settled NOSID: near-zero changes → fails

**Known limitation (accepted):** A C64 with an Ultimate II+ cartridge and virtual SID disabled generates FPGA-sourced bus noise at ~44 kHz, indistinguishable from the SwinSID Nano oscillator. 10+ discriminants were exhaustively tested (D41B, D41C, D419/D41A, D41F, frequency variation, waveform, interrupt context, monotone counting, write-to-read-register). All produced overlapping results between NOSID+U2+ and SwinSID Nano. This case is reported as SwinSID Nano — an accepted limitation documented in the program's readme.

---

## 13. SIDFX: SCI Serial Handshake and Secondary Chip Probing

SIDFX is a hardware cartridge that piggybacks on top of the SID chip in its DIP-28 socket. It adds a second SID channel, envelope extensions, and distortion effects. Detection requires speaking a complete serial protocol.

**The SCI (Serial Control Interface) protocol:** SIDFX implements a synchronous serial state machine over the D41E (data) and D41F (clock) register pins. Data is shifted out MSB-first, 8 bits per byte, with D41F toggling as the clock.

```asm
SCIPUT:    // Send one byte
    // 8 iterations: extract bit, write to D41E, toggle D41F clock
    ldy #$08
sciput_loop:
    lsr
    bcc sciput_zero
    lda #$01
    .byte $2C       // BIT $xxxx — skip next instruction
sciput_zero:
    lda #$00
cas_d41e_put: sta $D41E    // data bit
cas_d41f_hi:  lda #$01 : sta $D41F   // clock hi
cas_d41f_lo:  lda #$00 : sta $D41F   // clock lo
    dey; bne sciput_loop
    rts
```

**The login sequence:**
1. Send 16× `SCISYN` sync bytes to reset the SIDFX state machine to idle
2. Send PNP login: `$80 $50 $4E $50` (`$80` header, `'P' 'N' 'P'`)
3. Receive 4 bytes via `SCIGET`
4. Verify: `$45 $4C $12 $58` (vendor ID "EL" + product signature)

```asm
lda #$45 : cmp PNP+0 : bne NOSIDFX   // 'E'
lda #$4C : cmp PNP+1 : bne NOSIDFX   // 'L'
lda #$12 : cmp PNP+2 : bne NOSIDFX
lda #$58 : cmp PNP+3 : beq SIDFXFOUND // 'X'
```

On success: `data1 = $30` (SIDFX found). The detector then reads D41D and D41E to capture the hardware configuration:

- **D41D**: SW2 + SW1 + PLY bits — SW1 (bits 5:4) encodes the secondary SID address: `00`=D500 (CTR), `01`=D420 (LFT), `10`=DE00 (RGT)
- **D41E**: SID1 type (bits 1:0) + SID2 type (bits 3:2): `01`=6581, `02`=8580, `03`=unknown

---

## 14. PD SID and uSID64: Simpler Echo Tests

**PD SID** uses a simple 3-byte echo: write `'P'` to D41D, `'D'` to D41E, read D41E back — expects `'S'`. This 3-letter sequence identifies the chip's internal register processing pipeline.

```asm
lda #$50 : cks_d41D: sta $D41D    // 'P'
lda #$44 : cks_d41E: sta $D41E    // 'D'
cks_d41E_r: lda $D41E
cmp #$53                           // 'S'
beq pdsid_found
```

`data1 = $09` on success.

**Why `'P'` and `'D'` produce `'S'` in the readback** is an implementation detail of the PD SID firmware. The write-to-D41D value shifts one register position when read back — the same propagation behaviour as in ARMSID's DIS protocol, but with different sequence bytes.

---

## 15. Stereo SID Detection: Scanning Secondary Slots

After identifying the primary SID at D400, the detector scans for additional chips at the standard secondary addresses: D500, D600, D700, DE00, DF00. The `checksecondsid` routine uses the noise-waveform mirror test:

**Mirror test:** Activate noise waveform on voice 3. Read D41B at `$D400 + $20n` offsets. A real SID at that address produces non-zero changing values from its oscillator. A mirrored address (no chip) always reads the same bus float value.

```asm
// checksecondsid: iterate candidate addresses
// For each address: noise waveform on, read D41B twice
// If different: chip present at this address
lda #$01 : sta $D407    // freq hi (to make noise audible)
lda #$80 : sta $D412    // noise waveform
ldx #$08
css_loop:
    // set mptr_zp to candidate address
    // read D41B twice
    // if reads differ: add to sid_list
    dex; bne css_loop
```

Secondary chips are typed by the SIDFX configuration (if SIDFX is primary) or by re-running the full detection chain with `sptr_zp` pointing to the secondary address.

---

## 16. Self-Modifying Code — The Right Tool for Multi-Slot Probing

On the 6502, the only addressing modes for register I/O are absolute (`sta $D41B`, 3 bytes), absolute-indexed (`sta $D400,x`), and zero-page indirect indexed (`sta (ptr),y`). To probe the same SID registers at a different base address (D500 instead of D400), every `sta $D41B` must become `sta $D51B`. There is no "base register" or relative addressing.

The traditional solution: **self-modifying code**. Each SID register access instruction has its address bytes patched at runtime before the probe runs. The pattern is consistent throughout the codebase:

```asm
// Patch hi byte (e.g., change $D4xx to $D5xx)
lda sptr_zp+1               // load target hi byte (e.g., $D5)
sta sfx_dis_df+2            // patch hi byte of sta $D41F instruction
sta sfx_dis_di+2            // patch hi byte of sta $D41E
sta sfx_dis_ds+2            // ... and so on for every SID access

// Patch lo byte using subtraction chain to avoid carry
lda sptr_zp                 // load target lo byte (e.g., $00)
clc; adc #$1F               // start at +$1F (highest register)
sta sfx_dis_df+1            // lo byte of D41F access
sta sfx_dis_clrF+1
sec; sbc #$01               // step down to +$1E
sta sfx_dis_di+1            // lo byte of D41E access
sec; sbc #$01               // step down to +$1D
sta sfx_dis_ds+1            // lo byte of D41D access
sec; sbc #$02               // step down to +$1B (skip $1C)
sta sfx_dis_rd+1            // lo byte of D41B read
```

The `sec; sbc` chain is important: using `adc` to count downward would require separate `clc` instructions and risks carry from intermediate results. `sec; sbc #$01` is always carry-safe for small decrements within the same page.

**An alternative for a single address: `(sptr_zp),y`:** When only one or two instructions need to access a variable address, zero-page indirect indexed addressing is more economical than adding two more self-modification patches. BackSID's D41B accesses use this:

```asm
// Instead of patching "sta $D41B" for each SID slot:
ldy #$1B
sta (sptr_zp),y             // writes to sptr_zp + $1B — correct for any slot
```

Cost: 4 bytes vs 3 bytes for an absolute store. Savings: no additional self-modification patch (which would cost 6 bytes of patch code). For one or two accesses, `(sptr_zp),y` wins.

---

## 17. The NOSID Problem — When Empty is Louder Than Expected

The most insidious challenge in SID detection is correctly identifying an empty socket (no chip installed). A naive implementation fails in two ways:

**False positive (NOSID looks like a chip):** The SID data bus is shared between the 6510 and the SID. When the 6510 performs `lda $D41B` (a 3-byte opcode), the data bus carries the address bytes and opcode bytes as part of the fetch cycle. The SID socket — which sees the bus — retains these values capacitively. After the `lda` opcode, D41B reads the high byte of the `lda $D41B` opcode sequence (`$D4`) or a decaying average of recent bus activity. This value changes if the preceding code was varied, producing what looks like oscillator activity.

**False negative (chip looks like NOSID under one condition):** Early detection code that checked "did D41B change?" could be fooled by a freshly reset SID socket where all bus charge had dissipated to a constant value. Two reads returning the same value could mean "real chip at slow frequency" or "dead bus at constant float".

**Solutions applied across the codebase:**

1. **Temporal profiling (SwinSID Nano):** Measure change rate at 12ms then at 62ms. Declining rate = settling bus. Stable or increasing rate = active oscillator.

2. **Two-read stability with small tolerance (uSID64):** `|read2 - read1| ≤ $02` over 3ms gap. Chips hold stable; decaying bus drifts.

3. **Pre-check before sequence (BackSID):** Read D41F cold before writing anything. If already `$01`, it is bus float, not a chip echo.

4. **Real SID pre-check step 0.25:** Run `checkrealsid` before any oscillator-activity tests. Real 6581/8580 confirmed → skip all oscillator tests entirely.

5. **Threshold filtering (D41B readback):** `and #$FE; bne unknownSid` — rejects any D41B value other than `$00` or `$01`, eliminating bus float values like `$D4`.

---

## 18. Hardware Testing Methodology

Software testing in VICE is necessary but not sufficient. Emulators do not model bus capacitance, clock jitter, open-bus float behaviour, or the timing quirks of real SID hardware. The only way to be confident in a detection probe is to test it on real hardware.

### The hw_test.py Framework

`make hw_test` runs a Python script that:

1. **Builds** `siddetector.prg` via KickAssembler
2. **Reads symbols** from the generated `siddetector.vs` file to find the addresses of `kbdloop`, `do_restart`, and `sid_list` (the detection result array)
3. **Deploys** the PRG to a real C64 via the Ultimate 64 network API (`/v1/runners/sidcart`)
4. **Waits** for cold-boot detection to complete (configurable `detect_wait`)
5. **Reads** the `sid_list` memory via `c64u read-mem` — this uses the U64's debug memory access without interrupting execution
6. **Decodes** the result: slot count + per-slot (address, type code) pairs
7. **Runs tests**: sends keypresses (SPACE, I, D, R, T, P) using the `c64u keypress` API, then reads `sid_list` after each keypress to verify the chip survives navigation

**JMP-patch keypress injection:** The C64 program runs at 1 MHz with its own keyboard scan loop. The hw_test script cannot synchronise reliably to the main keyboard polling loop timing. Instead, the script patches two bytes at the `kbdloop` address with `JMP do_restart` (opcode `$4C` + 16-bit address), then sends the keypress. The C64 executes the JMP, performs the restart, and returns to `kbdloop`. This guarantees the keypress is processed at the right time regardless of relative PC timing between the host script and the C64.

```python
# Inject JMP do_restart at kbdloop to synchronise restart
c64u.write_mem(kbdloop, [0x4C, do_restart & 0xFF, do_restart >> 8])
c64u.keypress('SPACE')
# Wait for kbdloop to be reached again (detection complete)
while c64u.read_pc() != kbdloop:
    time.sleep(0.1)
```

**Stability verification:** After each navigation test, `sid_list` is read again. The test passes only if the list matches the baseline (cold-boot detection). This catches bugs where a navigation action corrupts the detection state — for example, if the info screen display code accidentally writes to SID registers and confuses a secondary probe.

**Result files:** Every run saves a timestamped result file in `tests/hw_test_result_YYYYMMDD_HHMMSS.txt`. This creates a log of which configurations were tested and when.

### Test Configuration Scenarios

The stereo configuration tests (C31–C43 in `teststatus.md`) document every combination of primary chip + SIDFX secondary that has been verified:

| ID | Primary | Secondary | SW1 | Result |
|----|---------|-----------|-----|--------|
| C31 | 6581 | SIDKick Pico 8580 | CTR→D500 | ✅ 9/9 |
| C32 | 6581 | PD SID | CTR→D500 | ✅ 9/9 |
| C33 | 6581 | SwinSID Ultimate | CTR→D500 | ✅ 9/9 |
| C34 | 6581 | ARMSID | CTR→D500 | ✅ 9/9 |
| C34b | 6581 | BackSID | CTR→D500 | ✅ cold boot (restarts: see §9) |
| C34a | 6581 | SwinSID Ultimate | LFT→D420 | ⚠️ bus conflict |
| C38 | 6581 | SIDKick Pico 8580 | LFT→D420 | ✅ 9/9 (shows 8580, probe skipped) |

---

## 19. SIDFX Secondary Probing — New Territory (V1.3.x)

The most significant development in the V1.3.x series was extending SID detection to identify *what chip is inside a SIDFX cartridge*. This turned out to require solving several non-trivial problems.

### The Starting Point

When SIDFX is detected, the detector reads D41E to learn the secondary chip's type: `$01` = 6581, `$02` = 8580, `$03` = unknown. SIDFX reports what it thinks is there based on configuration, not by probing the chip. So a BackSID in SIDFX SID2 slot will show as "8580" because the SIDFX was configured for 8580 mode — not because SIDFX knows it is a BackSID.

The goal: after SIDFX login, probe the secondary SID slot directly to identify the chip family.

### Problem 1: D4xx Bus Conflict

**Hypothesis:** Use the same DIS echo probe on the secondary slot (D420, D500, etc.).

**Problem:** The SIDFX secondary at D420 shares the SID1 chip select with D400. Address D43B (`$D400 + $3B = $D43B`) — which is D400+$1B, the OSC3 output — is **actively driven** by the primary SID chip. Even with the SIDFX cartridge routing writes to SID2, reading D43B returns the primary SID's live oscillator output, masking any echo from SID2.

**Solution:** Restrict all secondary probes to addresses D5xx–D7xx. For SIDFX SW1=CTR (D500), this is natural. For SW1=LFT (D420, D4xx range), probing is skipped entirely and the SIDFX-reported chip type is used as-is.

```asm
// sidfx_populate_sid_list: guards before probing
lda sptr_zp+1
cmp #$D4; beq sfx_pop_s2_add    // D4xx: skip probe (bus conflict)
cmp #$DE; beq sfx_pop_s2_add    // DE00: SIDFX I/O space, skip
cmp #$DF; beq sfx_pop_s2_add    // DF00: SIDFX I/O space, skip
```

### Problem 2: PDsid Mirror Overflow (V1.3.59)

**Symptom:** When PDsid (Public Domain SID) was installed as SIDFX SID2, the detector produced garbled addresses for all 8 SID slots, not just the secondary slot.

**Root cause:** The `sidstereostart` routine (which scans D500–DF00 for secondary chips) ran for SIDFX primaries. PDsid does not respond to the PD SID echo probe, so `sidstereostart` classified it as an 8580 at *every* mirrored address in the D5xx range (D500, D520, D540, ..., D5E0 — 8 addresses). This overflowed the 8-entry `sid_list` array. Entry 9 in a 1-indexed 8-element array aliases `sid_list_l[9]` → `sid_list_h[1]`, corrupting slot 1's high address byte.

**Fix:** Add an early-return guard at the top of `sidstereostart` for SIDFX primaries:

```asm
sidstereostart:
    lda data4
    cmp #$30                    // $30 = SIDFX found
    bne sss_not_sidfx
    rts                         // SIDFX: sidfx_populate_sid_list is authoritative
sss_not_sidfx:
    // ... existing scan code ...
```

### Problem 3: Probe Chain Architecture (V1.3.60–V1.3.61)

The secondary probe chain in `sidfx_populate_sid_list` was built iteratively as new chips were tested:

**Phase 1 (SIDKick Pico, V1.3.58):** `sfx_probe_skpico` — writes `$FF` to `base+$1F`, checks `'S'+'K'` at `base+$1D` via manual pointer at `base+$1E`.

**Phase 2 (SwinSID Ultimate, V1.3.60):** `sfx_probe_dis_echo` — writes the full DIS sequence to `base+$1F/$1E/$1D`, waits two `loop1sek` delays, reads `base+$1B`. Returns echo byte in A.

```asm
sfx_probe_dis_echo:
    // Patch all 8 instruction addresses for the target SID slot
    lda sptr_zp+1
    sta sfx_dis_df+2            // hi bytes
    // ... (6 more sta ..+2) ...
    lda sptr_zp
    clc; adc #$1F
    sta sfx_dis_df+1            // base+$1F ('D' write)
    sta sfx_dis_clrF+1
    sec; sbc #$01
    sta sfx_dis_di+1            // base+$1E ('I' write)
    sta sfx_dis_clrE+1
    sec; sbc #$01
    sta sfx_dis_ds+1; sta sfx_dis_pre+1; sta sfx_dis_clrD+1   // base+$1D
    sec; sbc #$02
    sta sfx_dis_rd+1            // base+$1B (read)
    // Pre-clear base+$1D to reset any previous echo state
    lda #$00
sfx_dis_pre:    sta $D41D
    // Write DIS sequence
    lda #$44
sfx_dis_df:     sta $D41F
    lda #$49
sfx_dis_di:     sta $D41E
    lda #$53
sfx_dis_ds:     sta $D41D
    jsr loop1sek; jsr loop1sek
sfx_dis_rd:     lda $D41B       // read echo
    pha
    lda #$00
sfx_dis_clrD:   sta $D41D       // cleanup: clear DIS state
sfx_dis_clrE:   sta $D41E
sfx_dis_clrF:   sta $D41F
    pla; rts                    // return echo byte in A
```

`A = $53` → SwinSID Ultimate; `A = $4E` → ARMSID/ARM2SID.

**Phase 3 (ARMSID, V1.3.61):** The same `sfx_probe_dis_echo` function handles ARMSID — the two chips give different echo bytes from the same DIS sequence.

**Phase 4 (BackSID, V1.3.63):** Reuse `checkbacksid` directly (see §9 for full protocol).

**Phase 5 (KungFuSID, V1.3.64):** Inline the `$A5` ACK test using `(sptr_zp),y` — no separate function needed:

```asm
sfx_pop_try_kfs:
    lda #$A5
    ldy #$1D
    sta (sptr_zp),y         // base+$1D ← $A5 (firmware-update magic)
    lda #$04
    jsr rp_delay            // ~12ms
    ldy #$1D
    lda (sptr_zp),y         // read back
    cmp #$5A                // new FW: byte-swap ACK
    beq sfx_pop_is_kfs
    cmp #$A5                // old FW: plain echo
    bne sfx_pop_s2_add      // neither → not KungFuSID
sfx_pop_is_kfs:
    lda #$0C                // $0C = KungFuSID
    bne sfx_pop_s2_save
```

**Phase 4 (BackSID, V1.3.63):** Reuse `checkbacksid` directly, after modifying it to use `(sptr_zp),y` for D41B access:

```asm
sfx_pop_try_armsid:
    cmp #$4E                    // 'N' = ARMSID?
    beq sfx_pop_is_armsid
    // BackSID probe: checkbacksid uses sptr_zp; result in data1
    jsr checkbacksid
    lda data1
    cmp #$0A                    // $0A = BackSID confirmed
    bne sfx_pop_s2_add          // not BackSID → use SIDFX default type
    beq sfx_pop_s2_save         // BackSID found: A=$0A, always taken (Z=1)
sfx_pop_is_armsid:
    lda #$05
sfx_pop_s2_save:
    sta buf_zp
```

The `beq sfx_pop_s2_save` after the BackSID check exploits the Z flag: if `cmp #$0A` matched (Z=1), `beq` is always taken, branching to `sfx_pop_s2_save` with A=$0A already loaded.

**Phase 5 (FPGASID SID2, V1.3.66):** After the KungFuSID probe falls through in the SID2 chain, call `checkfpgasid` with `sptr_zp` already pointing to the secondary slot. `checkfpgasid` already uses `sptr_zp` self-modification for all register accesses (D419/D41A/D41E/D41F), so no modifications were needed — just a `jsr checkfpgasid` followed by reading `data1` for `$06`/`$07`.

**Phase 6 (SID1=UNKN probe chain, V1.3.67–V1.3.68):** When SIDFX reports SID1 type = `$03` (UNKN), the chip is not recognised by SIDFX firmware — typically a modern replacement. Instead of recording "unknown", the detector now intercepts type=3 and runs its own probe chain at D400:

```asm
// type=3 (UNKN): probe D400
lda #$00
sta sptr_zp             // point sptr_zp → D400
lda #$D4
sta sptr_zp+1
jsr checkfpgasid        // data1=$06/$07 (FPGASID) or $F0
lda data1
bpl sfx_pop_s1_store    // bit7=0 → FPGASID found (must run before skpico)
jsr sfx_probe_skpico    // C=1: SIDKick Pico
bcc sfx_s1_not_skp
lda #$0B; bne sfx_pop_s1_store
sfx_s1_not_skp:
jsr checkpdsid          // data1=$09 (PDsid) or $F0
lda data1; cmp #$09; beq sfx_pop_s1_store
jsr sfx_probe_dis_echo  // DIS echo: 'S'=SwinSID-U, 'N'=ARMSID
cmp #$53; bne sfx_s1_not_swu
lda #$04; bne sfx_pop_s1_store   // SwinSID Ultimate
sfx_s1_not_swu:
cmp #$4E; bne sfx_pop_s1_norm
lda #$05; bne sfx_pop_s1_store   // ARMSID
sfx_pop_s1_norm:
lda #$F0                // not found → unknown
sfx_pop_s1_store:
sta sid_list_t,x
```

This covers ARMSID, SIDKick Pico, PD SID, SwinSID Ultimate, and FPGASID in the SIDFX SID1 slot. Verified on hardware: all five chip types correctly identified when SIDFX reports them as UNKN.

### Code Size Budget and Data Table Relocation (V1.3.67)

By V1.3.67 the code segment had grown to `$55FF` — exactly 0 bytes before the `sid_list` data table at `$5600`. Any new code would overwrite the detection result tables.

**Solution:** Move the data table origin from `$5600` to `$6000`. This is a single-line change in the source — all accesses use labels, not hardcoded addresses. The move created 1536 bytes of headroom (`$5600`–`$5FFF`), enough for the entire SID1=UNKN probe chain and all future SIDFX work.

The lesson: **when code and data abut, relocate data, not code.** Label-relative addressing means data moves freely; code rewrite costs are O(N) where N is the number of affected routines.

### Probe Ordering: D41E Corruption (V1.3.68)

During testing with FPGASID in the SID1 slot, FPGASID was not being detected despite checkfpgasid running first in the probe chain. The bug was a probe-ordering issue hidden inside `sfx_probe_skpico`:

`sfx_probe_skpico` enters SIDKick Pico's config mode by writing `$FF` to `base+$1F`. On a miss, it reads back `base+$1D` to check for `'S'+'K'`, then exits — but it **leaves `base+$1F = $FF` and `base+$1E = $E0` without cleanup**. These are exactly the registers `checkfpgasid` uses for its magic-cookie sequence (`$80` to `base+$1E` to enter identify mode; reads from `base+$19`/`base+$1A`). When `sfx_probe_skpico` ran first and missed, its dirty state reset FPGASID's config mode before `checkfpgasid` had a chance to run.

**Fix:** Reorder the SID1 probe chain so `checkfpgasid` always runs before `sfx_probe_skpico`. The `bpl` trick distinguishes result: `data1 = $06`/`$07` both have bit7 = 0 (positive); `$F0` (not found) has bit7 = 1 (negative). A single `bpl` after the `jsr checkfpgasid` branches on found / falls through on miss.

### FPGASID at SIDFX SID1 — An Unresolvable Hardware Limitation (V1.3.70)

After fixing the probe ordering, FPGASID in the SIDFX SID1 slot still failed to identify. The root cause is a hardware-level interference that no software fix can resolve:

1. **POT register masking:** FPGASID's identify protocol requires writing the magic cookie `$81`/`$65` to D419/D41A (the POT X/Y registers), then reading `$1D`/`$F5` back. But SIDFX actively drives D419/D41A with real joystick values read from its own hardware. The POT values are continuously refreshed by the SIDFX microcontroller — any value written by the detector is immediately overwritten, and any read returns the joystick position, not the FPGASID identify signature.

2. **SCI state machine reaction:** SIDFX monitors all writes to D41D/D41E/D41F as part of its SCI serial protocol. `checkfpgasid`'s write of `$80` to D41E (to set the "identify mode" flag) is interpreted by the SIDFX SCI state machine as a protocol byte, changing SIDFX's internal state in an unknown way.

Both problems are in hardware. There is no timing trick, no retry loop, no alternative register sequence that avoids them. **FPGASID installed in the SIDFX SID1 slot will always be reported as "unknown SID type" by the SIDFX register.** Documented as accepted limitation; the test matrix records this as a hardware constraint (C43a).

### Code Size Budget

All new code must fit between the end of the code segment and the start of `sid_list` at `$5600`. This margin was ~20 bytes at V1.3.62. The temptation is to add a full new probe function (`sfx_probe_backsid`), but this would require ~130 bytes: 7 hi-byte patches (21 bytes), lo-byte computation (37 bytes), pre-check/unlock/poll (70 bytes). 130 bytes of code into a 20-byte margin does not fit.

**The solution — reuse and economise:**
- Modify `checkbacksid` to handle any SID slot (change 2 hardcoded `sta $D41B` to `ldy #$1B; sta (sptr_zp),y` = +2 bytes)
- Call `checkbacksid` from the probe chain and read `data1` (12 bytes of probe chain additions)
- Total: 14 bytes new code. Fits with 9 bytes to spare.

The lesson: **before adding a new function, check whether an existing function can be made generic with a small modification.**

### The "????" Display Bug (V1.3.62)

When ARMSID was detected in a SIDFX secondary slot, the main display showed "ARMSID ????" — the `print_sid_type_4` function was being called to print the chip's 6581/8580 sub-type, but this function reads `armsid_sid_type_h` which is only populated during *primary* ARMSID detection. For a secondary ARMSID, `armsid_sid_type_h = $00` (not set), producing "????".

**Fix:** In the stereo display code, check whether SIDFX is the primary chip. If so, skip `print_sid_type_4`:

```asm
ssp_skp7:
    cmp #$05; bne ssp_skp8
    lda #<armsidf; ldy #>armsidf; jsr $AB1E   // print "ARMSID"
    lda data4; cmp #$30
    bne ssp_skp7_type           // not SIDFX: print chip type
    jmp ssp_skp20               // SIDFX: skip "????"
ssp_skp7_type:
    lda #$20; jsr $FFD2         // ' '
    jsr print_sid_type_4        // prints "6581", "8580", or "????"
    jmp ssp_skp20
```

---

## 20. Detection Chain Order — Why Sequence Matters

The detection chain runs sequentially. Each step either identifies the chip and halts, or falls through. The order is carefully chosen:

```
Step 0.25 — Real SID pre-check (checkrealsid, early)
    ↓ (not real SID)
Step 0.5  — SwinSID Nano (checkswinsidnano)
    ↓ (not SwinSID Nano)
Step 1    — SIDFX (DETECTSIDFX)
    ↓ (not SIDFX — then sidfx_populate_sid_list handles secondary)
Step 2    — ARMSID / ARM2SID / SwinSID Ultimate (Checkarmsid)
    ↓ (not ARM echo)
Step 3a   — PD SID (checkpdsid)
    ↓
Step 3b   — BackSID (checkbacksid)
    ↓
Step 3c   — SIDKick Pico (checkskpico)
    ↓
Step 3d   — FPGASID (checkfpgasid)
    ↓
Step 3e   — uSID64 (checkusid64)
    ↓
Step 4    — Real SID (checkrealsid, normal)
    ↓ (not real SID — emulator path)
Step 5    — KungFuSID (checkkungfusid)
    ↓
Step 5b   — $D418 decay fingerprint (calcandloop / ArithmeticMean)
    → VICE ResID / FastSID / HOXS64 / Frodo / YACE64 / EMU64 / NOSID
```

**Key ordering decisions:**

- **Real SID pre-check before SwinSID Nano:** A real 6581 LFSR advances at full CPU clock speed; it would pass SwinSID Nano's oscillator test and produce a false "SwinSID Nano" result. Pre-check runs `checkrealsid` first (writes only D412/D40F — safe to run early).

- **SIDFX before ARMSID:** SIDFX piggybacks on a real SID. If ARMSID ran first, it would find the echo protocol responding (via SIDFX's SCI state machine accidentally echoing register bytes) and misidentify.

- **BackSID before FPGASID:** FPGASID detection writes to D419/D41A (POT addresses). BackSID uses D41B–D41E. Running BackSID first avoids the POT writes interfering with BackSID's protocol.

- **KungFuSID after FPGASID and real SID:** KungFuSID detection writes `$A5` to D41D. ARMSID would echo `$A5` back (its RAM array returns any write), but ARMSID is caught earlier. FPGASID, after having its config mode reset, would not echo `$A5`. Real SID: D41D is write-only, does not echo.

---

## 21. Results Summary

| Chip | `data1` | Method | Status |
|------|---------|--------|--------|
| 6581 R2 | `$01` | OSC3 readback + MODE6581 table | ✅ |
| 6581 R3 | `$01` | OSC3 readback + MODE6581 table | ✅ |
| 6581 R4 | `$01` | OSC3 readback + MODE6581 table | ✅ |
| 6581 R4AR | `$01` | OSC3 readback + MODE6581 table | ✅ |
| 8580 | `$02` | OSC3 readback + MODE8580 table | ✅ |
| ARMSID | `$05` | DIS echo: D41B=`'N'`, D41C=`'O'` | ✅ |
| ARM2SID | `$05` | DIS echo: D41B=`'N'`, D41C=`'O'`, D41D=`'R'` | ✅ |
| FPGASID 8580 | `$06` | Magic cookie D419/D41A, D41F=`$3F` | ✅ |
| FPGASID 6581 | `$07` | Magic cookie D419/D41A, D41F=`$00` | ✅ |
| SwinSID Ultimate | `$04` | DIS echo: D41B=`'S'` | ✅ |
| SwinSID Nano | `$08` | OSC3 temporal profiling (2-stage) | ✅ |
| ULTISID 8580 (U64) | `$20` | UCI protocol + checkrealsid | ✅ |
| ULTISID 6581 (U64) | `$21` | UCI protocol + checkrealsid | ✅ (code; HW unverified) |
| SIDFX | `$30` | SCI serial PNP login | ✅ |
| SIDKick Pico 8580 | `$0B` | Config mode: `$FF→D41F`, `'S'+'K'` at D41D | ✅ |
| SIDKick Pico 6581 | `$0E` | Config mode + SIDFX type byte | ✅ |
| BackSID | `$0A` | Unlock/poll: `$02/$01/$B5/$1D`, D41F echo | ✅ |
| PD SID | `$09` | Echo: `'P'+'D'→D41D/E`, reads `'S'` | ✅ |
| KungFuSID | `$0C` | ACK: `$A5→D41D`, reads `$5A` or `$A5` | ✅ |
| uSID64 | `$0D` | Two-read stability after config write | ✅ |
| VICE ResID 6581/8580 | — | D418 decay fingerprint | ✅ |
| VICE FastSID | — | D418 decay fingerprint | ✅ |
| HOXS64 | — | D418 decay fingerprint | ✅ |
| Frodo | — | D418 decay fingerprint | ✅ |
| YACE64 | — | D418 decay fingerprint | ✅ |
| EMU64 | — | D418 decay fingerprint | ✅ |
| NOSID | — | All probes fail | ✅ |

**Stereo SIDFX secondary identification (V1.3.x):**

| Secondary chip | Probe | SID2 | SID1 (UNKN) |
|---------------|-------|------|-------------|
| SIDKick Pico | Config mode `'S'+'K'` | D5xx–D7xx only | ✅ |
| SwinSID Ultimate | DIS echo `'S'` | D5xx–D7xx only | ✅ |
| ARMSID | DIS echo `'N'` | D5xx–D7xx only | ✅ |
| BackSID | Unlock/poll `$01` | D5xx–D7xx only | — |
| KungFuSID | `$A5` → read `$5A`/`$A5` ACK | D5xx–D7xx only | — |
| FPGASID | Magic cookie D419/D41A | D5xx–D7xx only | ⚠️ (hardware limit) |
| PD SID | `'P'+'D'` echo `'S'` | — | ✅ |
| D4xx chips | — | Skipped (bus conflict) | N/A |
| DE/DF chips | — | Skipped (SIDFX cartridge I/O) | N/A |

---

## 22. Known Limitations

**SwinSID Nano / NOSID+U2+:** A C64 with an Ultimate II+ cartridge and virtual SID disabled is reported as SwinSID Nano rather than NOSID. The U2+ FPGA generates bus noise at ~44 kHz that is physically indistinguishable from the SwinSID Nano oscillator. 10+ discriminants were tested exhaustively without finding a reliable separator.

**BackSID one-shot detection:** BackSID only responds to its unlock protocol once per power cycle. On warm restart (SPACE key), the chip does not re-enter detection mode. The primary use case (cold boot detection) works correctly.

**SIDFX secondary at D420 (LFT position):** The D4xx bus conflict prevents DIS echo probing at D420. SwinSID Ultimate, ARMSID, and BackSID installed at D420 will show as their SIDFX-reported chip type (6581 or 8580), not as their actual identity. This is a hardware constraint — SID1 actively drives D43B (osc3), masking SID2's echo response.

**ARM2SID stereo at D400+D500:** If ARM2SID is installed as both primary and secondary (D400+D500 configuration), the D5xx probe sees D400's echo responses (bus mirroring), producing a false match for the D500 slot. This is tracked in the test matrix.

**FPGASID in SIDFX SID1 slot:** SIDFX drives D419/D41A (POT X/Y registers) with real joystick values from its own hardware, continuously overwriting any value the detector writes there. FPGASID's identify protocol requires reading `$1D`/`$F5` back from D419/D41A after writing the magic cookie — but SIDFX's joystick refresh makes those reads return joystick position instead. Additionally, SIDFX's SCI state machine monitors all writes to D41D/D41E/D41F; `checkfpgasid`'s write of `$80` to D41E to enter identify mode is treated as a protocol byte. Both problems are hardware constraints with no software workaround. FPGASID in SIDFX SID1 will always be reported as "unknown SID type".

**6510 I/O port trap:** The C64's 6510 CPU has an internal I/O port at addresses `$0000` (direction register) and `$0001` (data register). Bit 2 of `$0001` is the CHAREN bit: if cleared, the I/O area `$D000`–`$DFFF` is remapped to character ROM, silently redirecting all SID reads to ROM data. **Never use `$0001` as a scratch register in SID detection code.** Use zero-page addresses `$A2`–`$AF` or `$F6`–`$FF` instead. This caused a subtle debugging session when `sty $01` was accidentally used during development, causing all SID reads to return ROM bytes.

---

## 23. FM Expansion Detection — CBM SFX Sound Expander & FM-YAM (V1.4.x)

Detecting the OPL-based FM expansion cartridges — CBM's 1984 *Sound Expander* (YM3526) and XeNTaX's modern *FM-YAM* (YM3812) — turned out to be the single largest rabbit hole in the detector's history. Three separate issues compounded before detection finally stabilized.

### The wrong address

AdLib documentation, online references, and even the user's own example code all pointed at `$DF00`/`$DF01` for OPL register and data ports. Early V1.4 versions wrote there, detected nothing, and produced no audio — despite the hardware being physically installed. The breakthrough came from [XeNTaX's FM-YAM timing article](https://c64.xentax.com/index.php/15-testing-ym3812-register-write-timing):

> The three ports in the IOL2 space are:
> `$DF40` — register select/address, `$DF50` — data write, `$DF60` — chip status.
> "VICE doesn't know this" and requires these standard addresses.

The CBM Sound Expander cartridge decodes bit 4 of the address as the data-write strobe and bit 5 as the status-read strobe. `$DF00`/`$DF01` miss both decoders entirely — writes go to REU command register (if present) or open bus; reads return bus noise. Moving to `$DF40`/`$DF50`/`$DF60` fixed both detection and audio.

### The OPL /IRQ storm

Once writes started landing, detection still hung the entire machine on real hardware. The classic AdLib timer test (set Timer 1 period, start unmasked, wait 15 ms, read status for T1 flag) triggered an infinite IRQ loop:

1. T1 fires 10 ms into the wait → OPL asserts `/IRQ` on cartridge bus
2. `/IRQ` wired directly to CPU `/IRQ` → KERNAL IRQ handler at `$EA31` runs
3. `$EA31` only acknowledges CIA1 (reads `$DC0D`) — doesn't touch the OPL
4. OPL keeps `/IRQ` asserted → IRQ fires again immediately → hang

The `$EA31` handler has no concept of a cartridge IRQ source. Fix: start T1 with its IRQ masked (`reg $04 = $41` — `MASK_T1 | ST_T1`). Timer still counts and sets `T1_FLAG` (bit 6 of status) so detection works, but the chip never asserts `/IRQ`. Before returning, always issue `$04 = $80` (RST) to clear any flags set during the probe, then `PLP` to restore the caller's I flag exactly.

### The signature heuristic

With timing and addresses fixed, the next challenge was reading back a reliable detection signature. Spec says status should be `$00` after RST and exactly `$40` after masked T1 fires. But real FM-YAM on the test rig returned `$06`, `$04`, sometimes `$00` — not `$40`, not `$FF`. Several candidate checks were tested:

- `== $00` exact match: worked sometimes, missed the chip on noisy reads
- `(status & $E1) == $C0`: worked for VICE emulation (`$D4`) but false-positived on bus-noise `$D1` when no chip present
- `(status & $60) == $40`: false-positive on any bus-noise pattern that happened to set bit 6

The working heuristic is **`(status & $E0) == 0` on two reads**. Interpretation:

| State | Typical `$DF60` | `(& $E0)` | Verdict |
|-------|----------------|-----------|---------|
| Chip present, clean | `$00` | `$00` | ✓ detect |
| Chip present, noisy | `$06`, `$04`, `$12` | `$00` | ✓ detect |
| No chip, pure open bus | `$FF` | `$E0` | ✓ reject |
| No chip, bus noise | `$D1`, `$C5`, `$BB`, `$A4`, `$B7` | `$80`–`$E0` | ✓ reject |

The physical intuition: a real OPL drives the status bus actively, pulling it into the low-value range. Undriven bus noise on the C64 usually reflects the last CPU fetch or VIC data byte — which in practice almost always has at least one of bits 5–7 set.

### One label for two chips

Detection cannot distinguish YM3526 from YM3812 — both respond identically at `$DF40`/`$DF50`/`$DF60`, both accept the same timer and envelope registers, both report the same post-RST/post-timer status. OPL2's waveform-select (reg `$01 = $20`, reg `$E0`–`$F5`) is the only functional difference and is ignored by OPL1, producing no side effect the CPU can observe. After initially labelling the detection as "FM-YAM FOUND", the label was changed to the neutral `DF40 SFX/FM FOUND` — accurate for either card.

### Result

After settling at V1.4.19 the detector correctly identifies both CBM SFX Sound Expander and FM-YAM on real hardware across boot/restart/screen-visit cycles, with no false positives when the cartridge is unplugged. The `make hw_test` smoke suite covers the detection; the `T` sound test plays a 7-note arpeggio across 3 octaves with 3 FM instruments (Flute/Organ/Bell), matching the SID test's pattern voice-for-voice.

---

## Appendix: SID Register Quick Reference

| Address | Name | R/W | Notes |
|---------|------|-----|-------|
| D400–D406 | Voice 1 freq/pw/ctrl/env | W | |
| D407–D40D | Voice 2 freq/pw/ctrl/env | W | |
| D40E–D414 | Voice 3 freq/pw/ctrl/env | W | |
| D415–D418 | Filter/resonance/volume | W | D418 = master volume |
| D419 | POT X | R | Paddle X; used for FPGASID cookie |
| D41A | POT Y | R | Paddle Y; used for FPGASID cookie |
| D41B | OSC3 | R | Voice 3 oscillator MSB — key detection register |
| D41C | ENV3 | R | Voice 3 envelope |
| D41D–D41F | (write-only on real SID) | W | Echo registers on all modern clones |

---

## Appendix: Version History Relevant to Detection

| Version | Change |
|---------|--------|
| V1.2.27 | uSID64 two-read stability fix (double-read with $02 tolerance) |
| V1.2.32 | SwinSID Nano 3-retry Stage 1 + real-SID pre-check at Step 0.25 |
| V1.3.45 | ULTISID 7 filter curve variants; ULTISID display fixes |
| V1.3.58 | SIDKick Pico detection in SIDFX secondary (`sfx_probe_skpico`) |
| V1.3.59 | SIDFX early return in `sidstereostart` (fixes PDsid mirror overflow) |
| V1.3.60 | SwinSID Ultimate in SIDFX secondary (`sfx_probe_dis_echo`) |
| V1.3.61 | ARMSID in SIDFX secondary (same DIS probe, `$4E` echo) |
| V1.3.62 | Fix ARMSID secondary display: skip `print_sid_type_4` for SIDFX context |
| V1.3.63 | BackSID in SIDFX secondary (`checkbacksid` via `(sptr_zp),y` for D41B) |
| V1.3.64 | KungFuSID in SIDFX secondary (inline `$A5` ACK probe via `(sptr_zp),y`); `sfx_probe_dis_echo` rewritten to `(sptr_zp),y` (+30 bytes margin) |
| V1.3.66 | FPGASID in SIDFX secondary (SID2): call `checkfpgasid` with `sptr_zp` → secondary; no function changes needed |
| V1.3.67 | Data table relocated `$5600` → `$6000` (1536 bytes headroom); SID1=UNKN probe chain: FPGASID → SIDKick Pico → PD SID → DIS echo (SwinSID-U / ARMSID) |
| V1.3.68 | Fix probe ordering: `checkfpgasid` must run before `sfx_probe_skpico` (skpico dirty exit corrupts D41E, breaking FPGASID magic-cookie sequence) |
| V1.3.70 | Document FPGASID-in-SIDFX-SID1 as accepted hardware limitation; SIDFX POT masking and SCI reaction make it fundamentally undetectable |

---

*Source code: `siddetector.asm` (KickAssembler syntax)*
*Original ACME source: `siddetector.asm.acme.bak`*
*Original release: https://csdb.dk/release/?id=176909*
*Author: funfun/Triangle 3532*

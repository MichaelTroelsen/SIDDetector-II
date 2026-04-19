# Commodore SID 6581/8580 Register Reference

> Source: https://www.waitingforfriday.com/?p=661  
> Original Commodore 6581 datasheet, OCR'd and reformatted.

---

## Overview

The **6581 Sound Interface Device (SID)** is a single-chip, 3-voice electronic music synthesizer/sound effects generator compatible with the 65XX microprocessor family.

**Key features:**
- 3 Tone Oscillators (0–4 kHz range)
- 4 Waveforms per oscillator: Triangle, Sawtooth, Variable Pulse, Noise
- 3 Amplitude Modulators (48 dB range)
- 3 Envelope Generators (Attack 2ms–8s, Decay/Release 6ms–24s)
- Oscillator Synchronization & Ring Modulation
- Programmable Filter (30 Hz–12 kHz, 12 dB/octave)
- Master Volume Control
- 2 A/D POT Interfaces
- Random Number / Modulation Generator
- External Audio Input

---

## Register Map

Base address: **$D400** (C64). All registers are **WRITE-only** unless noted.

| Offset | Address | Name          | R/W | Description |
|--------|---------|---------------|-----|-------------|
| $00    | $D400   | FRELO1        | W   | Voice 1 Frequency Low byte |
| $01    | $D401   | FREHI1        | W   | Voice 1 Frequency High byte |
| $02    | $D402   | PWLO1         | W   | Voice 1 Pulse Width Low (bits 0–7) |
| $03    | $D403   | PWHI1         | W   | Voice 1 Pulse Width High (bits 8–11, upper 4 bits ignored) |
| $04    | $D404   | CR1           | W   | Voice 1 Control Register |
| $05    | $D405   | ATDCY1        | W   | Voice 1 Attack / Decay |
| $06    | $D406   | SUREL1        | W   | Voice 1 Sustain / Release |
| $07    | $D407   | FRELO2        | W   | Voice 2 Frequency Low byte |
| $08    | $D408   | FREHI2        | W   | Voice 2 Frequency High byte |
| $09    | $D409   | PWLO2         | W   | Voice 2 Pulse Width Low |
| $0A    | $D40A   | PWHI2         | W   | Voice 2 Pulse Width High |
| $0B    | $D40B   | CR2           | W   | Voice 2 Control Register |
| $0C    | $D40C   | ATDCY2        | W   | Voice 2 Attack / Decay |
| $0D    | $D40D   | SUREL2        | W   | Voice 2 Sustain / Release |
| $0E    | $D40E   | FRELO3        | W   | Voice 3 Frequency Low byte |
| $0F    | $D40F   | FREHI3        | W   | Voice 3 Frequency High byte |
| $10    | $D410   | PWLO3         | W   | Voice 3 Pulse Width Low |
| $11    | $D411   | PWHI3         | W   | Voice 3 Pulse Width High |
| $12    | $D412   | CR3           | W   | Voice 3 Control Register |
| $13    | $D413   | ATDCY3        | W   | Voice 3 Attack / Decay |
| $14    | $D414   | SUREL3        | W   | Voice 3 Sustain / Release |
| $15    | $D415   | FCLO          | W   | Filter Cutoff Frequency Low (bits 0–2) |
| $16    | $D416   | FCHI          | W   | Filter Cutoff Frequency High (bits 3–10) |
| $17    | $D417   | RESFIL        | W   | Resonance + Filter Voice Enable |
| $18    | $D418   | MODVOL        | W   | Filter Mode + Master Volume |
| $19    | $D419   | POTX          | **R** | POT X (A/D converter, updated every 512 cycles) |
| $1A    | $D41A   | POTY          | **R** | POT Y (A/D converter, updated every 512 cycles) |
| $1B    | $D41B   | OSC3/RANDOM   | **R** | Voice 3 Oscillator output (upper 8 bits) |
| $1C    | $D41C   | ENV3          | **R** | Voice 3 Envelope Generator output |
| $1D    | $D41D   | —             | —   | Unused (open bus / undefined) |
| $1E    | $D41E   | —             | —   | Unused (open bus / undefined) |
| $1F    | $D41F   | —             | —   | Unused (open bus / undefined) — used by clones as config register |

---

## Control Register (CR) Bit Definitions

Applies to $D404 (Voice 1), $D40B (Voice 2), $D412 (Voice 3):

| Bit | Name      | Description |
|-----|-----------|-------------|
| 0   | GATE      | 1 = start Attack/Decay/Sustain; 0 = start Release |
| 1   | SYNC      | Synchronise oscillator to Voice 3 (V1), V1 (V2), or V2 (V3) |
| 2   | RING MOD  | Ring modulate with adjacent oscillator (replaces Triangle) |
| 3   | TEST      | Reset and hold oscillator at zero (also silences noise) |
| 4   | TRI       | Triangle waveform enable |
| 5   | SAW       | Sawtooth waveform enable |
| 6   | SQU       | Square/Pulse waveform enable |
| 7   | NOI       | Noise waveform enable |

> **Note:** Multiple waveform bits can be set simultaneously for combined waveforms, but behaviour on real silicon differs between 6581 and 8580.

---

## Attack/Decay Register (ATDCY)

Upper nibble = Attack rate, Lower nibble = Decay rate:

| Value | Rate    |
|-------|---------|
| $0    | 2 ms    |
| $1    | 8 ms    |
| $2    | 16 ms   |
| $3    | 24 ms   |
| $4    | 38 ms   |
| $5    | 56 ms   |
| $6    | 68 ms   |
| $7    | 80 ms   |
| $8    | 100 ms  |
| $9    | 250 ms  |
| $A    | 500 ms  |
| $B    | 800 ms  |
| $C    | 1 s     |
| $D    | 3 s     |
| $E    | 5 s     |
| $F    | 8 s     |

> Decay and Release share the same table but Release rates are slightly longer (6ms–24s range).

---

## Sustain/Release Register (SUREL)

Upper nibble = Sustain level (0–15, linear), Lower nibble = Release rate (same table as Decay).

---

## Filter Registers

### $D415 — Filter Cutoff Low (bits 2–0)
### $D416 — Filter Cutoff High (bits 10–3)

11-bit value: `Fco ≈ Fn × (Fclk / 2^23)` (approximately 30 Hz – 12 kHz with standard 2200 pF caps).

### $D417 — Resonance / Filter Enable

| Bits | Description |
|------|-------------|
| 7–4  | Resonance (0 = minimum, 15 = maximum) |
| 3    | FILT EX — route External Input through filter |
| 2    | FILT 3  — route Voice 3 through filter |
| 1    | FILT 2  — route Voice 2 through filter |
| 0    | FILT 1  — route Voice 1 through filter |

### $D418 — Mode / Volume

| Bits | Description |
|------|-------------|
| 7    | 3 OFF — disconnect Voice 3 from output (useful for mod source only) |
| 6    | HP    — High-Pass filter output |
| 5    | BP    — Band-Pass filter output |
| 4    | LP    — Low-Pass filter output |
| 3–0  | VOL   — Master volume (0 = silent, 15 = maximum) |

---

## Read Registers

### $D419 — POTX / $D41A — POTY

Read potentiometer position (0–255). Updated every 512 clock cycles (~0.5 ms at 1 MHz). RC time constant: `RC ≈ 4.7 × 10⁻⁴ s` (47 kΩ + 10 nF recommended).

### $D41B — OSC3 / RANDOM

Reads upper 8 bits of Voice 3 oscillator phase accumulator. With Noise waveform selected ($D412 bit 7 = 1), acts as a pseudo-random number generator useful for vibrato, tremolo, or sound effects. Oscillator advances only when frequency > 0 and TEST bit = 0.

**Detection use:** On a real SID with Voice 3 running at non-zero frequency, this register changes every read. On NOSID it returns open-bus (typically $FF or last data bus value). On emulators and clones the behaviour varies — see below.

### $D41C — ENV3

Reads Voice 3 Envelope Generator output (0–255). Useful for dynamic filter modulation. Envelope advances only after GATE is set (bit 0 of $D412).

---

## Frequency Formula

```
Fout = (Fn × Fclk) / 16,777,216  Hz
```

At 1.0 MHz clock: `Fout = Fn × 0.05960464...  Hz`

Example: Middle C (261.63 Hz) → Fn = 4391 ($1127)

---

## 6581 vs 8580 Differences

| Feature | 6581 | 8580 |
|---------|------|------|
| Supply voltage | 12V + 5V | 9V + 5V |
| Filter capacitors | External 470pF | External 22nF |
| Filter character | Warm/resonant | Cleaner, more linear |
| Combined waveforms | Distinct artifacts | Different artifacts |
| Waveform DC offset | Present (6581 quirk) | Mostly absent |
| OSC3 open bits (7–5) | Read as 0 | Read as 0 |
| ENV3 open bits | Read as 0 | Read as 0 |
| D41D–D41F | Open bus ($FF or floating) | Open bus ($FF or floating) |

---

## Open Bus / NOSID Behaviour

Registers $D41D, $D41E, $D41F are **not implemented** on real SID chips. On real hardware the data bus floats or retains the last value driven onto it. Typical return values:

- **Real SID (6581/8580):** $D41F reads back $FF or the last byte on the data bus (unpredictable, varies with bus loading)
- **NOSID (no chip):** $D41F typically returns $FF (pull-up on data bus lines) or $7F
- **VICE ResID/FastSID:** Emulates open bus — returns $00 or $FF depending on version
- **uSID64:** Returns values in the $Fx range (high nibble = $F, top 4 bits always set) — see probe results

---

## SID Clone / Emulator Detection Summary

| Chip / Device | Detection Register | Method |
|---------------|-------------------|--------|
| 6581 R2/R3/R4 | $D41B (OSC3) | Sawtooth waveform readback + $D418 decay |
| 8580           | $D41B (OSC3) | Different decay rate from 6581 |
| ARMSID        | $D41D (echo) | Write "DIS"/"WOR" pattern, read back |
| ARM2SID       | $D41D (echo) | Version string readback |
| FPGASID       | $D41D + $F51D | Magic cookie + address readback |
| SwinsidU      | $D41D (echo) | Echo pattern |
| Swinsid Nano  | Elimination | Not responding to magic keys |
| uSID64        | $D41F top nibble | Bits 7–4 always = $F (with V3 silenced) |
| NOSID         | $D41B / $D41C | No oscillator advance, static value |
| VICE ResID    | $D418 decay | Specific decay timing fingerprint |
| VICE FastSID  | $D418 decay | Different decay timing fingerprint |

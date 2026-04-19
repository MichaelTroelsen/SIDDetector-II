# SID Chips and Replacements — Complete Reference

Reference for every SID variant detected by SID Detector v1.3.58, plus chips with placeholder screen rows. Covers the original hardware, all known clones and emulators, and how the detection code identifies each one.

> **Note on links:** Retro hardware websites move frequently. All links were current at time of writing — verify before purchasing.

---

## Table of contents

| # | Chip | Type | `data1` code |
|---|------|------|-------------|
| 1 | [MOS 6581](#1-mos-6581) | Real chip | `$01` |
| 2 | [MOS/CSG 8580](#2-moscsg-8580) | Real chip | `$02` |
| 3 | [ARMSID](#3-armsid) | ARM clone | `$05` |
| 4 | [ARM2SID](#4-arm2sid) | ARM clone (dual) | `$05` + `data3=$53` |
| 5 | [FPGASID](#5-fpgasid) | FPGA clone | `$06` / `$07` |
| 6 | [SwinSID Ultimate](#6-swinsid-ultimate) | AVR clone | `$04` |
| 7 | [SwinSID Nano](#7-swinsid-nano) | AVR clone | `$08` |
| 8 | [SwinSID Micro](#8-swinsid-micro) | AVR clone | — (disabled) |
| 9 | [ULTISID (U64)](#9-ultisid-u64) | FPGA (built-in) | `$20` / `$21` |
| 10 | [SIDFX](#10-sidfx) | Add-on cartridge | `$30` |
| 11 | [VICE ResID](#11-vice-resid) | Emulator | decay fingerprint |
| 12 | [VICE FastSID](#12-vice-fastsid) | Emulator | decay fingerprint |
| 13 | [HOXS64](#13-hoxs64) | Emulator | decay fingerprint |
| 14 | [Frodo](#14-frodo) | Emulator | decay fingerprint |
| 15 | [YACE64](#15-yace64) | Emulator | decay fingerprint |
| 16 | [EMU64](#16-emu64) | Emulator | decay fingerprint |
| 17 | [SIDKick](#17-sidkick) | RP2040 clone | screen row only |
| 18 | [BackSID](#18-backsid) | ARM clone | screen row only |
| 19 | [PD SID](#19-pd-sid) | Open-source clone | screen row only |
| 20 | [KungFuSID](#20-kungfusid) | ARM Cortex-M4 clone | screen row only |
| 21 | [uSID64](#21-usid64) | STM32 clone | `$0D` |

---

## Real SID Chips

---

### 1. MOS 6581

**Type:** Original Commodore SID chip (1982–1989)
**Package:** DIP-28
**Voltage:** 12 V (requires ±12 V supply — older C64 boards)
**Sub-revisions detected:** R2, R3, R4, R4AR

The first production SID. Known for its warm, gritty sound caused by a manufacturing quirk in the filter. Revisions differ in subtle filter resonance characteristics, which the detector maps using the `MODE6581` look-up table after the `$D41B` readback test.

**Detection method (`checkrealsid`):**
1. Write `$48` (gate bit set) to D412 (voice 3 control)
2. Shift right and write to D412 to activate sawtooth waveform
3. Read D41B (voice 3 oscillator output) — a real SID echoes a predictable value; open sockets and emulators do not
4. Read D41B a second time; compare against `$03` to confirm
5. Compare the D41B value sequence against `MODE6581` table to identify sub-revision
6. Set `data1 = $01`

```asm
// checkrealsid (siddetector.asm ~line 787)
lda #$48
crs_d412:  sta $d412        // gate on
crs_d40f:  sta $d40f
lsr                         // activate sawtooth
crs_d412_1: sta $d412
crs_d41b:   lda $d41b       // read OSC3 output
tax
and #$fe
bne unknownSid              // not 0 or 1 → not real SID
crs_d41b_1: lda $d41b
cmp #$03                    // 6581 and 8580 both return $03 here
```

**Where to buy (real chip, used):**
- [eBay — search "MOS 6581"](https://www.ebay.com/sch/i.html?_nkw=MOS+6581)
- [Retro Innovation (US)](https://www.go4retro.com)
- [Restore-Store (EU)](https://restore-store.de)
- [Individual Computers / iComp (EU)](https://icomp.de)

**Forum64 discussion:**
- [forum64.de — search: 6581](https://www.forum64.de/index.php?lexikon/index/)

**CSDB:**
- [csdb.dk — search: 6581](https://csdb.dk/search/?seinput=6581&type=all)

---

### 2. MOS/CSG 8580

**Type:** Revised Commodore SID chip (1987–1994)
**Package:** DIP-28
**Voltage:** 9 V (requires 9 V supply — later C64C and C128 boards)
**Sub-revisions detected:** standard 8580

Redesigned filter with cleaner, brighter sound. Has reduced filter distortion compared to 6581. Many musicians prefer the 6581 for its character; 8580 is more accurate but "thinner". The two chips are not drop-in compatible without a voltage regulator.

**Detection method (`checkrealsid`):**
Same OSC3 readback sequence as 6581. After the `$03` comparison passes, the D41B value sequence is compared against `MODE8580` table instead of `MODE6581`. Set `data1 = $02`.

**Where to buy (real chip, used):**
- [eBay — search "MOS 8580"](https://www.ebay.com/sch/i.html?_nkw=MOS+8580)
- [Retro Innovation (US)](https://www.go4retro.com)
- [Restore-Store (EU)](https://restore-store.de)

**CSDB:**
- [csdb.dk — search: 8580](https://csdb.dk/search/?seinput=8580&type=all)

---

## Modern Replacements

---

### 3. ARMSID

**Type:** Drop-in SID replacement based on ARM Cortex-M4
**Package:** DIP-28 adapter
**Processor:** STM32F410 ARM Cortex-M4 @ 100 MHz (hardware floating-point)
**Audio:** AD8515 op-amp, 12-bit DAC, ~62 kHz sampling (1/16 C64 bus clock)
**Voltage:** 6581/8580 mode auto-detected from supply voltage (threshold adjustable: 10.5 V or ~2 V); both PAL and NTSC supported
**Current firmware:** 2.17 (2026-02-21)

Emulates both 6581 and 8580 with automatic mode selection from supply voltage. Uses floating-point arithmetic for digital filter emulation. Firmware updates are applied from within the C64. Register writes and reads pass through the real bus, producing the distinctive echo behaviour the detector uses.

**Detection method (`Checkarmsid`):**

The routine exploits the fact that ARMSID echoes back write values in its voice-3 registers. Real SID chips do not provide readable register echo from most registers.

1. Zero all SID registers and zero-page scratch (`data1`, `data2`)
2. Wait for stable bus conditions (two `loop1sek` delays)
3. Write `'D'` ($44) to D41F, `'I'` ($49) to D41E, `'S'` ($53) to D41D
4. Wait two more `loop1sek` delays
5. Read D41B: `'S'` ($53) → Swinsid; `'N'` ($4E) → ARMSID family; other → unknown
6. Read D41C into `data2` (should be `'O'` = $4F for ARMSID)
7. Read D41D into `data3` (should be `'R'` = $53 for ARM2SID, else plain ARMSID)
8. Set `data1 = $05`

```asm
// Checkarmsid key reads (siddetector.asm ~line 658)
cas_d41B:  lda $D41b       // 'S'=$53 → Swinsid; 'N'=$4E → ARMSID family
cas_d41C:  lda $D41c       // 'O'=$4F for both ARMSID variants
cas_d41d7: lda $D41D       // 'R'=$53 → ARM2SID; other → plain ARMSID
```

> The self-modifying code at the start of `Checkarmsid` patches the high byte of all `cas_dXXX` labels at runtime so the same routine works for secondary SID slots (D500, D600, etc.).

**Where to buy:**
- [retrocomp.cz — official shop](https://www.retrocomp.cz)

**Official page:**
- [nobomi.cz — ARMSID](https://www.nobomi.cz/8bit/armsid/index_en.php)

**Forum64:**
- [forum64.de — search: ARMSID](https://www.forum64.de/index.php?search/&q=ARMSID)

**CSDB:**
- [csdb.dk — search: ARMSID](https://csdb.dk/search/?seinput=ARMSID&type=all)

---

### 4. ARM2SID

**Type:** Dual ARM SID replacement (stereo successor to ARMSID)
**Package:** DIP-28 adapter with expansion connector for second socket
**Processor:** STM32F446 @ 180 MHz (~2× faster than ARMSID; 2× FLASH, 4× RAM)
**Audio:** 2× 12-bit DAC, AD8646 stereo amplifier
**Voltage:** Both 6581 and 8580 modes selectable (manual or automatic from supply voltage)
**Current firmware:** 3.17 (2026-02-21)

ARM2SID can replace up to three chips simultaneously from one DIP-28 socket. It emulates two independent SID cores (configurable addresses) plus optionally an SFX sound expander or OPL2 FM synthesis (FM-YAM clone). Firmware updates are applied from within the C64/C128 using the configuration utility (`asid_t317.prg`).

**Supported SID addresses:** D400, D420, D500, D520, DE00, DE20, DF00, DF20

**Configuration options (via `asid_t317.prg`):**
- Chip type: 6581, 8580, or automatic (from supply voltage)
- Filter strength (6581: −7 to +7 steps; 8580: 3–12 kHz tuning)
- Digifix, ADSR bug correction, mono downmix, channel extension

**Detection method:**

Identical to ARMSID up through reading D41B (`'N'`) and D41C (`'O'`). The additional step:

- Read D41D into `data3`
- If `data3 = 'R'` ($53) → **ARM2SID** confirmed
- Else → plain ARMSID

```asm
// armsid dispatch (siddetector.asm ~line 275)
ldx data3
cpx #$53               // 'R' = ARM2SID
bne armsidlo           // not 'R' → plain ARMSID
// ARM2SID path:
lda #<arm2sidf
ldy #>arm2sidf
jsr $AB1E
```

`data1 = $05` (same as ARMSID; `data3 = $53` is the discriminator)

**Stereo SID detection:**

After identifying ARM2SID, the detector calls `armsid_get_version` which queries the chip's internal memory map via the configuration protocol (D41F←`'d'`, D41E←`'i'`, D41D←`'s'`). The map is returned as four nibble-packed bytes stored in `armsid_map_l/l2/h/h2`:

| Byte | Low nibble | High nibble |
|------|-----------|------------|
| `armsid_map_l` | Slot 0 (D400) | Slot 1 (D420) |
| `armsid_map_l2` | Slot 2 (D500) | Slot 3 (D520) |
| `armsid_map_h` | Slot 4 (DE00) | Slot 5 (DE20) |
| `armsid_map_h2` | Slot 6 (DF00) | Slot 7 (DF20) |

Nibble values: `0` = NONE, `1` = SIDL, `2` = SIDR, `3` = SFX-, `4` = SID3.

The stereo list (`sid_list`) is populated directly from this map by `arm2sid_populate_sid_list` — an unrolled routine that checks each of the 7 secondary slots and adds non-NONE entries. This approach is state-independent and gives identical results on cold boot and warm restart, unlike the noise-oscillator probing used for other chip types.

**Where to buy:**
- [retrocomp.cz — official shop](https://www.retrocomp.cz)

**Official page:**
- [nobomi.cz — ARM2SID](https://www.nobomi.cz/8bit/arm2sid/index_en.php)

**Forum64:**
- [forum64.de — search: ARM2SID](https://www.forum64.de/index.php?search/&q=ARM2SID)

**CSDB:**
- [csdb.dk — search: ARM2SID](https://csdb.dk/search/?seinput=ARM2SID&type=all)

---

### 5. FPGASID

**Type:** FPGA-based SID replacement
**Package:** DIP-28 adapter, pin-compatible with both 6581 and 8580 sockets
**Implementation:** Full FPGA (not software emulation) — cycle-exact digital logic plus analogue circuit modelling
**Price:** 79.99 € (inc. 19% VAT)
**Current firmware:** v0A (ConfiGuru config tool: v0.D)

Provides two fully independent SID cores from one socket, supporting 6-voice stereo or mixed mono output. 8-bit sample digitisation and playback, paddle and 1351 mouse support, and full EXTIN analogue input. Up to two configuration sets are saved permanently in onboard flash. Firmware updates are applied from within the C64 via floppy disk (~20 min on a standard 1541; a few minutes with JiffyDOS).

**SID2 address options:** D420, D500, DE00 (DE00 is write-only to avoid conflicts with expansion modules)

**Chip mode options (per SID core):**
- 6581 mode — nonlinear DACs, volume-register digitised sound; filter bias adjustable −8 to +7
- 8580 mode — linear DACs, digifix for digital audio playback
- Mixed waveform behaviour switchable between 6581 and 8580 models

**Audio output modes:** Dual (SID1 → ch1, SID2 → ch2) or Mix (SID1+SID2 → both channels)

**Device ID:** `$F51D` — this is the value the detector reads back from the identify sequence (D41A:D419 = `$F5`:`$1D`)

**Detection method (`checkfpgasid`):**

1. Write magic cookie: `$81` to D419, `$65` to D41A (enters FPGASID config mode)
2. Set bit 7 of D41E (`%10000000`) to activate the identify mode
3. Read D419 back: must be `$1D`
4. Read D41A back: must be `$F5`
   → Combined signature: `$F51D` — FPGASID device ID
5. Read D41F to determine chip model:
   - `$3F` → 8580 emulation mode → `data1 = $06`
   - `$00` → 6581 emulation mode → `data1 = $07`
6. Clear magic cookie (write `$00` to D419 and D41A) to exit config mode

```asm
// checkfpgasid (siddetector.asm ~line 746)
lda #$81
cfs_D419: sta $D419      // magic cookie byte 1
lda #$65
cfs_D41A: sta $D41A      // magic cookie byte 2
lda %10000000
cfs_D41E: sta $d41e      // set identify bit
cfs_D419_1: lda $D419
cmp #$1D                 // signature low byte
bne fpgasidf_nosound
cfs_D41A_1: lda $D41A
cmp #$F5                 // signature high byte ($F51D = FPGASID device ID)
bne fpgasidf_nosound
cfs_D41F: lda $D41f
cmp #$3f                 // $3F = 8580 mode, $00 = 6581 mode
```

**Where to buy:**
- [Kryoflux webstore](https://webstore.kryoflux.com/catalog/product_info.php?products_id=63)

**Official site:**
- [fpgasid.de](https://www.fpgasid.de)
- [fpgasid.de/documentation](https://www.fpgasid.de/documentation)
- [fpgasid.de/configuru](https://www.fpgasid.de/configuru)

**GitHub:**
- No public source repository (closed firmware)

**Forum64:**
- [forum64.de — search: FPGASID](https://www.forum64.de/index.php?search/&q=FPGASID)

**CSDB:**
- [csdb.dk — search: FPGASID](https://csdb.dk/search/?seinput=FPGASID&type=all)

---

### 6. SwinSID Ultimate

**Type:** ATmega-based SID replacement
**Package:** DIP-28 adapter
**Voltage:** Both 6581 and 8580 modes
**Compatibility:** Good; hardware-timed register echo

Uses an Atmel AVR ATmega microcontroller clocked at high frequency to emulate SID timing. Like ARMSID, it echoes written register values back through readable registers. The echo pattern for SwinSID Ultimate differs from ARMSID at D41B.

**Detection method:**

Same `Checkarmsid` routine as ARMSID. The difference is in the D41B readback:

- D41B = `'S'` ($53) → **SwinSID Ultimate** (`data1 = $04`)
- D41B = `'N'` ($4E) → ARMSID family

```asm
// Checkarmsid D41B read (siddetector.asm ~line 660)
cas_d41B: lda $D41b      // read back voice-3 D register
cmp #$53                 // 'S' = Swinsid Ultimate
bne ch_s_1
lda #$04
sta data1
```

**Where to buy:**
- Search eBay: "SwinSID Ultimate"
- [Restore-Store (EU)](https://restore-store.de)

**GitHub:**
- Search GitHub: `swinsid ultimate`

**Forum64:**
- [forum64.de — search: SwinSID](https://www.forum64.de/index.php?search/&q=SwinSID)

**CSDB:**
- [csdb.dk — search: SwinSID](https://csdb.dk/search/?seinput=SwinSID&type=all)

---

### 7. SwinSID Nano

**Type:** Smaller AVR-based SID replacement (no through-hole pad)
**Package:** Surface-mount adapter to DIP-28
**Voltage:** Configurable
**Compatibility:** Good for most software

Smaller and cheaper than SwinSID Ultimate. No magic-key echo protocol. Detected by a dual-frequency oscillator test on D41B (sawtooth waveform, voice 3).

**Detection method (`checkswinsidnano`):**

Two-step oscillator frequency response test:

1. **Slow frequency ($0001):** The oscillator accumulator advances by 1 per clock cycle. In ~6 ms the upper 8 bits (D41B) do not move. Two reads must be **identical**. A NOSID with random bus behaviour produces differing reads → rejected.

2. **Fast frequency ($FFFF):** Accumulator advances 65535 per cycle. In ~6 ms D41B cycles through all 256 values many times. Two reads must **differ**. A NOSID with deterministic bus behaviour (bus holds `$D4`, the high byte of the absolute `lda $D41B` opcode) gives identical reads → rejected.

Only a real oscillating chip passes both steps.

```asm
// siddetector.asm — checkswinsidnano
// Step 1: freq=$0001, two lda $D41B reads 6ms apart → must be same
// Step 2: freq=$FFFF, two lda $D41B reads 6ms apart → must differ
```

**Where to buy:**
- Search eBay: "SwinSID Nano"
- [Restore-Store (EU)](https://restore-store.de)

**Forum64:**
- [forum64.de — search: SwinSID Nano](https://www.forum64.de/index.php?search/&q=SwinSID+Nano)

---

### 8. SwinSID Micro

**Type:** Ultra-compact SwinSID (no-pad SMD variant)
**Package:** Tiny SMD, requires adapter
**Detection status:** Reserved (`data1 = $08`) but detection disabled

Detection of SwinSID Micro was partially implemented via `checkswinmicro` but disabled because it produced false positives on boards with an empty SID socket. The routine is preserved in the code as dead code after an unconditional `jmp nosound`.

**Detection method:** Currently not active. See TODO.md.

---

### 9. ULTISID (U64)

**Type:** Built-in SID emulation in the Ultimate 64 FPGA board
**Package:** Not a DIP chip — integrated in the U64 main board
**Voltage:** N/A (integrated)
**Compatibility:** Very high; developed alongside the cartridge firmware

The Ultimate 64 (U64) is a full C64 replacement board that includes FPGA-based SID emulation. ULTISID refers to this internal emulation. The detector identifies it using a different code path from the external chips.

`data1 = $20` → ULTISID 8580 mode
`data1 = $21` → ULTISID 6581 mode

**Where to buy:**
- [ultimate64.com — official shop](https://ultimate64.com)

**GitHub:**
- [github.com/GideonZ/1541ultimate](https://github.com/GideonZ/1541ultimate)

**Forum64:**
- [forum64.de — search: Ultimate 64](https://www.forum64.de/index.php?search/&q=Ultimate+64)

**CSDB:**
- [csdb.dk — search: Ultimate 64](https://csdb.dk/search/?seinput=ultimate+64&type=all)

---

### 10. SIDFX

**Type:** External SID enhancement cartridge (sits on top of the SID chip)
**Package:** Piggyback board on DIP-28 SID
**Voltage:** Powered by the SID socket
**Compatibility:** Works alongside real SID chip (does not replace it)

SIDFX adds features like stereo, envelope extensions, and distortion effects to an existing SID chip. It has an internal SCI (Serial Control Interface) state machine accessible via D41E/D41F register pins. The detector uses the SCI protocol to identify it.

**Detection method (`DETECTSIDFX`):**

Uses a full SCI serial handshake:

1. Send 16 × `SCISYN` sync commands to bring SIDFX state machine to idle
2. Send PNP login: `$80`, `'P'` ($50), `'N'` ($4E), `'P'` ($50)
3. Read back 4 bytes: vendor ID LSB, vendor ID MSB, product ID LSB, product ID MSB
4. Check signature: `$45`, `$4C`, `$12`, `$58` → SIDFX confirmed → `data1 = $30`
5. Any mismatch → `data1 = $31` (not present)

```asm
// DETECTSIDFX (siddetector.asm ~line 993)
lda #$80 : jsr SCIPUT    // PNP header
lda #$50 : jsr SCIPUT    // 'P'
lda #$4e : jsr SCIPUT    // 'N'
lda #$50 : jsr SCIPUT    // 'P'
jsr SCIGET               // read vendor ID LSB
// ...
lda #$45 : cmp PNP+0 : bne NOSIDFX   // 'E'
lda #$4c : cmp PNP+1 : bne NOSIDFX   // 'L'
lda #$12 : cmp PNP+2 : bne NOSIDFX
lda #$58 : cmp PNP+3 : beq SIDFXFOUND  // 'X'
```

**SCI serial protocol:** Each byte is shifted out MSB-first via D41E (data bit) and D41F (clock bit) using the `SCIPUT` / `SCIGET` routines.

**Where to buy:**
- [sidfx.dk — official site](https://www.sidfx.dk)
- Search eBay: "SIDFX C64"

**Forum64:**
- [forum64.de — search: SIDFX](https://www.forum64.de/index.php?search/&q=SIDFX)

**CSDB:**
- [csdb.dk — search: SIDFX](https://csdb.dk/search/?seinput=SIDFX&type=all)

---

## Emulators (software SID)

Emulators are identified by the `$D418` volume register decay fingerprint. The detector sets `D418 = $1F`, waits, and counts how many cycles elapse before it reaches zero. This rate differs between emulation cores. Six samples are taken and averaged via `ArithmeticMean`. The result is compared against the `MODE6581` / `MODE8580` / `MODEUNKN` tables in `checktypeandprint`.

---

### 11. VICE ResID

Cycle-accurate reSID emulation library. Two variants detected:
- `VICE3.3 RESID FS 8580` — reSID in 8580 mode with filter simulation
- `VICE3.3 RESID FS 6581` — reSID in 6581 mode

**GitHub:** [github.com/drfiemost/vice-emu](https://github.com/drfiemost/vice-emu)
**Official site:** [vice-emu.sourceforge.io](https://vice-emu.sourceforge.io)

---

### 12. VICE FastSID

Simplified, faster SID core in VICE. Less accurate filter than reSID but lower CPU load.
Detected as: `VICE3.3 FASTSID`

**GitHub:** same as VICE above

---

### 13. HOXS64

Windows-only C64 emulator with its own SID core.
**Official site:** [hoxs64.net](https://www.hoxs64.net)

---

### 14. Frodo

Classic multi-platform C64 emulator.
**GitHub:** [github.com/cebix/frodo4](https://github.com/cebix/frodo4)

---

### 15. YACE64

Yet Another C64 Emulator. Detected by its unique `$D418` decay rate.

---

### 16. EMU64

Another C64 emulator variant. Detected by decay fingerprint.

---

## Chips With Screen Rows (Detection Pending)

The following chips have dedicated rows on the main screen and browsable info pages (via the I key), but no active hardware detection probe yet. The rows exist as placeholders; the detection routine does not currently populate them.

---

### 17. SIDKick

**Type:** SID replacement based on Raspberry Pi Pico (RP2040 microcontroller)
**Package:** DIP-28 adapter
**Voltage:** 3.3 V logic, 5 V tolerant via level shifter
**Status:** Active open-source project
**Screen row:** 14 (`sidkick....:`)

Uses the RP2040 dual-core processor running a SID emulation core. The second core handles cycle-accurate bus timing while the first core handles audio output. Source code is publicly available.

**Detection status:** No unique register signature confirmed yet. SIDKick may exhibit register echo similar to ARMSID/SwinSID (firmware-dependent). If it echoes a unique byte sequence into voice-3 registers, the existing `Checkarmsid` framework can be extended. **Requires hardware testing.**

**GitHub:**
- Search GitHub: `sidkick c64 pico`

**Forum64:**
- [forum64.de — search: SIDKick](https://www.forum64.de/index.php?search/&q=SIDKick)

**CSDB:**
- [csdb.dk — search: SIDKick](https://csdb.dk/search/?seinput=SIDKick&type=all)

---

### 18. BackSID

**Type:** Drop-in SID replacement by BackBit
**Package:** DIP-28 — plugs directly into any C64, C64C, C128, or C128DCR SID socket; no adapter
**Processor:** ARM Cortex-M4 (specific part unpublished; closed hardware)
**Audio:** Burr-Brown op-amp output stage; dedicated analog circuit for POT X/Y (true paddle, mouse, KoalaPad support)
**Voltage:** Auto-detected from supply (9 V → 8580 mode, 12 V → 6581 mode; no jumper required)
**Price:** $39 USD
**Screen row:** 16 (`backsid....:`)

BackSID targets cycle-accurate SID reproduction with authentic analog POT support (a hardware differentiator from SwinSID Nano, which omits the analog section). The V2 hardware generation offers 2× sampling rate and 4× filter accuracy over V1.

**Hardware revisions:**

| Rev | Notes |
|-----|-------|
| V1 Rev 1 | Original; firmware up to 2.2.3 |
| V1 Rev 2 | Improved potentiometer accuracy (FW 2.0.0+) |
| V1 Rev 3 | KoalaPad and mouse support (FW 2.1.0+) |
| V2 | Current generation; 2× sample rate, 4× filter accuracy; requires FW 3.0.0+ |

**Firmware version history:**

| Version | Change |
|---------|--------|
| 3.0.0 | V2 hardware support; V1 no longer supported |
| 2.2.3 | Eased sound triggers (Ghosts 'N Goblins fix) |
| 2.2.2 | Fixed Robotron 2084 sound triggers |
| 2.2.1 | Reduced overall distortion |
| 2.2.0 | Auto or Koala pot option (rev 3 hardware) |
| 2.1.2 | Improved SYNC distortion |
| 2.1.1 | Fixed high-frequency filter glitch in 6581 mode |
| 2.1.0 | Hardware revision 3 support |
| 2.0.3 | 5 V on VDD support |
| 2.0.2 | Reduced filter distortion |
| 2.0.1 | Fixed paddle/harness pot range for revision 2 |
| 2.0.0 | Hardware revision 2; improved potentiometer accuracy |
| 1.0.7 | Fixed low-frequency noise dropout (Jumpman intro) |
| 1.0.6 | KoalaPad support (newer hardware only) |
| 1.0.5 | Improved paddle range for Atari paddles |
| 1.0.4 | Fixed paddle and diagnostic support |
| 1.0.3 | Improved register timing (NTSC blip fix) |
| 1.0.2 | Mouse support (newer hardware only) |
| 1.0.1 | True random number generator (Paradroid fix) |
| 1.0.0 | First public release |

**Detection status:** BackSID has **no published software identification mechanism**. It is intentionally transparent — it presents to software as a real 6581 or 8580 depending on supply voltage. No echo register, magic cookie, or identification sequence has been documented. The C64 Reloaded Mk2 board could not identify it at all until a 1 kΩ resistor was added between SID socket pins 25 and 26. Contacting BackBit directly would be required to determine whether FW 3.x for V2 hardware exposes any identification register.

**Where to buy:**
- [store.backbit.io — BackSID product page](https://store.backbit.io/product/backsid/)
- [newstuffforoldstuff.com](https://newstuffforoldstuff.com/display_product.py?pid=247)

**Firmware downloads:**
- [backbit.io/downloads/Firmware/BackSID/](https://backbit.io/downloads/Firmware/BackSID/)
- [Revisions.txt](https://backbit.io/downloads/Firmware/BackSID/Revisions.txt)

**GitHub:**
- No public repository (closed hardware and firmware)
- [github.com/evietron/BackBit-OpenSource](https://github.com/evietron/BackBit-OpenSource) — other BackBit open-source projects (not BackSID)

**Forum:**
- [forum.backbit.io](https://forum.backbit.io) (login required)
- [forum64.de — search: BackSID](https://www.forum64.de/index.php?search/&q=BackSID)

**CSDB:**
- [csdb.dk — search: BackSID](https://csdb.dk/search/?seinput=BackSID&type=all)

---

### 19. PD SID

**Type:** Open-source / public domain SID clone (category name)
**Package:** Varies by implementation
**Status:** Community project(s); build-it-yourself
**Screen row:** 15 (`pd sid.....:`)

PD SID is an umbrella label for open-source or freely available SID chip substitutes — various hobbyist designs using microcontrollers or FPGA targets depending on the specific implementation.

**Detection status:** Register behaviour is configurable by the builder. Detection depends on which firmware is flashed. If a reference firmware implements a specific echo pattern or identification register, a dedicated check can be added. **Requires identifying canonical firmware behaviour.**

**GitHub:**
- Search GitHub: `public domain sid c64`

**Forum64:**
- [forum64.de — search: PD SID](https://www.forum64.de/index.php?search/&q=pd+sid)

**CSDB:**
- [csdb.dk — search: pd sid](https://csdb.dk/search/?seinput=pd+sid&type=all)

---

### 20. KungFuSID

**Type:** Open-source ARM Cortex-M4 SID replacement
**Package:** DIP-28 footprint PCB — plugs directly into the SID socket; no adapter
**Processor:** STM32F405RGT6 or GD32F405RGT6 @ 168 MHz (ARM Cortex-M4 with FPU)
**Audio:** Internal 12-bit DAC (PA5), LM321 op-amp output buffer; ~62 kHz sample rate (1 MHz / multiplier 16)
**Voltage:** Auto-detected from supply via ADC on PA4 (resistor divider from SID VDD); threshold 2235 → above = 6581, below = 8580
**Screen row:** 17 (`kungfusid..:`)
**Status:** Active open-source project; latest release v0.2.3 (2026-03-15)

KungFuSID is an open hardware design derived from the SwinSID PCB (Tolaemon) and the UltiSID project. The firmware is based on the Kung Fu Flash bus handler and an STM32 SID player core. Both STM32F405 and GD32F405 are supported with the same firmware. The PCB includes KiCad design files and JLCPCB BOM/placement files.

**SID register map (32 registers, $D400–$D41F only — A5 must be clear):**

| Reg | Addr | Purpose |
|-----|------|---------|
| 0–24 | $D400–$D418 | Standard SID (voices, filter, volume) — write only |
| 25–26 | $D419–$D41A | POTX/POTY — read (returns 0; paddles not implemented) |
| 27 | $D41B | OSC3 / random — read |
| 28 | $D41C | ENV3 — read |
| **29** | **$D41D** | **Firmware update register** — write `$A5` to start update; read `$5A` as ACK |
| 30–31 | $D41E–$D41F | Spare — read returns 0 |

**Filter emulation:**
- 6581 mode: filter ceiling 12500 Hz
- 8580 mode: filter ceiling 16000 Hz
- Filter curves are linear (not hardware-accurate); some complex tunes do not play correctly

**Known limitations:**
- No paddle support (POTX/POTY always return 0)
- No manual 6581/8580 runtime switch (auto-detect only at boot)
- Not cycle-exact (~62 kHz sample rate vs 1 MHz bus)
- Some tunes have accuracy issues

**Detection status:** No published identification register. KungFuSID is transparent to software — it presents as a real 6581 or 8580 depending on supply voltage. However, **register 29 (`$D41D`) is the firmware-update trigger** (write `$A5` → read `$5A` ACK). This could potentially serve as a detection probe with a non-destructive read pattern, but this has not been tested. The `$D418` decay fingerprint may also differ due to the ~62 kHz sample rate; empirical testing on hardware would be needed to confirm.

**GitHub (open hardware + firmware):**
- [github.com/Sgw32/KungFuSID](https://github.com/Sgw32/KungFuSID)

**Related projects:**
- [Kung Fu Flash (base bus handler)](https://github.com/KimJorgensen/KungFuFlash)

**Where to buy:**
- [AmiBay forum thread](https://www.amibay.com/threads/kungfusid-sid-chip-emulator.2449119/) — ~€22 per unit

**Forum64:**
- [forum64.de — search: KungFuSID](https://www.forum64.de/index.php?search/&q=KungFuSID)

---

## How the detection code is structured

The detector in `siddetector.asm` runs a sequential chain. The first step that positively identifies a chip stops the chain and prints the result. Steps that find nothing fall through to the next step.

```
DETECTSIDFX
    │ data1=$30 → SIDFX FOUND
    │ else ↓
Checkarmsid (D41B echo test)
    │ 'S' → SwinSID Ultimate
    │ 'N'+'O'+'R' → ARM2SID
    │ 'N'+'O'+other → ARMSID
    │ else ↓
checkfpgasid (magic-cookie $F51D)
    │ $3F → FPGASID 8580
    │ $00 → FPGASID 6581
    │ else ↓
checkrealsid (sawtooth D41B readback)
    │ $01 → 6581 (+ sub-revision from MODE6581 table)
    │ $02 → 8580
    │ else ↓
checksecondsid (noise-mirror scan D41B × 10)
    │ $10 → second SID found at mirror address
    │ else ↓
nosound
    → data1=$F0 → NO SID

(after any positive result:)
calcandloop → $D418 decay fingerprint → emulator identification
```

The full test suite in `tests/test_suite.asm` covers all dispatch branches in this chain (23 test cases). Hardware-dependent probes (the actual register reads from real chips) require physical hardware to test.

---

---

### 21. uSID64

**Type:** STM32-based SID emulator (DIP-28 replacement)
**Package:** DIP-28
**Voltage:** 5V compatible
**`data1` code:** `$0D`

A SID emulator using an STM32 ARM microcontroller. Firmware configurable via a D41F register protocol — mode (auto/6581/8580/stereo), chip model, and other settings can be set without physical dip switches.

**Detection method (`checkusid64`):**

The uSID64 exposes a writable config register at D41F that echoes back a stable status byte after the unlock sequence `$F0 $10 $63 $00 $FF`. A real uSID64 holds this value stably; a floating NOSID bus decays from the written `$FF`.

Two reads of D41F after the sequence must:
1. Both be in the `$E0–$FC` range (not `$FF`)
2. Agree within `$02` of each other (stable — the chip is driving the bus)

A decaying bus either stays at `$FF` (rejected immediately) or drifts — two reads taken 3 ms apart will differ by more than `$02` (rejected by stability check).

```asm
// siddetector.asm — checkusid64
// Write $F0,$10,$63,$00,$FF to $D41F
// Read $D41F twice, 3ms apart
// Both must be in $E0-$FC AND differ by ≤$02
```

**Config tool protocol:**
The official SID_Config_Tool writes `$F0 $10 $63 <mode> $FF` to D41F:
- `$00` = auto
- `$01` = mono
- `$02`–`$04` = stereo (various configs)
- `$06` = force 6581
- `$08` = force 8580

**Screen row:** 14 (`USID64.....:`)

---

## See also

- [SID Detector on CSDB](https://csdb.dk/release/?id=176909)
- [SID chip on Wikipedia](https://en.wikipedia.org/wiki/MOS_Technology_6581)
- [C64 wiki — SID](https://www.c64-wiki.com/wiki/SID)
- [High Voltage SID Collection (HVSC)](https://hvsc.de)
- [forum64.de](https://www.forum64.de) — primary C64 hardware discussion community

# SID Detector — Memory Map

**Version:** V1.3.58  
**Assembler:** KickAssembler  
**Build output:** code $2400–$555C (164-byte margin to data segment), data $5600–$823E

---

## Zero Page ($0000–$00FF)

| Address | Const | Description |
|---------|-------|-------------|
| $0000–$0001 | — | **6510 I/O port** — NEVER write; clearing CHAREN bit disables SID/VIC/CIA |
| $0002–$00A1 | — | KERNAL/BASIC system workspace |
| $00A2 | `ZPArrayPtr` | Index into ArrayPtr1/2/3 for ArithmeticMean |
| $00A3 | `ZPbigloop` | Outer loop counter for calcandloop |
| $00A4 | `data1` | **Primary chip type code** (see Type Codes below) |
| $00A5 | `data2` | Secondary result byte (echo char or sub-type) |
| $00A6 | `data3` | Tertiary result byte (ARM2SID 'R' discriminator) |
| $00A7 | `za7` | Machine type: $FF=C64, $FC=C128, other=TC64 |
| $00A8 | `za8` | 16-bit pointer lo (used by checkanothersid) |
| $00A9 | `sidtype` | Current chip family being scanned in sidstereostart |
| $00AA | `tmp2_zp` | Temporary / SID entry counter in sidstereo_print |
| $00AB | `tmp1_zp` | Temporary (reserved) |
| $00AC | `tmp_zp` | Temporary (reserved) |
| $00AD | `y_zp` | Saved Y register (callee-save convention) |
| $00AE | `x_zp` | Saved X register (callee-save convention) |
| $00AF | `buf_zp` | Temporary buffer byte |
| $00B0 | `sid_music_flag` | 0=SID module silent, 1=play $1806 from IRQ |
| $00B1 | `colwash_flag` | 1=run COLWASH in IRQ, 0=suppress (sub-screens) |
| $00B2 | `retry_zp` | checkrealsid retry count (0–2) |
| $00B3 | `trk_v1env` | Tracker: voice-1 software envelope follower |
| $00B4 | `trk_v2env` | Tracker: voice-2 software envelope follower |
| $00B5 | `trk_v1prev` | Tracker: voice-1 previous gate bit (edge detect) |
| $00B6 | `trk_v2prev` | Tracker: voice-2 previous gate bit |
| $00B7 | `trk_patched` | 1 = player binary's $D4xx writes redirected to shadow |
| $00B8 | `trk_parity` | Frame parity (every-other-frame render gate) |
| $00B9 | `trk_scratch` | Tracker scratch (undo count / scan tmp) |
| $00BA | `trk_scratch2` | Tracker scratch (shadow pointer low) |
| $00BB | `trk_scratch3` | Tracker scratch (shadow pointer high) |
| $00BC | `trk_ptr_lo` | Tracker ZP pointer low (for `sta (ptr),y`) |
| $00BD | `trk_ptr_hi` | Tracker ZP pointer high |
| $00BE | `trk_tmp_nidx` | Tracker scratch (nibble / wave index) |
| $00BF | `tr_ctrl_tmp` | Tracker cached CTRL byte for current voice |
| $00C0–$00F5 | — | Unused by program |
| $00F6 | `cnt2_zp` | Inner mirror-scan step counter (fiktivloop / checkanothersid) |
| $00F7 | `sidnum_zp` | Number of SID chips found so far (0–8) |
| $00F8 | `cnt1_zp` | tab1/tab2 index during multi-SID scan |
| $00F9 | `sptr_zp` | SID address low byte (always $00 in current use) |
| $00FA | `sptr_zp1` | SID address high byte ($D4/$D5/$D6/$D7/$DE/$DF) |
| $00FB | `scnt_zp` | Mirror-scan step counter (0–$30 = 48 steps × $20) |
| $00FC | `mptr_zp` | Mirror-scan address low byte (00, 20, 40…E0) |
| $00FD | `mptr_zp1` | Mirror-scan address high byte ($D4–$DF) |
| $00FE | `mcnt_zp` | Index into tab1/tab2 (selects which SID page) |
| $00FF | `res_zp` | Reserved / result scratch |

---

## Stack ($0100–$01FF)

Standard 6502 hardware stack. Used by JSR/RTS, PHA/PLA. calcandloop uses TXS/TSX to save/restore loop counter in X across JSR.

---

## KERNAL/System Page ($0200–$03FF)

| Address | Description |
|---------|-------------|
| $02A6 | KERNAL PAL/NTSC variable (1=PAL, 0=NTSC); written by checkpalntsc |
| $0318–$0319 | **NMI vector** — patched to RTI during checkpalntsc, restored after |
| $0320–$03FF | KERNAL vectors and workspace (not used by program) |

---

## Screen RAM ($0400–$07FF)

| Address | Size | Description |
|---------|------|-------------|
| $0400–$07E7 | 1000 B | **Video screen RAM** — 40×25 characters |
| $0658 | 1 B | Spinner character cell (row 6, col 24) — updated by calc_start during decay measurement |
| $07E8 | 1 B | Decay timing counter low byte (off-screen, beyond 40×25=$07E7) |
| $07E9 | 1 B | Decay timing counter mid byte |
| $07EA | 1 B | Decay timing counter high byte |

The 3 bytes at $07E8–$07EA are deliberately placed in the off-screen area of RAM to reuse existing memory without disturbing the visible display.

---

## BASIC RAM ($0800–$09FF)

| Address | Size | Description |
|---------|------|-------------|
| $0800 | 1 B | BASIC line link (points back to self — end of BASIC) |
| $0801–$080C | 12 B | **BASIC stub** — `SYS 9216` launches main code at $2400 |
| $080D–$080E | 2 B | `basend` — two zero bytes (end-of-BASIC marker) |
| $080F–$09FF | — | Unused |

---

## TLR sid-detect2 ($0A00–$~$0BEA)

| Address | Description |
|---------|-------------|
| $0A00 | `tlr_data` — TLR's sid-detect2.prg embedded here (load skips 2-byte PRG header) |
| $0A00+ | Copied to $0801 and executed when user presses **L** (alternate SID detector) |

---

## SID Music Module ($1800–$2387)

| Address | Description |
|---------|-------------|
| $1800 | **Triangle Intro** by Michael Troelsen (Fun Fun), 1988 |
| $1800 | Init address — called with A=song-1 to select track |
| $1806 | Play address — called from IRQ every frame to advance music |
| $1807–$2387 | Music data and pattern tables |

The .sid file header (126 bytes) is stripped; raw binary embedded directly. Located below the code start ($2400) to avoid overlapping.

---

## Main Code Segment ($2400–$52FB)

**5-byte margin** to the data segment at $5300.

### Entry Points

| Address | Label | Description |
|---------|-------|-------------|
| $2400 | `start` | Program entry (SYS target); re-entered on SPACE restart |
| $2894 | `kbdloop` | Main keyboard poll loop (JMP-patch target for hw_test.py) |
| $2926 | `do_restart` | Cold restart handler |

### Screen Sub-systems

| Address | Label | Description |
|---------|-------|-------------|
| $2B93 | `info_kbdloop` | Info screen keyboard loop |
| $2CF5 | `debug_entry` | Debug page 1 entry (clears screen, renders debug data) |
| $31E2 | `dbg2_kbdloop` | Debug page 2 keyboard loop (JMP-patch target) |
| $322D | `dbg_kbdloop` | Debug page 1 keyboard loop (JMP-patch target) |
| $3315 | `readme_kbdloop` | README screen keyboard loop |
| $34FD | `snd_kbdloop` | Sound test keyboard loop |
| $376E | `printscreen` | Blit static 25×40 UI to screen RAM $0400 |

### Detection Chain

| Address | Label | Description |
|---------|-------|-------------|
| ~$2400+ | `DETECTSIDFX` | SIDFX cartridge (SCI serial protocol) |
| ~$2400+ | `Checkarmsid` | ARMSID/ARM2SID (register echo "DIS"/"WOR"/"NOR") |
| ~$2400+ | `checkfpgasid` | FPGASID (magic-cookie $81/$65 + $F51D readback) |
| ~$2400+ | `checkrealsid` | Real 6581/8580 (sawtooth $D41B readback) |
| ~$2400+ | `checksecondsid` | Additional SIDs at D500/D600/D700/DE00/DF00 |
| $3D9D | `sidstereostart` | Prints stereo SID results to screen |
| $4980 | `calc_start` | $D418 decay timing (emulator fingerprint) |

### Embedded Variables and Tables (in code body)

| Address | Label | Size | Description |
|---------|-------|------|-------------|
| $4C65 | `ultisid_str_lo` | 14 B | Lo/hi pointer table for UltiSID filter curve strings |
| $4D56 | `armsid_major` | 1 B | ARMSID firmware major version (2=ARMSID, 3=ARM2SID) |
| $4D57 | `armsid_minor` | 1 B | ARMSID firmware minor version (0–99) |
| $4D58 | `armsid_cfgtest` | 1 B | D41B after config open ($4E='N' if working) |
| $4D59 | `armsid_no_c` | 1 B | D41C after config entry (expect $4F='O') |
| $4D5A | `armsid_ei_b` | 1 B | D41B after 'ei' cmd (expect $53='S') |
| $4D5B | `armsid_ei_c` | 1 B | D41C after 'ei' cmd (expect $57='W') |
| $4D5C | `armsid_ii_b` | 1 B | D41B after 'ii' cmd (2=ARM2SID, other=ARMSID) |
| $4D5D | `armsid_ii_c` | 1 B | D41C after 'ii' cmd ('L'/$4C or 'R'/$52 for ARM2SID) |
| $4D5E | `armsid_sid_type_h` | 1 B | D41B after 'fi' cmd ('6'=6581, '8'=8580 emulated) |
| $4D5F | `armsid_auto_sid` | 1 B | D41B after 'gi' cmd ('7'=$37 = auto-detected) |
| $4D60 | `armsid_emul_mode` | 1 B | D41B after 'mm' cmd (0=SID,1=SFX,2=SFX+SID; ARM2SID only) |
| $4D61 | `armsid_map_l` | 1 B | D41B after 'lm' (slots 0+1 nibble-packed; ARM2SID only) |
| $4D62 | `armsid_map_l2` | 1 B | D41C after 'lm' (slots 2+3 nibble-packed) |
| $4D63 | `armsid_map_h` | 1 B | D41B after 'hm' (slots 4+5 nibble-packed) |
| $4D64 | `armsid_map_h2` | 1 B | D41C after 'hm' (slots 6+7 nibble-packed) |
| $4D65 | `is_u64` | 1 B | **1 = running on Ultimate64** (UCI $DF1F != $FF) |
| $4D66 | `fpgasid_sid2_type` | 1 B | SID2 type from $82 magic ($3F=8580, $00=6581) |
| $4D67 | `fpgasid_cpld_rev` | 1 B | FPGASID CPLD revision |
| $4D68 | `fpgasid_fpga_rev` | 1 B | FPGASID FPGA revision |
| $4D69 | `arm2sid_mapnames` | 20 B | 5 × 4-char slot labels: "----SIDLSIDRSFX-SID3" |
| $4D7D | `arm2sid_slot_d2` | 8 B | 2nd hex digit per slot ('4','4','5','5','E','E','F','F') |
| $4D8E | `backsid_d41f` | 1 B | D41F readback from checkbacksid ($42 = BackSID present) |
| $4D8F | `MODE6581` | 16 B | $D418 decay mode table for 6581 identification |
| $4D9F | `MODE8580` | 16 B | $D418 decay mode table for 8580 identification |
| $4DAF | `MODEUNKN` | 16 B | $D418 decay mode table for unknown |
| $4DC4 | `screen` | 1000 B | **Static screen data** (25 rows × 40 cols, screencode_upper) |
| $51AC | `COLOUR` | 49 B | Colour wash palette table for COLWASH animation |
| $51E0+ | `check_uci_ultisid` | — | UCI UltiSID check subroutine |
These variables physically reside in the data segment (see $54FC–$551F below), but are initialized and used exclusively from the code segment.

---

## Data Segment ($5300–$7EA7)

Explicitly placed with `* = $5300` in the assembler source.

### SID Result Tables ($5300–$5336)

| Address | Label | Size | Description |
|---------|-------|------|-------------|
| $5300 | `num_sids` | 8 B | Slot 0 = SID count found; slots 1–7 unused here |
| $5308 | `sid_list_l` | 8 B | SID address low byte per slot ($00 or $20) |
| $5310 | `sid_list_h` | 8 B | SID address high byte per slot ($D4/$D5/$D6/$D7/$DE/$DF) |
| $5318 | `sid_list_t` | 8 B | Chip type code per slot (see Type Codes below) |

Slot 0 is unused (reserved). Slots 1–7 hold detected SIDs. `num_sids[0]` = count of active slots.

### UCI Response Buffer ($5320–$5336)

| Address | Label | Size | Description |
|---------|-------|------|-------------|
| $5320 | `uci_resp` | 23 B | UCI GET_HWINFO response buffer |

Buffer layout (GET_HWINFO target=$04 cmd=$28 device=$01, 5 bytes per frame):

| Offset | Contents |
|--------|----------|
| [0] | Frame count (N) |
| [1..5] | Frame 1: lo, hi, sec_hi, sec_lo, T |
| [6..10] | Frame 2: lo, hi, sec_hi, sec_lo, T |
| [11..15] | Frame 3: lo, hi, sec_hi, sec_lo, T |
| [16..20] | Frame 4: lo, hi, sec_hi, sec_lo, T |
| [21] | Trailing byte from FIFO drain |
| [22] | UCI status after DATA_ACC reset ($00=Idle) |

T byte values: $83=UltiSID internal (FPGA), $85=external hardware SID.

### SID Presence Map ($5337–$5396)

| Address | Label | Size | Description |
|---------|-------|------|-------------|
| $5337 | `sid_map` | 96 B | Bit-mapped scan results for addresses $D400–$DFFF in $20 steps |

96 bytes cover 6 pages ($D4xx–$DFxx) × 8 offsets ($00, $20, $40, $60, $80, $A0, $C0, $E0) × 2 bytes per entry.

### Working Variables ($54FC–$551F)

| Address | Label | Size | Description |
|---------|-------|------|-------------|
| $54FC | `ArrayPtr` | 1 B | ArithMean working pointer |
| $54FD | `ArrayPtr1` | 11 B | Decay sample array 1 (6 measurements + padding) |
| $5508 | `ArrayPtr2` | 11 B | Decay sample array 2 |
| $5513 | `ArrayPtr3` | 11 B | Decay sample array 3 |
| $551E | `data4` | 2 B | Saved HW chip type (from detection chain; used by info page selector) |

### String Table ($5397–$54FB)

| Address | Label | Description |
|---------|-------|-------------|
| $5397 | `stringtable` | Start of null-terminated PETSCII chip name strings |
| $5397 | `shoxs` | "HOXS64" |
| — | `sreal6581` | "REAL 6581" |
| — | `snosound` | "NO SOUND" |
| — | `sfrodo` | "FRODO" |
| — | `sreal8580` | "REAL 8580" |
| — | `sSwinsidn` | "SWINSID NANO" |
| — | `sARMSID` | "ARMSID" |
| — | `sSwinsidU` | "SWINSID ULTIMATE" |
| — | `s6581R3/R4AR/R4/R2` | 6581 sub-revision strings |
| — | `sFPGAsid` | "FPGASID" |
| — | `sResid8580/6581` | VICE emulator strings |
| — | `sFastSid` | "VICE3.3 FASTSID" |
| — | `sULTIsid` | "ULTISID" |
| — | `sunknown` | "UNKNOWNSID" |
| — | `decay_spinner` | 8-frame spinner chars (* + / -) |
| — | `ArithMean` | 2-byte arithmetic mean result |

### Info Page Pointer Tables ($5520–$55A9)

| Address | Label | Size | Description |
|---------|-------|------|-------------|
| $5520 | `info_page_lo` | 18 B | Lo bytes of info page text pointers (18 pages) |
| $5532 | `info_page_hi` | 18 B | Hi bytes of info page text pointers |

### Debug String Labels ($55AA–$56D0)

Null-terminated ASCII labels used by the debug screen printer. Starting at `$55AA` (`dbg_s_data4`), running through labels for MCH, PAL, SID counts, ARMVER, FPGA, BACKSID, UCI, D418, D41B–D41F, ARR1–3, SID list, UCI resp header, etc.

| Notable address | Label |
|-----------------|-------|
| $5662 | `dbg_s_uci_resp` — "UCI RESP: " |

### Info Page Text Data ($56D1–~$7C5F)

| Address | Label | Description |
|---------|-------|-------------|
| $56D1 | `ip_nosid` | "NO SID DETECTED" info page |
| — | `ip_6581` | MOS 6581 info page |
| — | `ip_8580` | MOS 8580 info page |
| — | `ip_armsid` | ARMSID/ARM2SID info page |
| — | `ip_swinu` | SwinSID Ultimate info page |
| — | `ip_swinano` | SwinSID Nano info page |
| — | `ip_fpga8580/6581` | FPGASID info pages |
| — | `ip_sidfx` | SIDFX info page |
| — | `ip_ulti` | UltiSID (U64) info page |
| — | `ip_vice` | VICE emulator info page |
| — | `ip_hoxs` | HOXS64 info page |
| — | `ip_sidkpic` | SidKick Pico info page |
| — | `ip_pubdom` | PD SID info page |
| — | `ip_backsid` | BackSID info page |
| — | `ip_kungfusid` | KungFuSID info page |
| — | `ip_unknown` | Unknown SID info page |
| — | `ip_usid64` | uSID64 info page |
| — | `ip_readme` | README page (55 lines, scrollable) |
| — | `readme_header` | Fixed README header (screencode_upper) |
| — | `readme_nav_hint` | README navigation hint row |

### Data Segment Subroutines (~$7C60–$7EA7)

| Address | Label | Description |
|---------|-------|-------------|
| $7CDF | `uci_type_for_addr` | Determine UltiSID 6581/8580 via UCI GET_HWINFO + checkrealsid fallback |
| $7D9B | `dbg_print_frame` | Print "Fn:$xxyy T=xx INT/EXT [curve]\n" for debug page 2 |
| $7E43 | `dbg_uci_query` | Issue UCI GET_HWINFO, fill `uci_resp[0..22]`, drain FIFO |
| ~$7EA7 | *(end)* | Last byte of assembled binary |

---

## Tracker-View Shadow SID ($C000–$C01F)

| Address | Size | Description |
|---------|------|-------------|
| $C000–$C01F | 32 B | Shadow SID register mirror for Tracker view |

When the user enters the Tracker screen (P key), `tracker_patch_once` scans
the player binary at `$1806–$1FFF` and rewrites every `STA $D4xx` where
`xx < $20` so the player writes land in `$C0xx` instead of `$D4xx`. The
raster IRQ then copies `$C000–$C01F` → `$D400–$D41F` each frame *after*
calling the play routine. Result: audio path is unchanged, but the tracker
render code can read the write-only voice registers by inspecting the
shadow.

The undo table ensures a clean exit: on SPACE / P / Q, `tracker_unpatch`
restores every patched `$C0` back to `$D4`, so second-entry works fine.

---

## Tracker-View Code + Data ($9200–$9FFD)

| Address | Label | Description |
|---------|-------|-------------|
| $9200 | `tracker_patch_once` | Scan + patch player's SID writes to shadow |
| ~$9263 | `tracker_unpatch` | Restore original `$D4` high bytes |
| ~$928A | `tracker_entry` | Clear screen, draw chrome, run render loop |
| ~$932F | `tracker_exit` | Silence SID, unpatch, `jmp start` |
| ~$9413 | `scope_sample` | Read `$D41B` (OSC3) 40× at ~48c spacing |
| ~$9429 | `scope_plot` | Plot scope_buf as 8-row waveform |
| Tables | `note_freq_tbl` (192B), `note_name_tbl` (288B), `vu_colour_tbl` (20B), `scope_buf` (40B) |

Placed at `$9200` (above the $6000 data segment, below BASIC ROM at
`$A000`) so the CPU sees all of it as RAM without bank switching.

---

## Colour RAM ($D800–$DBE7)

| Address | Size | Description |
|---------|------|-------------|
| $D800–$DBE7 | 1000 B | **Colour RAM** — 4-bit colour attribute per screen cell |

Written indirectly by `printscreen` (via KERNAL colour routines). COLWASH animation shifts a 40-entry palette table through row 0 of colour RAM each IRQ.

---

## Hardware I/O ($D000–$DFFF)

### VIC-II ($D000–$D3FF)

| Address | Description |
|---------|-------------|
| $D018 | VIC-II memory control — set to $15 at startup (charset ROM $D000, uppercase set) |
| $D030 | Used by check128: open-bus=$FF on C64, $FC on C128, other on TC64 |
| $D0FE | Disambiguates C64+FC3 false positive in check128 |

### SID ($D400–$D7FF)

| Address | Description |
|---------|-------------|
| $D400–$D41C | SID registers (write-only on real hardware) |
| $D418 | Master volume / filter — read-back for $D418 decay fingerprint |
| $D41B | OSC3 random output — key read-back register for chip identification |
| $D41C | ENV3 envelope output |
| $D41D | Config register (ARMSID/SwinsidU write, FPGASID magic) |
| $D41E | Config register (ARMSID/SwinsidU write, FPGASID config mode) |
| $D41F | Config register (ARMSID/SwinsidU write, uSID64 stability test) |

### Expansion Port I/O ($DE00–$DFFF)

| Address | Description |
|---------|-------------|
| $DE00–$DEFF | I/O 1 — secondary SID scan target; SIDFX cartridge detection |
| $DF00–$DFFF | I/O 2 — secondary SID scan target |
| $DF1C | **UCI control/status register** — write PUSH_CMD ($01) / DATA_ACC ($02); read STATE+DATA_AV |
| $DF1D | UCI command FIFO write port — target ID, command byte, parameters |
| $DF1E | UCI response FIFO read port — response data bytes |
| $DF1F | UCI status byte — $FF=no UCI (non-U64), $00=Idle, $30=Data More |

`$DF1F != $FF` at startup → sets `is_u64 = 1` (confirmed Ultimate64).

---

## KERNAL ROM ($E000–$FFFF)

| Address | Description |
|---------|-------------|
| $AB1E | KERNAL: print zero-terminated PETSCII string (A=lo, Y=hi) |
| $E50C | KERNAL: position cursor (X=row, Y=col) |
| $FFD2 | KERNAL CHROUT: output character in A to current device |
| $FFE4 | KERNAL GETIN: read keyboard (not used in final build) |

---

## Chip Type Codes (`sid_list_t` / `data4`)

| Code | Chip |
|------|------|
| $01 | Real 8580 (checkrealsid: $D41B=0 after sawtooth gate) |
| $02 | Real 6581 (checkrealsid: $D41B=1 after sawtooth gate) |
| $04 | SwinSID Ultimate |
| $05 | ARMSID / ARM2SID |
| $06 | FPGASID 8580 |
| $07 | FPGASID 6581 |
| $08 | SwinSID Micro |
| $09 | PD SID |
| $0A | BackSID |
| $0B | SidKick Pico 8580 |
| $0C | uSID64 |
| $0D | KungFuSID |
| $0E | SidKick Pico 6581 |
| $10 | Second/stereo SID (generic) |
| $20 | ULTISID-8580-LO (U64 FPGA, filter curve 0) |
| $21 | ULTISID-8580-HI (filter curve 1) |
| $22 | ULTISID-6581 (filter curve 2) |
| $23 | ULTISID-6581-ALT (filter curve 3) |
| $24 | ULTISID-U2-LO (filter curve 4) |
| $25 | ULTISID-U2-MID (filter curve 5) |
| $26 | ULTISID-U2-HI (filter curve 6) |
| $30 | SIDFX |
| $F0 | Unknown / No SID |

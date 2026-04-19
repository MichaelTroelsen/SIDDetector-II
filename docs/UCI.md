# Ultimate Command Interface (UCI) — Research Notes

*For SID Detector / siddetector2. Based on empirical testing on Ultimate 64 + source
code analysis of GideonZ/1541ultimate firmware. Last updated V1.3.39.*

---

## 1. Overview

The UCI (Universal Command Interface) exposes the Ultimate 64 / Ultimate II+ firmware
to programs running on the C64. The C64 issues commands via four memory-mapped registers
in the I/O2 area ($DF00–$DFFF). The firmware processes the command asynchronously in a
FreeRTOS task and places a response in a read FIFO.

The UCI is used by SID Detector to:
1. Detect whether a U64 is present (`is_u64` flag)
2. Discover UltiSID emulated-SID addresses (`check_uci_ultisid`, `uci_type_for_addr`)
3. Display live firmware SID layout on debug page 2 (`dbg_uci_query`)

---

## 2. Register Map

| Address | R/W | Name      | Description |
|---------|-----|-----------|-------------|
| `$DF1C` | R   | STATUS    | State bits 5:4, DATA_AV bit 7 |
| `$DF1C` | W   | CONTROL   | PUSH_CMD ($01) or DATA_ACC ($02) |
| `$DF1D` | W   | CMD_FIFO  | Write command bytes here (target, command, args) |
| `$DF1E` | R   | DATA_FIFO | Read response bytes from here |
| `$DF1F` | R   | STATUS2   | Secondary status byte (read at end of response) |

### $DF1C read — STATUS bits

| Bit(s) | Name     | Meaning |
|--------|----------|---------|
| 7      | DATA_AV  | 1 = at least one byte available in DATA_FIFO ($DF1E) |
| 5:4    | STATE    | $00=Idle, $10=Command Busy, $20=Data Last, $30=Data More |
| 1      | STAT_AV  | 1 = status byte available in $DF1F |
| 0      | DATA_AV  | (same as bit 7 in some firmware versions) |

### $DF1C write — CONTROL values

| Value | Name     | Effect |
|-------|----------|--------|
| `$01` | PUSH_CMD | Dispatch command bytes accumulated in CMD_FIFO |
| `$02` | DATA_ACC | Acknowledge data; resets both data FIFO and state machine |

---

## 3. Command Protocol

### Sending a command

```
; Write target byte, command byte, argument bytes to $DF1D (CMD_FIFO)
lda #<target>; sta $DF1D
lda #<command>; sta $DF1D
lda #<arg1>;   sta $DF1D
; ... additional arg bytes ...
lda #$01; sta $DF1C          ; PUSH_CMD — dispatch
```

### Polling for response

Two polling methods have been used in this codebase:

**Method A — STATE bits (preferred, used in uci_type_for_addr / dbg_uci_query):**
```
lda $DF1C; and #$30           ; isolate STATE bits 5:4
cmp #$10                      ; Command Busy?
bne state_ready
; ... loop / timeout ...
state_ready:
lda $DF1C; bpl no_data        ; check DATA_AV (bit 7)
```

**Method B — DATA_AV / STAT_AV bits 0:1 (used in check_uci_ultisid — older code):**
```
lda $DF1C; and #$03           ; DATA_AV | STAT_AV
bne got_response
```
Method B can return on STAT_AV alone (error response with no data bytes). Method A is
cleaner for data reads.

### Reading response bytes

```
read_loop:
    lda $DF1E; sta buffer,x; inx
    ; stop when: buffer full OR DATA_AV bit 7 clears
    lda $DF1C; bmi read_loop
done:
    lda $DF1F; sta status   ; read/consume status byte from $DF1F
    lda #$02; sta $DF1C     ; DATA_ACC — acknowledge and reset
```

### Timeout handling

A 16-bit counter with DEX/DEY provides ~65536 iterations before giving up. The
firmware responds in microseconds on real hardware, so this is purely a safety guard.

---

## 4. Registered UCI Targets

Source: `software/io/command_interface/command_intf.h` — max 16 targets ($00–$0F).

| Target ID | Handler | Purpose |
|-----------|---------|---------|
| `$01` | Ultimate DOS instance 1 | File system access |
| `$02` | Ultimate DOS instance 2 | File system access |
| `$03` | NetworkTarget | TCP/UDP sockets |
| `$04` | ControlTarget | Machine control commands (used by SID Detector) |
| `$05` | SoftIECTarget | Software IEC bypass |
| `$06` | HTTP client (fw 3.15+) | HTTP GET/PUT/POST to internal server |
| `$07`–`$0F` | Empty / unregistered | Returns "UNKNOWN COMMAND" |

**Important:** Target `$02` is a filesystem target, NOT a config/attribute reader.
Gemini's suggestion of "Target $02 Read Attribute for CFG_AUDIO_SID_FILT" is incorrect.

---

## 5. Control Target ($04) — Command Reference

Source: `software/io/command_interface/control_target.h`

| Command byte | Name | Parameters | Returns |
|-------------|------|-----------|---------|
| `$01` | CTRL_CMD_IDENTIFY | — | "CONTROL TARGET V1.1" string |
| `$02` | CTRL_CMD_READ_RTC | — | *defined but not implemented* |
| `$03` | CTRL_CMD_FINISH_CAPTURE | — | empty |
| `$05` | CTRL_CMD_FREEZE | — | empty |
| `$06` | CTRL_CMD_REBOOT | — | empty |
| `$08` | CTRL_CMD_LOAD_REU | filename | status + filename |
| `$09` | CTRL_CMD_SAVE_REU | filename | status + filename |
| `$0F` | CTRL_CMD_U64_SAVEMEM | — | status string |
| `$11` | CTRL_CMD_DECODE_TRACK | GCR data | error codes per sector |
| `$12` | CTRL_CMD_ENCODE_TRACK | — | — |
| `$20` | CTRL_CMD_EASYFLASH | — | empty |
| **`$28`** | **CTRL_CMD_GET_HWINFO** | device byte | see §6 |
| `$29` | CTRL_CMD_GET_DRVINFO | — | drive type, IEC addr, power state |
| `$30` | CTRL_CMD_ENABLE_DISK_A | — | empty |
| `$31` | CTRL_CMD_DISABLE_DISK_A | — | empty |
| `$32` | CTRL_CMD_ENABLE_DISK_B | — | empty |
| `$33` | CTRL_CMD_DISABLE_DISK_B | — | empty |
| `$34` | CTRL_CMD_DISK_A_POWER | — | "on " or "off" string |
| `$35` | CTRL_CMD_DISK_B_POWER | — | "on " or "off" string |
| `$40` | CTRL_CMD_GET_RAMDISKINFO | — | 8 bytes: drive types + sizes |

All commands begin with mandatory bytes: `$04` (target), `<command>`, `<device/arg...>`.

---

## 6. GET_HWINFO — Detailed Analysis

**Command sequence:** `$04 $28 $01` → PUSH_CMD

The `device` byte selects what is returned:
- `device=0` — product identification string (e.g. "Ultimate 64")
- `device=1` — SID slot configuration (used by SID Detector)

### Official documentation status

**DEPRECATED** per 1541u-documentation.readthedocs.io:
> "Type indicator unclear; does not match actual implementation of SID control."

This deprecation notice is accurate and explains the observed behavior.

### Response format for device=1 (empirically confirmed on U64, fw ~3.x)

```
[0]        count (number of SID frames that follow, typically 2 or 4)
[1..5]     Frame 1:  lo, hi, byte3, byte4, type
[6..10]    Frame 2:  lo, hi, byte3, byte4, type
[11..15]   Frame 3:  lo, hi, byte3, byte4, type  (if count >= 3)
[16..20]   Frame 4:  lo, hi, byte3, byte4, type  (if count == 4)
[21]       trailing byte (value varies, $00 observed with 4 frames)
```
Total: 22 bytes in FIFO (21 payload + 1 trailing), plus `$DF1F` status byte.

**Address encoding within each frame:**
- `lo` = low byte of SID address (e.g. `$00` for $D500, `$20` for $D420)
- `hi` = high byte of SID address (e.g. `$D5` for $D500, `$D4` for $D420)
- `byte3`, `byte4` = secondary/mask bytes, always `$00 $00` on observed hardware

### Live capture — 5-SID U64 system

Hardware: ARM2SID@D400, ARM2SID@D420, ARMSID@DE00, UltiSID@D500, UltiSID@D600

```
Raw FIFO (22 bytes):
  04 00 D5 00 00 83  00 D6 00 00 83  00 D4 00 00 85  20 D4 00 00 85  00
  ^                  ^                ^                ^                ^
  count=4            F1 $D500 T=$83   F2 $D600 T=$83   F3 $D400 T=$85   F4 $D420 T=$85  trailing=$00

$DF1F status: $30  (read before DATA_ACC; reflects FIFO state at that moment)
```

### T byte encoding — hardware presence codes

| T value | Meaning |
|---------|---------|
| `$83`   | Enabled UltiSID (U64 internal SID emulation slot) |
| `$85`   | Enabled external hardware SID (ARMSID, real SID, etc.) |
| `$8x`   | Bit 7 = enabled; lower bits = firmware model code |

**These are NOT filter curve indices.** The firmware's `CFG_EMUSID1_FILTER` /
`CFG_EMUSID2_FILTER` config values (0–6) are stored in an internal `ConfigStore`
and are not returned by any UCI command.

### What was expected vs. what the firmware returns

An earlier assumption in this codebase (and from various AI suggestions) was that
the T byte would be a filter curve index in the range 0–6:

| Expected index | Filter curve name |
|----------------|-------------------|
| 0 | 8580 Lo |
| 1 | 8580 Hi |
| 2 | 6581 |
| 3 | 6581 Alt |
| 4 | U2 Low |
| 5 | U2 Mid |
| 6 | U2 High |

The actual firmware returns `$83`/`$85` instead. The `uci_type_for_addr` routine
handles this correctly: values ≥ 7 fall through to `checkrealsid` (real SID
oscillator test), which determines 6581 vs 8580. The detection results are correct
but via fallback, not via the UCI type byte.

---

## 7. SID Filter Curves — Why They Cannot Be Read via UCI

`CFG_EMUSID1_FILTER` (`$14`) and `CFG_EMUSID2_FILTER` (`$15`) are defined in
`software/u64/u64_config.cc`. They are stored in a `ConfigStore` object and only
surfaced via:

1. **The U64 on-screen menu** — interactive only
2. **HTTP REST API** — `GET /v1/configs` or `GET /v1/configs/UltiSIDs` returns a
   JSON object containing all config values. Accessible via UCI Target `$06`
   (HTTP client, firmware ≥ 3.15) but requires constructing an HTTP request in
   6502 code and parsing JSON — not practical within SID Detector's constraints.

There is no direct single-command UCI path to read filter curve settings.
**The filter curves shown on debug page 2 of SID Detector come from the
`sid_list_t` detection results, derived via `checkrealsid` oscillator testing.**

---

## 8. UCI Dirty State Bug and Fix

**Symptom:** After detection phase, debug page 2 showed stale/wrong GET_HWINFO data.

**Root cause:** `uci_type_for_addr` was reading only 21 bytes from the FIFO out of a
22-byte response (21 payload + 1 trailing). The trailing byte remained in the FIFO,
leaving the UCI STATE at `$30` (Data More). Subsequent calls received the leftover
byte as the start of a "new" response, corrupting the data.

**Fix (V1.3.37):** Changed the read loop stop condition from `cpx #$15` (21) to
`cpx #$16` (22) in both `uci_type_for_addr` and `dbg_uci_query`. This drains the
full 22-byte FIFO, leaving UCI in clean Idle state after DATA_ACC.

**Verification:** `uci_resp+22` (the `$DF1F` status byte) = `$00` confirms clean
handshake. Status `$30` indicates bytes were left in FIFO.

---

## 9. SID Detector Implementation Details

### Detection flow using UCI

```
startup
  └─ is_u64 flag set?  (checked via $D7FF / other probe)
       └─ yes: check_uci_ultisid
                 Issue GET_HWINFO (device=1)
                 For each frame with addr >= $D500:
                   Run Check2 (noise oscillator test)
                   If noise present: call uci_type_for_addr
                     Issue GET_HWINFO again
                     Match frame address to mptr_zp
                     If T byte 0–6: map to sid_list_t $20–$26
                     Else (T=$83/$85): fallback to checkrealsid
                   Add to sid_list as type $20–$26 (ULTISID-8580-LO .. ULTISID-6581-ALT)
```

### `uci_resp` buffer layout ($5320, 23 bytes)

```
[0]      count (frames in response)
[1..5]   Frame1: lo, hi, sec_hi, sec_lo, type
[6..10]  Frame2: lo, hi, sec_hi, sec_lo, type
[11..15] Frame3: lo, hi, sec_hi, sec_lo, type
[16..20] Frame4: lo, hi, sec_hi, sec_lo, type
[21]     trailing FIFO byte (drained to clear UCI state)
[22]     $DF1F status byte (captured before DATA_ACC)
```

### `sid_list_t` filter curve type codes

| Type | Constant | Meaning |
|------|----------|---------|
| `$20` | ULTISID-8580-LO | UltiSID, 8580 Lo filter (or fallback) |
| `$21` | ULTISID-8580-HI | UltiSID, 8580 Hi filter |
| `$22` | ULTISID-6581    | UltiSID, 6581 filter |
| `$23` | ULTISID-6581-ALT | UltiSID, 6581 Alt filter |
| `$24` | ULTISID-U2-LO   | UltiSID, U2 Low filter |
| `$25` | ULTISID-U2-MID  | UltiSID, U2 Mid filter |
| `$26` | ULTISID-U2-HI   | UltiSID, U2 High filter |

These come from `checkrealsid` or UCI type 0–6 (via `utfa_map: adc #$20`). On
current U64 firmware, UCI always returns `$83`/`$85`, so `checkrealsid` is always
used as fallback. The type range $20–$26 still works correctly — the filter curve
resolution is just less granular (only 8580 vs 6581 distinction, not all 7 curves).

---

## 10. Minimal 6502 GET_HWINFO Example

```asm
; Issue CTRL_CMD_GET_HWINFO (device=1) and drain response to buffer
; On entry: buffer at uci_resp (23 bytes), UCI must be idle
uci_get_hwinfo:
    lda #$04; sta $DF1D      ; target: ControlTarget
    lda #$28; sta $DF1D      ; command: GET_HWINFO
    lda #$01; sta $DF1D      ; device: 1 = SID config
    lda #$01; sta $DF1C      ; PUSH_CMD
    ldx #$00; ldy #$00
.poll:
    lda $DF1C
    and #$30                  ; STATE bits 5:4
    cmp #$10                  ; Command Busy?
    bne .ready
    dex; bne .poll
    dey; bne .poll
    rts                       ; timeout
.ready:
    lda $DF1C
    bpl .nodata               ; bit 7 = DATA_AV
    ldx #$00
.read:
    lda $DF1E; sta uci_resp,x; inx
    cpx #$16; beq .done       ; drain exactly 22 bytes (critical: clears trailing byte)
    lda $DF1C; bmi .read      ; more bytes available?
.done:
    lda $DF1F; sta uci_resp+22 ; save status ($00 = clean, $30 = stale bytes remain)
    lda #$02; sta $DF1C        ; DATA_ACC: acknowledge and reset
    rts
.nodata:
    lda $DF1F; sta uci_resp+22
    lda #$02; sta $DF1C
    rts
```

**Critical:** always drain to exactly 22 bytes (or until DATA_AV clears, whichever
comes first) and always issue DATA_ACC. Leaving bytes in the FIFO corrupts the next
caller's response.

---

## 11. Known Limitations and Open Questions

| Topic | Status |
|-------|--------|
| Filter curve reading | **Impossible via UCI.** No UCI command exposes ConfigStore values. HTTP target ($06) is the only programmatic path but requires JSON parsing. |
| GET_HWINFO T byte semantics | `$83`=UltiSID internal, `$85`=external HW SID. Bit 7 = enabled flag. Lower bits = firmware SID device model code. Not documented publicly. |
| GET_HWINFO secondary bytes | `byte3`/`byte4` = always `$00 $00` on tested hardware. Possibly mask/address-range encoding per firmware source. Meaning unknown. |
| GET_HWINFO frame count | Observed count=4 (2 emulated + 2 external). Older code assumed count=2. May vary with U64 firmware version. |
| HTTP target ($06) UCI protocol | Commands `HTTP_CMD_HEADER_CREATE` + `HTTP_CMD_DO_EXCHANGE_RAW` access the U64's internal REST API. Could retrieve filter curves as JSON. Not implemented; JSON parsing is prohibitive in 6502. |
| Frame count > 4 | Untested. Buffer sized for 4 frames (22 bytes). If firmware ever returns 5+ frames, drain loop will stop at 22 bytes and leave data in FIFO — UCI dirty. |

# SID Detector — Test Status

**Last updated:** 2026-04-18  
**Build:** `$2400–$5E4C` (code) `$6000–$943D` (data)  
**Version:** V1.4.21  
Legend: 🟢 OK · 🔴 NO · ⬜ not tested

---

## Master Test List

| # | Category | Chip / Config | Expected output | Result | Notes |
|---|----------|--------------|----------------|--------|-------|
| 1 | Real SID | 6581 R2 | `6581 R2` | 🟢 | |
| 2 | Real SID | 6581 R3 2084 | `6581 R3` | 🟢 | |
| 3 | Real SID | 6581 R4 | `6581 R4` | 🟢 | |
| 4 | Real SID | 6581 R4AR 5286 | `6581 R4AR` | 🟢 | |
| 5 | Real SID | 8580 | `8580` | 🟢 | |
| 6 | Replacement | ARMSID | `ARMSID Vx.xx` | 🟢 | Debug: CFG=4E4F EI=5357 II=02?? |
| 7 | Replacement | ARM2SID (left ch.) | `ARM2SID V3.xx` | 🟢 | Debug: CFG=4E4F EI=5357 II=024C |
| 8 | Replacement | ARM2SID (right ch.) | `ARM2SID V3.xx` | 🟢 | Debug: CFG=4E4F EI=5357 II=0252 |
| 9 | Replacement | ARM2SID stereo D400+D500 | both channels shown | 🔴 | stereo ARMSID mirror issue — D5xx triggers D400 chip |
| 10 | Replacement | FPGASID 8580 mode | `FPGASID 8580` | 🟢 | stereo row fixed: pre-populate D400 with type $06 |
| 11 | Replacement | FPGASID 6581 mode | `FPGASID 6581` | 🟢 | stereo row correct: type $07 |
| 12 | Replacement | Swinsid Nano | `SWINSID NANO` | 🟢 | D41B cnt test: freq=$FFFF noise waveform, 3-retry Stage 1 (reject if all cnt=7), Stage 2 at 62ms (cnt≥3). Step 0.25 real-SID pre-check prevents 6581 false positive. |
| 13 | Replacement | Swinsid Ultimate | `SWINSID ULTIMATE` | 🟢 | |
| 14 | Replacement | SIDFX (6581@D400 + SIDKick Pico 8580@D500, SW1=CTR) | `SIDFX` + `6581` at D400 + `SIDKICK-PICO` at D500 | 🟢 | V1.3.58: sfx_probe_skpico Phase 1 'S'+'K' probe at D51D confirmed on hw_test. Baseline: $D400 6581($01) $D500 SIDKick-pico-8580($0B) |
| 15 | Replacement | ULTISID 8580 (U64) | `8580 INT` | 🟢 | V1.3.45: main screen now shows "8580 INT" (was "ULTISID-8580-LO"); confirmed hw_test baseline $20 at D500/D600 |
| 16 | Replacement | ULTISID 6581 (U64) | `6581 INT` | ⬜ | V1.3.45: code fix in place (ssp_skp16); not verified on hardware (no 6581 UltiSID in test rig) |
| 17 | Replacement | SIDKick Pico | `SIDKICK-PICO` | 🟢 | Firmware 0.22 DAC64. D41E pointer manual (write $E0+i per byte), no auto-increment. |
| 18 | Replacement | PD SID | `PD SID` | 🟢 | |
| 19 | Replacement | BackSID | `BACKSID` | 🟢 | |
| 20 | Replacement | KungFuSID | `KUNGFUSID` | 🟢 | Old firmware: echo-based ($A5→$A5). New firmware: $A5→$5A ACK. Both detected. |
| 21 | Replacement | uSID64 | `USID64 FOUND` | 🟢 | D41F two-read stability: $F0,$10,$63,$00,$FF → read twice, both $E0-$FC, stable within $02. Verified 5/5 on real hardware. |
| 22 | Stereo slot | Second SID at D500 | second SID shown | 🟢 | Confirmed V1.3.45 hw_test baseline: ULTISID $20 at D500 |
| 23 | Stereo slot | Second SID at D600 | second SID shown | 🟢 | Confirmed V1.3.45 hw_test baseline: ULTISID $20 at D600 |
| 24 | Stereo slot | Second SID at D700 | second SID shown | ⬜ | Not tested |
| 25 | Stereo slot | Second SID at DE00 | second SID shown | 🟢 | Confirmed V1.3.45 hw_test baseline: ARMSID $05 at DE00 |
| 26 | Stereo slot | Second SID at DF00 | second SID shown | ⬜ | Not tested |
| 27 | Emulator | VICE ResID 6581 | `VICE C64 EMULATOR` | 🟢 | |
| 28 | Emulator | VICE ResID 8580 | `VICE C64 EMULATOR` | 🟢 | |
| 29 | Emulator | VICE FastSID 6581 | `VICE C64 EMULATOR` | 🟢 | |
| 30 | Emulator | VICE FastSID 8580 | `VICE C64 EMULATOR` | 🟢 | |
| 31 | Emulator | HOXS64 | `HOXS64 C64 EMULATOR` | 🟢 | |
| 32 | Emulator | Frodo | `FRODO` | 🟢 | |
| 33 | Emulator | YACE64 | `YACE64` | 🟢 | |
| 34 | Emulator | EMU64 | `EMU64` | 🟢 | |
| 35 | Emulator | No SID | `NO SID DETECTED` | 🟢 | |
| 36 | Platform | C64 PAL | correct detection | 🟢 | primary target |
| 37 | Platform | C64 NTSC | correct detection | 🟢 | |
| 38 | Platform | C128 PAL | correct detection | 🟢 | |
| 39 | Platform | C128 NTSC | correct detection | 🟢 | |
| 40 | Platform | TC64 | correct detection | 🟢 | |

---

## Combination / Stereo Config Tests

Legend: 🟢 OK · 🔴 FAIL · ⬜ not tested · ⚠️ known limitation

**Address notation:** D420 = MixSID default secondary; D500 = typical stereo expander; DE00 = SIDFX default

### MixSID — two chips in SID socket adapter (D400 + D420)

| # | D400 (primary) | D420 (secondary) | Expected | Result | Notes |
|---|---------------|-----------------|----------|--------|-------|
| C01 | 6581 | 6581 | `6581 Rx` + `6581` at D420 | ⬜ | |
| C02 | 6581 | 8580 | `6581 Rx` + `8580` at D420 | ⬜ | |
| C03 | 8580 | 6581 | `8580` + `6581` at D420 | 🟢 | V1.3.76: TEST-bit reset of CS2 voice3 in step2_armsid fixes wrong slot2 address (D4A0/D4E0 drift); KungFuSID false-positive fixed in V1.3.75; hw_test 10/10 (2×) |
| C04 | 8580 | 8580 | `8580` + `8580` at D420 | ⬜ | |
| C05 | ARMSID | ARMSID | `ARMSID` + `ARMSID` at D420 | 🟢 | User's rig: D400+D420 both ARMSID confirmed V1.3.45 |
| C06 | ARMSID | 6581 | `ARMSID` + `6581` at D420 | 🟢 | V1.3.74: fallback Checkarmsid at D400 handles ARMSID@CS1 correctly; hw_test 10/10 |
| C07 | ARMSID | 8580 | `ARMSID` + `8580` at D420 | 🟢 | V1.3.71: lda $D41B ACK in s_s_arm_call_real fixes ARMSID bus contention; hw_test 10/10 on MixSID rig |
| C08 | 6581 | ARMSID | `6581 Rx` + `ARMSID` at D420 | 🟢 | V1.3.74: single CS2-DIS window in step2_armsid; pre-clean zeroes D41F for U64 uSID64 state machine reset; hw_test 10/10 |
| C09 | 8580 | ARMSID | `8580` + `ARMSID` at D420 | 🟢 | V1.3.73: jmp s_s_l3 in s_s_add for sidtype=$05 exits ARMSID scan early (avoids D5xx-DFxx garbage on U64); hw_test 10/10 |
| C10 | FPGASID 8580 | 6581 | `FPGASID 8580` + `6581` at D420 | ⬜ | |
| C11 | FPGASID 6581 | 8580 | `FPGASID 6581` + `8580` at D420 | ⬜ | |
| C12 | 6581 | FPGASID 8580 | `6581 Rx` + `FPGASID 8580` at D420 | ⬜ | |
| C13 | SwinSID Nano | 6581 | `SWINSID NANO` + `6581` at D420 | ⬜ | |
| C14 | SwinSID Nano | 8580 | `SWINSID NANO` + `8580` at D420 | ⬜ | |
| C15 | 6581 | SwinSID Nano | `6581 Rx` + `SWINSID NANO` at D420 | ⬜ | |
| C16 | 8580 | SwinSID Nano | `8580` + `SWINSID NANO` at D420 | ⬜ | |
| C17 | SIDKick Pico | 6581 | `SIDKICK-PICO` + `6581` at D420 | ⬜ | |
| C18 | SIDKick Pico | 8580 | `SIDKICK-PICO` + `8580` at D420 | ⬜ | |
| C19 | KungFuSID | 6581 | `KUNGFUSID` + `6581` at D420 | ⬜ | |
| C20 | KungFuSID | 8580 | `KUNGFUSID` + `8580` at D420 | ⬜ | |

### MixSID / StereoSID — D400 + D500

| # | D400 (primary) | D500 (secondary) | Expected | Result | Notes |
|---|---------------|-----------------|----------|--------|-------|
| C21 | 6581 | 6581 | `6581 Rx` + `6581` at D500 | ⬜ | |
| C22 | 6581 | 8580 | `6581 Rx` + `8580` at D500 | ⬜ | |
| C23 | 8580 | 6581 | `8580` + `6581` at D500 | ⬜ | |
| C24 | 8580 | 8580 | `8580` + `8580` at D500 | ⬜ | |
| C25 | ARMSID | 6581 | `ARMSID` + `6581` at D500 | 🔴 | Mirror issue: ARMSID primary skips D5xx stereo scan |
| C26 | ARMSID | 8580 | `ARMSID` + `8580` at D500 | 🔴 | Mirror issue: same as C25 |
| C27 | 6581 | ARMSID | `6581 Rx` + `ARMSID` at D500 | ⬜ | |
| C28 | 8580 | ARMSID | `8580` + `ARMSID` at D500 | ⬜ | |
| C29 | SwinSID Ultimate | 6581 | `SWINSID ULTIMATE` + `6581` at D500 | ⬜ | SwinSID U echo test may trigger at D500 — risk of wrong-address detection |
| C30 | 6581 | SwinSID Nano | `6581 Rx` + `SWINSID NANO` at D500 | ⬜ | |

### SIDFX — cartridge adds second SID; address set by SW1 (CTR=D500, LFT=D420, RGT=DE00)

Note: SIDFX D41E reports hosted chip types as 6581/8580/UNKN. Secondary probed in order: (1) SIDKick Pico (sfx_probe_skpico, 'S'+'K' echo at +$1D); (2) SwinSID Ultimate / ARMSID (sfx_probe_dis_echo, DIS sequence via (sptr_zp),y, reads +$1B: 'S'→SwinsidU, 'N'→ARMSID); (3) BackSID (checkbacksid via (sptr_zp),y for D41B, unlock $02/$01/$B5/$1D, poll D41F for $01); (4) KungFuSID (inline (sptr_zp),y: $A5→+$1D, read back: $5A new-FW / $A5 old-FW). Probes run for D5xx–D7xx; D4xx (LFT slot) skipped for SIDKick Pico (sfx_probe_skpico needs CS1) and for ARMSID primary (primary ARMSID snoops CS2 DIS writes and drives $4E aggressively on all D4xx data-bus reads, contaminating D43B=OSC3). Non-ARMSID primaries (6581/8580 real) allow the DIS probe at D420 to run safely. DE/DF skipped (SIDFX cartridge I/O). BackSID only responds to unlock protocol once per power cycle; detected on cold boot only.

| # | D400 (socket) | Secondary (SIDFX) | SW1 | Expected | Result | Notes |
|---|--------------|------------------|-----|----------|--------|-------|
| C31 | 6581 | SIDKick Pico 8580 | CTR→D500 | `SIDFX` + `6581` at D400 + `SIDKICK-PICO` at D500 | 🟢 | V1.3.58: confirmed hw_test 9/9. Baseline: $D400 6581($01) $D500 SIDKick-pico-8580($0B) |
| C32 | 6581 | PD SID (8580) | CTR→D500 | `SIDFX` + `6581` at D400 + `8580` at D500 | 🟢 | V1.3.59: sidstereostart early-return for SIDFX prevents PDsid mirror overflow. Baseline: $D400 6581($01) $D500 8580($02). hw_test 9/9 |
| C33 | 6581 | SwinSID Ultimate | CTR→D500 | `SIDFX` + `6581` at D400 + `SWINSID-U` at D500 | 🟢 | V1.3.61: sfx_probe_dis_echo 'S' echo confirmed. Baseline: $D400 6581($01) $D500 SwinSID-U($04). hw_test 9/9 |
| C34 | 6581 | ARMSID | CTR→D500 | `SIDFX` + `6581` at D400 + `ARMSID` at D500 | 🟢 | V1.3.61: sfx_probe_dis_echo 'N' echo confirmed. Baseline: $D400 6581($01) $D500 ARMSID/ARM2SID($05). hw_test 9/9 |
| C34a | 6581 | SwinSID Ultimate | LFT→D420 | `SIDFX` + `6581` at D400 + `SWINSID-U` at D420 | ⚠️ | WONTFIX: 6581 primary drives D43B (OSC3, mapped reg), contaminating DIS echo. Shows SIDFX-reported type (8580). hw_test 9/9 V1.3.84 |
| C34b | 6581 | BackSID | CTR→D500 | `SIDFX` + `6581` at D400 + `BACKSID` at D500 | 🟢 | V1.3.63: checkbacksid via (sptr_zp),y. Cold boot: BackSID($0A) ✓. Restarts: 8580($02) — BackSID one-shot protocol per power cycle. hw_test 0/9 (restart fails expected) |
| C34c | 6581 | KungFuSID (new FW) | CTR→D500 | `SIDFX` + `6581` at D400 + `KUNGFUSID` at D500 | 🟢 | V1.3.64/65: new FW ($5A ACK) detected. hw_test 9/9 |
| C34d | 6581 | KungFuSID (old FW) | CTR→D500 | `SIDFX` + `6581` at D400 + `KUNGFUSID` at D500 | ⚠️ | Old FW echoes $A5 — indistinguishable from SIDFX secondary bus latch (any chip echoes last write). Shows as 8580. Not fixable in software. hw_test 9/9 (shows 8580) |
| C34e | 6581 | FPGASID 6581 mode | CTR→D500 | `SIDFX` + `6581` at D400 + `FPGASID-6581` at D500 | 🟢 | V1.3.66: checkfpgasid magic-cookie protocol works at D500. POT regs (base+$19/$1A/$1E/$1F) respond at secondary addr. Baseline: $D400 6581($01) $D500 FPGASID-6581($07). hw_test 9/9 |
| C34f | ARMSID | 8580 (real) | CTR→D500 | `SIDFX` + `ARMSID` at D400 + `8580` at D500 | 🟢 | V1.3.67: SID1=UNKN probe: sfx_probe_dis_echo 'N' at D400. SIDFX reports ARMSID as UNKN (type 3); now probed and identified. Baseline: $D400 ARMSID/ARM2SID($05) $D500 8580($02). hw_test 9/9 |
| C34g | SIDKick Pico 8580 | 8580 (real) | CTR→D500 | `SIDFX` + `SIDKICK-PICO` at D400 + `8580` at D500 | 🟢 | V1.3.68: SID1=UNKN probe: sfx_probe_skpico 'S'+'K' at D400. SIDFX reports SIDKick Pico as UNKN; now detected ($0B, 8580 default). Baseline: $D400 SIDKick-pico-8580($0B) $D500 8580($02). hw_test 9/9 |
| C34h | PD SID | 8580 (real) | CTR→D500 | `SIDFX` + `PD-SID` at D400 + `8580` at D500 | 🟢 | V1.3.69: SID1=UNKN probe: checkpdsid 'P'+'D'→'S' echo at D400. SIDFX reports PD SID as UNKN; now detected ($09). Baseline: $D400 PD-SID($09) $D500 8580($02). hw_test 9/9 |
| C34i | SwinSID Ultimate | 8580 (real) | CTR→D500 | `SIDFX` + `SWINSID-U` at D400 + `8580` at D500 | 🟢 | V1.3.68: SID1=UNKN probe: sfx_probe_dis_echo 'S' echo at D400. SIDFX reports SwinSID U as UNKN; now detected ($04). Baseline: $D400 SwinSID-U($04) $D500 8580($02). hw_test 9/9 |
| C34j | SwinSID Ultimate | SIDKick Pico 8580 | CTR→D500 | `SIDFX` + `SWINSID-U` at D400 + `SIDKICK-PICO` at D500 | 🟢 | V1.3.69: dual replacement chip combination. Baseline: $D400 SwinSID-U($04) $D500 SIDKick-pico-8580($0B). hw_test 9/9 |
| C35b | 6581 | 8580 (real) | CTR→D500 | `SIDFX` + `6581` at D400 + `8580` at D500 | 🟢 | V1.3.65: real 8580 correctly shows 8580($02), no false KungFuSID positive. hw_test 9/9 |
| C35 | 6581 | 6581 | CTR→D500 | `SIDFX` + `6581` at D400 + `6581` at D500 | ⬜ | |
| C36 | 6581 | 8580 | CTR→D500 | `SIDFX` + `6581` at D400 + `8580` at D500 | ⬜ | |
| C37 | 6581 | 6581 | LFT→D420 | `SIDFX` + `6581` at D400 + `6581` at D420 | ⬜ | |
| C38 | 6581 | SIDKick Pico 8580 | LFT→D420 | `SIDFX` + `6581` at D400 + `8580` at D420 | 🟢 | V1.3.58: shows 8580 (probe skipped — D4xx bus conflict); hw_test 9/9 |
| C39 | 6581 | 6581 | RGT→DE00 | `SIDFX` + `6581` at D400 + `6581` at DE00 | ⬜ | |
| C40 | 6581 | SIDKick Pico 8580 | RGT→DE00 | `SIDFX` + `6581` at D400 + `8580` at DE00 | 🟢 | V1.3.58: shows 8580 (probe skipped — DE00 is SIDFX cartridge I/O); hw_test 9/9 |
| C41 | ARMSID | 8580 | CTR→D500 | `SIDFX` + `ARMSID` at D400 + `8580` at D500 | 🟢 | Covered by C34f (confirmed V1.3.67) |
| C42 | SIDKick Pico | 8580 | CTR→D500 | `SIDFX` + `SIDKICK-PICO` at D400 + `8580` at D500 | 🟢 | Covered by C34g (confirmed V1.3.68) |
| C44 | 6581 | ARMSID | LFT→D420 | `SIDFX` + `6581` at D400 + `8580` at D420 | ⚠️ | WONTFIX: ARMSID firmware responds to DIS only via CS1 slot. At D420 (CS2), DIS writes produce no echo at D43B or D41B. SIDFX reports ARMSID as 8580; falls back to SIDFX-reported type. hw_test V1.3.84 confirmed. |
| C45 | 6581 | SIDKick Pico | LFT→D420 | `SIDFX` + `6581` at D400 + `8580` at D420 | ⚠️ | WONTFIX: sfx_probe_skpico needs CS1 (config mode). SIDFX write-buffer caches +$1D writes for any chip (artifact). DIS contaminated by 6581 driving D43B. Falls back to SIDFX-reported type. hw_test V1.3.84 confirmed (shows 8580). |
| C43 | FPGASID 8580 | 8580 | CTR→D500 | `SIDFX` + `8580` at D400 + `8580` at D500 | ⬜ | |
| C43a | FPGASID 8580 (SID1) | SIDKick Pico 8580 | CTR→D500 | `SIDFX` + `FPGASID-8580` at D400 + `SIDKICK-PICO` at D500 | ⚠️ | V1.3.70: FPGASID at SIDFX SID1 undetectable. SIDFX drives D419/D41A (POT) overriding FPGASID identify-mode readback. SIDFX reports SID1=UNKN; probe chain runs but returns $F0. Shows as Unknown/NoSID. Accepted hw limitation. |

### U64 (UltiSID in secondary slots)

| # | D400 (primary) | Secondary | Expected | Result | Notes |
|---|---------------|----------|----------|--------|-------|
| C39 | ARMSID | ULTISID 8580 at D500+D600 | `ARMSID` + `8580 INT` at D500 + `8580 INT` at D600 | 🟢 | User's U64 rig confirmed V1.3.45 hw_test baseline |
| C40 | ARMSID | ULTISID 8580 at DE00 | `ARMSID` + `8580 INT` at DE00 | 🟢 | User's U64 rig confirmed V1.3.45 hw_test baseline |
| C41 | 6581 | ULTISID 8580 at D500 | `6581 Rx` + `8580 INT` at D500 | ⬜ | |
| C42 | 8580 | ULTISID 8580 at D500 | `8580` + `8580 INT` at D500 | ⬜ | |
| C43 | ARMSID | ULTISID 6581 at D500 | `ARMSID` + `6581 INT` at D500 | ⬜ | No 6581 UltiSID in test rig |

---

## Unit Tests (`make ci`)

Last result: **29 / 29** ✅ (2026-04-16 — `$1D` at `$07E8` via `make ci`)

| # | Test | Input | Expected | Result |
|---|------|-------|----------|--------|
| U01 | Machine: C64 | `za7=$FF` | C64 | 🟢 |
| U02 | Machine: C128 | `za7=$FC` | C128 | 🟢 |
| U03 | Machine: TC64 | `za7=$2A` | TC64 | 🟢 |
| U04 | SIDFX found | `data1=$30` | SIDFX YES | 🟢 |
| U05 | SIDFX not found | `data1=$31` | SIDFX NO | 🟢 |
| U06 | Swinsid Ultimate | `data1=$04` | SWINSID-U | 🟢 |
| U07 | ARM2SID dispatch | `data1=$05 d2=$4F d3=$53` | ARM2SID | 🟢 |
| U08 | ARMSID dispatch | `data1=$05 d2=$4F d3=$00` | ARMSID | 🟢 |
| U09 | ARMSID no match | `data1=$05 d2=$00` | NONE | 🟢 |
| U10 | ARMSID no match | `data1=$F0` | NONE | 🟢 |
| U11 | FPGASID 8580 | `data1=$06` | FPGA 8580 | 🟢 |
| U12 | FPGASID 6581 | `data1=$07` | FPGA 6581 | 🟢 |
| U13 | FPGASID no match | `data1=$F0` | NONE | 🟢 |
| U14 | Real 6581 | `data1=$01` | 6581 | 🟢 |
| U15 | Real 8580 | `data1=$02` | 8580 | 🟢 |
| U16 | Real SID no match | `data1=$F0` | NONE | 🟢 |
| U17 | Second SID | `data1=$10` | SECOND SID | 🟢 |
| U18 | No sound | `data1=$F0` | NO SOUND | 🟢 |
| U19 | ArithMean (3 vals) | `mean(10,20,30)` | 20 | 🟢 |
| U20 | ArithMean (6 same) | `mean(5×6)` | 5 | 🟢 |
| U21 | ArithMean (4 vals) | `mean(100,50,75,25)` | 62 | 🟢 |
| U22 | ArithMean (empty) | `mean([])` | 0 | 🟢 |
| U23 | FPGA stereo entry | `$D500, sidnum=0` | sid_list[1] correct | 🟢 |
| U24 | PDsid dispatch | `data1=$09` | PD SID | 🟢 |
| U25 | BackSID dispatch | `data1=$0A` | BACKSID | 🟢 |
| U26 | SIDKick-pico dispatch | `data1=$0B` | SIDKICK-PICO | 🟢 |
| U27 | KungFuSID dispatch | `data1=$0C` | KUNGFUSID | 🟢 |
| U28 | ARM2SID SFX-only | `armsid_emul_mode=$01, armsid_major=ARM2` | ARM2SID SFX mode | 🟢 |
| U29 | ARM2SID SFX+SID | `armsid_emul_mode=$02, armsid_major=ARM2` | ARM2SID SFX+SID mode | 🟢 |

> All 29 unit tests pass as of 2026-04-16. Run `make ci` to verify.

---

## hw_test (automated hardware smoke test)

Last result: **12 / 12** ✅ (2026-04-11 — `python scripts/hw_test.py`)  
Hardware: `[1]$D400 ARMSID($05)  [2]$D420 ARMSID($05)  [3]$DE00 ARMSID($05)  [4]$D500 ULTISID-8580($20)  [5]$D600 ULTISID-8580($20)`

| # | Test | Result |
|---|------|--------|
| H01 | SPACE restart ×3 (stable) | 🟢 |
| H02 | Info screen return (stable) | 🟢 |
| H03 | Debug page 1 return (stable) | 🟢 |
| H04 | Debug page 2 UCI count ≥ 1 | 🟢 |
| H05 | Debug page 2 UCI status not $30 | 🟢 |
| H06 | Debug page 2 UCI F1 hi=$D5 in $D4–$DF | 🟢 |
| H07 | Debug page 2 return (stable) | 🟢 |
| H08 | Readme screen return (stable) | 🟢 |
| H09 | Sound test screen return (stable) | 🟢 |
| H10 | P music toggle (no restart) | 🟢 |

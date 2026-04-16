// =============================================================================
// SID Detector v1.3.72  -  Commodore 64 SID chip identification utility
// by funfun/triangle 3532
// =============================================================================
// Identifies 24+ variants of SID chips and emulators by probing hardware
// registers, measuring timing behaviour, and checking identifying byte
// sequences left in read-back registers.
//
// Detection chain (executed once at startup):
//   1. DETECTSIDFX    - SIDFX cartridge (SCI serial protocol handshake)
//   2. Checkarmsid    - ARMSID / ARM2SID  (register echo "DIS" + "WOR" / "NOR")
//   3. checkfpgasid   - FPGASID           (magic-cookie config + $F51D readback)
//   4. checkrealsid   - real 6581 / 8580  (sawtooth waveform + $D41B readback)
//   5. checksecondsid - additional SID at D500/D600/D700/DE00/DF00
//   6. calcandloop    - $D418 decay timing fingerprint (identifies emulators)
//
// Result codes stored in data1 ($A4):
//   $01=6581  $02=8580  $04=SwinsidU  $05=ARMSID  $06=FPGA8580
//   $07=FPGA6581  $10=secondSID  $30=SIDFX  $F0=unknown/none
//
// Memory layout:
//   $0801  BASIC stub (SYS 2061)
//   $080D  Main program and all subroutines
//   $1D00  Result tables: num_sids, sid_list_l/h/t, sid_map
// =============================================================================

* = $0801
    .word $0801     // BASIC line link (points back to self = end of BASIC)
    .word $0DCC     // BASIC line number (unused, end-of-program marker)
    .byte   $9e     // BASIC token for SYS
    .text "9216"    // decimal address of start: $2400
    .byte   0       // end of BASIC line

// SID music module: Triangle Intro by Michael Troelsen (Fun Fun), 1988
// Load address $1800, init $1800 (A=song-1), play $1806
// Embedded here so code can start at $2400, safely above SID range ($1800-$2387)
.var sidFile = LoadBinary("bin/Triangle_Intro.sid")
* = $1800
    .fill sidFile.getSize() - $7E, sidFile.get(i + $7E)  // skip 126-byte header+load-addr

// TLR's original second SID detector (sid-detect2 by TLR)
// Embedded at $0A00 (free gap). Copied to $0801 and executed when L is pressed.
.var tlrFile = LoadBinary("bin/sid-detect2.prg")
* = $0A00
tlr_data:
    .fill tlrFile.getSize() - 2, tlrFile.get(i + 2)    // skip 2-byte PRG load-address header

// V1.20
// ARM2SID detection - done
// TC64 detection
// SFX Sound expander - half done
// MISTer C64
//
// V1.00
// problem:
// FPGA D400 og D500// you cannot poke FPGAsid for second(sid). Need to test with 2 physical sids. 
//------------------------------------------------------------------------------------------------------------
// todo:
// check for FCiii, and skip like 128 check!!
// unknown sid at D400, should also write in sid_list_h,low,type
// check SwinsidNano by eliminating others. Check if D400 and D500 is mirrored. NoSID will not mirror!!! 
// Turbo Chameleon also has sid emultaion and is detectable
// ARMSID2 detection
// show sterosid of sidfx
// show sterosid of FPGASID
// SWINSID NANO (NOPAD) detection - howto
// ULTISID (U64) - asked
// uSID64 detection - done ($D41F config register readback, $0D)
//
// ----------------------------------------------------------------------------------------------------------
// test case
// D400: 6581 D500:Swindsid     - error
// D400: Swindsid D500:6581     - error
// D400: Swindsid DE00:6851     - error
// D400: 8580 D500:armsid       - 
// D400: armsid D500:8580       - error
// D400: armsid DE00:8580       - error 
// D400: armsid D500:armsid     -  
// D400: Swindsid D500:Swindsid - 
// D400: armsid D500:Swindsid   - OK
// D400: armsid D420:Swindsid   - OK
// D400: 8580 DE00:6581         - OK 
// D400: fpgasid                - 
// D400: swinnano               - 
// D400: ultisid                - 
 


    
// =============================================================================
// Zero-page and constant equates
// =============================================================================

// KERNAL addresses
.const nmivec        = $0318   // NMI interrupt vector (patched during PAL/NTSC check)
.const readkeyboard  = $ffe4   // KERNAL: read keyboard (not used in final build)

// Detection result scratch registers ($A2-$AF)
// These are freely used within detection routines and overwritten between calls.
.const ZPArrayPtr  = $A2   // index into ArrayPtr1/2/3 for ArithmeticMean
.const ZPbigloop   = $A3   // outer loop counter for calcandloop
.const data1       = $A4   // primary result byte (chip type code)
.const data2       = $A5   // secondary result byte (echo char or sub-type)
.const data3       = $A6   // tertiary result byte (ARM2SID 'R' discriminator)
.const za7         = $A7   // machine type: $FF=C64, $FC=C128, other=TC64
.const za8         = $A8   // 16-bit pointer used by checkanothersid (lo)
                            //   za8+1 = high byte
.const sidtype     = $A9   // current chip family being scanned in sidstereostart
                            //   $05=ARMSID/SwinsidU, $06=FPGAsid8580, $07=FPGAsid6581, $01=real
.const tmp2_zp     = $AA   // temporary / sid entry counter in sidstereo_print
.const tmp1_zp     = $AB   // temporary (reserved)
.const tmp_zp      = $AC   // temporary (reserved)
.const y_zp        = $AD   // saved Y register (callee-save convention)
.const x_zp        = $AE   // saved X register (callee-save convention)
.const buf_zp      = $AF   // temporary buffer byte
.const sid_music_flag = $B0 // 0=SID module silent, 1=play $1806 from IRQ
.const colwash_flag   = $B1 // 1=run COLWASH in IRQ, 0=suppress (sub-screens)
.const retry_zp       = $B2 // checkrealsid retry count (0=1st try, 1=2nd, 2=3rd)

// Detection state ($F6-$FF)
.const cnt2_zp  = $F6   // inner mirror-scan step counter (fiktivloop / checkanothersid)
.const sidnum_zp= $F7   // number of SID chips found so far (0-8)
.const cnt1_zp  = $F8   // tab1/tab2 index during multi-SID scan

// SID base-address pointer (updated per scan slot)
// sptr_zp:sptr_zp+1 = low:high byte of the SID register page being tested
//   e.g. $00:$D4 → $D400, $00:$D5 → $D500 etc.
.const sptr_zp  = $F9   // SID address low byte  (always $00 in current use)
.const sptr_zp1 = $FA   // SID address high byte (D4/D5/D6/D7/DE/DF)

// Mirror-scan pointer — used in checksecondsid / fiktivloop / checkanothersid
// mptr_zp:mptr_zp+1 walks through $D4xx..$DFxx in $20 steps
.const scnt_zp  = $FB   // mirror-scan step counter (0-$30 = 48 steps × $20)
.const mptr_zp  = $FC   // mirror-scan address low byte  (00,20,40..E0)
.const mptr_zp1 = $FD   // mirror-scan address high byte (D4,D5,D6..DF)
.const mcnt_zp  = $FE   // index into tab1/tab2 (selects which SID page)
.const res_zp   = $FF   // reserved / result scratch

    
basend:                     // end-of-BASIC marker (two zero bytes)
    .word 0
    *=$2400             // code origin: $2400 = decimal 9216 = SYS target


    
// ============================================================
// ENTRY POINT - invoked by SYS 2061; re-entered when SPACE pressed.
// Order: init tables -> draw screen -> PAL/NTSC -> machine type -> detection chain
// ============================================================
start:
                sei                     // disable IRQ during initialisation
                lda #$00                // silence SID on any restart path
                sta $D418               // master volume = 0
                sta $D404               // voice 1 control (gate off, waveform clear)
                sta $D40B               // voice 2 control (gate off, waveform clear)
                sta $D412               // voice 3 control (gate off, waveform clear — was $D411 which is PW-hi)
                sta $D40F               // voice 3 freq hi (clear $FF left by checksecondsid)
                sta $D41E               // clear FPGASID D41E (write-only in normal mode; harmless)
                sta colwash_flag        // suppress COLWASH until readkey2 enables it
                lda #$15                // $D018: charset ROM at $D000, uppercase/graphics set
                sta $D018               // switch to uppercase character set
                ldx #$00
                lda #$00
                sta data4               // init: no HW SID type saved yet
                sta res_zp              // init: no tentative SwinSID Nano result
                sta retry_zp            // init: no retries yet
init_sid_list:                          // zero the 8-slot SID result tables
                sta sid_list_h,x        // SID address high byte ($D4/$D5 ...)
                sta sid_list_l,x        // SID address low byte  ($00/$20 ...)
                sta sid_list_t,x        // chip type code for this slot
                inx
                cpx #$08               // 8 slots; slot 0 unused, slots 1-7 active
                bne init_sid_list
                
                lda #$00
                sta sid_music_flag      // ensure SID module is silent at startup/restart
                jsr printscreen         // blit static 25x40 UI to screen RAM $0400

                // checkpalntsc patches NMI vector to RTI then checks if a
                // raster IRQ at line $137 fires; result written to $02A6:
                //   1 = PAL  (~50 Hz, 312 raster lines)
                //   0 = NTSC (~60 Hz, 263 raster lines)
                // All timing loops below depend on this value.
                jsr checkpalntsc
                lda $02a6               // read KERNAL PAL/NTSC variable
                beq cntsc               // 0 = NTSC
                txs                     // KERNAL cursor call uses X/Y; TXS preserves X
                ldx #13                 // row 13 = "pal/ntsc..:" screen line
                ldy #13                 // col 13 = result field
                jsr $E50C               // KERNAL $E50C: position cursor (row=X, col=Y)
                tsx
                lda #<pal_text
                ldy #>pal_text
                jsr  $AB1E              // KERNAL $AB1E: print zero-terminated PETSCII string
                jmp check_cbmtype
cntsc:
                txs
                ldx #13
                ldy #13
                jsr $E50C
                tsx
                lda #<ntsc_text
                ldy #>ntsc_text
                jsr  $AB1E
// check128 probes $D030 (C128 speed register; open bus on C64 -> $FF).
// If $D030 != $FF, writes $2A to $D0FE as final arbiter. Result -> za7:
//   $FF = C64,  $FC = C128,  other = TC64 (Turbo Chameleon 64 cartridge)
// The two-register approach also handles FC3 cartridge: FC3 drives $D030 to
// non-$FF but leaves $D0FE as open bus ($FF), so za7 = $FF -> C64 (correct).
check_cbmtype:
                jsr check128
                txs
                ldx #13                 // same row as PAL/NTSC; col 30 for machine label
                ldy #30
                jsr $E50C
                tsx
                lda za7
                cmp #$FF
                bne c128_c128           // not $FF -> check C128 vs TC64
                lda #<c64_text          // $FF = standard Commodore 64
                ldy #>c64_text
                jsr  $AB1E
                jmp ibegin
c128_c128:
                lda za7
                cmp #$FC               // $FC = Commodore 128
                bne c128_tc64
                lda #<c128_text
                ldy #>c128_text
                jsr  $AB1E
                jmp ibegin
c128_tc64:                             // za7 != $FF and != $FC -> Turbo Chameleon 64
                lda #<tc64_text
                ldy #>tc64_text
                jsr  $AB1E

// ============================================================
// Detection sequence
// ============================================================
ibegin:
                // VIC "bad lines" (raster=$FF): CPU stolen ~43 cycles -> corrupt SID writes.
                lda #$ff
iloop1:          cmp $d012               // spin until raster line != $FF
                bne iloop1
                // Busy-wait ~1300 us (256 x ~5 cycles at 1 MHz PAL) so the
                // SIDFX cartridge completes its power-on SCI state-machine init.
                ldx #$00
iloop2:          inx
                bne iloop2

                // --- Step 0: Zero ARMSID version state (queried later, after Checkarmsid confirms chip) ---
                lda     #$00
                sta     armsid_major
                sta     armsid_minor
                sta     armsid_sid_type_h
                sta     armsid_auto_sid
                sta     armsid_emul_mode
                sta     armsid_map_l
                sta     armsid_map_l2
                sta     armsid_map_h
                sta     armsid_map_h2
                sta     is_u64
                sta     fpgasid_sid2_type  // cleared: re-populated by checkfpgasid if FPGASID found
                sta     fpgasid_cpld_rev
                sta     fpgasid_fpga_rev

                // --- Step 0.1: Detect Ultimate64 via UCI Status Register ---
                // UCI is mapped by default to $DF1C-$DF1F on Ultimate64.
                // $DF1F = UCI Status: returns 0 (idle) on U64; open bus ($FF) on real C64.
                // Any hardware without UCI at $DF1F will read $FF here.
                lda     $DF1F
                cmp     #$FF
                beq     step01_done         // $FF = open bus = not U64
                lda     #$01
                sta     is_u64              // confirmed Ultimate64
step01_done:

                // --- Step 0.25: Real SID pre-check (no D41F writes — safe to run early) ---
                // checkrealsid uses only D412/D40F/D41B — never D41F.
                // Running it here lets us skip checkswinsidnano for real 6581/8580,
                // preventing false "SwinSID Nano found" on real SID hardware.
                // A second checkrealsid probe is also run inline at step 2 to guard
                // against MixSID interference (see step 2 comment for details).
                // (checkrealsid will run again at its normal Step 6 position to print the result.)
                lda #$00
                sta sptr_zp             // SID base low = $00
                lda #$D4
                sta sptr_zp+1           // SID base high = $D4
                jsr checkrealsid
                lda data1
                cmp #$01
                beq step0_real_save
                cmp #$02
                bne step0_real_skip
step0_real_save:
                jmp step1_sidfx         // real SID confirmed → skip SwinSID Nano test
step0_real_skip:

                // --- Step 0.5: SwinSID Nano (must run before any $D41F writes) ---
                // DETECTSIDFX and Checkarmsid both write to $D41F which permanently
                // disturbs SwinSID Nano mode.  Test while SID registers are still clean.
                jsr checkswinsidnano
                lda data1
                cmp #$08
                bne step1_sidfx         // not SwinSID Nano → continue
                // Tentative SwinSID Nano. uSID64 triggers the same OSC3 pattern.
                // Veto: run checkusid64 now (D41F writes safe — SwinSID Nano test done).
                jsr checkusid64
                lda data1
                cmp #$0D
                bne csn_not_usid64      // not uSID64 → confirmed SwinSID Nano
                txs
                ldx #$0E               // row 14 = "USID64.....:"
                ldy #13
                jsr $E50C
                tsx
                lda #<usid64f
                ldy #>usid64f
                jsr $AB1E
                jmp end
csn_not_usid64: lda #$08
                sta res_zp              // save tentative SwinSID Nano; continue detection chain
                jmp step1_sidfx         // magic-key detections (SIDFX, ARMSID…) take priority
step1_sidfx:
                // --- Step 1: SIDFX ---
                // Sends SCI "PNP" login ($80 $50 $4E $50) via D41E/D41F serial pins.
                // Reads back 4 vendor/product ID bytes; checks for $45 $4C $12 $58.
                // data1=$30 = SIDFX found,  data1=$31 = not found.
                jsr DETECTSIDFX

                ldx data1
                cpx #$30               // $30 = SIDFX confirmed
                bne nosidfxl
                lda #$30
                sta data4              // remember SIDFX was found
                txs
                ldx #12                // row 12 = "sidfx......:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<sidfxu
                ldy #>sidfxu
                jmp sidfxprint
nosidfxl:
                txs
                ldx #12
                ldy #13
                jsr $E50C
                tsx
                lda #<nosidfxu
                ldy #>nosidfxu 
sidfxprint:
                jsr $AB1E
step2_armsid:
                // --- Step 2: ARMSID / ARM2SID / Swinsid Ultimate ---
                // MixSID C06 approach: single CS2-DIS window.
                //
                // MixSID C06 config: 6581@CS1 (D400-D41F) + ARMSID@CS2 (D420-D43F).
                // ARMSID snoops ALL bus writes regardless of chip-select.  Writing the
                // DIS trigger sequence ('D'/'I'/'S') to CS1 addresses would cause
                // ARMSID to enter DIS mode and drive D41B with $4E, preventing the
                // 6581 OSC3 sawtooth from being read.
                //
                // Fix: enter DIS mode via CS2 direct (D43F/D43E/D43D).  While ARMSID
                // is in CS2-DIS mode it does NOT drive D41B — reading D41B during the
                // DIS window gets the genuine 6581 OSC3 waveform.  Then read D43B to
                // exit DIS (ACK), and check whether 6581/8580 was detected.
                //
                // Pre-clean voice3 at both CS1 and CS2 for a consistent oscillator
                // state.  D41F is written first to reset the U64 FPGA uSID64 state
                // machine — if debug page 2 ran checkusid64 internally, D41F could be
                // left in a partially-armed state that triggers false uSID64 detection
                // on the next run unless explicitly cleared here.
                // CS2 voice3 oscillator reset: TEST bit locks the accumulator at 0 and
                // resets the LFSR to its chip-specific seed.  Without this, checkrealsid
                // (run when fiktivloop identifies the secondary SID type) leaves the CS2
                // voice3 accumulator at a non-zero value.  On the next restart, step2_armsid
                // zeroes freq but not the accumulator, so D43B (OSC3) reads non-zero →
                // checksecondsid falsely fails at D420 and the scan drifts to D4A0 etc.
                // Writing TEST then $00 guarantees accumulator=0 going into the scan.
                // Mirror detection at D440+ still works: checkrealsid for D420 advances
                // the LFSR past the reset seed via bit-19 oscillator transitions (~28 cycles
                // at freq=$4800), so Check 1 sees a non-zero LFSR value at D440+.
                lda #$08
                sta $D432               // CS2 voice3 ctrl = TEST (reset osc + LFSR)
                lda #$00
                sta $D41F               // reset CS1 D41F (uSID64 state machine reset)
                sta $D412               // CS1 voice3 ctrl = 0
                sta $D40F               // CS1 voice3 freq hi = 0
                sta $D40E               // CS1 voice3 freq lo = 0
                sta $D432               // CS2 voice3 ctrl = 0 (TEST cleared; osc frozen at 0)
                sta $D42F               // CS2 voice3 freq hi = 0 (D420+$0F)
                sta $D42E               // CS2 voice3 freq lo = 0 (D420+$0E)
                sta $D438               // CS2 volume = 0 (D420+$18)
                sta $D43D               // CS2 D41D = 0 x3 (D420+$1D)
                sta $D43D
                sta $D43D
                jsr loop1sek            // pre-DIS settle
                jsr loop1sek
                lda #$44                // 'D' -> D43F (CS2)
                sta $D43F
                lda #$49                // 'I' -> D43E (CS2)
                sta $D43E
                lda #$53                // 'S' -> D43D (CS2)
                sta $D43D
                jsr loop1sek            // post-DIS-trigger settle
                jsr loop1sek
                // checkrealsid at D400 inside CS2-DIS window (D43B not yet read)
                lda #$00
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jsr checkrealsid        // probe 6581/8580 OSC3
                // Read D43C (data2) while DIS still active, then D43B (ACK exits DIS)
                lda $D43C               // 'O'=$4F=ARMSID, 'W'=$57=SwinsidUlt
                sta data2
                lda $D43B               // ACK: exits DIS; 'N'=$4E=ARMSID, 'S'=$53=SwinsidUlt
                sta tmp_zp              // save D43B for dispatch below
                // Dispatch real SID BEFORE CS2 cleanup: D43x holds 'D'/'I'/'S' from
                // DIS entry; zeroing them before checkusid64 triggers false uSID64
                // detection via U64 FPGA state machine.
                lda data1
                cmp #$01                // 6581 confirmed at D400?
                beq step2_skip_armsid
                cmp #$02                // 8580 confirmed at D400?
                beq step2_skip_armsid
                // Not a real SID — CS2 cleanup before ARMSID/SwinsidU/fallback
                lda #$00
                sta $D438
                sta $D43D
                sta $D43D
                sta $D43D
                sta $D43E
                sta $D43E
                sta $D43E
                sta $D43F
                sta $D43F
                sta $D43F
                jsr loop1sek
                jsr loop1sek
                // Check D43B ACK for ARMSID/SwinsidU at D420
                lda tmp_zp
                cmp #$4E                // 'N' -> ARMSID at D420
                beq step2_armsid_found
                cmp #$53                // 'S' -> SwinSID Ultimate at D420
                beq step2_swinsidu_d420
                // Fallback: Checkarmsid at D400
                lda #$00
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jsr Checkarmsid
                jmp step2_after_armsid
step2_swinsidu_d420:
                lda #$04                // SwinsidU confirmed at CS2
                sta data1
                lda #$20
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jmp step2_after_armsid
step2_armsid_found:
                // ARMSID confirmed at D420; data2 already set from D43C above
                lda #$05
                sta data1
                lda #$20
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jmp step2_after_armsid
step2_skip_armsid:
                lda #$F0                // report: no ARMSID/SwinsidU at D400
                sta data1
                jmp checkpdsid_step     // skip remaining step-2 dispatch
step2_after_armsid:
                ldx data1
                cpx #04                // $04 = 'S' in D41B -> Swinsid Ultimate
                bne armsid
                txs
                ldx #03                // row 3 = "swinsid...:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<swinsidUf
                ldy #>swinsidUf
                jsr $AB1E
                jmp end
armsid:
                // data1=$05 -> 'N' echo detected -> ARMSID family.
                ldx data1
                cpx #05                // $05 = 'N' -> ARMSID family; else try PDsid
                bne checkpdsid_step
                ldx data2
                cpx #$4f               // 'O'=$4F must be in D41C for both variants
                bne checkpdsid_step
                // Confirmed ARMSID family at D400. Now query firmware version + II probe.
                // Called here (not at startup) so ARM2SID has been powered on long enough.
                jsr armsid_get_version
                lda armsid_major
                cmp #$03               // firmware major version 3 -> ARM2SID confirmed
                bne armsidlo
                // ARM2SID confirmed (armsid_major=$03)
                txs
                ldx #02                // row 2 = "armsid....:" line
                ldy #13
                jsr $E50C
                // emul_mode=0: "ARM2SID FOUND V3.xx L 6581"
                // emul_mode=1: "ARM2SID +SFX  V3.xx L"        (SFX only — no SID type)
                // emul_mode=2: "ARM2SID +SFX  V3.xx L 6581"   (SFX+SID)
                lda armsid_emul_mode
                and #$03
                beq arm2_print_found   // mode=0: normal "FOUND" string
                lda #<arm2sid_sfxf
                ldy #>arm2sid_sfxf
                jsr $AB1E              // "ARM2SID +SFX "
                jmp arm2_print_ver
arm2_print_found:
                lda #<arm2sidf
                ldy #>arm2sidf
                jsr $AB1E              // "ARM2SID FOUND"
arm2_print_ver:
                jsr print_armsid_ver   // " V3.xx"
                jsr print_armsid_ch    // " L" or " R"
                lda armsid_emul_mode
                and #$03
                cmp #$01               // SFX only? → skip SID type
                beq arm2_sfx_done
                lda #$20
                jsr $FFD2
                jsr print_sid_type_4   // "6581" or "8580"
arm2_sfx_done:
                jmp end
                tsx                    // unreachable; kept for padding
armsidlo:
                // Plain ARMSID (armsid_major != $03)
                txs
                ldx #02
                ldy #13
                jsr $E50C
                tsx
                lda #<armsidf
                ldy #>armsidf
                jsr $AB1E
                jsr print_armsid_ver   // append " V2.xx"
                lda #$20
                jsr $FFD2
                jsr print_sid_type_4   // append "6581" or "8580"
                jmp end
// --- Step 3: PDsid ---
// Write 'P'=$50 to D41D, 'D'=$44 to D41E; read back D41E.
// If reads 'S'=$53 → PDsid confirmed (data1=$09).
checkpdsid_step:
                lda #$00
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jsr checkpdsid
                ldx data1
                cpx #$09               // $09 = PDsid confirmed
                bne checkbacksid_step
                txs
                ldx #10                // row 10 = "PD SID....:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<pdsidf
                ldy #>pdsidf
                jsr $AB1E
                jmp end

// --- Step 3b: BackSID ---
// Protocol: write D41B=$02, D41C=$01, D41D=$B5, D41E=$1D; poll D41F up to 15x.
// checkbacksid polls every ~42ms (re-writes D41B each time, matches backsid.prg).
checkbacksid_step:
                lda #$00
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jsr checkbacksid
                ldx data1
                cpx #$0A               // $0A = BackSID confirmed
                bne checkskpico_step
                txs
                ldx #08                // row 8 = "BACKSID....:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<backsidf
                ldy #>backsidf
                jsr $AB1E
                jmp end

// --- Step 3c: SIDKick-pico ---
// Write $FF to D41F (enter config mode), $E0 to D41E (VERSION_STR pointer),
// read D41D: byte[0]='S'/$53, byte[1]='K'/$4B → SIDKick-pico (data1=$0B).
checkskpico_step:
                lda #$00
                sta sptr_zp
                lda #$D4
                sta sptr_zp+1
                jsr checkskpico
                ldx data1
                cpx #$0B               // $0B = SIDKick-pico 8580
                beq cskp_disp
                cpx #$0E               // $0E = SIDKick-pico 6581
                bne fpgasid
cskp_disp:
                txs                    // save data1 ($0B/$0E) in SP
                ldx #07                // row 7 = "SIDKICK....:" line
                ldy #13
                jsr $E50C
                tsx                    // restore data1 to X
                cpx #$0E               // 6581?
                bne cskp_print_8580
                lda #<skpicof_6581
                ldy #>skpicof_6581
                jsr $AB1E
                jmp cskp_fm_disp
cskp_print_8580:
                lda #<skpicof
                ldy #>skpicof
                jsr $AB1E
cskp_fm_disp:
                // Append "+FM" if config[8] is 4 or 5 (FM_ENABLE = 6 - config[8] > 0).
                lda skpico_fm
                cmp #$04
                bcc cskp_no_fm          // < 4: no FM
                cmp #$06
                bcs cskp_no_fm          // >= 6: FM_ENABLE=0, not active
                lda #$2B                // '+'
                jsr $FFD2
                lda #$46                // 'F'
                jsr $FFD2
                lda #$4D                // 'M'
                jsr $FFD2
cskp_no_fm:     jmp end

// --- Step 4: FPGASID ---
// Writes magic cookie $81/$65 to D419/D41A to enter config mode,
// sets D41E bit 7, then reads back D419/D41A expecting $1D/$F5 ($F51D).
// D41F=$3F -> 8580 mode (data1=$06); D41F=$00 -> 6581 mode (data1=$07).
fpgasid:
                lda #$00
                sta sptr_zp             // point sptr_zp at $D400
                lda #$d4
                sta sptr_zp+1
                jsr checkfpgasid
                ldx data1
                cpx #$06               // $06 = FPGASID in 8580 mode
                bne fpgasidf_6581_l
                txs
                ldx #04                // row 4 = "fpgasid...:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<fpgasidf_8580u
                ldy #>fpgasidf_8580u
                jsr $AB1E
                jmp end
fpgasidf_6581_l:
                ldx data1
                cpx #$07               // $07 = FPGASID in 6581 mode
                bne checkusid64_entry
                txs
                ldx #04
                ldy #13
                jsr $E50C
                tsx
                lda #<fpgasidf_6581u
                ldy #>fpgasidf_6581u
                jsr $AB1E
                jmp end                
// --- Step 3b: uSID64 ---
// Write config unlock seq $F0,$10,$63,$00,$FF to $D41F, read back.
// uSID64 returns $E0-$FC (top nibble $F, never exactly $FF).
// Real SID, NOSID, and Swinsid Nano all return $FF or values below $E0.
// data1=$0D -> uSID64
checkusid64_entry:
                jsr checkusid64
                lda data1
                cmp #$0D
                bne checkphysical
                txs
                ldx #$0E               // row 14 = "USID64.....:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<usid64f
                ldy #>usid64f
                jsr $AB1E
                jmp end

// --- Step 4: Real SID ---
// Activates sawtooth waveform on voice 3, then reads D41B (OSC3 register).
// Real SIDs return specific values; emulators/no-SID fail the check.
// data1=$01 -> 6581,  data1=$02 -> 8580
checkphysical:
                lda     #$00
                sta     sptr_zp
                lda     #$d4
                sta     sptr_zp+1
                lda $D41B               // ACK: ARMSID tristate trigger (CS1 read; result discarded)
                                        // MixSID C06 (6581@CS1 + ARMSID@CS2): if Checkarmsid ran
                                        // above and triggered ARMSID DIS mode, ARMSID drives $4E
                                        // on D41B regardless of CS2 state.  Reading D41B here as a
                                        // CS1 access signals ARMSID to tristate before checkrealsid.
                jsr checkrealsid
                lda data1
                sta $5801               // DIAG: save step-4 checkphysical result ($5801)
                ldx data1
                cpx #$01               // $01 = 6581 confirmed
                bne checkphysical_8580
                txs
                ldx #05                // row 5 = "6581 sid..:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<l6581f
                ldy #>l6581f
                jsr $AB1E
                jsr print_retry_star   // append '*' if any retries were needed
                jmp end
checkphysical_8580:
                ldx data1
                cpx #$02               // $02 = 8580 confirmed
                bne checkphysical2
                txs
                ldx #06                // row 6 = "8550 sid..:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<l8580f
                ldy #>l8580f
                jsr $AB1E
                jsr print_retry_star   // append '*' if any retries were needed
                jmp end
// --- Step 5: second SID scan ---
// Use noise-waveform mirror trick: real SID at $D41B generates non-zero values,
// while a mirrored address always reads 0.  data1=$10 if a second slot is found.
checkphysical2:
                lda #$00
                sta mptr_zp             // start mirror scan at $D400
                lda #$d4
                sta mptr_zp+1
                jsr checksecondsid
                ldx data1
                cpx #$10               // $10 = second SID slot detected
                bne swinmicro
                txs
                ldx #11                // row 11 = "nosid......:" (shows UNKNOWN here)
                ldy #13
                jsr $E50C
                tsx
                lda #<unknownsid
                ldy #>unknownsid
                jsr $AB1E
                jmp end
swinmicro:
                // checkswinmicro disabled: causes false positives on boards with no SID.
                //jsr checkswinmicro
                // --- Step 5b: KungFuSID (all other hardware checks exhausted) ---
                // Old firmware: D41D echoes last write ($A5 → $A5).
                // New firmware: D41D returns $5A (FW_UPDATE_START_ACK).
                jsr checkkungfusid     // A = $0C (found) or $F0 (not found)
                cmp #$0C
                bne check_swin_nano
                ldx #09                // row 9 = "KUNGFUSID.:" line
                ldy #13
                jsr $E50C
                lda #<kungfusidf
                ldy #>kungfusidf
                jsr $AB1E
                jmp end
// --- Step 5c: Swinsid Nano ---
// All other hardware checks exhausted. If noise waveform on voice 3
// produces non-zero output at D41B, a Swinsid Nano is present.
// A completely empty socket returns $00 (open bus).
check_swin_nano:
                // SwinSID Nano was already tested at Step 0.5 (before any $D41F writes).
                // res_zp = $08 if tentative result was saved; $00 → fall through to nosound.
                lda res_zp
                cmp #$08
                bne nosound
                txs
                ldx #03                // row 3 = "swinsid...:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<swinsidnanof
                ldy #>swinsidnanof
                jsr $AB1E
                jmp end
nosound:                               // no SID chip detected
                txs
                ldx #11                // row 11 = "nosid......:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<nosoundf
                ldy #>nosoundf
                jsr $AB1E 
                
// ============================================================
// Post-detection: multi-SID scan, decay fingerprint, IRQ loop
// ============================================================
end:
                lda data4               // SIDFX already detected? keep data4=$30
                cmp #$30
                beq end_skip_save
                lda data1               // save detected chip type for info page
                cmp #$F0
                beq end_skip_save       // $F0 = unknown; keep any SIDFX flag in data4
                sta data4
end_skip_save:
                lda #$00
                sta sidnum_zp           // reset found-SID counter before multi-SID scan

                // Pre-populate sid_list[1] = D400 for chip types whose D4xx outer scan is
                // skipped (ARMSID/SwinSID U) or bypassed (real SID uses fiktivloop_d400).
                // SIDFX: directly populate D400 + secondary SID from saved D41D/D41E.
                lda data4
                cmp #$30               // SIDFX: check first; block too large for short branch
                bne end_sfx_not_sidfx
                jsr sidfx_populate_sid_list
                jmp end_pre_d400_skip
end_sfx_not_sidfx:
                cmp #$04
                beq end_pre_d400
                cmp #$05
                beq end_pre_d400
                cmp #$06                // FPGASID 8580: pre-populate D400 with correct type
                beq end_pre_d400
                cmp #$07                // FPGASID 6581: pre-populate D400 with correct type
                beq end_pre_d400
                cmp #$08                // Swinsid Nano: single chip at D400, no stereo
                beq end_pre_d400
                cmp #$0A                // BackSID: pre-populate D400; stereo scan skipped
                beq end_pre_d400
                cmp #$0B                // SIDKick-pico 8580: only at D400, mirrors across D4xx-D7xx
                beq end_pre_d400
                cmp #$0E                // SIDKick-pico 6581: same
                beq end_pre_d400
                cmp #$01
                beq end_pre_d400
                cmp #$02
                beq end_pre_d400
                cmp #$0C               // KungFuSID: always single at D400
                beq end_pre_d400
                cmp #$0D               // uSID64: always single at D400
                beq end_pre_d400
                jmp end_pre_d400_skip  // unknown type → no pre-populate
end_pre_d400:
                ldx #$01
                stx sidnum_zp
                lda data4
                sta sid_list_t,x        // chip type ($04 or $05)
                lda #$00
                sta sid_list_l,x        // low byte = $00
                lda #$D4
                sta sid_list_h,x        // high byte = $D4 → D400
end_pre_d400_skip:

                // Scan all SID address slots (D4xx..DFxx in $20 increments)
                // for each chip family; record results in sid_list_h/l/t.
                // BackSID scans first so other detection writes don't disturb its echo state.
                lda #$00
                sta tmp_zp              // init stereo spinner counter (IRQs off; can't use $A2)
                lda #$0A                // $0A = BackSID family (first: cleanest SID register state)
                sta sidtype
                jsr sidstereostart

                lda #$05                // $05 = ARMSID / Swinsid Ultimate family
                sta sidtype
                lda armsid_major
                cmp #$03                // ARM2SID: use map-based list (accurate + consistent)
                bne end_arm_scan        // not ARM2SID → normal scan
                jsr arm2sid_populate_sid_list
                jmp end_arm_done
end_arm_scan:
                jsr sidstereostart
end_arm_done:

                lda #$06                // $06 = FPGAsid family
                sta sidtype
                jsr sidstereostart

                lda #$09                // $09 = PDsid family
                sta sidtype
                jsr sidstereostart

                lda #$0B                // $0B = SIDKick-pico family
                sta sidtype
                jsr sidstereostart

                // Real SID stereo: fiktivloop_d400 sets up D400 as scan base and calls
                // fiktivloop. D400 is already pre-populated; fiktivloop skips it (noise
                // check on primary returns non-zero), skips D420-D7xx mirrors, and finds
                // real independent second SIDs (DE/DF area or actual stereo cartridge).
                // ARM2SID: skip fiktivloop if not on U64 — map-based list is complete.
                // ARM2SID+U64: run fiktivloop to find UltiSID at addresses outside ARM2SID
                // map (e.g. D600). Dedup in fll_found_ok prevents double-counting ARM2SID slots.
                lda armsid_major
                cmp #$03
                bne end_skip_arm2sid    // not ARM2SID → run fiktivloop normally
                lda is_u64
                beq end_skip_fiktiv     // ARM2SID + not U64 → skip fiktivloop
end_skip_arm2sid:
                // Set sidtype = primary chip type so fiktivloop's f_l_l_found
                // calls checkfpgasid (not checkrealsid) for FPGASID secondaries.
                // SIDFX: skip fiktivloop — noise-mirror trick fails (D5xx mirrors D4xx noise)
                // SwinSID U: skip fiktivloop — OSC3 (D41B) returns 0 with noise enabled on
                // AVR-based emulators, so checksecondsid falsely detects D500 as a second SID.
                // SwinSID U is always a single-slot device; no stereo config exists.
                lda data4
                cmp #$30
                beq end_skip_fiktiv
                cmp #$04                // SwinSID Ultimate: always single-slot
                beq end_skip_fiktiv
                sta sidtype
                jsr fiktivloop_d400
end_skip_fiktiv:

                // If no SID was found at any address, record D400 as unknown ($F0)
                // so the stereo display shows something rather than being blank.
                lda sidnum_zp
                bne end_sid_found
                ldx #$01
                stx sidnum_zp
                lda #$F0
                sta sid_list_t,x
                lda #$00
                sta sid_list_l,x
                lda #$D4
                sta sid_list_h,x
end_sid_found:
                lda #$13                // restore 'S' at $0680 (spinner left it on last frame)
                sta $0680
                jsr backsid_post_fixup  // print stereo SIDs + fix row 8 if BackSID found

                // --- Step 6: $D418 decay fingerprint ---
                // Skipped when a chip was already identified by magic detection
                // (data4 != $F0).  The decay profile is only meaningful for
                // emulators that fall through to nosound (data4 = $F0).
                lda data4
                cmp #$F0
                bne skip_decay          // magic ID → skip decay, print "N/A"

                lda #$00
                sta tmp_zp          // init spinner frame index
                jsr calcandloop
funny_print:
                lda #$24                // '$' screencode: restore after decay done
                sta $0658
                ldx #15                 // row 15 = "$d418 decay:" line
                ldy #13
                jsr $E50C
                jsr checktypeandprint   // classify and print the decay fingerprint
                jmp after_decay

skip_decay:
                lda #$24                // restore '$' spinner char on decay row
                sta $0658               // row 15, col 0
                lda #$0E               // 'N' (screen code)
                sta $0665               // row 15, col 13
                lda #$2F               // '/'
                sta $0666
                lda #$01               // 'A'
                sta $0667

after_decay:
                // cursor cleanup via $AB1E removed: we now write directly to screen RAM,
                // so no KERNAL cursor artifact exists at row 0 to erase.

                jsr colorize_rows       // colour-code result rows in $D800

//debugm2         jsr readkeyboard
//                beq debugm2

// Install a raster IRQ at line 0 for the colour-wash animation and
// spacebar detection.  The IRQ fires once per frame (~50/60 Hz).
readkey2:
           // Reset stack pointer to $FF before enabling the IRQ.
           // calcandloop uses txs/tsx to preserve X across jsr calls, which
           // leaves SP at the loop-counter value (~6).  With SP that low the
           // IRQ entry sequence (hardware P/PCL/PCH + handler A/X/Y + two jsr
           // frames) overflows the page-1 stack, wraps, and corrupts itself.
           ldx #$FF
           txs                     // SP = $FF: full, empty stack
           ldx #<IRQ
           ldy #>IRQ
           lda #$00
           stx $0314               // CIA1 IRQ vector low byte  -> our IRQ handler
           sty $0315               // CIA1 IRQ vector high byte
           sta $D012               // trigger raster IRQ at line 0
           lda #$7F
           sta $DC0D               // CIA1: disable timer IRQs (VIC raster only)
           lda #$1B
           sta $D011               // VIC ctrl: enable display, select raster IRQ source
           lda #$01
           sta $D01A               // VIC IRQ mask: enable raster IRQ (bit 0)
           sta colwash_flag        // enable COLWASH animation on main screen
           cli                     // re-enable interrupts

// ============================================================
// Keyboard polling loop — direct CIA1 matrix scan.
// SCNKEY ($FF9F) + GETIN ($FFE4) is unreliable when CIA1 timers
// are disabled: SCNKEY may skip the keyboard scan internally.
// Instead, we read the hardware directly:
//   $DC00 = row select (write 0 to select a row)
//   $DC01 = column read (bit 0 = pressed, active low)
// Row 7 ($DC00 = $7F):  bit 4 = SPACE,  bit 6 = Q
// Row 4 ($DC00 = $EF):  bit 1 = I
// Debounce: wait until SPACE, Q and I are all released before polling.
// ============================================================
kbdwait:
           lda #$7F                // select row 7
           sta $DC00
           lda $DC01               // read columns (0 = pressed)
           and #$50                // mask bit 4 (SPACE) + bit 6 (Q)
           cmp #$50                // both released?
           bne kbdwait
           lda #$EF                // select row 4
           sta $DC00
           lda $DC01
           and #$02                // bit 1 = I
           beq kbdwait             // I still held; keep waiting
           lda #$FB                // select row 2
           sta $DC00
           lda $DC01
           and #$02                // bit 1 = R
           beq kbdwait             // R still held; keep waiting
           lda #$FB                // select row 2 (T = bit 6)
           sta $DC00
           lda $DC01
           and #$40                // bit 6 = T
           beq kbdwait             // T still held; keep waiting
           lda #$DF                // select row 5
           sta $DC00
           lda $DC01
           and #$06                // bit 1 = P, bit 2 = L
           cmp #$06                // both released?
           bne kbdwait             // P or L still held; keep waiting
kbdloop:
           lda #$7F                // select row 7
           sta $DC00
           lda $DC01               // read columns
           tax                     // save
           and #$10                // bit 4 = SPACE (0 = pressed)
           bne kbd_not_space
           jmp do_restart
kbd_not_space:
           txa
           and #$40                // bit 6 = Q (0 = pressed)
           bne kbd_not_q
           jmp do_quit
kbd_not_q:
           lda #$EF                // select row 4
           sta $DC00
           lda $DC01
           and #$02                // bit 1 = I (0 = pressed)
           beq do_info
           lda #$FB                // select row 2 (D=bit2, R=bit1, T=bit6)
           sta $DC00
           lda $DC01
           sta buf_zp              // save row 2 reading
           and #$04                // bit 2 = D
           beq do_debug
           lda buf_zp
           and #$02                // bit 1 = R
           beq do_readme
           lda buf_zp
           and #$40                // bit 6 = T
           beq do_soundtest
           lda #$DF                // select row 5
           sta $DC00
           lda $DC01
           sta buf_zp              // save row 5 reading
           and #$02                // bit 1 = P
           beq do_sid_music
           lda buf_zp
           and #$04                // bit 2 = L
           beq do_tlr
           jmp kbdloop
do_sid_music:
           lda sid_music_flag
           bne sid_music_stop      // already playing → stop
           sei                     // guard init against mid-frame IRQ call to $1806
           ldx #$00
           ldy #$00
           lda #$00                // subtune 0 = song 1
           jsr $1800               // SID init: Triangle Intro
           lda #$01
           sta sid_music_flag      // arm IRQ play
           cli
           jmp sid_key_wait
sid_music_stop:
           sei
           lda #$00
           sta sid_music_flag      // disarm IRQ play
           sta $D418               // silence volume register
           cli
sid_key_wait:
           lda #$DF                // wait for P to be released before returning
           sta $DC00
           lda $DC01
           and #$02                // bit 1 = P
           beq sid_key_wait
           jmp kbdloop
do_info:
           jmp info_entry          // Info screen
do_debug:
           jmp debug_entry         // Debug info screen
do_readme:
           jmp readme_entry        // README scrollable viewer
do_soundtest:
           jmp sound_test_entry    // SID sound test
do_tlr:
           jmp tlr_entry           // TLR second SID detector (copies to $0801, jmp $0815)
do_restart:
           lda #$00
           sta sid_music_flag      // stop SID module before restart
           jmp start

do_quit:
           sei
           lda #$00
           sta $D019               // clear VIC IRQ flags
           sta $D01A               // disable VIC raster IRQ
           lda #$81
           sta $DC0D               // re-enable CIA1 timer A (keyboard scan)
           sta $DD0D               // re-enable CIA2 timer A
           lda #$31                // restore $0314/$0315 to KERNAL default ($EA31)
           sta $0314
           lda #$EA
           sta $0315
           cli
           jsr $FF81               // KERNAL: reset I/O and screen colours
           jsr $E544               // KERNAL: clear screen
           lda #<goodbye_text
           ldy #>goodbye_text
           jsr $AB1E               // print goodbye message
           jmp $E37B               // KERNAL warm-start BASIC -> READY prompt

goodbye_text:
           .text "GOODBYE"
           .byte 13, 0             // CR + null terminator

// ============================================================
// TLR SECOND SID DETECTOR LAUNCHER
// tlr_entry: jumped to from do_tlr when L is pressed.
// 1. Clears screen.
// 2. Copies sid-detect2 (489 bytes, tlr_data $0A00) to $0801.
// 3. Patches TLR's exit JMP at $08CA: $A474→tlr_wait, so
//    SPACE key returns to siddetector instead of going to BASIC.
// 4. Jumps to $0815 (SYS 2069 = TLR ML entry).
// ============================================================
tlr_entry:
           sei
           lda #$00
           sta sid_music_flag      // disarm SID music IRQ
           sta $D418               // silence volume register
           sta $D01A               // disable VIC raster IRQ
           // Clear screen RAM and colour RAM
           lda #$20                // space screencode
           ldx #$00
tlr_cls:
           sta $0400,x
           sta $0500,x
           sta $0600,x
           sta $0700,x
           lda #$01                // white
           sta $D800,x
           sta $D900,x
           sta $DA00,x
           sta $DB00,x
           lda #$20
           inx
           bne tlr_cls
           // Copy page 0: 256 bytes (tlr_data $0A00-$0AFF → $0801-$0900)
           ldy #$00
tlr_cp0:
           lda tlr_data,y
           sta $0801,y
           iny
           bne tlr_cp0
           // Copy page 1: 233 bytes (tlr_data+256 $0B00-$0BE8 → $0901-$09E9)
           ldy #$00
tlr_cp1:
           lda tlr_data+256,y
           sta $0901,y
           iny
           cpy #233                // 489 - 256 = 233 remaining bytes
           bne tlr_cp1
           // Patch TLR's exit: JMP $A474 at $08CA → JMP tlr_wait.
           // $08CA holds opcode $4C (unchanged); $08CB/$08CC = target address.
           lda #<tlr_wait
           sta $08CB               // lo byte of patched jump target
           lda #>tlr_wait
           sta $08CC               // hi byte of patched jump target
           // Patch TLR's leading CR before the title ($08CD = $0D) → $13 (HOME).
           // HOME positions cursor to row 0 without scrolling, so the title
           // "SID-DETECT2 / TLR" lands on the top line and stays there.
           lda #$13                // PETSCII HOME: cursor to (0,0), no scroll
           sta $08CD               // replaces leading $0D in TLR title string
           // Patch TLR's trailing CR after title ($08DF = $0D) → $00 (end of string).
           // TLR scans 96 SID slots (12 SID MAP rows) + up to 8 SID list rows = 25 rows.
           // Without this patch the last entry's CR scrolls the screen, losing row 0.
           lda #$00
           sta $08DF               // removes trailing $0D after "SID-DETECT2 / TLR"
           // Reset KERNAL cursor to row 0, col 0 so TLR starts printing from the top.
           // (screen RAM was cleared above but KERNAL cursor ZP vars were not reset)
           lda #$00
           sta $D3                 // cursor column = 0
           sta $D6                 // current row = 0
           sta $D1                 // screen pointer lo = $00
           lda #$04
           sta $D2                 // screen pointer hi = $04 → $0400 (row 0)
           // Jump to TLR machine code entry point
           jmp $0815               // SYS 2069 = TLR detector ML start

// ============================================================
// tlr_wait: TLR's patched exit JMP lands here.
// Writes "PRESS SPACE TO RETURN" directly to row 24 screen RAM
// (no KERNAL print, so the screen never scrolls).
// Then waits for SPACE and restarts siddetector.
// ============================================================
tlr_wait:
           // Write "PRESS SPACE TO RETURN" to row 24 screen RAM (centred at col 9).
           // Row 24 = $0400 + 24*40 = $07C0; col 9 → $07C9.
           ldx #$00
tlr_writ:
           lda tlr_msg_text,x
           beq tlr_wait_rel        // null = done
           sta $07C9,x
           inx
           bne tlr_writ
tlr_wait_rel:                      // debounce: wait for SPACE to be released
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10                // bit 4 = SPACE (0 = pressed)
           beq tlr_wait_rel
tlr_wait_prs:                      // wait for SPACE to be pressed
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10
           bne tlr_wait_prs
           jmp start               // SPACE pressed: restart siddetector
// "PRESS SPACE TO RETURN" in C64 screen codes (A=$01 … Z=$1A, space=$20)
tlr_msg_text:
           .byte $10,$12,$05,$13,$13,$20,$13,$10,$01,$03,$05,$20,$14,$0F,$20,$12,$05,$14,$15,$12,$0E,$00

// ============================================================
// INFO PAGE SYSTEM
// info_entry: jumped to from do_info when I is pressed.
// Determines the page index from data4 (saved HW chip type)
// then calls show_info_page.
// ============================================================
info_entry:
           // Map data4 (saved hw chip type) to info page number
           lda data4
           cmp #$01
           bne ie_not01
           lda #1                  // IP_6581
           bne ie_show
ie_not01:
           cmp #$02
           bne ie_not02
           lda #2                  // IP_8580
           bne ie_show
ie_not02:
           cmp #$03
           beq ie_swinano
           cmp #$08
           bne ie_not08
ie_swinano:
           lda #5                  // IP_SWINANO
           bne ie_show
ie_not08:
           cmp #$04
           bne ie_not04
           lda #4                  // IP_SWINU
           bne ie_show
ie_not04:
           cmp #$05
           bne ie_not05
           lda #3                  // IP_ARMSID
           bne ie_show
ie_not05:
           cmp #$06
           bne ie_not06
           lda #6                  // IP_FPGA8580
           bne ie_show
ie_not06:
           cmp #$07
           bne ie_not07
           lda #7                  // IP_FPGA6581
           bne ie_show
ie_not07:
           cmp #$09
           bne ie_not09
           lda #13                 // IP_PUBDOM (index 13 = ip_pubdom)
           bne ie_show
ie_not09:
           cmp #$0A
           bne ie_not0A
           lda #14                 // IP_BACKSID (index 14 = ip_backsid)
           bne ie_show
ie_not0A:
           cmp #$0B
           bne ie_not0B
           lda #12                 // IP_SIDKPIC (index 12 = ip_sidkpic)
           bne ie_show
ie_not0B:
           cmp #$0E
           bne ie_not0E
           lda #12                 // IP_SIDKPIC (6581 variant — same info page)
           bne ie_show
ie_not0E:
           cmp #$0C
           bne ie_not0C
           lda #15                 // IP_KUNGFUSID (index 15 = ip_kungfusid)
           bne ie_show
ie_not0C:
           cmp #$0D
           bne ie_not0D
           lda #17                 // IP_USID64
           bne ie_show
ie_not0D:
           cmp #$30
           bne ie_nosidfx
           lda #8                  // IP_SIDFX
           bne ie_show
ie_nosidfx:
           // No specific HW SID - determine emulator page from decay values
           jsr get_emu_page        // returns page number in A
ie_show:
           sta tmp1_zp             // current page index

// ============================================================
// show_info_page: full render of info page at index tmp1_zp.
// Resets scroll offset (buf_zp) to 0, then does full render.
// sip_render can be jumped to directly to re-render without reset.
// ============================================================
show_info_page:
           lda #$00
           sta buf_zp               // reset scroll offset to top

sip_render:
           // Protect rendering from $1806 ZP clobber; re-enable at info_kbdwait
           sei
           lda #$00
           sta colwash_flag        // suppress COLWASH while in info screen
           // Set charset and colors
           lda #$15
           sta $D018               // screen at $0400, charset at $1000
           lda #$00
           sta $D020               // border: black
           sta $D021               // background: black
           // Clear screen RAM ($0400-$07E7) — 3x256 + 232 bytes
           lda #$20
           ldx #$00
sip_clr256:
           sta $0400,x
           sta $0500,x
           sta $0600,x
           inx
           bne sip_clr256
           ldx #$00
sip_clrrem:
           sta $0700,x
           inx
           cpx #232
           bne sip_clrrem
           // Fill color RAM ($D800-$DBE7) with white ($01)
           lda #$01
           ldx #$00
sip_col256:
           sta $D800,x
           sta $D900,x
           sta $DA00,x
           inx
           bne sip_col256
           ldx #$00
sip_colrem:
           sta $DB00,x
           inx
           cpx #232
           bne sip_colrem
           // Position KERNAL cursor at row 0, col 0
           lda #$00
           sta $D1
           lda #$04
           sta $D2
           lda #$00
           sta $D3
           sta $D6
           // Load info page pointer into ZP $FE/$FF
           ldy tmp1_zp
           lda info_page_lo,y
           sta $FE
           lda info_page_hi,y
           sta $FF
           // Phase 1: print heading (title + dashes = 2 lines) in white
           lda #$01
           sta $0286
           lda #$02
           sta tmp2_zp             // CR counter: stop after 2nd CR
           ldy #$00
sip_hdr:
           lda ($FE),y
           beq sip_hdr_end
           cmp #$0D
           bne sip_hdr_char
           jsr $FFD2               // print CR
           iny
           bne sip_hdr_cr_ok
           inc $FF
sip_hdr_cr_ok:
           dec tmp2_zp
           bne sip_hdr             // not 2nd CR yet
           jmp sip_hdr_end         // 2nd CR done: heading complete
sip_hdr_char:
           jsr $FFD2               // print non-CR char
           iny
           bne sip_hdr
           inc $FF
           jmp sip_hdr
sip_hdr_end:
           // Row 23: dash separator in white ($0798-$07BF, $DBB8-$DBDF)
           lda #$01
           ldy #39
sip_sep_col:
           sta $DBB8,y
           dey
           bpl sip_sep_col
           lda #$2D
           ldy #39
sip_sep_scr:
           sta $0798,y
           dey
           bpl sip_sep_scr
           // Row 24: nav hint in white
           lda #$C0
           sta $D1
           lda #$07
           sta $D2
           lda #$00
           sta $D3
           lda #$18                // 24 decimal
           sta $D6
           lda #$01
           sta $0286
           lda #<info_nav_hint
           sta $FE
           lda #>info_nav_hint
           sta $FF
           ldy #$00
sip_hint:
           lda ($FE),y
           beq sip_hint_done
           jsr $FFD2
           iny
           bne sip_hint
           inc $FF
           bne sip_hint
sip_hint_done:
           jsr sip_redraw_content  // fill rows 2-22 with scrollable body

// Re-enable IRQ for SID music during keyboard wait/loop
// Wait for all keys to be released before polling
info_kbdwait:
           cli
           lda #$7F                // row 7
           sta $DC00
           lda $DC01
           and #$50                // SPACE (bit4) + Q (bit6)
           cmp #$50
           bne info_kbdwait
           lda #$FE                // row 0
           sta $DC00
           lda $DC01
           and #$04                // CRSR RIGHT (bit2)
           cmp #$04
           bne info_kbdwait
           lda #$EF                // row 4
           sta $DC00
           lda $DC01
           and #$02                // I key (bit1)
           cmp #$02
           bne info_kbdwait
           lda #$FD                // row 1
           sta $DC00
           lda $DC01
           and #$22                // W (bit1) + S (bit5)
           cmp #$22
           bne info_kbdwait

info_kbdloop:
           // SPACE → restart detection
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10                // bit4 = SPACE
           bne info_kbd_no_space
           jmp info_do_space
info_kbd_no_space:
           // W → scroll up
           lda #$FD
           sta $DC00
           lda $DC01
           and #$02                // W (row1 bit1)
           beq info_scroll_up
           // S → scroll down
           lda #$FD
           sta $DC00
           lda $DC01
           and #$20                // S (row1 bit5)
           beq info_scroll_dn
           // B → previous page
           lda #$F7
           sta $DC00
           lda $DC01
           and #$10                // bit4 = B
           beq info_prev_page
           // M → next page
           lda #$EF
           sta $DC00
           lda $DC01
           and #$10                // bit4 = M
           beq info_next_page
           // CRSR key
           lda #$FE                // row 0
           sta $DC00
           lda $DC01
           and #$04                // CRSR RIGHT (bit2)
           bne info_kbdloop        // not pressed
           // Check LEFT SHIFT for direction
           lda #$FD
           sta $DC00
           lda $DC01
           and #$80                // bit7 = LEFT SHIFT
           bne info_crsr_right
info_prev_page:
           lda tmp1_zp
           beq info_wrap_last
           dec tmp1_zp
           jmp show_info_page
info_wrap_last:
           lda #16
           sta tmp1_zp
           jmp show_info_page
info_crsr_right:
info_next_page:
           lda tmp1_zp
           cmp #16
           bcs info_wrap_first
           inc tmp1_zp
           jmp show_info_page
info_wrap_first:
           lda #$00
           sta tmp1_zp
           jmp show_info_page

// Scroll up: decrement offset and fast-redraw content
info_scroll_up:
info_sup_again:
           lda buf_zp
           beq info_sup_held       // already at top
           dec buf_zp
           sei
           jsr sip_redraw_content  // protect redraw from $1806 ZP clobber
           cli
           lda #$60
           jsr rp_delay
info_sup_held:
           lda #$FD
           sta $DC00
           lda $DC01
           and #$02                // W still held?
           beq info_sup_again
           jmp info_kbdloop

// Scroll down: increment offset and fast-redraw content
info_scroll_dn:
info_sdn_again:
           inc buf_zp
           sei
           jsr sip_redraw_content  // protect redraw from $1806 ZP clobber
           cli
           lda #$60
           jsr rp_delay
info_sdn_held:
           lda #$FD
           sta $DC00
           lda $DC01
           and #$20                // S still held?
           beq info_sdn_again
           jmp info_kbdloop

info_do_space:
           jmp start

// ============================================================
// sip_redraw_content: clear rows 2-22 and reprint body from
// current scroll offset (buf_zp). Fixed rows 0-1 and 23-24
// are NOT touched. Called from sip_render and scroll handlers.
// tmp1_zp = page index; buf_zp = scroll offset (lines to skip).
// Uses tmp2_zp as scratch counter; trashes $FE/$FF.
// ============================================================
sip_redraw_content:
           // Clear rows 2-22: $0450-$0797 (840 bytes)
           lda #$20
           ldx #$50                // start at $0450 (row 2)
sip_rc_clr1:
           sta $0400,x
           inx
           bne sip_rc_clr1         // clears $0450-$04FF (176 bytes)
           ldx #$00
sip_rc_clr2:
           sta $0500,x
           sta $0600,x
           inx
           bne sip_rc_clr2         // clears $0500-$06FF (512 bytes)
           ldx #$00
sip_rc_clr3:
           sta $0700,x
           inx
           cpx #$98                // stop before $0798 (row 23 dashes)
           bne sip_rc_clr3         // clears $0700-$0797 (152 bytes)
           // Position cursor at row 2, col 0
           lda #$50
           sta $D1                 // $0450 lo
           lda #$04
           sta $D2                 // $0450 hi
           lda #$00
           sta $D3                 // cursor column = 0
           lda #$02
           sta $D6                 // cursor row = 2
           // Yellow text for body
           lda #$07
           sta $0286
           // Load page pointer
           ldy tmp1_zp
           lda info_page_lo,y
           sta $FE
           lda info_page_hi,y
           sta $FF
           // Skip heading: advance past 2 CRs (title line + dashes line)
           lda #$02
           sta tmp2_zp
           ldy #$00
sip_rc_shdr:
           lda ($FE),y
           beq sip_rc_print_start  // null: empty page
           iny
           bne sip_rc_shdr_ok
           inc $FF
sip_rc_shdr_ok:
           cmp #$0D
           bne sip_rc_shdr
           dec tmp2_zp
           bne sip_rc_shdr
           // Skip scroll offset (buf_zp additional lines)
           lda buf_zp
           beq sip_rc_print_start
           sta tmp2_zp
sip_rc_scrl:
           lda ($FE),y
           beq sip_rc_print_start
           iny
           bne sip_rc_scrl_ok
           inc $FF
sip_rc_scrl_ok:
           cmp #$0D
           bne sip_rc_scrl
           dec tmp2_zp
           bne sip_rc_scrl
           // Print up to 21 lines of body (rows 2-22)
sip_rc_print_start:
           lda #21
           sta tmp2_zp             // line counter
sip_rc_print:
           lda ($FE),y
           beq sip_rc_done         // null: end of page
           cmp #$0D
           bne sip_rc_pchar
           // CR: print, decrement line counter
           jsr $FFD2
           iny
           bne sip_rc_cr_ok
           inc $FF
sip_rc_cr_ok:
           dec tmp2_zp
           bne sip_rc_print
           jmp sip_rc_done         // 21 lines filled
sip_rc_pchar:
           jsr $FFD2               // print non-CR char
           iny
           bne sip_rc_print
           inc $FF
           jmp sip_rc_print
sip_rc_done:
           lda tmp1_zp
           cmp #3              // IP_ARMSID = 3
           bne sip_rc_notarm
           jsr arm2sid_print_extra
           jmp sip_rc_ret
sip_rc_notarm:
           cmp #12             // IP_SIDKPIC = 12
           bne sip_rc_notskp
           jsr skpico_print_extra
           jmp sip_rc_ret
sip_rc_notskp:
           cmp #6              // IP_FPGA8580 = 6
           beq sip_rc_fpga
           cmp #7              // IP_FPGA6581 = 7
           bne sip_rc_ret
sip_rc_fpga:
           jsr fpgasid_print_extra
sip_rc_ret:
           rts

// ============================================================
// DEBUG PAGE  (press D on main screen)
// Shows raw detection values: machine type, PAL/NTSC, data1-4,
// decay samples, ArithMean result, and full sid_list.
// SPACE returns to main (jmp start re-runs detection).
// Uses ZP $FC-$FF as scratch. Safe after readkey2 IRQ installed.
// ============================================================
debug_entry:
           lda #$00
           sta $D01A               // disable VIC raster IRQ
           lda #$15
           sta $D018               // charset at $1000
           lda #$00
           sta $D020               // border: black
           sta $D021               // background: black
           // Clear screen + color RAM (4×256 bytes each)
           lda #$20
           ldx #$00
dbg_clr:
           sta $0400,x
           sta $0500,x
           sta $0600,x
           sta $0700,x
           lda #$01
           sta $D800,x
           sta $D900,x
           sta $DA00,x
           sta $DB00,x
           lda #$20
           inx
           bne dbg_clr
           // Cursor to row 0, col 0
           lda #$00
           sta $D1
           lda #$04
           sta $D2
           lda #$00
           sta $D3
           sta $D6
           // Heading in white
           lda #$01
           sta $0286
           lda #<dbg_s_title
           sta $FE
           lda #>dbg_s_title
           sta $FF
           jsr dbg_str
           // Rest of page in yellow
           lda #$07
           sta $0286
           // Line: MACHINE:XX  PAL:XX  SIDS:XX
           lda #<dbg_s_machine
           sta $FE
           lda #>dbg_s_machine
           sta $FF
           jsr dbg_str
           lda za7
           jsr print_hex
           lda #<dbg_s_pal
           sta $FE
           lda #>dbg_s_pal
           sta $FF
           jsr dbg_str
           lda $02A6
           jsr print_hex
           lda #<dbg_s_numsids
           sta $FE
           lda #>dbg_s_numsids
           sta $FF
           jsr dbg_str
           lda sidnum_zp
           jsr print_hex
           lda #$0D
           jsr $FFD2
           lda #$0D
           jsr $FFD2               // blank line
           // Line: DATA1:XX DATA2:XX DATA3:XX D4:XX
           lda #<dbg_s_data1
           sta $FE
           lda #>dbg_s_data1
           sta $FF
           jsr dbg_str
           lda data1
           jsr print_hex
           lda #<dbg_s_data2
           sta $FE
           lda #>dbg_s_data2
           sta $FF
           jsr dbg_str
           lda data2
           jsr print_hex
           lda #<dbg_s_data3
           sta $FE
           lda #>dbg_s_data3
           sta $FF
           jsr dbg_str
           lda data3
           jsr print_hex
           lda #<dbg_s_data4
           sta $FE
           lda #>dbg_s_data4
           sta $FF
           jsr dbg_str
           lda data4
           jsr print_hex
           lda #$0D
           jsr $FFD2
           // Line: ARM:Vx.xx CFG:XX XX EI:XX XX II:XXXX  (uses print_armsid_ver for version)
           lda #<dbg_s_armver
           sta $FE
           lda #>dbg_s_armver
           sta $FF
           jsr dbg_str
           jsr print_armsid_ver   // prints " Vx.xx" (decimal, skips if major=0)
           lda #$20
           jsr $FFD2
           lda #<dbg_s_cfg
           sta $FE
           lda #>dbg_s_cfg
           sta $FF
           jsr dbg_str
           lda armsid_cfgtest     // D41B after config entry (expect $4E = PETSCII 'n')
           jsr print_hex
           lda armsid_no_c        // D41C after config entry (expect $4F = PETSCII 'o')
           jsr print_hex
           // EI: and II: continue on same line as ARMVER/CFG
           // Line: EI:XX XX II:XX XX (EI: $45/$49→expect $53/$57; II: $49/$49→02+$4C/$52)
           lda #<dbg_s_arm_ei
           sta $FE
           lda #>dbg_s_arm_ei
           sta $FF
           jsr dbg_str
           lda armsid_ei_b        // D41B after 'ei' ($53='S')
           jsr print_hex
           lda #$20
           jsr $FFD2
           lda armsid_ei_c        // D41C after 'ei' ($57='W')
           jsr print_hex          // no explicit space — ' II:' label has leading space
           lda #<dbg_s_arm_ii
           sta $FE
           lda #>dbg_s_arm_ii
           sta $FF
           jsr dbg_str
           lda armsid_ii_b        // D41B after 'ii' (02=ARM2SID)
           jsr print_hex          // space then ii_c follows
           lda armsid_ii_c        // D41C after 'ii' ('L'=$4C or 'R'=$52)
           jsr print_hex
           lda #$0D
           jsr $FFD2
           // ARM2SID only: EMUL mode + 8-slot memory map (2 lines of 4 slots each)
           lda armsid_major
           cmp #$03
           beq dbg_a2_do
           jmp dbg_a2_skip
dbg_a2_do:
           lda #<dbg_s_emul
           sta $FE
           lda #>dbg_s_emul
           sta $FF
           jsr dbg_str
           // print mode: SID/SFX/BOT
           lda armsid_emul_mode
           cmp #$03
           bcc dbg_a2_emul_ok
           lda #$00
dbg_a2_emul_ok:
           tax
           lda dbg_emul_ch0,x
           jsr $FFD2
           lda dbg_emul_ch1,x
           jsr $FFD2
           lda dbg_emul_ch2,x
           jsr $FFD2
           lda #$0D
           jsr $FFD2
           // 8-slot map: 4 per line → 2 lines
           ldx #0
dbg_a2_ml:
           stx x_zp
           lda #$44          // 'D'
           jsr $FFD2
           ldx x_zp
           lda arm2sid_slot_d2,x
           jsr $FFD2         // 2nd hex digit
           txa
           and #$01          // odd slot → 'D?20' else 'D?00'
           beq dbg_a2_e00
           lda #$32          // '2'
           jsr $FFD2
           lda #$30          // '0'
           jsr $FFD2
           jmp dbg_a2_eq
dbg_a2_e00:
           lda #$30          // '0'
           jsr $FFD2
           lda #$30          // '0'
           jsr $FFD2
dbg_a2_eq:
           lda #$3D          // '='
           jsr $FFD2
           ldx x_zp
           jsr get_slot_map_val
           jsr print_map_name
           ldx x_zp
           inx
           stx x_zp
           cpx #8
           beq dbg_a2_done
           txa
           and #$03
           beq dbg_a2_nl     // every 4 slots → newline
           lda #$20          // space separator
           jsr $FFD2
           ldx x_zp
           jmp dbg_a2_ml
dbg_a2_nl:
           lda #$0D
           jsr $FFD2
           ldx x_zp
           jmp dbg_a2_ml
dbg_a2_done:
           lda #$0D
           jsr $FFD2
dbg_a2_skip:
           // Line: FPGA:C=XX F=XX T2:XX  (FPGASID revision; only if primary is FPGASID)
           lda data4
           cmp #$06               // FPGASID 8580?
           beq dbg_fpga_do
           cmp #$07               // FPGASID 6581?
           bne dbg_fpga_skip
dbg_fpga_do:
           lda #<dbg_s_fpga_c
           sta $FE
           lda #>dbg_s_fpga_c
           sta $FF
           jsr dbg_str
           lda fpgasid_cpld_rev
           jsr print_hex
           lda #<dbg_s_fpga_f
           sta $FE
           lda #>dbg_s_fpga_f
           sta $FF
           jsr dbg_str
           lda fpgasid_fpga_rev
           jsr print_hex
           lda #<dbg_s_fpga_t2
           sta $FE
           lda #>dbg_s_fpga_t2
           sta $FF
           jsr dbg_str
           lda fpgasid_sid2_type
           jsr print_hex
           lda #$0D
           jsr $FFD2
dbg_fpga_skip:
           // ── SIDFX: show D41D/D41E decoded fields (always shown; harmless on non-SIDFX) ──
           // Line 1: SIDFX SW2:CTR SW1:LFT PLY:AUTO
           // Line 2: SID1:6581 SID2:8580 @D500   (address from sid_list slot 2 if present)
dbg_sidfx_do:
           // Read values captured during DETECTSIDFX — no SCI calls here.
           // Calling REGUNHIDE/REGHIDE from the debug screen left the SIDFX
           // $DExx cartridge area in a state that caused false secondary SID
           // detections on subsequent SPACE restarts.
           lda sidfx_d41d
           sta $FC                // D41D: SW2[7:6] SW1[5:4] SCAP[3] PLY[2:0]
           lda sidfx_d41e
           sta $FD                // D41E: SID2[3:2] SID1[1:0]
           // "SIDFX SW2:" then CTR/LFT/RGT
           lda #<dbg_s_sidfx
           sta $FE
           lda #>dbg_s_sidfx
           sta $FF
           jsr dbg_str
           lda $FC
           lsr
           lsr
           lsr
           lsr
           lsr
           lsr
           and #$03
           jsr dbg_print_sw_lcr
           // " SW1:" then CTR/LFT/RGT
           lda #<dbg_s_sidfx_sw1
           sta $FE
           lda #>dbg_s_sidfx_sw1
           sta $FF
           jsr dbg_str
           lda $FC
           lsr
           lsr
           lsr
           lsr
           and #$03
           jsr dbg_print_sw_lcr
           // " PLY:" then AUTO/SID1/SID2/BOTH
           lda #<dbg_s_sidfx_ply
           sta $FE
           lda #>dbg_s_sidfx_ply
           sta $FF
           jsr dbg_str
           lda $FC
           and #$03
           jsr dbg_print_ply
           lda #$0D
           jsr $FFD2
           // "SID1:" then NONE/6581/8580/UNKN
           lda #<dbg_s_sidfx_s1
           sta $FE
           lda #>dbg_s_sidfx_s1
           sta $FF
           jsr dbg_str
           lda $FD
           and #$03
           jsr dbg_print_sidtype
           // " SID2:" then NONE/6581/8580/UNKN
           lda #<dbg_s_sidfx_s2
           sta $FE
           lda #>dbg_s_sidfx_s2
           sta $FF
           jsr dbg_str
           lda $FD
           lsr
           lsr
           and #$03
           jsr dbg_print_sidtype
           lda #$0D
           jsr $FFD2
           // Line 3: SIDFX playback addresses — RVS-highlight the active SW1 profile.
           // SW1 bits[5:4] of D41D: 00=CTR→D500  01=LFT→D420  10=RGT→DE00
           lda #<dbg_s_sidfx_adr     // "ADR:"
           sta $FE
           lda #>dbg_s_sidfx_adr
           sta $FF
           jsr dbg_str
           lda $FC                   // D41D (captured at detection time)
           lsr
           lsr
           lsr
           lsr
           and #$03
           sta buf_zp                // buf_zp = SW1 (0=CTR 1=LFT 2=RGT)
           ldx #$01                  // LFT profile
           lda #<dbg_s_adr_lft
           sta $FE
           lda #>dbg_s_adr_lft
           sta $FF
           jsr dbg_adr_rvs_print     // "D400/D420" — highlighted if SW1==LFT
           ldx #$00                  // CTR profile
           lda #<dbg_s_adr_ctr
           sta $FE
           lda #>dbg_s_adr_ctr
           sta $FF
           jsr dbg_adr_rvs_print     // " D400/D500" — highlighted if SW1==CTR
           ldx #$02                  // RGT profile
           lda #<dbg_s_adr_rgt
           sta $FE
           lda #>dbg_s_adr_rgt
           sta $FF
           jsr dbg_adr_rvs_print     // " D400/DE00" — highlighted if SW1==RGT
           lda #$0D
           jsr $FFD2
dbg_sidfx_adr_done:
dbg_sidfx_skip:
           // Line: BACKSID:XX  (D41F echo value captured during checkbacksid)
           lda #<dbg_s_backsid
           sta $FE
           lda #>dbg_s_backsid
           sta $FF
           jsr dbg_str
           lda backsid_d41f       // D41F readback from checkbacksid ($42 = BackSID present)
           jsr print_hex
           lda #$0D
           jsr $FFD2
           // Line: UCI:DF1F=XX  U64:X  (UCI status register + U64 flag)
           lda #<dbg_s_uci
           ldy #>dbg_s_uci
           jsr $AB1E
           lda $DF1F              // live read of UCI status register
           jsr print_hex
           lda #<dbg_s_u64
           ldy #>dbg_s_u64
           jsr $AB1E
           lda is_u64
           jsr print_hex
           lda #$0D
           jsr $FFD2
           jmp dbg_sid_list        // D41B/arrays/SID2 on page 2

// ── SIDFX decode helpers (called from SIDFX debug block above) ────────────
// dbg_print_ply: A=0..3 → "AUTO"/"SID1"/"SID2"/"BOTH"
dbg_print_ply:
           tax
           lda dbg_ply_str_lo,x
           sta $FE
           lda dbg_ply_str_hi,x
           sta $FF
           jmp dbg_str

// dbg_print_sidtype: A=0..3 → "NONE"/"6581"/"8580"/"UNKN"
dbg_print_sidtype:
           tax
           lda dbg_sid_str_lo,x
           sta $FE
           lda dbg_sid_str_hi,x
           sta $FF
           jmp dbg_str

// dbg_adr_rvs_print: print string at $FE/$FF; wrap in RVS if buf_zp == X.
// X = SW1 value that makes this profile active (0=CTR 1=LFT 2=RGT).
dbg_adr_rvs_print:
           txa
           cmp buf_zp
           bne darp_body
           lda #$12                // RVS ON
           jsr $FFD2
darp_body:
           jsr dbg_str             // print string via $FE/$FF
           txa
           cmp buf_zp
           bne darp_done
           lda #$92                // RVS OFF
           jsr $FFD2
darp_done:
           rts

// dbg_print_sw_lcr: print "L C R" with active SW position in RVS.
// Input: A = sw value (0=CTR 1=LFT 2=RGT). Uses tmp_zp ($AC) as temp.
dbg_print_sw_lcr:
           sta tmp_zp
           // "L" — active when tmp_zp==1 (LFT)
           lda tmp_zp
           cmp #$01
           bne dplcr_l_norm
           lda #$12; jsr $FFD2          // RVS ON
dplcr_l_norm:
           lda #$4C; jsr $FFD2          // 'L'
           lda tmp_zp
           cmp #$01
           bne dplcr_l_off
           lda #$92; jsr $FFD2          // RVS OFF
dplcr_l_off:
           // " C" — active when tmp_zp==0 (CTR)
           lda #$20; jsr $FFD2          // ' '
           lda tmp_zp
           bne dplcr_c_norm             // non-zero → not CTR
           lda #$12; jsr $FFD2          // RVS ON
dplcr_c_norm:
           lda #$43; jsr $FFD2          // 'C'
           lda tmp_zp
           bne dplcr_c_off
           lda #$92; jsr $FFD2          // RVS OFF
dplcr_c_off:
           // " R" — active when tmp_zp==2 (RGT)
           lda #$20; jsr $FFD2          // ' '
           lda tmp_zp
           cmp #$02
           bne dplcr_r_norm
           lda #$12; jsr $FFD2          // RVS ON
dplcr_r_norm:
           lda #$52; jsr $FFD2          // 'R'
           lda tmp_zp
           cmp #$02
           bne dplcr_r_off
           lda #$92; jsr $FFD2          // RVS OFF
dplcr_r_off:
           rts

dbg_techdata_s:
           // ── Page 2: D41B:XX D41C:XX D41D:XX D41E:XX D41F:XX  (live reads) ──
           lda #<dbg_s_d41b
           sta $FE
           lda #>dbg_s_d41b
           sta $FF
           jsr dbg_str
           lda $D41B
           jsr print_hex
           lda #<dbg_s_d41c
           sta $FE
           lda #>dbg_s_d41c
           sta $FF
           jsr dbg_str
           lda $D41C
           jsr print_hex
           lda #<dbg_s_d41d
           sta $FE
           lda #>dbg_s_d41d
           sta $FF
           jsr dbg_str
           lda $D41D
           jsr print_hex
           lda #<dbg_s_d41e
           sta $FE
           lda #>dbg_s_d41e
           sta $FF
           jsr dbg_str
           lda $D41E
           jsr print_hex
           lda #<dbg_s_d41f
           sta $FE
           lda #>dbg_s_d41f
           sta $FF
           jsr dbg_str
           lda $D41F
           jsr print_hex
           lda #$0D
           jsr $FFD2
           lda #$0D
           jsr $FFD2               // blank line
           // D418 live read + decay arrays (6 samples each)
           lda #<dbg_s_d418
           sta $FE
           lda #>dbg_s_d418
           sta $FF
           jsr dbg_str
           lda $D418
           jsr print_hex
           lda #<dbg_s_potx
           sta $FE
           lda #>dbg_s_potx
           sta $FF
           jsr dbg_str
           lda $D419
           jsr print_hex
           lda #<dbg_s_poty
           sta $FE
           lda #>dbg_s_poty
           sta $FF
           jsr dbg_str
           lda $D41A
           jsr print_hex
           lda #$0D
           jsr $FFD2
           lda #<dbg_s_arr1
           sta $FE
           lda #>dbg_s_arr1
           sta $FF
           jsr dbg_str
           ldx #$00
dbg_arr1:
           lda ArrayPtr1,x
           jsr print_hex
           lda #$20
           jsr $FFD2               // space
           inx
           cpx #$06
           bne dbg_arr1
           lda #$0D
           jsr $FFD2
           lda #<dbg_s_arr2
           sta $FE
           lda #>dbg_s_arr2
           sta $FF
           jsr dbg_str
           ldx #$00
dbg_arr2:
           lda ArrayPtr2,x
           jsr print_hex
           lda #$20
           jsr $FFD2
           inx
           cpx #$06
           bne dbg_arr2
           lda #$0D
           jsr $FFD2
           lda #<dbg_s_arr3
           sta $FE
           lda #>dbg_s_arr3
           sta $FF
           jsr dbg_str
           ldx #$00
dbg_arr3:
           lda ArrayPtr3,x
           jsr print_hex
           lda #$20
           jsr $FFD2
           inx
           cpx #$06
           bne dbg_arr3
           lda #$0D
           jsr $FFD2
           // ArithMean result
           lda #<dbg_s_mean
           sta $FE
           lda #>dbg_s_mean
           sta $FF
           jsr dbg_str
           lda ArithMean
           jsr print_hex
           lda #$20
           jsr $FFD2
           lda ArithMean+1
           jsr print_hex
           lda #$0D
           jsr $FFD2
           lda #$0D
           jsr $FFD2               // blank line
           jmp dbg_sid2_section    // skip SID list (page 2 path)

dbg_sid_list:
           // SID list
           lda #<dbg_s_sidlist
           sta $FE
           lda #>dbg_s_sidlist
           sta $FF
           jsr dbg_str
           lda sidnum_zp
           jsr print_hex
           lda #$29                // ')'
           jsr $FFD2
           lda #$0D
           jsr $FFD2
           ldx #$01                // entries are 1-indexed
dbg_sids:
           cpx sidnum_zp
           beq dbg_sids_last
           bcs dbg_sids_done
dbg_sids_last:
           lda sid_list_h,x
           beq dbg_sids_done       // hi=0 = empty slot
           lda #$20                // leading space
           jsr $FFD2
           lda sid_list_h,x
           jsr print_hex           // e.g. "D4"
           lda sid_list_l,x
           jsr print_hex           // e.g. "00" → "D400"
           lda #$3A                // ':'
           jsr $FFD2
           lda #$20
           jsr $FFD2
           lda sid_list_t,x
           jsr dbg_print_sid_typename  // e.g. "FPGASID 8580 FOUND"
           lda #$0D
           jsr $FFD2
           inx
           cpx #$08                // max 7 entries
           bne dbg_sids
dbg_sids_done:
           jmp dbg_p1_nav          // page 1 → nav (skip SID2 section)

dbg_sid2_section:
           // UltiSID filter curve section: scan sid_list for types $20-$26
           lda #$0D
           jsr $FFD2
           lda #<dbg_s_ultisid_hdr
           sta $FE
           lda #>dbg_s_ultisid_hdr
           sta $FF
           jsr dbg_str             // "ULTISID FILTER CURVE:\n"
           lda sidnum_zp
           beq dbg_sid2_skip       // no SIDs → skip
           lda #$01
           sta tmp2_zp             // slot counter
dbg_u_scan:
           ldy tmp2_zp
           lda sid_list_t,y        // type code for this slot
           cmp #$20
           bcc dbg_u_next          // < $20 → not UltiSID
           cmp #$27
           bcs dbg_u_next          // >= $27 → not UltiSID
           // Print "SIDn: XXYY  <filter curve name>\n"
           sta buf_zp              // save type code
           lda #$53; jsr $FFD2     // 'S'
           lda #$49; jsr $FFD2     // 'I'
           lda #$44; jsr $FFD2     // 'D'
           ldy tmp2_zp
           tya
           clc
           adc #$30                // slot digit '1'-'9'
           jsr $FFD2
           lda #$3A; jsr $FFD2     // ':'
           lda #$20; jsr $FFD2     // ' '
           ldy tmp2_zp
           lda sid_list_h,y
           jsr print_hex           // address hi
           lda sid_list_l,y
           jsr print_hex           // address lo
           lda #$20; jsr $FFD2     // ' '
           lda #$20; jsr $FFD2     // ' '
           // Print filter curve name from table
           lda buf_zp
           sec
           sbc #$20                // index 0-6
           asl                     // × 2 for word table
           tax
           lda ultisid_str_lo,x    // reuse main screen table
           ldy ultisid_str_hi,x
           jsr $AB1E
           lda #$0D; jsr $FFD2     // newline
dbg_u_next:
           ldy tmp2_zp
           cpy sidnum_zp
           beq dbg_sid2_skip       // last slot done
           inc tmp2_zp
           jmp dbg_u_scan
dbg_sid2_skip:
           // ── UCI live GET_HWINFO query + decoded display ────────────────────
           lda is_u64
           bne dbg_uci_act
           jmp dbg_uci_skip
dbg_uci_act:
           // uci_resp already populated during startup detection — no live query needed
           lda #$0D; jsr $FFD2
           // "UCI RESP: " + raw bytes 0..10
           lda #<dbg_s_uci_resp; sta $FE
           lda #>dbg_s_uci_resp; sta $FF
           jsr dbg_str
           ldx #$00
dbg_uci_lp:
           lda uci_resp,x; jsr print_hex
           lda #$20; jsr $FFD2
           inx; cpx #$0B; bne dbg_uci_lp
           lda #$0D; jsr $FFD2    // newline after first 11 bytes
           // second line: bytes 11-20 (frames 3+4 raw, no spaces — fits 40 cols)
dbg_uci_lp2:
           lda uci_resp,x; jsr print_hex; inx
           cpx #$15; bne dbg_uci_lp2
           lda #$0D; jsr $FFD2
           // Decode Frame 1 if count >= 1
           lda uci_resp+0; beq dbg_uci_skip
           lda uci_resp+2; sta sptr_zp1  // F1 addr hi
           lda uci_resp+1; sta sptr_zp   // F1 addr lo
           lda uci_resp+5; sta mptr_zp   // F1 type
           lda #$31; sta buf_zp          // '1'
           jsr dbg_print_frame
           // Decode Frame 2 if count >= 2
           lda uci_resp+0; cmp #$02; bcc dbg_uci_skip
           lda uci_resp+7; sta sptr_zp1  // F2 addr hi
           lda uci_resp+6; sta sptr_zp   // F2 addr lo
           lda uci_resp+10; sta mptr_zp  // F2 type
           lda #$32; sta buf_zp          // '2'
           jsr dbg_print_frame
dbg_uci_skip:
           // ── Page 2 nav ────────────────────────────────────────────────────
dbg_p2_nav:
           lda #$C0
           sta $D1
           lda #$07
           sta $D2
           lda #$00
           sta $D3
           lda #$18
           sta $D6
           lda #$01
           sta $0286               // white
           lda #<dbg_nav_p2
           ldy #>dbg_nav_p2
           jsr $AB1E
dbg2_kbdwait:
           lda #$FB                // wait for D key release
           sta $DC00
           lda $DC01
           and #$04
           cmp #$04
           bne dbg2_kbdwait
dbg2_kbdloop:
           lda #$FB                // D key → page 1
           sta $DC00
           lda $DC01
           and #$04
           bne dbg2_ck_spc
           jmp debug_entry
dbg2_ck_spc:
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10                // SPACE → restart
           beq dbg2_space
           jmp dbg2_kbdloop
dbg2_space:
           jmp start

           // ── Page 1 nav ────────────────────────────────────────────────────
dbg_p1_nav:
           lda #$C0
           sta $D1
           lda #$07
           sta $D2
           lda #$00
           sta $D3
           lda #$18
           sta $D6
           lda #$01
           sta $0286               // white
           lda #<dbg_nav_p1
           ldy #>dbg_nav_p1
           jsr $AB1E
dbg_kbdwait:
           lda #$FB                // wait for D key release
           sta $DC00
           lda $DC01
           and #$04
           cmp #$04
           bne dbg_kbdwait
dbg_kbdloop:
           lda #$FB                // D key → page 2
           sta $DC00
           lda $DC01
           and #$04
           bne dbg_ck_spc
           jmp debug_entry_p2
dbg_ck_spc:
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10                // SPACE → restart
           beq dbg_space
           jmp dbg_kbdloop
dbg_space:
           jmp start

// ── Page 2 entry point ─────────────────────────────────────────���──────────
debug_entry_p2:
           lda #$00
           sta $D01A               // disable VIC raster IRQ
           lda #$15
           sta $D018               // charset at $1000
           lda #$00
           sta $D020               // border: black
           sta $D021               // background: black
           lda #$20
           ldx #$00
dbg2_clr:
           sta $0400,x
           sta $0500,x
           sta $0600,x
           sta $0700,x
           lda #$01
           sta $D800,x
           sta $D900,x
           sta $DA00,x
           sta $DB00,x
           lda #$20
           inx
           bne dbg2_clr
           lda #$00
           sta $D1
           lda #$04
           sta $D2
           lda #$00
           sta $D3
           sta $D6
           lda #$01
           sta $0286               // white
           lda #<dbg_s_title_p2
           sta $FE
           lda #>dbg_s_title_p2
           sta $FF
           jsr dbg_str             // use dbg_str (updates $D6) instead of $AB1E
           lda #$07
           sta $0286               // yellow
           jmp dbg_techdata_s      // render tech data then SID2 → dbg_p2_nav

// dbg_str: print null-terminated string from ($FE/$FF) via $FFD2
dbg_str:
           ldy #$00
dbg_str_lp:
           lda ($FE),y
           beq dbg_str_done
           jsr $FFD2
           iny
           bne dbg_str_lp
           inc $FF
           bne dbg_str_lp
dbg_str_done:
           rts

// ============================================================
// README PAGE  (press R on main screen)
// Scrollable text viewer with Markdown-like colour coding.
// W = scroll up, S = scroll down, SPACE = restart detection.
// tmp1_zp ($AB) = scroll offset (index of top visible line).
// Content is printed via KERNAL $FFD2; inline PETSCII colour
// codes ($05=white headings, $9E=yellow content) are embedded
// directly in readme_text so $FFD2 handles colour automatically.
// Separator (row 22) and nav hint (row 24) are written directly
// to screen + colour RAM.
// ============================================================
.const README_LINES      = 83
.const README_MAX_SCROLL = 62    // README_LINES - 21 visible rows (row 0 is a fixed header)

readme_entry:
           lda #$00
           sta tmp1_zp             // scroll offset = 0

show_readme_page:
           // Protect rendering from $1806 ZP clobber; re-enable at readme_kbdwait
           sei
           lda #$00
           sta colwash_flag        // suppress COLWASH while in readme screen
           lda #$15
           sta $D018               // charset at $1000
           lda #$00
           sta $D020               // border: black
           sta $D021               // background: black
           // Clear screen RAM and colour RAM
           lda #$20                // space
           ldx #$00
rp_clr:
           sta $0400,x
           sta $0500,x
           sta $0600,x
           sta $0700,x
           lda #$01                // white default colour
           sta $D800,x
           sta $D900,x
           sta $DA00,x
           sta $DB00,x
           lda #$20
           inx
           bne rp_clr
           // Draw header (rows 0-1), footer (rows 23-24); content redrawn on every scroll
           jsr rp_draw_header
           jsr rp_draw_footer
           jsr rp_redraw_content

// Debounce: wait for SPACE and R to be released before polling.
// W and S are NOT debounced here so hold-to-scroll works from
// the first keypress without a release cycle.
readme_kbdwait:
           cli                     // re-enable IRQ for SID music
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10                // SPACE (row7 bit4)
           beq readme_kbdwait
           lda #$FB
           sta $DC00
           lda $DC01
           and #$02                // R (row2 bit1)
           beq readme_kbdwait

readme_kbdloop:
           // SPACE → restart detection
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10
           beq readme_do_space
           // W → scroll up
           lda #$FD
           sta $DC00
           lda $DC01
           and #$02                // W (row1 bit1)
           beq readme_scroll_up
           // S → scroll down
           lda #$FD
           sta $DC00
           lda $DC01
           and #$20                // S (row1 bit5)
           beq readme_scroll_dn
           jmp readme_kbdloop

// ---- Scroll up: decrement offset, fast redraw, repeat while W held ----
readme_scroll_up:
rp_sup_again:
           lda tmp1_zp
           beq rp_sup_held         // already at top; just check if still held
           dec tmp1_zp
           sei
           jsr rp_redraw_content   // protect redraw from $1806 ZP clobber
           cli
           lda #$60                // ~60ms delay between scroll steps
           jsr rp_delay
rp_sup_held:
           lda #$FD                // re-read row 1 for W
           sta $DC00
           lda $DC01
           and #$02
           beq rp_sup_again        // W still held → scroll again
           jmp readme_kbdloop      // released → back to poll

// ---- Scroll down: increment offset, fast redraw, repeat while S held ----
readme_scroll_dn:
rp_sdn_again:
           lda tmp1_zp
           cmp #README_MAX_SCROLL
           bcs rp_sdn_held         // already at bottom
           inc tmp1_zp
           sei
           jsr rp_redraw_content   // protect redraw from $1806 ZP clobber
           cli
           lda #$60
           jsr rp_delay
rp_sdn_held:
           lda #$FD
           sta $DC00
           lda $DC01
           and #$20                // S (row1 bit5)
           beq rp_sdn_again        // S still held → scroll again
           jmp readme_kbdloop

readme_do_space:
           jmp start

// ============================================================
// rp_draw_header: write fixed title row to row 0 screen+colour RAM.
// Called once from show_readme_page; NOT called during scroll.
// ============================================================
rp_draw_header:
           lda #$07                // yellow
           ldy #39
rp_hdr_col:
           sta $D800,y
           dey
           bpl rp_hdr_col
           lda #<readme_header
           sta $FE
           lda #>readme_header
           sta $FF
           ldy #$00
rp_hdr_wr:
           lda ($FE),y
           beq rp_hdr_done
           sta $0400,y
           iny
           cpy #40
           bne rp_hdr_wr
           // Row 1: dash separator in white ($0428-$044F, $D828-$D84F)
           lda #$01
           ldy #39
rp_row1_col:
           sta $D828,y
           dey
           bpl rp_row1_col
           lda #$2D
           ldy #39
rp_row1_scr:
           sta $0428,y
           dey
           bpl rp_row1_scr
rp_hdr_done:
           rts

// ============================================================
// rp_draw_footer: draw separator (row 23) and nav hint (row 24).
// Called once from show_readme_page; not called during scroll.
// ============================================================
rp_draw_footer:
           // Row 23: dash separator in white ($0798-$07BF, $DBB8-$DBDF)
           lda #$01
           ldy #39
rp_sep_col:
           sta $DBB8,y
           dey
           bpl rp_sep_col
           lda #$2D
           ldy #39
rp_sep_scr:
           sta $0798,y
           dey
           bpl rp_sep_scr
           // Row 24: nav hint in white
           lda #$01
           ldy #39
rp_hint_col2:
           sta $DBC0,y
           dey
           bpl rp_hint_col2
           lda #<readme_nav_hint
           sta $FE
           lda #>readme_nav_hint
           sta $FF
           ldy #$00
rp_hint_wr2:
           lda ($FE),y
           beq rp_footer_done
           sta $07C0,y
           iny
           cpy #40
           bne rp_hint_wr2
rp_footer_done:
           rts

// ============================================================
// rp_redraw_content: clear content rows 2-22 and reprint from
// the current scroll offset (tmp1_zp). Called for each scroll
// step. Does NOT redraw fixed rows 0-1 or footer rows 23-24.
// ============================================================
rp_redraw_content:
           // Clear content area rows 2-22: $0450-$0797 (840 bytes = 21 rows × 40)
           // Rows 0-1 are fixed header+dashes; row 23-24 are fixed footer.
           lda #$20
           ldx #$50               // start at $0450 (row 2)
rrc_clr3:
           sta $0400,x            // $0450-$04FF
           inx
           bne rrc_clr3
           ldx #$00
rrc_clr_p1:
           sta $0500,x            // $0500-$05FF
           sta $0600,x            // $0600-$06FF
           inx
           bne rrc_clr_p1
           // Clear remaining 152 bytes ($0700-$0797) = rows 20-22
           ldx #$00
rrc_clr4:
           sta $0700,x
           inx
           cpx #$98                // stop before $0798 (row 23 dashes)
           bne rrc_clr4
           // Position KERNAL cursor at row 2, col 0
           lda #$50
           sta $D1
           lda #$04
           sta $D2
           lda #$00
           sta $D3
           lda #$02
           sta $D6
           // Initial print colour: white
           lda #$01
           sta $0286
           // Load text pointer
           lda #<readme_text
           sta $FE
           lda #>readme_text
           sta $FF
           // Scan to scroll offset
           ldy #$00
           ldx tmp1_zp
           beq rrc_print_start
rrc_scan:
           lda ($FE),y
           beq rrc_print_start
           cmp #$0D
           bne rrc_scan_next
           dex
           beq rrc_past_cr
rrc_scan_next:
           iny
           bne rrc_scan
           inc $FF
           jmp rrc_scan
rrc_past_cr:
           iny
           bne rrc_print_start
           inc $FF
           ldy #$00
rrc_print_start:
           ldx #21
rrc_print_lp:
           lda ($FE),y
           beq rrc_done
           cmp #$0D
           beq rrc_handle_cr
           jsr $FFD2
           iny
           bne rrc_print_lp
           inc $FF
           jmp rrc_print_lp
rrc_handle_cr:
           jsr $FFD2
           iny
           bne rrc_cr_ok
           inc $FF
           ldy #$00
rrc_cr_ok:
           dex
           bne rrc_print_lp
rrc_done:
           rts

// ============================================================
// rp_delay: busy-wait delay.  A = outer loop count.
// Duration = A * 255 * 3 cycles (~3ms per unit at 1 MHz PAL).
// Also used as st_pause for the SID sound test.
// ============================================================
rp_delay:
           cmp #$00
           beq rp_delay_done
           tay                     // save count
           txa
           pha                     // save X
           tya
           tax                     // count → X
rp_dly_outer:
           ldy #$ff
rp_dly_inner:
           dey
           bne rp_dly_inner
           dex
           bne rp_dly_outer
           pla
           tax                     // restore X
rp_delay_done:
           rts

// ============================================================
// SID SOUND TEST  (press T on main screen)
// Adapted from the Dead Test cartridge sound_test.asm.
// Plays a 3-voice SID melody testing sawtooth, triangle and
// pulse waveforms across 3 outer iterations (~5 seconds total).
// All three voices are silenced on entry and exit.
// rp_delay is reused as the timing delay (same subroutine).
// ============================================================
sound_test_entry:
           lda #$00
           sta $D01A               // disable VIC raster IRQ
           lda #$15
           sta $D018
           lda #$00
           sta $D020
           sta $D021
           // Clear screen + colour RAM
           lda #$20
           ldx #$00
snd_clr:
           sta $0400,x
           sta $0500,x
           sta $0600,x
           sta $0700,x
           lda #$01
           sta $D800,x
           sta $D900,x
           sta $DA00,x
           sta $DB00,x
           lda #$20
           inx
           bne snd_clr
           // Cursor to row 0, col 0
           lda #$00
           sta $D1
           lda #$04
           sta $D2
           lda #$00
           sta $D3
           sta $D6
           lda #$07                // yellow
           sta $0286
           // Print title ending with "NOW TESTING: "
           lda #<snd_title
           sta $FE
           lda #>snd_title
           sta $FF
           jsr dbg_str
           // Print D400 address (always the primary SID)
           lda #$D4
           jsr print_hex
           lda #$00
           jsr print_hex
           // Ensure st_soundtest is patched for D400
           lda #$D4
           jsr snd_patch_page
           // Silence all SID voices before test
           lda #$00
           ldx #$18
snd_init:
           sta $D400,x
           dex
           bpl snd_init
           // Run the sound test on D400
           jsr st_soundtest
           // Silence D400 after test
           lda #$00
           ldx #$18
snd_mute:
           sta $D400,x
           dex
           bpl snd_mute
           // Cycle through additional detected SIDs (slots 2..sidnum_zp).
           // For each: patch st_soundtest for that page, print label, play full melody.
           lda sidnum_zp
           cmp #$02               // need at least 2 SIDs
           bcc snd_extra_done
           lda #$02
           sta buf_zp             // buf_zp = current slot index
snd_extra_loop:
           lda buf_zp
           cmp sidnum_zp
           beq snd_extra_body     // slot == last → process
           bcc snd_extra_body     // slot < last → process
           jmp snd_extra_done     // slot > last → all done
snd_extra_body:
           lda #<snd_now_testing
           sta $FE
           lda #>snd_now_testing
           sta $FF
           jsr dbg_str
           ldx buf_zp
           lda sid_list_h,x       // print address high byte
           jsr print_hex
           ldx buf_zp
           lda sid_list_l,x       // print address low byte
           jsr print_hex
           // Patch st_soundtest for this SID page
           ldx buf_zp
           lda sid_list_h,x
           jsr snd_patch_page
           // Set sptr_zp for mute operations
           ldx buf_zp
           lda sid_list_l,x
           sta sptr_zp
           lda sid_list_h,x
           sta sptr_zp+1
           // Silence this SID
           ldy #$18
           lda #$00
snd_ex_mute1:
           sta (sptr_zp),y
           dey
           bpl snd_ex_mute1
           // Play full melody on this SID
           jsr st_soundtest
           // Silence this SID after melody
           ldy #$18
           lda #$00
snd_ex_mute2:
           sta (sptr_zp),y
           dey
           bpl snd_ex_mute2
           inc buf_zp
           jmp snd_extra_loop
snd_extra_done:
           // Restore st_soundtest to D400 for next T-press
           lda #$D4
           jsr snd_patch_page
           // Print "DONE - PRESS SPACE"
           lda #<snd_done
           sta $FE
           lda #>snd_done
           sta $FF
           jsr dbg_str
// Wait for SPACE → restart
snd_kbdwait:
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10
           beq snd_kbdwait
snd_kbdloop:
           lda #$7F
           sta $DC00
           lda $DC01
           and #$10
           beq snd_done_space
           jmp snd_kbdloop
snd_done_space:
           jmp start

// ---- snd_patch_page: patch the SID page byte in all 31 sta $D4xx ----
// instructions inside st_soundtest to point at a different SID page.
// A = page byte (e.g. $D4 for D400, $D5 for D500, $D6 for D600).
// Trashes nothing — uses sta abs to write A to each instruction's hi-byte.
snd_patch_page:
           sta st_p1+2
           sta st_p2+2
           sta st_p3+2
           sta st_p4+2
           sta st_p5+2
           sta st_p6+2
           sta st_p7+2
           sta st_p8+2
           sta st_p9+2
           sta st_p10+2
           sta st_p11+2
           sta st_p12+2
           sta st_p13+2
           sta st_p14+2
           sta st_p15+2
           sta st_p16+2
           sta st_p17+2
           sta st_p18+2
           sta st_p19+2
           sta st_p20+2
           sta st_p21+2
           sta st_p22+2
           sta st_p23+2
           sta st_p24+2
           sta st_p25+2
           sta st_p26+2
           sta st_p27+2
           sta st_p28+2
           sta st_p29+2
           sta st_p30+2
           sta st_p31+2
           rts

// ---- st_soundtest: the 3-voice test melody ----
// Adapted from Dead Test sound_test.asm.  rp_delay used for timing.
// Each sta $D4xx has a st_pN: label so snd_patch_page can relocate
// the melody to any SID page by writing a new high byte at st_pN+2.
st_soundtest:
           lda #$14
st_p1:     sta $D418               // FILTER_VOL: vol=4, no filter
           lda #$00
st_p2:     sta $D417               // FILTER_RES_ROUT = 0
           lda #$3e
st_p3:     sta $D405               // VOICE_1_ATK_DEC
           lda #$ca
st_p4:     sta $D406               // VOICE_1_SUS_VOL_REL
           lda #$00
st_p5:     sta $D412               // VOICE_3_CTRL = 0
           lda #$03                // outer iteration counter (3=saw, 2=tri, 1=pulse, 0=noise)
st_mainloop:
           pha                     // save outer counter
           ldx #$06                // inner: 7 notes (X=6..0)
st_loopA:
           lda st_sound1,x
st_p6:     sta $D401               // Voice1 Freq Hi
           lda st_sound2,x
st_p7:     sta $D400               // Voice1 Freq Lo
           pla
           tay
           lda st_sound8,y
st_p8:     sta $D402               // Voice1 Pulse Lo
           lda st_sound9,y
st_p9:     sta $D403               // Voice1 Pulse Hi
           lda st_sound7,y
st_p10:    sta $D404               // Voice1 Ctrl (waveform + gate)
           tya
           pha
           lda #$6a
           jsr rp_delay            // note duration (~81 ms)
           lda #$00
st_p11:    sta $D404               // gate off
           lda #$00
           jsr rp_delay            // zero: returns immediately
           dex
           bne st_loopA
           // --- Voice 2 ---
           lda #$00
st_p12:    sta $D417
           lda #$18
st_p13:    sta $D418
           lda #$3e
st_p14:    sta $D40C               // VOICE_2_ATK_DEC
           lda #$ca
st_p15:    sta $D40D               // VOICE_2_SUS_VOL_REL
           ldx #$06
st_loopB:
           lda st_sound3,x
st_p16:    sta $D408               // Voice2 Freq Hi
           lda st_sound4,x
st_p17:    sta $D407               // Voice2 Freq Lo
           pla
           tay
           lda st_sound8,y
st_p18:    sta $D409               // Voice2 Pulse Lo
           lda st_sound9,y
st_p19:    sta $D40A               // Voice2 Pulse Hi
           lda st_sound7,y
st_p20:    sta $D40B               // Voice2 Ctrl
           tya
           pha
           lda #$6a
           jsr rp_delay
           lda #$00
st_p21:    sta $D40B               // gate off
           lda #$00
           jsr rp_delay
           dex
           bne st_loopB
           // --- Voice 3 ---
           lda #$00
st_p22:    sta $D417
           lda #$1f
st_p23:    sta $D418
           lda #$3e
st_p24:    sta $D413               // VOICE_3_ATK_DEC
           lda #$ca
st_p25:    sta $D414               // VOICE_3_SUS_VOL_REL
           ldx #$06
st_loopC:
           lda st_sound5,x
st_p26:    sta $D40F               // Voice3 Freq Hi
           lda st_sound6,x
st_p27:    sta $D40E               // Voice3 Freq Lo
           pla
           tay
           lda st_sound8,y
st_p28:    sta $D410               // Voice3 Pulse Lo
           lda st_sound9,y
st_p29:    sta $D411               // Voice3 Pulse Hi
           lda st_sound7,y
st_p30:    sta $D412               // Voice3 Ctrl
           tya
           pha
           lda #$6a
           jsr rp_delay
           lda #$00
st_p31:    sta $D412               // gate off
           lda #$00
           jsr rp_delay
           dex
           bne st_loopC
           // Decrement outer counter; exit when negative
           pla
           tay
           dey
           tya
           bmi st_done
           jmp st_mainloop
st_done:
           rts

// ============================================================
// colorize_rows: write green/red/yellow to color RAM for result rows.
// Called once after all detection printing, before readkey2.
// Scans screen col 13 of each row: non-space = result present.
//
// Row layout (screen rows 2-23):
//   2-10: chip detection rows  → green=found, red=blank
//   11   : NOSID row           → red=found (bad), white=blank
//   12   : SIDFX               → green=found, red=blank
//   13   : PAL/NTSC            → yellow=found, white=blank
//   14   : uSID64              → yellow=found, white=blank
//   15   : $D418 DECAY         → yellow always
//   16-23: stereo SID rows     → green=found, white=blank
//
// Colors: $01=white $02=red $05=green $07=yellow
// Uses ZP $FC-$FF as scratch pointers (safe before readkey2).
// ============================================================
colorize_rows:
           lda #$5D            // screen ptr = $0400 + 2*40 + 13 = $045D
           sta $FE
           lda #$04
           sta $FF
           lda #$5D            // color ptr  = $D800 + 2*40 + 13 = $D85D
           sta $FC
           lda #$D8
           sta $FD
           ldx #$00            // X = row index: 0=row2 .. 21=row23
cr_next:
           ldy #$00
           lda ($FE),y         // screen char at col 13 of this row

           cpx #$09            // row 11 = NOSID
           bne cr_not_nosid
           cmp #$20
           bne cr_set_red      // content = no SID found = red
           lda #$01            // blank = ok = white
           jmp cr_apply
cr_not_nosid:
           cpx #$0B            // row 13 = PAL/NTSC
           bne cr_not_palntsc
           cmp #$20
           bne cr_set_yellow
           lda #$01
           jmp cr_apply
cr_not_palntsc:
           cpx #$0C            // row 14 = uSID64
           bne cr_not_usid64
           cmp #$20
           bne cr_set_yellow
           lda #$01
           jmp cr_apply
cr_not_usid64:
           cpx #$0D            // row 15 = $D418 DECAY
           bne cr_not_decay
           lda #$07            // always yellow (informational)
           jmp cr_apply
cr_not_decay:
           cpx #$0E            // X >= 14 = rows 16-23 (stereo)
           bcc cr_chip_row
           cmp #$20            // stereo: green if found, white if blank
           bne cr_set_green
           lda #$01
           jmp cr_apply
cr_chip_row:
           cmp #$20            // chip rows: green if found, red if blank
           bne cr_set_green
cr_set_red:
           lda #$02            // red
           jmp cr_apply
cr_set_yellow:
           lda #$07            // yellow
           jmp cr_apply
cr_set_green:
           lda #$05            // green
cr_apply:
           ldy #$1A            // write 27 bytes (cols 13-39, index 0-26)
cr_col:
           sta ($FC),y
           dey
           bpl cr_col
           lda $FE             // advance screen ptr by 40
           clc
           adc #$28
           sta $FE
           bcc cr_ns
           inc $FF
cr_ns:
           lda $FC             // advance color ptr by 40
           clc
           adc #$28
           sta $FC
           bcc cr_nc
           inc $FD
cr_nc:
           inx
           cpx #$16            // 22 rows done (rows 2-23)?
           bne cr_next
           rts

// ============================================================
// get_emu_page: look at decay measurement (data1/data2/data3)
// and return the matching info page number in A.
// Same matching logic as checktypeandprint.
// ============================================================
get_emu_page:
           lda data3
           cmp #$02
           bne gep_check_swinano   // data3!=$02 -> continue checks
           jmp gep_unknown         // data3=$02 -> unknown
gep_check_swinano:
           // Swinsid Nano: data1=$01-02, data2=$00
           lda data1
           cmp #$01
           bcc gep_ulti
           cmp #$03
           bcs gep_ulti
           lda data2
           bne gep_ulti
           lda #5                  // IP_SWINANO
           rts
gep_ulti:
           // ULTIsid: data1=$DA-F1, data2=$00
           lda data1
           cmp #$DA
           bcc gep_hoxs
           cmp #$F2
           bcs gep_hoxs
           lda data2
           bne gep_hoxs
           lda #9                  // IP_ULTI
           rts
gep_hoxs:
           // HOXS64: data2=$19, data3=$00
           lda data2
           cmp #$19
           bne gep_rfp6581d
           lda data3
           bne gep_rfp6581d
           lda #11                 // IP_HOXS
           rts
gep_rfp6581d:
           // C64DBG ResIDFP: data2=$07, data3=$00
           lda data2
           cmp #$07
           bne gep_fast6581d
           lda data3
           bne gep_fast6581d
           lda #10                 // IP_VICE
           rts
gep_fast6581d:
           // C64DBG FastSID: data1=$05, data2=$00
           lda data1
           cmp #$05
           bne gep_resid6581d
           lda data2
           bne gep_resid6581d
           lda #10                 // IP_VICE
           rts
gep_resid6581d:
           // C64DBG ResID: data2=$03, data3=$00
           lda data2
           cmp #$03
           bne gep_swinsidu_d
           lda data3
           bne gep_swinsidu_d
           lda #10                 // IP_VICE
           rts
gep_swinsidu_d:
           // SwinsidU decay: data2=$16-18, data3=$00
           lda data2
           cmp #$16
           bcc gep_fpgasid_d
           cmp #$19
           bcs gep_fpgasid_d
           lda data3
           bne gep_fpgasid_d
           lda #4                  // IP_SWINU
           rts
gep_fpgasid_d:
           // FPGAsid decay: data2=$05-06, data3=$00
           lda data2
           cmp #$05
           bcc gep_resid8580
           cmp #$07
           bcs gep_resid8580
           lda data3
           bne gep_resid8580
           lda #6                  // IP_FPGA8580
           rts
gep_resid8580:
           // VICE ResID 8580: data2=$98, data3=$00
           lda data2
           cmp #$98
           bne gep_resid6581
           lda data3
           bne gep_resid6581
           lda #10                 // IP_VICE
           rts
gep_resid6581:
           // VICE ResID 6581: data2=$01, data3=$00
           lda data2
           cmp #$01
           bne gep_fastsid
           lda data3
           bne gep_fastsid
           lda #10                 // IP_VICE
           rts
gep_fastsid:
           // VICE FastSID: data1=$02-04, data2=$00
           lda data1
           cmp #$02
           bcc gep_unknown
           cmp #$05
           bcs gep_unknown
           lda data2
           bne gep_unknown
           lda #10                 // IP_VICE
           rts
gep_unknown:
           lda #16                 // IP_UNKNOWN
           rts

// Called only by the VIC raster IRQ (CIA1 timer IRQs are disabled).
// No register saves needed: $EA31 already saved A/X/Y before dispatching here.
IRQ:
           lda #$01
           sta $D019               // clear raster flag (write-1-to-clear bit 0)
           lda #$00
           sta $D012               // keep raster trigger at line 0 next frame
           lda sid_music_flag      // if SID module active, call play routine each frame
           beq irq_no_music
           jsr $1806               // SID play (Triangle Intro, 50 Hz)
irq_no_music:
           lda colwash_flag        // skip COLWASH in sub-screens (info/readme)
           beq irq_done
           jsr COLWASH             // advance one step of colour-wash animation
irq_done:
           jmp $EA7E               // KERNAL: restore saved Y/X/A, RTI

              
// EXITINTRO: no longer called in v1.2 (SPACE now restarts detection instead
// of exiting to BASIC).  Kept for reference.
EXITINTRO:
           jsr $E544               // KERNAL: clear screen
           lda #$81
           stx $0314               // restore CIA1 IRQ vector to KERNAL default
           sty $0315
           sta $DC0D               // re-enable CIA1 interrupts
           sta $DD0D               // re-enable CIA2 interrupts
           lda #$00
           sta $D019               // clear VIC IRQ flags
           sta $D01A               // disable VIC IRQ mask
           jsr $FF81               // KERNAL: reset screen colours (blue border+screen)
           jmp $E37B               // KERNAL: warm-start BASIC
              
// ============================================================
// printscreen -- copies the 1000-byte screen table to video RAM
// and initialises colour RAM to white (1).
// Screen RAM: $0400-$07E7  (4 x 256-byte pages + 232 bytes)
// Colour RAM: $D800-$DBE7  (same layout)
// ============================================================
printscreen:
    jsr $E544               // KERNAL: clear screen (fills screen RAM with spaces)
    lda #00                 // colour 0 = black
    sta $D020               // VIC border colour register
    sta $D021               // VIC background colour register
    lda #07                 // colour 7 = yellow
    sta $0286               // KERNAL text colour variable

    ldx #0
lp:
    lda screen,x            // copy screen data page 0 ($0000-$00FF of table)
    sta $0400,x             // -> video RAM $0400-$04FF
    lda screen+$0100,x
    sta $0500,x             // -> video RAM $0500-$05FF
    lda screen+$0200,x
    sta $0600,x             // -> video RAM $0600-$06FF
    lda screen+$02e8,x      // last partial page (232 bytes)
    sta $06e8,x             // -> video RAM $06E8-$07CF
    lda #1                  // colour 1 = white
    sta $d800,x             // colour RAM $D800-$D8FF
    sta $d900,x             // colour RAM $D900-$D9FF
    sta $da00,x             // colour RAM $DA00-$DAFF
    sta $dae8,x             // colour RAM $DAE8-$DB CF
    inx
    bne lp
    rts
//-------------------------------------------------------------------------

Checkarmsid:     
                stx     x_zp            // $ad 
                sty     y_zp            // $ae
                pha                     // 

//                sta     sptr_zp         // load lowbyte 00  (Sidhome)
//                sta     sptr_zp+1       // store highbyte D4 (Sidhome)
// -- hack --
//                ldy     sptr_zp
//                ldx     sptr_zp+1
                
                lda     sptr_zp+1
                sta     cas_d418+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_1+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_2+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_3+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_4+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_5+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_1+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_2+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_3+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_4+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_5+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_6+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41B+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41C+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_3+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_4+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_5+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_3+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_4+2      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_5+2      // timing issue requieres runtime mod of upcodes.
//
                lda     sptr_zp
                clc
                adc     #$18            // Voice 3 control at D418
                sta     cas_d418+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_1+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_2+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_3+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_4+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d418_5+1      // timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                clc
                adc     #$1D            // Voice 3 control at D418
                sta     cas_d41D+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_1+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_2+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_3+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_4+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_5+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_6+1      // timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                clc
                adc     #$1b            // Voice 3 control at D418
                sta     cas_d41B+1      // timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                clc
                adc     #$1C            // Voice 3 control at D418
                sta     cas_d41C+1      // timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                clc
                adc     #$1E            // Voice 3 control at D418
                sta     cas_d41E+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_3+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_4+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_5+1      // timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                clc
                adc     #$1F            // Voice 3 control at D418
                sta     cas_d41F+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_3+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_4+1      // timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_5+1      // timing issue requieres runtime mod of upcodes.
// -- hack --

                lda #0    // 
cas_d418:        sta $D418 //
cas_d418_1:      sta $D418 //
cas_d418_2:      sta $D418 //
cas_d41D:        sta $D41D //
cas_d41D_1:      sta $D41D //
cas_d41D_2:      sta $D41D //
                sta data1
                sta data2 
                jsr loop1sek
                jsr loop1sek
                lda #$44  // 'D'=$44 = PETSCII 'd' — ARMSID/ARM2SID use PETSCII not ASCII
cas_d41F:        sta $D41F //
                lda #$49  // 'I'=$49 = PETSCII 'i'
cas_d41E:        sta $D41E //
                lda #$53  // 'S'=$53 = PETSCII 's'
cas_d41D_3:      sta $D41D //
                jsr loop1sek
                jsr loop1sek
cas_d41B:        lda $D41b // S=swin n=arm
                cmp #$53
                bne ch_s_1
                lda #$04
                sta data1
                jmp ch_s_3   
ch_s_1:
                cmp #$4E
                bne ch_s_2
                lda #$05
                sta data1
                jmp ch_s_3   
ch_s_2:
                lda #$F0    
                sta data1 // 
ch_s_3:
cas_d41C:        lda $D41c // w=swin o=arm
                sta data2 //
                lda #0    //
cas_d41d7:       lda $D41D // R=arm2sid
                sta data3 //
                lda #0    //
cas_d418_3:      sta $D418 //
cas_d418_4:      sta $D418 //
cas_d418_5:      sta $D418 //
cas_d41D_6:      sta $D41D //
cas_d41D_4:      sta $D41D //
cas_d41D_5:      sta $D41D //
cas_d41E_3:      sta $D41E //
cas_d41E_4:      sta $D41E //
cas_d41E_5:      sta $D41E //
cas_d41F_3:      sta $D41F //
cas_d41F_4:      sta $D41F //
cas_d41F_5:      sta $D41F //
                jsr loop1sek          // <--- D7 80
                jsr loop1sek

                ldx     x_zp            // $ad 
                ldy     y_zp            // $ae
                pla                     // 
                rts
//-------------------------------------------------------------------------
// checkpdsid: detect PDsid by writing 'P'/$50 to D41D, 'D'/$44 to D41E,
// then reading D41E; if it echoes back 'S'/$53 → PDsid (data1=$09).
// Uses sptr_zp for address so stereo scan can call it at any SID slot.
//-------------------------------------------------------------------------
checkpdsid:
                stx x_zp
                sty y_zp
                pha

                lda sptr_zp+1
                sta cpds_d41D+2         // high byte → D41D instruction
                sta cpds_d41E_w+2       // high byte → D41E write
                sta cpds_d41E_r+2       // high byte → D41E read

                lda sptr_zp
                clc
                adc #$1D                // offset $1D = voice3 freq lo (D41D)
                sta cpds_d41D+1
                lda sptr_zp
                clc
                adc #$1E                // offset $1E = voice3 freq hi (D41E)
                sta cpds_d41E_w+1
                sta cpds_d41E_r+1

                lda #$50                // 'P'
cpds_d41D:      sta $D41D
                lda #$44                // 'D'
cpds_d41E_w:    sta $D41E
cpds_d41E_r:    lda $D41E
                cmp #$53                // 'S' = PDsid confirmed
                bne cpds_notfound
                lda #$09                // data1 = $09 = PDsid
                sta data1
                jmp cpds_done
cpds_notfound:
                lda #$F0
                sta data1
cpds_done:
                ldx x_zp
                ldy y_zp
                pla
                rts

// checkbacksid: moved to second segment (after backsid_post_fixup)

//-------------------------------------------------------------------------
// checkskpico: detect SIDKick-pico via config mode VERSION_STR readback,
// then read primary model type via auto-detect mechanism.
//
// Phase 1 — identity (config mode):
//   Write $FF to D41F (enter config mode), $E0/$E1 to D41E (manual pointer),
//   read D41D twice: byte[0]='S'($53), byte[1]='K'($4B).
//
// Phase 2 — model type (auto-detect, normal mode):
//   The config page-0 read ($00 to D41E) extends config-mode and poisons D43B
//   reads via the ARMSID scan's D41D writes, breaking secondary detection.
//   Instead, use SKpico's auto-detect trigger (normal SID operation):
//     1. Write $00 to D418 → exits config mode (non-config-register write)
//     2. Write $FF to D40E, D40F, D412 (preconditions: reg[0x0E/0F/12]=$FF)
//     3. Write $20 to D412 → trigger: REG_AUTO_DETECT_STEP=1
//     4. Read D41B → returns 2 (8580) or 3 (6581) from REG_MODEL_DETECT_VALUE
//     5. Write $00 to D412 → stop waveform
//   data1 = $0B (8580) or $0E (6581).
//
// Note: all addresses use sptr_zp (=$D400 when called from checkskpico_step).
// D40E/D40F/D412/D41B/D418 use hardcoded D400 offsets (always primary SID).
checkskpico:
                stx x_zp
                sty y_zp
                pha
                lda #$00
                sta skpico_fm       // default: no FM; set by Phase 3 if chip found
                lda sptr_zp+1
                sta cskp_d41F+2
                sta cskp_d41E+2
                sta cskp_d41E2+2
                sta cskp_d41D_s+2
                sta cskp_d41D_k+2
                lda sptr_zp
                clc
                adc #$1F            // offset $1F = D41F
                sta cskp_d41F+1
                lda sptr_zp
                clc
                adc #$1E            // offset $1E = D41E
                sta cskp_d41E+1
                sta cskp_d41E2+1
                lda sptr_zp
                clc
                adc #$1D            // offset $1D = D41D
                sta cskp_d41D_s+1
                sta cskp_d41D_k+1
                // Phase 1: identity via VERSION_STR
                lda #$FF            // enter config mode
cskp_d41F:      sta $D41F
                lda #$E0            // select byte[0]
cskp_d41E:      sta $D41E
cskp_d41D_s:    lda $D41D           // byte[0]: expect 'S' = $53
                cmp #$53
                bne cskp_notfound
                lda #$E1            // advance pointer to byte[1]
cskp_d41E2:     sta $D41E
cskp_d41D_k:    lda $D41D           // byte[1]: expect 'K' = $4B
                cmp #$4B
                bne cskp_notfound
                // Phase 2: model type via auto-detect
                // Write to D418 (non-config reg) → exits config mode immediately.
                lda #$00
                sta $D418           // exit config mode; volume=0 (cleanup later)
                // Set auto-detect preconditions in normal mode.
                lda #$FF
                sta $D40E           // reg[0x0E]=$FF (voice 3 freq lo)
                sta $D40F           // reg[0x0F]=$FF (voice 3 freq hi)
                sta $D412           // reg[0x12]=$FF (all waveforms: precondition)
                lda #$20
                sta $D412           // trigger: D412=$20 → REG_AUTO_DETECT_STEP=1
                lda $D41B           // read: 2=8580, 3=6581 (REG_MODEL_DETECT_VALUE)
                pha                 // save model value
                lda #$00
                sta $D412           // stop waveform
                pla                 // restore model value
                cmp #$02            // 2 = SID_MODEL_DETECT_VALUE_8580
                beq cskp_found_8580
                lda #$0E            // 3=6581 (or unexpected → treat as 6581)
                sta data1
                jmp cskp_phase3
cskp_found_8580:
                lda #$0B            // 2=8580
                sta data1
                // Phase 3 — FM Sound Expander: read config[8] (CFG_SID2_TYPE).
                // Re-enter config mode (primary D400 always): $FF→D41F, $00→D41E (page 0),
                // then discard config[0..7] and read config[8].
                // config[8] >= 4 → FM enabled (FM_ENABLE = 6 - config[8] > 0 for values 4/5).
                // FM maps to $DF00 (requires A8/IO hardware connection).
cskp_phase3:
                lda #$FF
                sta $D41F           // re-enter config mode (primary SID always at D400)
                lda #$00
                sta $D41E           // page 0: config[] access starting at config[0]
                ldx #$08
cskp_fm_lp:    lda $D41D           // discard config[0..7] (auto-increment)
                dex
                bne cskp_fm_lp
                lda $D41D           // 9th read = config[8] = CFG_SID2_TYPE
                sta skpico_fm       // store: 0-3=SID types, >=4=FM mode
                lda #$00
                sta $D418           // exit config mode (non-config-reg write)
                jmp cskp_done
cskp_notfound:
                lda #$F0
                sta data1
cskp_done:
                ldx x_zp
                ldy y_zp
                pla
                rts

//-------------------------------------------------------------------------
// checkkungfusid: detect KungFuSID via $D41D handshake (from fw_start protocol).
// Write $A5 (FW_UPDATE_START_MAGIC) to D41D, wait ~20ms, read D41D.
// KungFuSID responds with $5A (FW_UPDATE_START_ACK). Real SIDs do not.
//-------------------------------------------------------------------------
// checkusid64: detect uSID64 by $D41F config register readback.
// Write unlock sequence $F0,$10,$63,$00,$FF to $D41F, then read twice.
// uSID64 holds a stable value in $E0-$FC on both reads (chip drives the bus).
// NOSID floating bus decays from the written $FF: reads drift downward, so
// two reads will differ by more than $02 even if both land in $E0-$FE range.
// Returns data1=$0D (found) or $F0 (not found). Trashes A.
//-------------------------------------------------------------------------
checkusid64:
                // Silence SID voices so bus is quiet
                sei                    // protect write→read from IRQ bus contamination
                lda #$00
                sta $D418               // volume=0
                // Write config unlock sequence to $D41F
                lda #$F0
                sta $D41F
                lda #$10
                sta $D41F
                lda #$63
                sta $D41F
                lda #$00               // mode = auto
                sta $D41F
                lda #$FF
                sta $D41F
                // Single read: uSID64 drives $FE (>=$E0, !=$FF); NOSID bus
                // decays to ~$9A after the write cycle (<$E0). No second read
                // needed — NOSID never reaches $E0+ on an immediate read here.
                lda $D41F
                cli                    // IRQ safe again; A preserved across IRQ
                cmp #$FF
                beq cusid_notfound     // $FF = open bus
                cmp #$E0
                bcc cusid_notfound     // < $E0 = NOSID artifact
                lda #$0D               // data1 = $0D = uSID64
                bne cusid_end          // always taken
cusid_notfound: lda #$F0
cusid_end:      sta data1
                rts

// Uses (sptr_zp),Y indirect so stereo scan can call it at any SID slot.
// data1=$0C = KungFuSID, data1=$F0 = not found.  Trashes A and Y.
//-------------------------------------------------------------------------
checkkungfusid:
                lda #$A5                // FW_UPDATE_START_MAGIC
                sta $D41D               // write to D41D
                lda #26                 // ~20ms delay
                jsr rp_delay
                lda $D41D               // read back D41D
                cmp #$5A                // new firmware: FW_UPDATE_START_ACK?
                // NOTE: only $5A (new firmware ACK) is accepted. The old-firmware
                // $A5 check was removed: real SID chips echo the last-written value
                // from bus capacitance/internal latches; $A5 persists indefinitely
                // on some chips, causing false positives. $5A is a unique ACK that
                // real SIDs never produce (inverse of $A5 is chip-specific firmware).
                bne ckfs_notfound
ckfs_found:     lda #$0C                // data1 = $0C = KungFuSID
                jmp ckfs_end
ckfs_notfound:  lda #$F0
ckfs_end:       sta data1
                rts

//-------------------------------------------------------------------------
// checkswinsidnano: detect SwinSID Nano via consecutive-read update-rate test.
// Called at Step 0.5 (before DETECTSIDFX) while SID registers are clean.
// Returns data1 = $08 (found) or $F0 (not found).
//-------------------------------------------------------------------------
checkswinsidnano:
                // SwinSID Nano detection — consecutive-read update-rate test.
                //
                // MUST be called before any $D41F writes (Step 0.5, before DETECTSIDFX).
                // $D41F writes permanently change SwinSID Nano's AVR mode; writing $00
                // back does NOT restore clean state.
                //
                // Two-stage consecutive-read update-rate test.
                //
                // The SwinSID Nano AVR updates OSC3 ($D41B) at its SID-frame boundary
                // (~45kHz steady state, ~17kHz at startup).  The U2+ FPGA with virtual
                // SID disabled also starts slowly from its initial LFSR state.
                // A single 12ms count test cannot distinguish SwinSID Nano from U2+
                // NOSID in its initial state — both give cnt_12ms < 3 in 7 pairs.
                //
                // Empirical findings (probed on real hardware):
                //   Real 6581/8580: LFSR updates every ~1 clock @ freq=$FFFF → cnt=7 ALWAYS.
                //   SwinSID Nano AVR: updates at ~44kHz → cnt=3-7, hits 7 in ~40% of attempts.
                //   NOSID+U2+ (virtual SID disabled): U2+ FPGA noise → cnt=3-7 (identical to Nano).
                //
                // Stage 1 rejects real SID (always cnt=7 in ALL 3 attempts).
                // Stage 2 detects SwinSID Nano (cnt_62ms >= 3) — also matches NOSID+U2+, which
                // is an accepted limitation: U2+ bus noise is indistinguishable from SwinSID Nano.
                //
                // Decision: Stage1 passes (cnt<7 in at least 1 of 3 attempts) AND cnt_62ms >= 3.
                lda #$00
                ldx #$1F
csn_rst_loop:   sta $D400,x
                dex
                bpl csn_rst_loop
                lda #$05
                jsr rp_delay            // ~6ms settle

                lda #$FF
                sta $D40E               // freq=$FFFF (maximum LFSR clock rate)
                sta $D40F
                lda #$81                // noise + gate=1
                sta $D412
                lda #$0A
                jsr rp_delay            // ~12ms for oscillator to start

                // Stage 1: up to 3 consecutive attempts, 8 reads (7 pairs) each.
                // Real 6581: LFSR updates ~every clock → ALL 7 pairs always differ → cnt=7 every time.
                // SwinSID Nano: AVR updates at ~44kHz → cnt=7 in only ~40% of attempts.
                // → P(all 3 attempts give cnt=7 for SwinSID Nano) ≈ 6% (acceptable false-negative rate).
                // → Reject only when ALL attempts give cnt=7 (guaranteed real-SID speed).
                // NOSID/U2+: indistinguishable from SwinSID Nano here; Stage 2 handles it.
                lda #$03
                sta data3               // attempt counter (data3=$A6; safe: set by Checkarmsid in Step 2)
csn_s1_loop:    lda $D41B
                sta data2               // last value
                ldy #$00                // change counter
                ldx #$07                // 7 more reads
csn_rd1:        lda $D41B
                cmp data2
                beq csn_s1
                iny
                sta data2
csn_s1:         dex
                bne csn_rd1
                cpy #$07
                bcc csn_s1_pass         // cnt<7 in this attempt → proceed to Stage 2
                dec data3
                bne csn_s1_loop         // try again
                jmp csn_notfound        // all 3 gave cnt=7 → real SID speed → NOT SwinSID Nano
csn_s1_pass:

                // cnt_12ms < 7: ambiguous. Wait 50ms more and retest.
                lda #$27
                jsr rp_delay            // ~50ms

                // Stage 2: count changes in 8 reads (7 pairs)
                lda $D41B
                sta data2
                ldy #$00
                ldx #$07
csn_rd2:        lda $D41B
                cmp data2
                beq csn_s2
                iny
                sta data2
csn_s2:         dex
                bne csn_rd2
                cpy #$03
                bcc csn_notfound        // cnt_62ms < 3 → NOSID/U2+ fresh → NOT SwinSID Nano

                lda #$00
                sta $D412               // silence voice 3
                lda #$08
                sta data1
                rts
csn_notfound:   lda #$00
                sta $D412               // silence voice 3
                lda #$F0
                sta data1
                rts

//-------------------------------------------------------------------------

checkfpgasid:

                stx     x_zp            // $ad 
                sty     y_zp            // $ae
                pha                     // 
    // To do this enable configuration mode by writing the magic cookie, then set the identify bit in D41E
    // Finally read out registers $19/25 and $1A/26 and check the result for the value $F51D. 245/29
    // When the value matches, FPGASID is identified.
    // set config mode.

                lda     sptr_zp+1
                sta     cfs_D419+2
                sta     cfs_D419_1+2
                sta     cfs_D419_2+2
                sta     cfs_D41A+2
                sta     cfs_D41A_1+2
                sta     cfs_D41A_2+2
                sta     cfs_D41E+2
                sta     cfs_D41E_1+2
                sta     cfs_D41F+2

                lda     sptr_zp
                clc
                adc     #$19
                sta     cfs_D419+1
                sta     cfs_D419_1+1
                sta     cfs_D419_2+1
                lda     sptr_zp
                clc
                adc     #$1A
                sta     cfs_D41A+1
                sta     cfs_D41A_1+1
                sta     cfs_D41A_2+1
                lda     sptr_zp
                clc
                adc     #$1E
                sta     cfs_D41E+1
                sta     cfs_D41E_1+1
                lda     sptr_zp
                clc
                adc     #$1F
                sta     cfs_D41F+1

                // Write magic cookie → enter SID1 config mode.
                // Go DIRECTLY to identify mode ($80) — do NOT write D41E=$00 (revision mode)
                // at this stage. Writing revision mode corrupts FPGASID SID2's state and
                // causes D43B to return $FF, preventing fiktivloop from detecting D420.
                // Revisions are read later in fll_fpga_sid2 (after D420 is confirmed).
                lda #$81
cfs_D419:        sta $D419
                lda #$65
cfs_D41A:        sta $D41A
                lda %10000000           // $80 = identify mode
cfs_D41E:        sta $d41e
                // if F51D → FPGASID confirmed
cfs_D419_1:      lda $D419
                cmp #$1D
                bne fpgasidf_nosound
cfs_D41A_1:      lda $D41A
                cmp #$F5
                bne fpgasidf_nosound
cfs_D41E_1:      lda $D41e // C9
cfs_D41F:        lda $D41f // hvis 3F=8580 00=6581
                cmp #$3f
                bne fpgasidf_6581
                lda #$06
                sta data1
                sta data2
                jmp fpgaclearmagic 
            fpgasidf_6581:    
                cmp #$00
                bne fpgasidf_nosound
                lda #$07
                sta data1
                sta data2
                jmp fpgaclearmagic
            fpgasidf_nosound:
                lda #$F0 // not found
                sta data1
                sta data2
            fpgaclearmagic:
                // Always entered in SID1 config mode (after $81/$65 magic + D41E=$80).
                // Exit config mode by writing $00 to D419/D41A while in identify mode (D41E=$80).
                // V1.3.06 behavior: do NOT touch D41E here — exiting from identify mode keeps
                // FPGASID SID2 in a clean state (D43B reads $00 during fiktivloop noise scan).
                // SID2 type is queried in fiktivloop (fll_fpga_sid2) after D420 is confirmed.
                lda #$00
cfs_D419_2:      sta $D419              // write $00 to D419 — exits SID1 config mode
cfs_D41A_2:      sta $D41A              // write $00 to D41A

                ldx     x_zp            // $ad
                ldy     y_zp            // $ae
                pla                     //
                rts

//-------------------------------------------------------------------------
checkrealsid:
// from https://github.com/GideonZ/1541ultimate/blob/master/software/6502/sidcrt/player/advanced/detection.asm
//                lda     #$0    // 
//                sta     sptr_zp         // load lowbyte 00  (Sidhome)
//                lda     #$d4            // load highbyte D4  (Sidhome)
//                sta     sptr_zp+1       // store highbyte D4 (Sidhome)

                stx     x_zp            // $ad 
                sty     y_zp            // $ae
                pha                     // 
// -- hack --
//                ldy     sptr_zp
//                ldx     sptr_zp+1
                
                lda     sptr_zp+1
                sta     crs_d412+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d412_1+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d412_2+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d412_retry+2  // patch retry stop-oscillator STA
                sta     crs_d40f+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d40f_1+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_1+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_2+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_3+2      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_4+2      // timing issue requieres runtime mod of upcodes.
//
                lda     sptr_zp
                clc
                adc     #$12            // Voice 3 control at D418
                sta     crs_d412+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d412_1+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d412_2+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d412_retry+1  // patch retry stop-oscillator STA
                lda     sptr_zp
                clc
                adc     #$0f            // Voice 3 control at D418
                sta     crs_d40f+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d40f_1+1      // timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                clc
                adc     #$1b            // Voice 3 control at D418
                sta     crs_d41b+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_1+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_2+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_3+1      // timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_4+1      // timing issue requieres runtime mod of upcodes.
                
// -- hack --
// Retry up to 3 times: VIC bad-line DMA steals can corrupt timing on any
// single attempt; a fresh attempt starts at a different raster position.
                lda #$03
                sta buf_zp      // retry counter
crs_retry:
                lda #$48        // test bit should be set
crs_d412:        sta $d412
crs_d40f:        sta $d40f
                sei             // protect timing-sensitive reads from IRQ/DMA steal
                lsr             // activate sawtooth waveform
crs_d412_1:      sta $d412
crs_d41b:        lda $d41b
                tax             // a to x
                and #$fe        // 00 or 01 → real SID; anything higher → fail/retry
                bne crs_maybe_retry
crs_d41b_1:      lda $d41b       // should always be $03 on a real SID
                cmp #$03
                bne crs_maybe_retry
crs_d41b_2:      lda $d41b       // should be $05-$06
                cmp #$07
                bcs crs_maybe_retry
crs_d41b_3:      lda $d41b       // should be $08
                cmp #$08
                bne crs_maybe_retry
                // success: save how many retries were needed (3 - buf_zp)
                lda #$03
                sec
                sbc buf_zp      // 0=first try, 1=2nd, 2=3rd
                sta retry_zp
                jmp loop2
crs_maybe_retry:
                cli             // re-enable IRQ before delay
                lda #$00
crs_d412_retry:  sta $d412       // stop oscillator before retry
                dec buf_zp
                beq unknownSid  // all 3 attempts failed
                lda #$01        // ~1ms settle between attempts
                jsr rp_delay
                jmp crs_retry
unknownSid:
                ldx #$F0
loop2:
                txa
                sta data1
                cli             // ensure IRQ is on (may arrive here from success path)
                cmp #$00  // 
                beq sid8580 // 
                cmp #$01  // 
                beq sid6581 // 
                jmp unknown // 
sid8580:        
                lda #$02
                sta data1
                jmp stoprealsid
sid6581:         
                lda #$01
                sta data1
                jmp stoprealsid
unknown:         
                lda #$F0
                sta data1

stoprealsid:
                lda #$00
crs_d412_2:      sta $D412
crs_d40f_1:      sta $d40f
crs_d41b_4:      lda $d41b

                ldx     x_zp            // $ad
                ldy     y_zp            // $ae
                pla                     //
                rts

                
//-------------------------------------------------------------------------
checksecondsid:
// the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
//(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
// https://csdb.dk/forums/?roomid=11&topicid=114511
// if the second SID is differenct from D400 typer then base must be SECOND sid memory address and not D400.
// find last entry ind sid_list by using num_sids


                stx     x_zp            // $ad 
                sty     y_zp            // $ae
                pha                     // 
                
                lda #$f0
                sta data1
css_begin:                
                // High byte
                lda     sptr_zp+1
                sta     css_d412_5+2      // timing issue requieres runtime mod of upcodes.
                sta     css_d40f_5+2      // timing issue requieres runtime mod of upcodes.
                sta     css_d412+2      // timing issue requieres runtime mod of upcodes.
                sta     css_d40f+2      // timing issue requieres runtime mod of upcodes.

                lda     mptr_zp+1
                sta     css_d41b+2      // timing issue requieres runtime mod of upcodes.
                sta     css_d41b_5+2      // timing issue requieres runtime mod of upcodes.
                // low byte
                lda     sptr_zp
                clc
                adc     #$12            // Voice 3 control at D418
                sta     css_d412_5+1      // timing issue requieres runtime mod of upcodes.
                sta     css_d412+1      // timing issue requieres runtime mod of upcodes.

                lda     mptr_zp
                clc
                adc     #$1b            // Voice 3 control at D41B
                sta     css_d41b+1      // timing issue requieres runtime mod of upcodes.
                sta     css_d41b_5+1      // timing issue requieres runtime mod of upcodes.

                lda     sptr_zp
                clc
                adc     #$0f            // Voice 3 control at D40F
                sta     css_d40f+1      // timing issue requieres runtime mod of upcodes.
                sta     css_d40f_5+1      // timing issue requieres runtime mod of upcodes.
                
// -- hack --
css_hack1:
                lda #$81        // activate noise waveform
css_d412:        sta $d412
                lda #$FF        // 
css_d40f:        sta $d40f
                ldx #$00
css_d41b:        lda $d41b

                cmp #$00        // Hvis 0, så er sid fundet.
                bne stopsrealsid
                inx
                cpx #10 // if random gets 0 for some times it means it's not a mirror of d41b
                bne css_d41b
cssfound:       
                ldx mptr_zp+1
                ldy mptr_zp
                lda #$10
                sta data1
//// debug                
//                lda mptr_zp+1
//                jsr PRBYTE
//                lda mptr_zp
//                jsr PRBYTE
//                lda data1
//                jsr PRBYTE
//debugm1:
//       jsr readkeyboard
//       beq debugm1
//                

stopsrealsid:            
                lda #$00
css_d412_5:      sta $D412
css_d40f_5:      sta $d40f
css_d41b_5:      lda $d41b
    

                ldx     x_zp            // $ad 
                ldy     y_zp            // $ae
                pla                     // 
                rts 

//-------------------------------------------------------------------------
     
DETECTSIDFX:

    //Even though the SIDFX registers are hidden the D41E and D41F registers still receive
    //  all writes and the SIDFX state machine will react to them, but they won't cause any
    //  harm without the correct unlock sequence. But if there has been any random/unauthorized
    //  writes since last reset (or last SCI command) then the internal state machine may be
    //  in an unknown state. A sequence of SCISYN commands will eventually bring it back into
    //  idle state where it can receive new commands. At least 8 SCISYN commands are required
    //  but 16 are recommended in order to ensure compatibility with future firmware releases
    //  (when using a loop the number of iterations doesn't usually matter).

    ldy #$0f
dloop2:   jsr SCISYN    //bring SIDFX SCI state machine into a known state
    dey
    bpl dloop2

    lda #$80    //PNP hardware detection
    jsr SCIPUT
    lda #$50
    jsr SCIPUT    //send login "PNP"
    lda #$4e
    jsr SCIPUT
    lda #$50
    jsr SCIPUT

    jsr SCIGET    //Read vendor ID LSB
    sta PNP+0
    jsr SCIGET    //Read vendor ID MSB
    sta PNP+1
    jsr SCIGET    //Read product ID LSB
    sta PNP+2
    jsr SCIGET    //Read product ID MSB
    sta PNP+3

    lda #$45    //check device ID string
    cmp PNP+0
    bne NOSIDFX
    lda #$4c
    cmp PNP+1
    bne NOSIDFX
    lda #$12
    cmp PNP+2
    bne NOSIDFX
    lda #$58
    cmp PNP+3
    beq SIDFXFOUND

NOSIDFX:

    //optionally warn user that SIDFX was not detected
    lda #$00
    sta sidfx_d41d    // clear saved SIDFX regs (not detected)
    sta sidfx_d41e
    lda #$31
    sta data1
    sta data2
    jmp PLAYTUNE

SIDFXFOUND:
    lda #$30
    sta data1
    sta data2
    jsr REGUNHIDE   //unhide register map
    lda $D41D
    sta sidfx_d41d  // save D41D: SW2[7:6] SW1[5:4] SCAP[3] PLY[2:0]
    lda $D41E
    sta sidfx_d41e  // save D41E: SID2[3:2] SID1[1:0]

//    hvad skal der ske efter detect?
    
//    lda $d41d   //Get SW1 position
//    lsr
//    lsr
//    lsr
//    lsr
//    and #$03
    //your code
    //optionally warn user if SW1 is not in center position (manually overriden)

//    lda $d41d   //Get operating mode
//    and #$07
    //your code

//    lda $d41d   //Get stereo capability (are all grabbers installed?)
//    and #$08
    //your code

    lda $d41e   //Get SID1 model
    and #$03
    //your code
//    jsr PRBYTE // 03 = UNKN

    lda $d41e   //Get SID2 model
    lsr
    lsr
    and #$03
    //your code
//    jsr PRBYTE // 01 = 6581, 02 = 8580, 03 = UNKN 

    lda $d41e   //Get SID models
    and #$0f
    sta $d41e
    tax
//    jsr PRBYTE // 07 = 
    
//    lda MODE6581,x    //get mode for 6581 playback
    //or
//    lda MODE8580,x    //get mode for 8580 playback
  
//    lda MODE8580,x    //get mode for 8580 playback
//    bne dloop3

    //optionally warn user that the requested SID type is not available
//dloop3   
//    and #$07
//    ora #$f0
//    sta $d41d   //Set playback mode
//    sta $d41d
    //It is recommended to hide the control registers before initialization and playback of SID tunes
    //  because unauthorized writes to the D41D-D41F area may cause unexpected behavior.
    //But if only used with a SID player that never accesses these addresses there is of course no issues.
    jsr REGHIDE   //hide register map
    
PLAYTUNE:
    // Flush SCI state machine to idle before hiding registers.
    // DETECTSIDFX PNP sequence leaves SCI in an unknown state; without
    // this sync, REGHIDE may fail and the $DExx cartridge area can
    // respond to read cycles, causing checksecondsid false positives.
    ldy #$0f
playtune_sync:
    jsr SCISYN
    dey
    bpl playtune_sync
    jsr REGHIDE   //hide register map
    //play SID tune

    jsr loop1sek
    jsr loop1sek
    jsr loop1sek
    jsr loop1sek
    rts
    
//-------------------------------------------------------------------------
// check pal/ntsc
//-------------------------------------------------------------------------

checkpalntsc:
              jsr palntsc                 // perform check
              sta $02a6                   // update KERNAL-variable
              rts
palntsc:
              sei                         // disable interrupts
              ldx nmivec
              ldy nmivec+1                // remember old NMI-vector
              lda #<rti2
              sta nmivec
              lda #>rti2                // let NMI-vector point to
              sta nmivec+1                // a rti
wait:
              lda $d012
              bne wait                    // wait for rasterline 0 or 256
              lda #$37
              sta $d012
              lda #$9b                    // write testline $137 to the
              sta $d011                   // latch-register
              lda #$01
              sta $d019                   // clear IMR-Bit 0
wait1:
              lda $d011                   // Is rasterbeam in the area
              bpl wait1                   // 0-255? if yes, wait
wait2:
              lda $d011                   // Is rasterbeam in the area
              bmi wait2                   // 256 to end? if yes, wait
              lda $d019                   // read IMR
              and #$01                    // mask Bit 0
              sta $d019                   // clear IMR-Bit 0
              stx nmivec
              sty nmivec+1                // restore old NMI-vector
              cli                         // enable interrupts
              rts                         // return

rti2:         rti                         // go immediately back after
                                          // a NMI    


//-------------------------------------------------------------------------
//  Subroutine to print a byte in A in hex form (destructive)
//-------------------------------------------------------------------------

PRBYTE:          pha                     //Save A for LSD
                stx  x_zp            // $ad 
                sty  y_zp            // $ad 
                lda #35                  // print #  
                jsr $ffd2
                pla
                pha
                lsr                     //logic shift right -
                lsr
                lsr                     //MSD to LSD position
                lsr
                jsr     PRHEX           //Output hex digit
                ldx  x_zp            // $ad 
                ldy  y_zp            // $ad 
                pla                     //Restore A

// Fall through to print hex routine

//-------------------------------------------------------------------------
//  Subroutine to print a hexadecimal digit
//-------------------------------------------------------------------------

PRHEX:           and     #%00001111     //Mask LSD for hex print
                ora     #'0'            //Add "0"
                cmp     #'9'+1          //Is it a decimal digit?
                bcc     echo            //Yes! output it
                adc     #6              //Add offset for letter A-F

echo:            jsr $ffd2
                rts
                
//--------------------------------------------------------------------------------------------------
// Unhide SIDFX control registers
//
// A,X modified
//--------------------------------------------------------------------------------------------------

REGUNHIDE:
    lda #$c0    //unhide register map
    jsr SCIPUT
    lda #$45
    jsr SCIPUT
    
    jsr SCISYN    //wait for registers to become ready
    rts

//--------------------------------------------------------------------------------------------------
// Hide SIDFX control registers
//
// A,X modified
//--------------------------------------------------------------------------------------------------

REGHIDE:
    lda #$c1    //hide register map
    jsr SCIPUT
    lda #$44
    jsr SCIPUT

    jsr SCISYN    //wait for registers to become hidden
    rts

//--------------------------------------------------------------------------------------------------
// Exchange SCI (Serial Comminication Interface) byte
//
// A must contain the byte to send
// A will contain the byte received
// X modified
//--------------------------------------------------------------------------------------------------

SCIGET:
SCISYN:
    ldx #$0f    //delay
loop4:   dex
    bpl loop4
    lda #$00    //"nop" SCI command
SCIPUT:
    ldx #$07    //transfer 8 bits (MSB first)
    stx $d41e   //bring SCI sync signal low
loop5:   pha     //save data byte
    sta $d41f   //transmit bit 7
    lda $d41f   //receive bit 0
    ror     //push bit 0 to carry flag
    pla     //restore data byte
    rol     //shift transmitted bit out and received bit in
    dex     //next bit
    bpl loop5      //done?
    stx $d41e   //bring SCI sync signal high
    rts
    
//--------------------------------------------------------------------------------------------------                
// init map
// while 96
// D400, D500, D600, D700, DE00, DF00
// 00,20,40,60,80,A0,C0,E0 ($20)
// sidlist, high
// sidlist, low
// sidlist, type (00,01,02,03,04,05,06,07,08)
// sptr_zp+1 = high
// sptr_zp = low
// hvis c128, så brug tab2. (D5, D6, DF)

tab2:  .byte $D4,$D7,$DE,$DE
tab1:  .byte $D4,$D5,$D6,$D7,$DE,$DF,$DF



sidstereostart:
        // SIDFX: sidfx_populate_sid_list already built the complete sid_list from
        // hardware config (D41D/D41E). Skip generic scan to prevent PDsid/ARMSID
        // false positives from D5xx SID2 mirrors (all 8 x$20 offsets would match).
        lda data4
        cmp #$30
        bne sss_not_sidfx
        rts             // return immediately — SIDFX list already built
sss_not_sidfx:
        // Flush SIDFX SCI to idle before scanning $DExx.
        // checkfpgasid and checkusid64 write D41E/D41F and can leave
        // the SIDFX SCI in a state where $DExx cartridge registers
        // respond to reads, causing false secondary SID detections.
        ldy #$0f
sss_sync:
        jsr SCISYN
        dey
        bpl sss_sync
        jsr REGHIDE
        lda #$00
//        sta sidnum_zp //
        sta sptr_zp   // store lowbyte   00
        lda #$d4      // load highbyte D4  (Sidhome)
        sta sptr_zp+1 // store highbyte D4 (Sidhome)
        ldx #00       // 
        stx scnt_zp   // counter fra 0 til 48.
        ldy #01 // must be 1
        sty mcnt_zp   // y index til tab1
s_s_l1:
        // Spinner: advance tmp_zp frame counter on every slot entry.
        // IRQs are off during scan so $A2 can't be used; tmp_zp is safe.
        inc tmp_zp
        lda tmp_zp
        and #$07
        tax
        lda decay_spinner,x    // reuse same spinner chars as $D418 decay
        sta $0680
        lda #$F0
        sta data1
        sta data2

       lda sidtype
       cmp #$05 // armsid
       beq s_s_is_armsid
       jmp s_s_FPGAsid
s_s_is_armsid:
       // ARMSID/SwinsidU: skip DE/DF expansion space; in D4xx page, skip D400 and any
       // address where bit5=0 (ARMSID window, mirror of primary).  bit5=1 addresses
       // (D420/D460/D4A0/D4E0) may be 8580 windows on MixSID — allow mirror test.
       // DE/DF is I/O expansion space — always skip.
       lda sptr_zp+1
       cmp #$DE       // skip DE/DF expansion space
       bcs s_s_arm_skip
       // skip D400 itself and ARMSID mirror windows in D4xx page
       // MixSID GAL: CS1(ARMSID) when A5=0, CS2(8580) when A5=1.
       // D4xx with lo-byte bit5=0 → ARMSID window (D440/D480/D4C0) → mirrors of D400.
       // D4xx with lo-byte bit5=1 → potential 8580 window (D420/D460) → test.
       cmp #$D4
       bne s_s_arm_chk   // not in D4xx page → allow (D5xx-D7xx)
       lda sptr_zp
       beq s_s_arm_skip   // lo = $00 → D400 itself → skip
       and #$20            // bit5: 0=ARMSID window, 1=8580/independent window
       beq s_s_arm_skip    // bit5=0 → ARMSID mirror in D4xx (D440/D480/D4C0) → skip
       jmp s_s_arm_chk     // bit5=1 → potential 8580 at D420/D460/D4A0/D4E0 → test
s_s_arm_skip:
       jmp s_s_next
s_s_arm_chk:
       // Mirror detection using oscillator cross-read.
       //
       // The old $AA/$55 D41D write-back test failed for MixSID because ARMSID
       // processes D41D writes through its DIS state machine (not a plain echo),
       // causing the read-back to coincidentally equal $AA for mirror addresses.
       //
       // New approach:
       //   1. Silence the candidate's voice 3 (clears stale LFSR/accumulator state
       //      from any prior Checkarmsid call at this or a sibling window).
       //   2. Start primary D400 voice 3 as sawtooth+gate with freq $FF (fast).
       //      Sawtooth avoids the LFSR-stuck-at-zero problem of noise waveform.
       //   3. Read scan_addr+$1B (OSC3) in a short loop.
       //      Mirror  → same oscillator → non-zero within a few cycles → skip.
       //      Independent chip → idle oscillator → stays 0 → detect.
       ldy #$12
       lda #$00
       sta (sptr_zp),y     // silence candidate voice 3 ctrl (clears stale state)
       lda #$FF
       sta $D40F           // primary D400 voice 3 freq hi = max (fast ramp)
       lda #$21            // sawtooth + gate on primary D400 voice 3
       sta $D412
       ldy #$1B
       ldx #$18            // 24 read attempts (~2 accumulator wraps at freq=$FF00)
s_s_arm_mlp:
       lda (sptr_zp),y     // read scan_addr+$1B (candidate OSC3)
       bne s_s_arm_is_mirror // non-zero → shares primary oscillator → mirror → skip
       dex
       bne s_s_arm_mlp
       // All zeros → independent chip → fall through to detect
       lda #$00
       sta $D412           // stop primary voice 3
       sta $D40F
       jmp s_s_arm_detect
s_s_arm_is_mirror:
       // OSC3 read returned non-zero during cross-read loop.
       // On restart ARMSID briefly drives D43B non-zero even when MixSID GAL
       // has deasserted ARMSID CS for D43B. Give the ARM processor ~1ms to
       // fully tristate, then attempt detection anyway — the mirror check below
       // will correctly reject any true mirrors of already-found SIDs.
       lda #$00
       sta $D412           // stop primary voice 3
       sta $D40F
       lda #$01
       jsr rp_delay        // ~1ms: wait for ARMSID ARM to tristate D43B
s_s_arm_detect:
       // ARMSID snoops ALL bus writes regardless of chip-select (CS1/CS2).
       // Writing the DIS sequence ('D'/'I'/'S') to D5xx-D7xx reaches the ARMSID
       // at D400 and triggers it into DIS mode — causing candidate+$1B to read
       // $4E (ARMSID ACK) and Checkarmsid to falsely confirm ARMSID at D5xx.
       // Fix: only call Checkarmsid in the D4xx page (where ARMSID is physically
       // present on the MixSID socket). Outside D4xx, skip directly to checkrealsid.
       lda sptr_zp+1
       cmp #$D4
       bne s_s_arm_skip_armsid_chk    // not D4xx → skip Checkarmsid
       jsr Checkarmsid
       // If Checkarmsid didn't find ARMSID/SwinsidU, try checkrealsid.
       // This handles MixSID: ARMSID at D400, real 8580 at D420.
       // checkrealsid tests the candidate via its own oscillator timing —
       // immune to ARMSID bus contention.
       lda data1
       cmp #$F0
       beq s_s_arm_skip_armsid_chk  // $F0 = not found → continue to mirror check
       jmp s_s_arm_found            // ARMSID/SwinsidU found → proceed normally
s_s_arm_skip_armsid_chk:
       // Mirror check: if any already-found real SID (type $01 or $02) drives noise
       // and candidate+$1B reads non-zero, the candidate is a mirror → skip.
       lda sidnum_zp
       beq s_s_arm_call_real  // no found SIDs yet → skip mirror check
       tax
s_s_arm_mir_lp:
       lda sid_list_t,x
       cmp #$01
       beq s_s_arm_mir_test
       cmp #$02
       bne s_s_arm_mir_nx
s_s_arm_mir_test:
       // Sawtooth at max freq on found_sid[x] voice3; read candidate+$1B 3×.
       // Sawtooth is reliable: with freq=$FF00 the OSC3 accumulator ramps to non-zero
       // in ~2 clock cycles. Noise fails when the 8580 LFSR was reset to 0 by the
       // test bit in a prior checkrealsid and hasn't had time to recover.
       lda sid_list_l,x
       clc
       adc #$0F               // found_sid+$0F = voice3 freq_hi
       sta s_s_arm_mir_fh+1
       sta s_s_arm_mir_fhz+1
       sta s_s_arm_mir_fhz2+1
       lda sid_list_h,x
       sta s_s_arm_mir_fh+2
       sta s_s_arm_mir_fhz+2
       sta s_s_arm_mir_fhz2+2
       lda sid_list_l,x
       clc
       adc #$12
       sta s_s_arm_mir_en+1
       sta s_s_arm_mir_cl+1
       sta s_s_arm_mir_cl2+1
       lda sid_list_h,x
       sta s_s_arm_mir_en+2
       sta s_s_arm_mir_cl+2
       sta s_s_arm_mir_cl2+2
       lda #$FF
s_s_arm_mir_fh:  sta $D40F   // self-mod → found_sid[x]+$0F (freq_hi = max)
       lda #$21               // sawtooth + gate
s_s_arm_mir_en:  sta $D412   // self-mod → found_sid[x]+$12 (ctrl)
       ldy #$1B
       lda (sptr_zp),y        // read candidate+$1B (OSC3) — 3 attempts
       bne s_s_arm_mir_hit
       lda (sptr_zp),y
       bne s_s_arm_mir_hit
       lda (sptr_zp),y
       bne s_s_arm_mir_hit
       // not a mirror: cleanup found_sid[x] voice3 and continue checking
       lda #$00
s_s_arm_mir_cl:  sta $D412   // self-mod → stop ctrl
s_s_arm_mir_fhz: sta $D40F   // self-mod → clear freq_hi
       jmp s_s_arm_mir_nx
s_s_arm_mir_hit:
       // mirror confirmed: cleanup and skip candidate
       lda #$00
s_s_arm_mir_cl2:  sta $D412  // self-mod → found_sid[x]+$12 (stop)
s_s_arm_mir_fhz2: sta $D40F  // self-mod → found_sid[x]+$0F (clear freq)
       jmp s_s_arm_mir_skip
s_s_arm_mir_nx:
       dex
       bne s_s_arm_mir_lp
s_s_arm_call_real:
       // Try DIS echo before checkrealsid to detect SwinSID U / ARMSID at D5xx–D7xx.
       // Safe for real SID primary ($01/$02): no snooping issues.
       // Also safe for ARMSID primary ($05) at D5xx+: sfx_probe_dis_echo reads
       // candidate+$1B (not D41B), so D400 ARMSID snooping the DIS writes does not
       // affect the result. The cleanup writes ($00 to base+$1D–$1F) reset ARMSID's
       // state; the s_s_skip_dis D41B read tristate-ACKs it on a no-match path.
       lda data4
       cmp #$01               // primary = 6581?
       beq s_s_try_dis
       cmp #$02               // primary = 8580?
       beq s_s_try_dis
       cmp #$05               // primary = ARMSID at D400?
       bne s_s_skip_dis
       // ARMSID primary: safe to probe D5xx+. Skip D4xx (that's the primary itself).
       lda sptr_zp+1
       cmp #$D4               // D4xx page → primary ARMSID slot → no DIS probe
       beq s_s_skip_dis
s_s_try_dis:
       jsr sfx_probe_dis_echo // A = echo from sptr_zp+$1B after DIS sequence
       cmp #$53               // 'S' = SwinSID Ultimate
       bne s_s_try_dis_arm
       lda #$04               // SwinSID Ultimate confirmed
       sta data1
       jmp s_s_arm_found
s_s_try_dis_arm:
       cmp #$4E               // 'N' = ARMSID
       bne s_s_skip_dis
       lda #$05               // ARMSID confirmed
       sta data1
       jmp s_s_arm_found
s_s_skip_dis:
       lda $D41B              // ACK ARMSID DIS: read CS1/$1B so ARM tristates data bus before checkrealsid
       jsr checkrealsid       // candidate confirmed independent; identify 6581/8580
s_s_arm_found:
       jmp s_s_ff
s_s_arm_mir_skip:
       jmp s_s_next           // mirror of an already-found real SID → skip
s_s_FPGAsid:
       lda sidtype
       cmp #$06 // FPGASid
       bne s_s_pdsid
//       jsr checkfpgasid
       jmp s_s_ff
s_s_pdsid:
       lda sidtype
       cmp #$09 // PDsid
       bne s_s_backid
       jsr checkpdsid
       jmp s_s_ff
s_s_backid:
       lda sidtype
       cmp #$0A // BackSID
       bne s_s_skpico
       jmp s_s_next   // BackSID mirrors D400 across D4xx-D7xx; pre-populated above, skip scan
s_s_skpico:
       lda sidtype
       cmp #$0B // SIDKick-pico: mirrors across D4xx-D7xx; D400 pre-populated, skip scan
       bne s_s_kungfu
       jmp s_s_next
s_s_kungfu:
       cmp #$0C // KungFuSID: always at D400, no stereo support (A = sidtype from above)
       bne s_s_6581
       jmp s_s_next    // skip stereo scan for KungFuSID
s_s_6581:
       lda sidtype
       cmp #$01 // 6581
       bne s_s_nosound
       jsr checkrealsid
       jmp s_s_ff
//debug
       //lda sptr_zp+1
       //jsr PRBYTE
       //lda sptr_zp
       //jsr PRBYTE
       //lda data1
       //jsr PRBYTE
s_s_nosound:
       jmp s_s_l3

//* Scan for and mark mirrors
// The problem is that the SID replicate the values of registers (00..1F) on the highbyte.
// D500, D520, D540, D560..D5F0 will show the same value even though the chip select address is D500.
// 
// find d400
// find second sid from d420 to d7e0 (fiktiv)
// check de00 to df00
//
s_s_ff:

       lda data1
       cmp #$10   // hvis >10 next
       bcc s_s_ff_found
       jmp s_s_next        // data1 >= $10 → not found
s_s_ff_found:
       ////// found sid //////
       ////// found sid //////
       ////// found sid //////
       // Dedup: skip if sptr_zp is already in sid_list.
       // fiktivloop (called from the primary SID) may have already registered
       // this address; the outer scan would otherwise add it a second time.
       lda sidnum_zp
       beq s_s_add             // list empty – no check needed
       tax                     // x = number of existing entries (1-based)
s_s_dup_lp:
       lda sid_list_h,x
       cmp sptr_zp+1
       bne s_s_dup_nx
       lda sid_list_l,x
       cmp sptr_zp
       bne s_s_dup_nx2
       jmp s_s_next            // already in list — skip
s_s_dup_nx2:
s_s_dup_nx:
       dex
       bne s_s_dup_lp
       // CS2 mirror dedup: D460/D4A0/D4E0 are all CS2 windows on MixSID — same physical
       // ARMSID chip as D420.  Exact-address dedup above misses these aliases.
       // Rule: if data1=$04/$05 AND candidate is D4xx with bit5=1 (CS2 window) AND
       // a D4xx CS2 ARMSID/SwinsidU entry is already in the list → mirror → skip.
       lda data1
       cmp #$04
       beq s_s_cs2_chk
       cmp #$05
       bne s_s_add            // not ARMSID/SwinsidU → proceed to add
s_s_cs2_chk:
       lda sptr_zp+1
       cmp #$D4               // D4xx page?
       bne s_s_add            // not D4xx → legitimate second ARMSID (e.g. D500) → allow
       lda sptr_zp
       and #$20               // bit5 = 1 → CS2 window (D420/D460/D4A0/D4E0)?
       beq s_s_add            // bit5=0 → CS1 window or primary slot → allow
       // Candidate is a D4xx CS2 window.
       // Check if a D4xx CS2 ARMSID/SwinsidU is already in sid_list.
       lda sidnum_zp
       beq s_s_add            // list empty → add (can't be a duplicate)
       tax
s_s_cs2_dup_lp:
       lda sid_list_t,x
       cmp #$04
       beq s_s_cs2_dup_test
       cmp #$05
       bne s_s_cs2_dup_nx
s_s_cs2_dup_test:
       lda sid_list_h,x
       cmp #$D4               // existing entry in D4xx?
       bne s_s_cs2_dup_nx
       lda sid_list_l,x
       and #$20               // existing entry in CS2 window (bit5=1)?
       bne s_s_cs2_mir        // yes → same physical CS2 chip → mirror → skip
s_s_cs2_dup_nx:
       dex
       bne s_s_cs2_dup_lp
       jmp s_s_add            // no prior D4xx CS2 ARMSID → add this one
s_s_cs2_mir:
       jmp s_s_next           // D4xx CS2 ARMSID already in list → mirror → skip
s_s_add:
       ldx sidnum_zp //
       inx
       stx sidnum_zp
       // load sid_list
       lda data1
       sta sid_list_t,x
       lda sptr_zp
       sta sid_list_l,x
       lda sptr_zp+1
       sta sid_list_h,x
       // load sid_list
       
       // fiktiv loop 
       lda sptr_zp
       sta mptr_zp
       ldy sptr_zp+1
       sty mptr_zp+1
       ldx mcnt_zp
       stx cnt1_zp
       ldx scnt_zp
       stx cnt2_zp
// hvorfor #$DE????????? har samme mirror af værdier som d500,d600, // i stedet for anothersid brug 6581/8580.
       cpy #$DE // hvis y>=#$DE 
       bcs s_s_next // hvis #$DE så skip
//--
       lda sidtype
       cmp #$05       //ARMSID / SwinsidU
       bne s_s_lfpgasid
       // Exit sidstereostart immediately after recording the ARMSID/SwinsidU entry.
       // Root cause: checkanothersid wrote $D4 to za8+1 which aliases sidtype ($A9),
       // causing s_s_l1 to dispatch to s_s_nosound → RTS — an accidental early exit.
       // Without that side-effect (our jmp s_s_next), sidtype=$05 was preserved and
       // the scan continued into D5xx-DFxx, finding ULTISID slots and adding garbage.
       // Fix: jmp s_s_l3 (= RTS) exits sidstereostart explicitly, same behaviour as
       // old code but without calling checkanothersid or producing a duplicate entry.
       // ARMSID/SwinsidU mirrors at D5xx-D7xx would cause false positives anyway
       // (see TODO: end_skip_armsid_scan), so early exit is the correct behaviour.
       jmp s_s_l3
s_s_lfpgasid:
       lda sidtype
       cmp #$06       //FPGAsid
       bne s_s_lfpgasid_2
//       jsr checkanothersid
       jsr fiktivloop // find second sid max DFFF
//       jsr checksecondFPGA
       jsr s_s_l3
s_s_lfpgasid_2:
       lda sidtype
       cmp #$07       //FPGAsid
       bne s_s_l6581
//       jsr checkanothersid
       jsr fiktivloop // find second sid max DFFF
//       jsr checksecondFPGA
       jsr s_s_l3
s_s_l6581:
       // brug kun fiktivloop hvis D400 er 8580, 6581
       lda sidtype
       cmp #$01
       bne s_s_next
       // set values
       jsr fiktivloop // find second sid max DFFF
       jsr s_s_l3


s_s_E000:
       // sæt DE00
       // check for FCIII
//       lda #$00
       lda #$E0
       sta sptr_zp 
//       lda #$DE
       lda #$DF
       sta sptr_zp+1 
       lda #$2F       // scnt_zp+1=$30 in s_s_next → immediate exit; was lda $20 (ZP read)
       sta scnt_zp    // which was $2F in V1.2.3 but varies with KERNAL state in V1.2.4+
       ldy #$05       // set DE00 i tab1
       sty mcnt_zp    //
       
       
       // sid map giver mening.... undgå at printe undervejs, men vent til sidst.
       // high, low, type, 
s_s_next:       
       lda sptr_zp
       cmp #$E0 // hvis E0, y++
       bne s_s_l2
       // get D4 from tab1
       ldy mcnt_zp
       lda tab1,y
       sta sptr_zp+1
       iny
       sty mcnt_zp
s_s_l2:       
       // add #$20
       lda sptr_zp
       clc // clear cary
       adc #$20
       sta sptr_zp
       ldx scnt_zp
       inx
       stx scnt_zp
       cpx #$30
       beq s_s_l3
       jmp s_s_l1 
//--------------------------
s_s_l3:
       rts   
//--------------------------------------------------------------------------------------------------                
// cnt1_zp
// mptr_zp
fiktivloop:
//* Scan for and mark mirrors
// The problem is that the SID mirrors the values of registers (00..1F) on the highbyte.
// D500, D520, D540, D560..D7F0 will show the same value even though the chip select address is D500.
// the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
//(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
// https://csdb.dk/forums/?roomid=11&topicid=114511
// DE00 and DF00 also mirror values

// set values
       lda sptr_zp+1
       sta mptr_zp+1
       lda sptr_zp
       sta mptr_zp
f_l_l1:
//       jsr checkfpgasid
//       lda data1
//       cmp $07
//       bne f_l_l_fpga1
//       jmp f_l_l_found
//f_l_l_fpga1
//       lda data1
//       cmp $06
//       bne f_l_l_sec
//       jmp f_l_l_found
f_l_l_sec:
       // ARM2SID+U64: fast path for secondary SID detection.
       // Bypasses checksecondsid (unreliable due to ARM2SID bus coupling:
       // writing $81 to D412 causes D5xx/D6xx to read non-zero, falsely
       // flagging mirrors as separate chips).
       // DFxx is always skipped (UCI registers).
       // Only probe page-aligned offsets (lo=$00): D500, D600, D700 etc.
       // Skips mirror addresses at D520, D540, D620, D640, D680 etc. which
       // share the same 32-register UltiSID chip decoded at $20-byte intervals.
       // uci_c2_add skips $FF reads (open bus on unconfigured sockets).
       lda armsid_major
       cmp #$03               // ARM2SID primary?
       bne fll_std_detect
       lda is_u64
       beq fll_std_detect     // not U64 → normal check path
       lda mptr_zp+1
       cmp #$D4               // D4xx: standard (ARM2SID socket range)
       beq fll_std_detect
       cmp #$D5
       bcc fll_std_detect     // < D5xx: standard (safety net)
       cmp #$DE
       beq fll_std_detect     // = $DExx: standard (ARM2SID typically here)
       cmp #$DF
       bcs fll_u64_skip       // >= $DFxx: always skip (UCI regs)
       // D5xx-DDxx: only probe at page-aligned address (lo=$00).
       // Mirrors at D620, D640, D680 etc. have lo≠$00 and are skipped here.
       lda mptr_zp
       bne fll_u64_skip       // lo≠$00 → skip (mirror address)
       // Page-aligned UltiSID socket: direct oscillator test.
       // U64 returns $FF for idle oscillator; uci_c2_add skips $FF (open bus).
       jsr uci_c2_add         // Check 2 on mptr_zp; adds to sid_list as ULTISID-8580
       jmp f_l_next           // continue scan
fll_u64_skip:
       jmp f_l_next           // skip this address
fll_std_detect:
       // Pre-clear mptr+$12 (candidate voice 3 ctrl) to silence voice 3 output.
       // Write $00 (no waveform, no gate, no TEST): the SID waveform output is 0
       // whenever no waveform bit is selected, regardless of oscillator or LFSR
       // state. This is more robust than the previous $88 (TEST+NOISE) approach:
       //   - Real 8580: TEST resets LFSR to a chip-specific non-zero seed on some
       //     revisions, so $88 left D+$1B non-zero → checksecondsid falsely rejected.
       //   - ULTISID: same result — no waveform selected → OSC3=0 by SID spec.
       // For mirrors (mptr+$12 = sptr+$12): checksecondsid immediately overrides
       // with $81, so the mirror test still works correctly.
       lda mptr_zp
       clc
       adc #$12
       sta fll_preclear+1     // patch low byte of mptr+$12
       lda mptr_zp+1
       sta fll_preclear+2     // patch high byte of mptr+$12
       lda #$00               // no waveform: SID output = 0 regardless of LFSR state
fll_preclear: sta $D41B       // self-mod: write $00 to mptr+$12 → OSC3=0
       jsr checksecondsid
       lda data1
       cmp #$10
       beq fll_checks      // $10 = found candidate; fall into checks
       jmp f_l_next        // not found; advance scan (bne range too large)
fll_checks:

       // Pre-patch mptr+$1B read instruction used by BOTH checks below.
       lda mptr_zp
       clc
       adc #$1B            // mptr + $1B = voice 3 waveform output
       sta fll_mread+1
       sta fll_cread+1
       lda mptr_zp+1
       sta fll_mread+2
       sta fll_cread+2

       // ── Check 1: Mirror check ─────────────────────────────────────────
       // For each already-found SID, enable noise on it and read mptr+$1B.
       // If non-zero, mptr shares the same hardware address decode as that
       // SID (e.g. DE20 mirrors DE00 because the chip only decodes A0–A4).
       // Skip the candidate if a mirror is detected.
       lda sidnum_zp
       beq fll_mirr_done   // no found SIDs yet; skip
       tax                 // x = current entry count (1-based)
fll_mlp:
       lda sid_list_l,x
       clc
       adc #$12            // found SID[x] + $12 = voice 3 control
       sta fll_menbl+1
       sta fll_mclra+1
       sta fll_mclrb+1
       lda sid_list_h,x
       sta fll_menbl+2
       sta fll_mclra+2
       sta fll_mclrb+2
       lda #$81            // noise waveform on
fll_menbl:  sta $D412      // self-mod → found SID[x]+$12
       ldy #$08            // 8 read attempts
fll_mrd:
fll_mread:  lda $D41B      // self-mod → mptr+$1B
       bne fll_is_mir      // non-zero → mptr mirrors SID[x] → skip
       dey
       bne fll_mrd
       lda #$00
fll_mclra:  sta $D412      // disable noise on SID[x]
       dex
       bne fll_mlp         // check next found SID
       jmp fll_mirr_done   // not a mirror of any found SID
fll_is_mir:
       lda #$00
fll_mclrb:  sta $D412      // disable noise on SID[x]
       jmp f_l_next        // skip: candidate is a hardware mirror
fll_mirr_done:

       // FPGASID / SIDKick-pico: skip Check 2 entirely. Writing noise to mptr+$12
       // corrupts the secondary SID's voice 3 oscillator (D43B stays non-zero after
       // cleanup), causing the secondary to be rejected as a mirror on the next restart.
       // checksecondsid + Check 1 already confirmed the secondary is a real second SID.
       lda sidtype
       cmp #$06               // FPGASID 8580?
       beq f_l_l_found
       cmp #$07               // FPGASID 6581?
       beq f_l_l_found
       cmp #$0B               // SIDKick-pico 8580?
       beq f_l_l_found
       cmp #$0E               // SIDKick-pico 6581?
       beq f_l_l_found

       // ── Check 2: Confirmation via ENV3 ────────────────────────────────
       // GATE=1 triggers the envelope generator; ENV3 (mptr+$1C) advances
       // from 0 within ~9 cycles (attack rate 0 = fastest: ~1970 cycles/256
       // steps ≈ 7.7 cycles/step). 32 read attempts cover ~288 cycles → ~37
       // envelope steps, so ENV3 ≥ $25 on a real SID.
       // A real SID returns non-zero ENV3; open bus always reads 0.
       // ENV3 avoids both the LFSR-at-zero trap (fll_preclear's TEST+NOISE
       // resets 8580 LFSR to the stuck-at-zero fixed point) and the
       // accumulator-frequency dependency of the sawtooth approach.
       lda mptr_zp
       clc
       adc #$12
       sta fll_cctrl+1
       sta fll_czero+1
       lda mptr_zp+1
       sta fll_cctrl+2
       sta fll_czero+2
       // Re-patch fll_cread to mptr+$1C (ENV3, not OSC3)
       lda mptr_zp
       clc
       adc #$1C
       sta fll_cread+1
       lda mptr_zp+1
       sta fll_cread+2
       // Set fastest attack: write $00 to mptr+$13 (AD register)
       lda mptr_zp
       clc
       adc #$13
       sta fll_cad+1
       lda mptr_zp+1
       sta fll_cad+2
       lda #$00
fll_cad: sta $D413         // self-mod → mptr+$13 (AD=0: fastest attack ~9 cy/step)
       lda #$01             // GATE=1, no waveform (envelope advances, oscillator idle)
fll_cctrl:  sta $D412      // self-mod → mptr+$12
       ldx #$20             // up to 32 read attempts (~288 cycles → ~37 ENV3 steps)
fll_clp:
fll_cread:  lda $D41B      // self-mod → mptr+$1C (ENV3)
       bne fll_conf
       dex
       bne fll_clp
       jmp f_l_next         // open-bus: ENV3 stayed 0; skip
fll_conf:
       lda #$00
fll_czero:  sta $D412      // self-mod → mptr+$12 (clear GATE, stop envelope)

f_l_l_found:
       //hvis fundet
       // sanity check
       lda sidnum_zp
       cmp #$08
       bcc fll_found_ok        // sidnum < 8: proceed
       jmp f_l_next            // sidnum >= 8: done
fll_found_ok:
       // Dedup: skip if mptr_zp address is already in sid_list.
       // Needed when ARM2SID+U64: arm2sid_populate_sid_list pre-filled D420/DE00 etc.
       lda sidnum_zp
       beq fll_no_dup          // list empty → no check needed
       tax                     // x = sidnum_zp (count, 1-based entries)
fll_dup_lp:
       lda sid_list_h,x
       cmp mptr_zp+1
       bne fll_dup_nx
       lda sid_list_l,x
       cmp mptr_zp
       bne fll_dup_nx
       jmp f_l_next            // address already in list → skip
fll_dup_nx:
       dex
       bne fll_dup_lp
fll_no_dup:
       // sanity check
       ////// found sid //////
       ldx sidnum_zp //
       inx
       stx sidnum_zp
       // Save original sptr_zp (scan root) before identification overwrites it.
       // Restored after fll_sid_typed so the next checksecondsid call still
       // uses the correct primary chip for its noise write. Without this,
       // a MixSID/interleaved config causes every subsequent candidate to get
       // noise written to the wrong chip, producing false secondary detections.
       lda sptr_zp
       sta za8
       lda sptr_zp+1
       sta za8+1
       lda mptr_zp+1
       sta sptr_zp+1
       lda mptr_zp
       sta sptr_zp
       // identify type at mptr:
       // FPGASID: config regs live only at D400 (SID1 POTX/Y). Secondary addrs
       // cannot be re-detected. Use fpgasid_sid2_type (read via $82 magic in checkfpgasid).
       // All other chip families: use checkrealsid to classify 6581 vs 8580.
       lda sidtype
       cmp #$06               // FPGASID 8580 primary?
       beq fll_fpga_jmp
       cmp #$07               // FPGASID 6581 primary?
       beq fll_fpga_jmp
       cmp #$0B               // SIDKick-pico 8580?
       beq fll_skp_detect
       cmp #$0E               // SIDKick-pico 6581?
       beq fll_skp_detect
       jmp fll_try_real
fll_fpga_jmp:
       jmp fll_fpga_sid2
fll_skp_detect:
       // ── SIDKick-pico secondary type detection ────────────────────────
       // Read config[8] (CFG_SID2_TYPE) via primary SID config mode.
       // Protocol: write $FF to D41F (enter config), $00 to D41E (select
       // config page 0), read D41D 9× (auto-increment). 9th = config[8].
       // SKpico.c: config[8]==0 → 6581, non-zero → 8580.
       // Uses primary SID (always D400) — zero writes to secondary registers,
       // no D43B state change.
       lda #$FF
       sta $D41F              // enter primary SID config mode
       lda #$00
       sta $D41E              // config page 0: access starts at config[0]
       ldx #$08
fll_skp_cfg_lp:
       lda $D41D              // discard config[0..7] (auto-increment)
       dex
       bne fll_skp_cfg_lp
       lda $D41D              // 9th read = config[8] (CFG_SID2_TYPE)
       // X was trashed by the loop counter — restore secondary slot index
       pha                    // save config[8] before ldx changes flags
       ldx sidnum_zp          // restore secondary slot index for fll_fpga_done
       pla                    // restore config[8], sets Z flag
       beq fll_skp_s_6581     // 0 = 6581
       lda #$0B               // non-zero = 8580 → SIDKick-pico 8580
       jmp fll_fpga_done
fll_skp_s_6581:
       lda #$0E               // 6581 → SIDKick-pico 6581
       jmp fll_fpga_done
fll_fpga_sid2:
       // D420 is confirmed. Read SID2 type via FPGASID config mode.
       // $82/$65 enters SID2 identify mode; D41F returns type ($3F=8580, $00=6581).
       // $00/$00 exits. This must run AFTER Check 2 is skipped (Check 2 corrupts
       // D43B; $82/$65 is now safe because D43B was never touched in this run).
       lda #$82
       sta $D419
       lda #$65
       sta $D41A
       lda $D41F              // SID2 type: $3F=8580, $00=6581
       sta fpgasid_sid2_type
       lda #$00
       sta $D419
       sta $D41A
       lda fpgasid_sid2_type
       cmp #$3f
       beq fll_fpga_8580
       cmp #$00
       bne fll_fpga_inherit   // unexpected → inherit primary
       lda #$07               // 6581 secondary
       jmp fll_fpga_done
fll_fpga_8580:
       lda #$06               // 8580 secondary
       jmp fll_fpga_done
fll_fpga_inherit:
       lda sidtype            // fallback: inherit primary type
fll_fpga_done:
       // Store FPGASID / SIDKick-pico secondary entry, then EXIT fiktivloop immediately.
       // Both have exactly 2 SID slots (D400+D420). Continuing to scan D440+
       // would enable noise on D432 (secondary voice 3 ctrl) during Check 1,
       // leaving D43B with a stale LFSR value — causing D420 to be rejected as
       // a mirror on the next restart. Early exit prevents this corruption.
       sta sid_list_t,x
       lda sptr_zp;    sta sid_list_l,x
       lda sptr_zp+1;  sta sid_list_h,x
       jmp f_l_done    // exit fiktivloop — skip D440+ scan for FPGASID
fll_try_real:
       // If ARM2SID primary on U64: any secondary reaching here is UltiSID.
       // ARM2SID occupies the physical socket; no real chip can be at secondary
       // addresses. UltiSID emulates the SID oscillator accurately and would
       // otherwise pass checkrealsid — so we skip the real SID test entirely.
       lda armsid_major
       cmp #$03               // ARM2SID primary?
       bne fll_not_arm2sid_u64
       lda is_u64
       bne fll_ultisid        // ARM2SID + U64 → UltiSID, no checkrealsid needed
fll_not_arm2sid_u64:
       jsr checkrealsid       // returns data1=$01(8580),$02(6581),$F0(unknown)
       lda data1
       cmp #$01
       beq fll_sid_typed
       cmp #$02
       beq fll_sid_typed
       lda is_u64              // on Ultimate64 (non-ARM2SID primary)?
       bne fll_ultisid
       lda #$10                // fallback: unknown/generic second SID
       jmp fll_sid_typed
fll_ultisid:
       // Determine 6581 vs 8580 from U64 UCI filter curve config.
       // sptr_zp == mptr_zp at this point (both set from mptr_zp above).
       // uci_type_for_addr queries UCI GET_HWINFO for the SID model.
       stx x_zp               // save slot index (uci_type_for_addr trashes X)
       jsr uci_type_for_addr  // input: mptr_zp; output: A = $21 (6581) or $20 (8580)
       ldx x_zp               // restore slot index
fll_sid_typed:
       // load sid_list
       sta sid_list_t,x
       lda sptr_zp
       sta sid_list_l,x
       lda sptr_zp+1
       sta sid_list_h,x
       // Restore scan root so the next fiktivloop iteration uses the correct
       // primary chip. sptr_zp was saved to za8 in fll_no_dup above.
       lda za8
       sta sptr_zp
       lda za8+1
       sta sptr_zp+1
       // SIDFX primary: exit fiktivloop immediately after finding secondary.
       // Continuing the mirror scan with FREQ=0 causes mirror detection to fail
       // (LFSR stuck at 0), falsely confirming mirror addresses as separate SIDs.
       // This corrupts secondary oscillator state on every run, making the scan
       // non-deterministic. Same early-exit pattern used for FPGASID/SIDKick-pico.
       lda data4
       cmp #$30               // SIDFX primary?
       beq f_l_done           // yes: exit immediately

f_l_next:       
       lda mptr_zp
       cmp #$E0 // hvis E0, y++
       bne f_l_l2
       // get D4 from tab1
       ldy cnt1_zp 
       // if c128 then lda tab2,y
       lda za7
       cmp #$FF 
       bne f_l_l3
       lda tab1,y
       jmp f_l_l4
f_l_l3:       
       lda tab2,y // c128
f_l_l4:       
       sta mptr_zp+1
       iny
       sty cnt1_zp 
f_l_l2:       
       // add #$20 
       lda mptr_zp
       clc // clear cary
       adc #$20
       sta mptr_zp
       ldy mptr_zp+1
       ldx cnt2_zp
       inx
       stx cnt2_zp
       cpx #$30       // ikke $30
       bcs f_l_done   // cnt2 >= $30 → done
       jmp f_l_l1     // continue (bcc range exceeded by confirmation code above)
f_l_done:
       rts
//--------------------------------------------------------------------------------------------------                
checkanothersid:
// FPGAsid and ARMsid/Swinsid Ultimate
// the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
//(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
// https://csdb.dk/forums/?roomid=11&topicid=114511


                stx     x_zp            // $ad 
                sty     y_zp            // $ae
                pha                     // 
                
                lda #$f0
                sta data1
                
ccas_begin:                
//                lda     mptr_zp+1
//                lda     mptr_zp
                
//                adc     #$1b            // Voice 3 control at D41B
//                sta     ccas_d41b+1      // timing issue requieres runtime mod of upcodes.
//                lda     mptr_zp
                
// -- hack --
ccas_hack1:
                lda #$81        // activate noise waveform
                sta $d412
                lda #$FF        // 
                sta $d40f
                ldx #$d4        // set x = $D400
                stx za8+1
                ldx #$00
                stx za8         // set x = $D400 
                
ccas_d41b:        //lda $d41b
                ldy #$1b
                lda (za8),y  // lda D41B 
                cmp #$00        // Hvis 0, så er sid fundet.
                bne ccas_loop
                inx
                cpx #10 // if random gets 0 for some times it means it's not a mirror of d41b
                bne ccas_d41b
                jmp ccasfound
                
ccas_loop:       lda za8
                clc
                adc #$20
                sta za8       // zfb+$20
                bne ccas_noinczfc  // forskellige fra 0
                inc za8+1
                lda za8+1
                cmp #$d8      // 
                bcs ccasstopsrealsid  // hvis >= $D800 så finished
ccas_noinczfc:
                jmp ccas_d41b // en tur til
                
ccasfound:      
                lda #$10
                sta data1
                lda     za8
                sta     sptr_zp         // store lowbyte 00 (Sidhome)
                lda     za8+1            // load highbyte D4  (Sidhome)
                sta     sptr_zp+1       // store highbyte D4 (Sidhome)
                jsr Checkarmsid     
                lda data1
                cmp #04 // S
                bne ccas_armsid
                // swinddectect
                jmp ccas_writesidl 
ccas_armsid:
                lda data1
                cmp #05 // N
                bne ccas_fpgasid
                jmp ccas_writesidl 
                // armsid 
ccas_fpgasid:
                lda #$10
                sta data1
                lda     za8
                sta     sptr_zp         // store lowbyte 00 (Sidhome)
                lda     za8+1            // load highbyte D4  (Sidhome)
                sta     sptr_zp+1       // store highbyte D4 (Sidhome)
//debug
                //lda     za8+1            // load highbyte D4  (Sidhome)
                //jsr PRBYTE
                //lda     za8
                //jsr PRBYTE
                //
                jsr checkfpgasid
// debug
//                lda data1
//                jsr PRBYTE
                
                lda data1
                cmp #06 // N
                bne ccas_fpgasid2
                jmp ccas_writesidl 
ccas_fpgasid2:
                lda data1
                cmp #07 // N
                bne ccasstopsrealsid
//-----                
ccas_writesidl:
                ldx sidnum_zp //
                inx
                stx sidnum_zp
                lda data1 
                sta sid_list_t,x
                lda sptr_zp
                sta sid_list_l,x
                lda sptr_zp+1
                sta sid_list_h,x
                // load sid_list

//debug
       //lda sptr_zp+1
       //jsr PRBYTE
       //lda sptr_zp
       //jsr PRBYTE
       //lda data1
       //jsr PRBYTE


                
ccasstopsrealsid:            

                ldx     x_zp            // $ad 
                ldy     y_zp            // $ae
                pla                     // 
                rts 


//--------------------------------------------------------------------------------------------------                
checksecondFPGA:
//* Scan for and mark mirrors
// The problem is that the SID mirrors the values of registers (00..1F) on the highbyte.
// D500, D520, D540, D560..D7F0 will show the same value even though the chip select address is D500.
// the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
//(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
// https://csdb.dk/forums/?roomid=11&topicid=114511
// DE00 and DF00 also mirror values

// set values
// D400
       lda #$D4
       lda sptr_zp+1
       sta mptr_zp+1
       lda #$00
       lda sptr_zp
       sta mptr_zp
csfp_l_l1:
       jsr checkfpgasid
       lda data1
       cmp $07
       bne csfp_l_l_fpga1
       jmp csfp_l_l_found
csfp_l_l_fpga1:
       lda data1
       cmp $06
       bne csfp_l_l_sec
       jmp csfp_l_l_found
csfp_l_l_sec:
//       jsr checksecondsid
//       lda data1
//       cmp #$10
//       bne csfp_l_next
        jmp csfp_l_next

csfp_l_l_found:
       //hvis fundet
       // sanity check
       lda sidnum_zp
       cmp #$08
       bcs csfp_l_next// hvis x >=09 then slut     
       // sanity check
       ////// found sid //////
       ldx sidnum_zp // 
       inx 
       stx sidnum_zp
       lda mptr_zp+1
       sta sptr_zp+1
       lda mptr_zp
       sta sptr_zp
       // load sid_list
       lda data1 
       sta sid_list_t,x
       lda sptr_zp
       sta sid_list_l,x
       lda sptr_zp+1
       sta sid_list_h,x
       // load sid_list
       // choose next sid found as base
       lda sptr_zp+1
       lda sptr_zp
       
       
csfp_l_next:       
       lda mptr_zp
       cmp #$E0 // hvis E0, y++
       bne csfp_l_l2
       // get D4 from tab1
       ldy cnt1_zp 
       // if c128 then lda tab2,y
       lda za7
       cmp #$FF 
       bne csfp_l_l3
       lda tab1,y
       jmp csfp_l_l4
csfp_l_l3:       
       lda tab2,y // c128
csfp_l_l4:       
       sta mptr_zp+1
       iny
       sty cnt1_zp 
csfp_l_l2:       
       // add #$20 
       lda mptr_zp
       clc // clear cary
       adc #$20
       sta mptr_zp
       ldy mptr_zp+1
       ldx cnt2_zp
       inx
       stx cnt2_zp
       cpx #$30       // ikke $30
       bcc csfp_l_l1        
       rts
                
//--------------------------------------------------------------------------------------------------                
sidstereo_print:

// check FPGA, SWIN, ARMSID  
//swinsidUf      .text "SWINSID ULTIMATE FOUND"   ,0  // data1=$04 data2=$57
//armsidf        .text "ARMSID FOUND" ,0              // data1=$05 data2=$4f
//nosoundf       .text "NOSID FOUND" ,0               // data1=$f0 data2=$f0
//fpgasidf_8580u .text "FPGASID 8580 FOUND"   ,0      // data1=$06 data2=$3f
//fpgasidf_6581u .text "FPGASID 6581 FOUND"   ,0      // data1=$07 data2=$00
//l6581f         .text "6581 FOUND"   ,0             // data1=$02 data2=$02
//l8580f         .text "8580 FOUND" ,0               // data1=$01 data2=$01
//swinsidnanof   .text "SWINSID NANO FOUND" ,0        // data1=$10 data2=$10

//        lda sidnum_zp
//        jsr PRBYTE
        
        lda sidnum_zp
        bne ssp_init 
        jmp ssp_ex1
ssp_init:
        ldy #$00
        sty tmp2_zp// counter antal sid.
ssp_loop:
        ldy tmp2_zp
        iny
        sty tmp2_zp
        lda #15             // stereo SID entries start at row 16 (15 + tmp2_zp)
        clc
        adc tmp2_zp
        tax
        ldy #13    // Select column
        jsr $E50C   // Set cursor
//        lda sptr_zp+1
        ldy tmp2_zp
        lda sid_list_h,y
        // sanity
        bne ssp_loop2 // hvis $00 i high, så stop     
        jmp ssp_skp20
        // sanity
ssp_loop2:        
        lda sid_list_h,y
        jsr     print_hex
//        lda sptr_zp
        lda sid_list_l,y
        jsr     print_hex
        lda     #$20        // space
        jsr     $ffd2
//        lda     data1
        lda sid_list_t,y  // type
        cmp     #$02
        bne     ssp_skp4
        lda     #<l8580f
        ldy     #>l8580f
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp4:
        cmp     #$01
        bne     ssp_skp5
        lda     #<l6581f
        ldy     #>l6581f
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp5:
        cmp     #$04
        bne     ssp_skp6
        lda     #<swinsidUf
        ldy     #>swinsidUf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp6:
        cmp     #$05
        bne     ssp_skp7
        lda     armsid_major
        cmp     #$03        // firmware major version 3 = ARM2SID
        beq     ssp_a2_arm2
        lda     #$05        // restore type code for ssp_skp7's cmp #$05
        jmp     ssp_skp7
ssp_a2_arm2:
        // ARM2SID stereo entry: "ARM2SID SIDL 6581+SFX" format
        lda     sid_list_h,y
        ldx     sid_list_l,y
        jsr     arm2sid_slot_lookup  // (high,low) → A = map value
        sta     tmp_zp               // save map value across string print
        lda     #<arm2sid_shortf
        ldy     #>arm2sid_shortf
        jsr     $AB1E                // print "ARM2SID "
        lda     tmp_zp
        jsr     print_map_name       // "SIDL"/"SIDR"/"SID3"/"SFX-"/"----"
        lda     tmp_zp
        cmp     #$03                 // SFX- slot? skip SID type (OPL2, not a SID)
        beq     ssp_a2_arm2_done
        lda     #$20
        jsr     $FFD2
        jsr     print_sid_type_4     // "6581" or "8580" (SID slots only)
ssp_a2_arm2_done:
        jmp     ssp_skp20
ssp_skp7:
        cmp     #$05
        bne     ssp_skp8
        lda     #<armsidf
        ldy     #>armsidf
        jsr     $ab1e
        // armsid_sid_type_h only valid for primary ARMSID; skip SID type when SIDFX secondary.
        lda     data4
        cmp     #$30
        bne     ssp_skp7_type       // not SIDFX → print SID type
        jmp     ssp_skp20           // SIDFX: "ARMSID FOUND" only, no "????"
ssp_skp7_type:
        lda     #$20
        jsr     $FFD2
        jsr     print_sid_type_4     // skip version; show SID type
        jmp     ssp_skp20
ssp_skp8:
        cmp     #$06
        bne     ssp_skp9
        lda     #<fpgasidf_8580u
        ldy     #>fpgasidf_8580u
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp9:
        cmp     #$07
        bne     ssp_skp10
        lda     #<fpgasidf_6581u
        ldy     #>fpgasidf_6581u
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp10:
        cmp     #$10
        bne     ssp_skp11
        // If primary is ARM2SID: show slot map + SID type for this address
        lda     data4
        cmp     #$05
        bne     ssp_skp10_gen
        lda     armsid_major
        cmp     #$03
        bne     ssp_skp10_gen
        lda     sid_list_h,y
        ldx     sid_list_l,y
        jsr     arm2sid_slot_lookup
        sta     tmp_zp               // save map value across string print
        lda     #<arm2sid_shortf
        ldy     #>arm2sid_shortf
        jsr     $AB1E                // print "ARM2SID "
        lda     tmp_zp
        jsr     print_map_name
        lda     tmp_zp
        cmp     #$03                 // SFX- slot? skip SID type
        beq     ssp_skp10_done
        lda     #$20
        jsr     $FFD2
        jsr     print_sid_type_4     // SID slots only
ssp_skp10_done:
        jmp     ssp_skp20
ssp_skp10_gen:
        lda     #<secondsid
        ldy     #>secondsid
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp11:
        cmp     #$09
        bne     ssp_skp11b
        lda     #<pdsidf
        ldy     #>pdsidf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp11b:
        cmp     #$0A
        bne     ssp_skp11c
        lda     #<backsidf
        ldy     #>backsidf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp11c:
        cmp     #$0B
        bne     ssp_skp11d
        lda     #<skpicof
        ldy     #>skpicof
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp11d:
        cmp     #$0E
        bne     ssp_skp12
        lda     #<skpicof_6581
        ldy     #>skpicof_6581
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp12:
        cmp     #$08
        bne     ssp_skp13
        lda     #<swinsidnanof
        ldy     #>swinsidnanof
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp13:
        cmp     #$0C
        bne     ssp_skp14
        lda     #<kungfusidf
        ldy     #>kungfusidf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp14:
        cmp     #$0D
        bne     ssp_skp15
        lda     #<usid64f
        ldy     #>usid64f
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp15:
        cmp     #$30
        bne     ssp_skp16
        lda     #<sidFXf
        ldy     #>sidFXf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp16:
        // UltiSID: show "8580 INT" ($20/$21/$24-$26) or "6581 INT" ($22/$23)
        cmp     #$20
        bcc     ssp_skp16b      // < $20 → not ultisid
        cmp     #$27
        bcs     ssp_skp16b      // >= $27 → not ultisid
        sec
        sbc     #$22            // A - $22: 6581 types ($22/$23) → 0/1; others wrap or ≥2
        cmp     #$02            // C=0 → result 0 or 1 → 6581; C=1 → 8580
        lda     #<ultisid_8580_int
        ldy     #>ultisid_8580_int
        bcs     ssp_u_print     // C=1 → 8580 (includes $20/$21 which underflow to $FE/$FF)
        lda     #<ultisid_6581_int
        ldy     #>ultisid_6581_int
ssp_u_print:
        jsr     $AB1E
        jmp     ssp_skp20
ssp_skp16b:
        cmp     #$F0
        bne     ssp_skp20
        lda     #<unknownsid
        ldy     #>unknownsid
        jsr     $ab1e
ssp_skp20:

//debugl:
//       jsr readkeyboard
//       beq debugl
//        
        lda     #13
        jsr     $ffd2
        ldy tmp2_zp
        cpy #$08            // cap at 8 entries (rows 16-23; row 24 = shortcut line)
        beq ssp_ex1
        cpy sidnum_zp
        beq ssp_ex1
        jmp ssp_loop
ssp_ex1:
        rts

//--------------------------------------------------------------------------------------------------
// armsid_get_version: query ARMSID/ARM2SID firmware version at $D400.
// Properly enters config mode with lowercase 'd'(64),'i'(69),'s'(73),
// then sends version query 'v'(76),'i'(69), reads D41B→armsid_major,
// D41C→armsid_minor, then closes config. Hardcoded to $D400.
// Call after Checkarmsid confirms ARMSID family at D400.
// Trashes A. Preserves X, Y.
//--------------------------------------------------------------------------------------------------
armsid_get_version:
                stx x_zp
                sty y_zp
                pha
                // Silence SID (D418=0 ×3) matching testc312 najdi() SIDaddr[24]=0 ×3 before sidoffon
                lda #$00
                sta $D418
                sta $D418
                sta $D418
                // sid_off(): D41D=0 ×3 only — matches reference exactly, no D41E/D41F writes
                sta $D41D
                sta $D41D
                sta $D41D
                // Pre-config delay: 1× loop1sek ≈ 3ms.
                // Called after Checkarmsid confirms chip (chip has been on for >100ms by then).
                jsr loop1sek
                // Enter config mode — PETSCII: 'd'=$44→D41F, 'i'=$49→D41E, 's'=$53→D41D
                // (PETSCII 'd'=0x44, 'i'=0x49, 's'=0x53 — identical to ASCII uppercase 'D','I','S')
                lda #$44          // PETSCII 'd'
                sta $D41F
                lda #$49          // PETSCII 'i'
                sta $D41E
                lda #$53          // PETSCII 's'
                sta $D41D
                // Inside-config delay: Y=60 → ~301 cycles ≈ ref delay(1)
                ldy #60
agv_dly1a:      dey
                bne agv_dly1a
                // Read D41B/D41C — "NO" check: $4E (PETSCII 'n'), $4F (PETSCII 'o') if config opened
                lda $D41B
                sta armsid_cfgtest  // D41B (expect $4E = PETSCII 'n')
                lda $D41C
                sta armsid_no_c     // D41C (expect $4F = PETSCII 'o')
                // Send 'e'/'i' command — PETSCII 'e'=$45, 'i'=$49
                // EI probe: D41B→$53 (PETSCII 's'), D41C→$57 (PETSCII 'w') on ARMSID/ARM2SID
                lda #$45          // PETSCII 'e'
                sta $D41F
                lda #$49          // PETSCII 'i'
                sta $D41E
                ldy #60
agv_dly_ei:     dey
                bne agv_dly_ei
                lda $D41B
                sta armsid_ei_b     // expect $53 (PETSCII 's')
                lda $D41C
                sta armsid_ei_c     // expect $57 (PETSCII 'w')
                // Send 'i'/'i' command — ARM2SID ident: D41B=2, D41C=PETSCII 'l'=$4C or 'r'=$52
                lda #$49          // PETSCII 'i'
                sta $D41F
                lda #$49          // PETSCII 'i'
                sta $D41E
                ldy #60
agv_dly_ii:     dey
                bne agv_dly_ii
                lda $D41B
                sta armsid_ii_b     // 2=ARM2SID, other=ARMSID
                lda $D41C
                sta armsid_ii_c     // PETSCII 'l'=$4C or 'r'=$52 for ARM2SID
                // Send 'v'/'i' command — PETSCII 'v'=$56, 'i'=$49 — firmware version query
                lda #$56          // PETSCII 'v'
                sta $D41F
                lda #$49          // PETSCII 'i'
                sta $D41E
                // Inside-config delay before read
                ldy #60
agv_dly1b:      dey
                bne agv_dly1b
                // Read firmware version
                lda $D41B         // major: 2=ARMSID, 3=ARM2SID
                sta armsid_major
                lda $D41C         // minor: 0-99 raw
                sta armsid_minor
                // Query emulated SID type ('f','i') — PETSCII 'f'=$46, 'i'=$49
                lda #$46          // PETSCII 'f'
                sta $D41F
                lda #$49          // PETSCII 'i'
                sta $D41E
                ldy #60
agv_dly_fi:     dey
                bne agv_dly_fi
                lda $D41B         // '6'=$36 (6581) or '8'=$38 (8580)
                sta armsid_sid_type_h
                // Query auto-detect ('g','i') — PETSCII 'g'=$47
                lda #$47          // PETSCII 'g'
                sta $D41F
                lda #$49          // PETSCII 'i'
                sta $D41E
                ldy #60
agv_dly_gi:     dey
                bne agv_dly_gi
                lda $D41B         // '7'=$37 = auto-detected
                sta armsid_auto_sid
                // ARM2SID only (major=3): query memory mapping
                lda armsid_major
                cmp #$03
                bne agv_skip_memmap
                // Mode ('m','m') — PETSCII 'm'=$4D
                lda #$4D
                sta $D41F
                lda #$4D
                sta $D41E
                ldy #60
agv_dly_mm:     dey
                bne agv_dly_mm
                lda $D41B         // bits 1:0 = mode (0=SID,1=SFX,2=SFX+SID)
                sta armsid_emul_mode
                // Low map ('l','m') — PETSCII 'l'=$4C
                lda #$4C
                sta $D41F
                lda #$4D
                sta $D41E
                ldy #60
agv_dly_lm:     dey
                bne agv_dly_lm
                lda $D41B         // slots 0 (lo nibble) + 1 (hi nibble)
                sta armsid_map_l
                lda $D41C         // slots 2 (lo) + 3 (hi)
                sta armsid_map_l2
                // High map ('h','m') — PETSCII 'h'=$48
                lda #$48
                sta $D41F
                lda #$4D
                sta $D41E
                ldy #60
agv_dly_hm:     dey
                bne agv_dly_hm
                lda $D41B         // slots 4 (lo) + 5 (hi)
                sta armsid_map_h
                lda $D41C         // slots 6 (lo) + 7 (hi)
                sta armsid_map_h2
agv_skip_memmap:
                // Close config: 3× write 0 to D41D
                lda #$00
                sta $D41D
                sta $D41D
                sta $D41D
                pla
                ldx x_zp
                ldy y_zp
                rts

//--------------------------------------------------------------------------------------------------
// arm2sid_populate_sid_list: add non-NONE ARM2SID slots 1-7 to sid_list.
// Slot 0 (D400) is already pre-populated. Iterates slots 1-7 using the map data
// from armsid_get_version (armsid_map_l/l2/h/h2) — map value 0=NONE → skip.
// Slot addresses: 0=D400/00, 1=D420/20, 2=D500/00, 3=D520/20,
//                 4=DE00/00, 5=DE20/20, 6=DF00/00, 7=DF20/20.
// All active slots added with type $05. Trashes A, tmp_zp, sptr_zp. Preserves X, Y.
//--------------------------------------------------------------------------------------------------
arm2sid_populate_sid_list:
// Add non-NONE ARM2SID slots 1-7 to sid_list (slot 0 = D400, already added).
// Reads armsid_map_l/l2/h/h2; each byte is nibble-packed (lo=even slot, hi=odd slot).
// Slots: 0=D4/00, 1=D4/20, 2=D5/00, 3=D5/20, 4=DE/00, 5=DE/20, 6=DF/00, 7=DF/20.
// Unrolled: no loop, no index table — each slot tested explicitly. Trashes A,X. Preserves Y.
                // Slot 1 (D420): armsid_map_l high nibble
                lda armsid_map_l
                lsr                     // shift high nibble to low
                lsr
                lsr
                lsr
                beq a2spl_s1            // 0 = NONE
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$20
                sta sid_list_l,x
                lda #$D4
                sta sid_list_h,x
a2spl_s1:       // Slot 2 (D500): armsid_map_l2 low nibble
                lda armsid_map_l2
                and #$0F
                beq a2spl_s2
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$00
                sta sid_list_l,x
                lda #$D5
                sta sid_list_h,x
a2spl_s2:       // Slot 3 (D520): armsid_map_l2 high nibble
                lda armsid_map_l2
                lsr
                lsr
                lsr
                lsr
                beq a2spl_s3
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$20
                sta sid_list_l,x
                lda #$D5
                sta sid_list_h,x
a2spl_s3:       // Slot 4 (DE00): armsid_map_h low nibble
                lda armsid_map_h
                and #$0F
                beq a2spl_s4
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$00
                sta sid_list_l,x
                lda #$DE
                sta sid_list_h,x
a2spl_s4:       // Slot 5 (DE20): armsid_map_h high nibble
                lda armsid_map_h
                lsr
                lsr
                lsr
                lsr
                beq a2spl_s5
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$20
                sta sid_list_l,x
                lda #$DE
                sta sid_list_h,x
a2spl_s5:       // Slot 6 (DF00): armsid_map_h2 low nibble
                lda armsid_map_h2
                and #$0F
                beq a2spl_s6
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$00
                sta sid_list_l,x
                lda #$DF
                sta sid_list_h,x
a2spl_s6:       // Slot 7 (DF20): armsid_map_h2 high nibble
                lda armsid_map_h2
                lsr
                lsr
                lsr
                lsr
                beq a2spl_done
                ldx sidnum_zp
                inx
                stx sidnum_zp
                lda #$05
                sta sid_list_t,x
                lda #$20
                sta sid_list_l,x
                lda #$DF
                sta sid_list_h,x
a2spl_done:     rts

//--------------------------------------------------------------------------------------------------
// sidfx_populate_sid_list: populate sid_list from saved SIDFX D41D/D41E registers.
// Slot 1 = D400 with SID1 type; slot 2 = secondary SID (SW1 address) with SID2 type.
// SID2 probed for: D5xx+ SIDKick Pico (sfx_probe_skpico config mode), then
// ARMSID/SwinSID U (sfx_probe_dis_echo via OSC3 D43B), BackSID, KungFuSID, FPGASID.
// D420: skpico skipped (CS1-only firmware); SIDFX write-buffers unmapped regs so only
// D43B (mapped OSC3) is reliable. SIDKick Pico at D420 cannot be specifically identified.
// Uses buf_zp ($AF), tmp_zp ($AC), sptr_zp ($F9/$FA). Trashes A, X, Y.
//--------------------------------------------------------------------------------------------------
sidfx_populate_sid_list:
                ldx #$01
                stx sidnum_zp
                lda #$00
                sta sid_list_l,x        // D400 low = $00
                lda #$D4
                sta sid_list_h,x        // D400 high = $D4
                lda sidfx_d41e
                and #$03                // SID1 type: 0=NONE 1=6581 2=8580 3=UNKN
                beq sfx_pop_s1_norm     // 0=NONE → $F0
                cmp #$03
                bne sfx_pop_s1_store    // 1/2 → use as-is
                // type=3 (UNKN): probe D400 — FPGASID first (sfx_probe_skpico writes D41E=$E0
                // without cleanup on miss, corrupting FPGASID magic-cookie state if run first).
                lda #$00
                sta sptr_zp             // point sptr_zp → D400
                lda #$D4
                sta sptr_zp+1
                jsr checkfpgasid        // data1=$06/$07(FPGASID) or $F0 — must run before skpico
                lda data1
                bpl sfx_pop_s1_store    // bit7=0 → $06/$07: FPGASID found
                jsr sfx_probe_skpico    // C=1: SIDKick Pico found (trashes A; preserves X,Y)
                bcc sfx_s1_not_skp
                lda #$0B                // SIDKick Pico (8580 default — SIDFX UNKN, mode indeterminate)
                bne sfx_pop_s1_store    // always taken
sfx_s1_not_skp:
                jsr checkpdsid          // data1=$09(PDsid) or $F0
                lda data1
                cmp #$09
                beq sfx_pop_s1_store    // A=$09 → PDsid found
                jsr sfx_probe_dis_echo  // sptr_zp still D400; A = echo from D41B
                cmp #$53                // 'S' = SwinSID Ultimate
                bne sfx_s1_not_swu
                lda #$04                // SwinSID Ultimate
                bne sfx_pop_s1_store    // always taken
sfx_s1_not_swu:
                cmp #$4E                // 'N' = ARMSID
                bne sfx_pop_s1_norm     // not any known chip → $F0
                lda #$05                // ARMSID type code
                bne sfx_pop_s1_store    // always taken (A=$05 ≠ 0)
sfx_pop_s1_norm:
                lda #$F0                // 0=NONE or UNKN+not found → $F0
sfx_pop_s1_store:
                sta sid_list_t,x
                // SID2 type from sidfx_d41e bits 3:2
                lda sidfx_d41e
                lsr; lsr
                and #$03                // 0=NONE 1=6581 2=8580 3=UNKN
                bne sfx_pop_s2_notnone  // non-zero → has second SID
                jmp sfx_pop_done        // 0=NONE → no second SID
sfx_pop_s2_notnone:
                cmp #$03
                bne sfx_pop_s2_type_ok
                lda #$F0                // 3=UNKN → $F0
sfx_pop_s2_type_ok:
                sta buf_zp              // save normalized SID2 type (1/2/$F0)
                // Secondary address from SW1 (sidfx_d41d bits 5:4): 0=CTR 1=LFT 2=RGT
                lda sidfx_d41d
                lsr; lsr; lsr; lsr
                and #$03
                sta tmp_zp              // save SW1 index for reuse after probe
                tay
                lda sidfx_sec_lo,y
                sta sptr_zp             // secondary base address for sfx_probe_skpico
                lda sidfx_sec_hi,y
                sta sptr_zp+1
                // Probe secondary SID.
                // sfx_probe_skpico (config mode via base+$1F) requires CS1 — does NOT work
                // at D420 (CS2). SIDFX write-buffers unmapped regs ($1D–$1F) so D43D echo
                // returns any written value regardless of chip — not discriminating.
                // DE/DF is SIDFX cartridge I/O — no probe possible there.
                // D420 DIS probe (D43B=OSC3, mapped): works UNLESS primary is ARMSID.
                // ARMSID primary snoops CS2 DIS writes and drives $4E aggressively on all
                // D4xx reads (same address space, shared bus), contaminating D43B. Skip DIS
                // for D420 when primary is ARMSID ($05); use SIDFX-reported type instead.
                lda sptr_zp+1
                cmp #$DE; beq sfx_pop_s2_add    // DE00: SIDFX cartridge I/O → skip all
                cmp #$DF; beq sfx_pop_s2_add    // DF00: SIDFX cartridge I/O → skip all
                cmp #$D4; bne sfx_pop_not_d4    // not D420 → D5xx+: run skpico probe
                // D420: check if primary SID is ARMSID (sid_list_t[x], x=1 here).
                // data4=$30 (SIDFX flag) — primary type is in sid_list_t,x.
                lda sid_list_t,x
                cmp #$05                        // ARMSID primary?
                beq sfx_pop_s2_add              // yes → D43B contaminated → use SIDFX type
                jmp sfx_pop_try_dis             // no → safe to probe D420 with DIS
sfx_pop_not_d4:
                jsr sfx_probe_skpico    // D5xx+: C=1: SIDKick Pico found; C=0: not found
                bcc sfx_pop_skp_miss
sfx_skp_s2_match:
                // SIDKick Pico confirmed at secondary: remap type code
                lda buf_zp
                cmp #$01                // 6581 mode?
                bne sfx_skp_s2_8580
                lda #$0E                // SIDKick Pico 6581
                bne sfx_pop_s2_save     // always taken
sfx_skp_s2_8580:
                lda #$0B                // SIDKick Pico 8580 (or UNKN → default 8580)
                bne sfx_pop_s2_save     // always taken (A=$0B ≠ 0)
sfx_pop_skp_miss:
sfx_pop_try_dis_d4:
sfx_pop_try_dis:
                jsr sfx_probe_dis_echo  // A = echo byte from base+$1B after DIS sequence
                cmp #$53                // 'S' = SwinSID Ultimate
                bne sfx_pop_try_armsid
                lda #$04                // $04 = SwinSID Ultimate
                bne sfx_pop_s2_save     // always taken
sfx_pop_try_armsid:
                cmp #$4E                // 'N' = ARMSID / ARM2SID
                beq sfx_pop_is_armsid
                // BackSID: reuse checkbacksid (sptr_zp already set); result in data1
                jsr checkbacksid
                lda data1
                cmp #$0A                // $0A = BackSID confirmed?
                bne sfx_pop_try_kfs     // no → try KungFuSID
                beq sfx_pop_s2_save     // yes (Z=1): A=$0A, always taken
sfx_pop_try_kfs:
                // KungFuSID: write $A5 to base+$1D, wait, read back $5A (new FW ACK only).
                // Old FW echo ($A5) is rejected — indistinguishable from real SID bus float.
                // (sptr_zp),y — no self-mod needed. rp_delay clobbers Y.
                lda #$A5
                ldy #$1D
                sta (sptr_zp),y         // base+$1D ← $A5 (firmware-update magic)
                lda #$04                // ~3ms
                jsr rp_delay
                ldy #$1D
                lda (sptr_zp),y         // read back base+$1D
                cmp #$5A                // new FW only: byte-swap ACK ($A5→$5A)
                bne sfx_pop_try_fpga    // not $5A → not KungFuSID → try FPGASID
sfx_pop_is_kfs:
                lda #$0C                // $0C = KungFuSID
                bne sfx_pop_s2_save     // always taken (A=$0C ≠ 0)
sfx_pop_try_fpga:
                // FPGASID: checkfpgasid uses sptr_zp self-mod; sptr_zp already → secondary.
                // POT regs (base+$19/$1A/$1E/$1F) carry magic-cookie protocol.
                // Returns data1=$06(8580)/$07(6581)/$F0(not found).
                jsr checkfpgasid
                lda data1
                cmp #$06                // FPGASID 8580 mode
                beq sfx_pop_fpga_found
                cmp #$07                // FPGASID 6581 mode
                bne sfx_pop_s2_add      // not FPGASID ($F0 or other) → use SIDFX-reported type
sfx_pop_fpga_found:
                jmp sfx_pop_s2_save     // A=$06 or $07 → save FPGASID type code
sfx_pop_is_armsid:
                lda #$05                // $05 = ARMSID
sfx_pop_s2_save:
                sta buf_zp
sfx_pop_s2_add:
                ldy tmp_zp              // restore SW1 index
                ldx sidnum_zp
                inx; stx sidnum_zp
                lda sidfx_sec_lo,y
                sta sid_list_l,x
                lda sidfx_sec_hi,y
                sta sid_list_h,x
                lda buf_zp
                sta sid_list_t,x
sfx_pop_done:   rts

//--------------------------------------------------------------------------------------------------
// sfx_probe_skpico: probe the SID at sptr_zp:sptr_zp+1 for SIDKick Pico identity.
// Phase 1 only: enters config mode (write $FF to base+$1F), checks VERSION_STR[0]='S'
// and VERSION_STR[1]='K' via manual pointer at base+$1E, read at base+$1D.
// If found, exits config mode by writing $00 to base+$18 (volume register).
// Returns: C=1 found, C=0 not found. Trashes A only; preserves X, Y.
//--------------------------------------------------------------------------------------------------
sfx_probe_skpico:
                // Patch self-modifying addresses with secondary SID base
                lda sptr_zp+1
                sta sfx_skp_f+2
                sta sfx_skp_e1+2
                sta sfx_skp_e2+2
                sta sfx_skp_ds+2
                sta sfx_skp_dk+2
                sta sfx_skp_vol+2
                lda sptr_zp
                clc
                adc #$1F
                sta sfx_skp_f+1         // base+$1F
                sec; sbc #$01
                sta sfx_skp_e1+1        // base+$1E
                sta sfx_skp_e2+1        // base+$1E
                sec; sbc #$01
                sta sfx_skp_ds+1        // base+$1D
                sta sfx_skp_dk+1        // base+$1D
                sec; sbc #$05
                sta sfx_skp_vol+1       // base+$18
                lda #$FF
sfx_skp_f:      sta $D41F               // enter config mode
                lda #$E0                // pointer → byte[0]
sfx_skp_e1:     sta $D41E
sfx_skp_ds:     lda $D41D               // read byte[0]: expect 'S'=$53
                cmp #$53
                bne sfx_skp_miss
                lda #$E1                // pointer → byte[1]
sfx_skp_e2:     sta $D41E
sfx_skp_dk:     lda $D41D               // read byte[1]: expect 'K'=$4B
                cmp #$4B
                bne sfx_skp_miss
                lda #$00
sfx_skp_vol:    sta $D418               // exit config mode (non-config reg write)
                sec                     // found
                rts
sfx_skp_miss:
                clc                     // not found
                rts

//--------------------------------------------------------------------------------------------------
// sfx_probe_dis_echo: write ARM DIS sequence to secondary SID, return echo from +$1B in A.
// Clears base+$1D before DIS (reset ARM/SwinSID state), then writes:
//   'D'=$44→base+$1F, 'I'=$49→base+$1E, 'S'=$53→base+$1D.
// Waits loop1sek×2, ACKs primary ARMSID (if any), reads base+$1B into A, cleans up.
// Caller checks: A=$53 → SwinSID Ultimate; A=$4E → ARMSID/ARM2SID; other → not found.
// Uses (sptr_zp),y indirect-indexed — no self-modification needed.
// loop1sek uses X only (preserves Y). rp_delay not used.
// Trashes A, Y; preserves X.
// In generic stereo scan: only call for D5xx–D7xx — D4xx bus conflict (SID1 drives +$1B).
// Exception: safe at D4xx from sidfx_populate_sid_list — SIDFX isolates D43B from SID1.
// Note: SIDFX write-buffers unmapped regs ($1D–$1F), so only use D43B (mapped OSC3) for
// detection at D420; never rely on D43D/D43E/D43F readback for chip identification.
// Primary ARMSID ACK: ARMSID snoops CS2 DIS writes (CS-agnostic) and aggressively drives
// $4E on ALL reads until D41B is read. This contaminates base+$1B of the secondary SID.
// ACK D41B before reading secondary base+$1B, except when sptr_zp=D400 where D41B IS
// the target echo. Skip ACK when lo=0 and hi=$D4 (D400 slot).
//--------------------------------------------------------------------------------------------------
sfx_probe_dis_echo:
                lda #$00                // pre-clear base+$1D (reset ARM/SwinSID echo state)
                ldy #$1D
                sta (sptr_zp),y
                lda #$44                // 'D' → base+$1F
                ldy #$1F
                sta (sptr_zp),y
                lda #$49                // 'I' → base+$1E
                dey                     // $1F→$1E
                sta (sptr_zp),y
                lda #$53                // 'S' → base+$1D
                dey                     // $1E→$1D
                sta (sptr_zp),y
                jsr loop1sek
                jsr loop1sek
                // ACK primary ARMSID before reading secondary base+$1B.
                // Skip when sptr_zp=D400 (lo=$00, hi=$D4): D41B IS the echo we want.
                lda sptr_zp+1
                cmp #$D4
                bne sfx_dis_ack         // D5xx+ → ACK
                lda sptr_zp
                beq sfx_dis_no_ack      // lo=0, hi=$D4 → D400 slot → skip ACK
sfx_dis_ack:    lda $D41B               // ACK: clears primary ARMSID bus drive
sfx_dis_no_ack:
                ldy #$1B
                lda (sptr_zp),y         // read echo from base+$1B
                pha
                lda #$00                // cleanup: clear DIS state
                ldy #$1D
                sta (sptr_zp),y         // clear base+$1D
                iny                     // $1D→$1E
                sta (sptr_zp),y         // clear base+$1E
                iny                     // $1E→$1F
                sta (sptr_zp),y         // clear base+$1F
                pla                     // return echo byte in A
                rts

//--------------------------------------------------------------------------------------------------
// print_armsid_ver: print " V" + major + "." + minor (two digits) via CHROUT.
// Skips if armsid_major=0 (version unknown). Trashes A and X.
//--------------------------------------------------------------------------------------------------
print_armsid_ver:
                lda armsid_major
                beq pav_done        // 0 = version unknown, skip
                pha                 // save major
                lda #$20            // ' '
                jsr $FFD2
                lda #$56            // 'V'
                jsr $FFD2
                pla                 // restore major
                clc
                adc #$30            // convert to ASCII digit
                jsr $FFD2           // print major digit
                lda #$2E            // '.'
                jsr $FFD2
                lda armsid_minor    // 0-99 raw
                ldx #$30            // tens digit accumulator (ASCII '0')
pav_div:        cmp #10
                bcc pav_divdone
                sec
                sbc #10
                inx
                jmp pav_div
pav_divdone:    pha                 // save units value
                txa
                jsr $FFD2           // print tens digit
                pla
                clc
                adc #$30            // convert units to ASCII
                jsr $FFD2           // print units digit
pav_done:       rts

//--------------------------------------------------------------------------------------------------
// print_armsid_ch: print " L" or " R" (ARM2SID channel) via CHROUT.
// Reads armsid_ii_c: $4C='L', $52='R'. Trashes A.
//--------------------------------------------------------------------------------------------------
print_armsid_ch:
                lda #$20
                jsr $FFD2
                lda armsid_ii_c
                cmp #$4C            // PETSCII 'l' → displays 'L'
                beq pac_ok
                cmp #$52            // PETSCII 'r' → displays 'R'
                beq pac_ok
                lda #$3F            // '?' for unknown
pac_ok:         jmp $FFD2

//--------------------------------------------------------------------------------------------------
// print_retry_star: if checkrealsid needed retries (retry_zp > 0), print '*' via CHROUT.
// Called right after printing "6581 FOUND" / "8580 FOUND" on the main screen.
// Trashes A.
//--------------------------------------------------------------------------------------------------
print_retry_star:
                lda retry_zp
                beq prs_exit        // 0 retries → nothing to show
                lda #$2A            // '*' (ASCII / screen code)
                jsr $FFD2           // CHROUT: print at current cursor position
prs_exit:       rts

// print_sid_type_4: print 4-char SID type "6581" or "8580" (no space). Trashes A.
// Reads armsid_sid_type_h: '6'=$36 → 6581, '8'=$38 → 8580, else "????".
//--------------------------------------------------------------------------------------------------
print_sid_type_4:
                lda armsid_sid_type_h
                cmp #$36            // '6' → 6581
                beq pst_6581
                cmp #$38            // '8' → 8580
                beq pst_8580
pst_unk:        lda #$20            // ' ' (unknown type — print 4 spaces)
                jsr $FFD2
                jsr $FFD2
                jsr $FFD2
                jsr $FFD2
                rts
pst_6581:       lda #$36            // '6'
                jsr $FFD2
                lda #$35            // '5'
                jsr $FFD2
                lda #$38            // '8'
                jsr $FFD2
                lda #$31            // '1'
                jmp $FFD2
pst_8580:       lda #$38            // '8'
                jsr $FFD2
                lda #$35            // '5'
                jsr $FFD2
                lda #$38            // '8'
                jsr $FFD2
                lda #$30            // '0'
                jmp $FFD2

//--------------------------------------------------------------------------------------------------
// dbg_print_sid_typename: print type name string for a sid_list type code.
// Input: A = type code; Preserves X (saved via x_zp). Trashes A, Y.
// Uses KERNAL $AB1E (print zero-terminated string, lo=A hi=Y).
//--------------------------------------------------------------------------------------------------
dbg_print_sid_typename:
                stx x_zp
                cmp #$06
                bne dpst_n06
                lda #<fpgasidf_8580u
                ldy #>fpgasidf_8580u
                jsr $AB1E
                jmp dpst_done
dpst_n06:       cmp #$07
                bne dpst_n07
                lda #<fpgasidf_6581u
                ldy #>fpgasidf_6581u
                jsr $AB1E
                jmp dpst_done
dpst_n07:       cmp #$01
                bne dpst_n01
                lda #<l8580f
                ldy #>l8580f
                jsr $AB1E
                jmp dpst_done
dpst_n01:       cmp #$02
                bne dpst_n02
                lda #<l6581f
                ldy #>l6581f
                jsr $AB1E
                jmp dpst_done
dpst_n02:       cmp #$05
                bne dpst_n05
                lda #<armsidf
                ldy #>armsidf
                jsr $AB1E
                jmp dpst_done
dpst_n05:       cmp #$04
                bne dpst_n04
                lda #<swinsidUf
                ldy #>swinsidUf
                jsr $AB1E
                jmp dpst_done
dpst_n04:       cmp #$0A
                bne dpst_n0A
                lda #<backsidf
                ldy #>backsidf
                jsr $AB1E
                jmp dpst_done
dpst_n0A:       cmp #$0B
                bne dpst_n0B
                lda #<skpicof
                ldy #>skpicof
                jsr $AB1E
                jmp dpst_done
dpst_n0B:       cmp #$0E
                bne dpst_n0E
                lda #<skpicof_6581
                ldy #>skpicof_6581
                jsr $AB1E
                jmp dpst_done
dpst_n0E:       cmp #$10
                bne dpst_n10
                lda #<secondsid
                ldy #>secondsid
                jsr $AB1E
                jmp dpst_done
dpst_n10:       cmp #$20
                bcc dpst_n20    // < $20 → hex fallback
                cmp #$27
                bcs dpst_n20    // >= $27 → hex fallback
                // UltiSID filter curve variant: type $20-$26 → table lookup
                sec
                sbc #$20        // index 0-6
                asl             // × 2
                tax
                lda ultisid_str_lo,x
                ldy ultisid_str_hi,x
                jsr $AB1E
                jmp dpst_done
dpst_n20:       jsr print_hex   // fallback: show raw hex code
dpst_done:      ldx x_zp
                rts

//--------------------------------------------------------------------------------------------------
// print_map_name: print 4-char slot label from arm2sid_mapnames.
// Input: A = map value 0-4 (0=----, 1=SIDL, 2=SIDR, 3=SFX-, 4=SID3). Preserves X. Trashes Y.
//--------------------------------------------------------------------------------------------------
print_map_name:
                cmp #5
                bcc pmn_ok
                lda #0
pmn_ok:         asl                 // offset = value × 4
                asl
                sta buf_zp          // save string offset ($AF)
                stx x_zp            // preserve X across FFD2 calls
                ldy #4
pmn_loop:       ldx buf_zp
                lda arm2sid_mapnames,x
                jsr $FFD2
                inc buf_zp
                dey
                bne pmn_loop
                ldx x_zp
                rts

//--------------------------------------------------------------------------------------------------
// get_slot_map_val: extract nibble-packed map value for slot X.
// Input: X = slot 0-7. Output: A = map value 0-4. Preserves X, Y.
// armsid_map_l/l2/h/h2 must be 4 consecutive bytes (slots 0-1, 2-3, 4-5, 6-7).
//--------------------------------------------------------------------------------------------------
get_slot_map_val:
                stx x_zp
                sty y_zp
                txa
                lsr                 // byte index = slot / 2
                tay
                txa
                and #$01            // odd slot → high nibble
                beq gsm_lo
                lda armsid_map_l,y
                lsr
                lsr
                lsr
                lsr
                jmp gsm_done
gsm_lo:         lda armsid_map_l,y
                and #$0F
gsm_done:       ldx x_zp
                ldy y_zp
                rts

//--------------------------------------------------------------------------------------------------
// arm2sid_slot_lookup: get map value for a SID address pair.
// Input: A = address high ($D4/$D5/$DE/$DF), X = low ($00 or $20).
// Output: A = map value 0-4. Trashes tmp_zp, x_zp, y_zp.
//--------------------------------------------------------------------------------------------------
arm2sid_slot_lookup:
                stx tmp_zp          // save low byte
                cmp #$D4
                bne asl_d5
                lda #0
                jmp asl_got
asl_d5:         cmp #$D5
                bne asl_de
                lda #2
                jmp asl_got
asl_de:         cmp #$DE
                bne asl_df
                lda #4
                jmp asl_got
asl_df:         cmp #$DF
                bne asl_unk
                lda #6
                jmp asl_got
asl_unk:        lda #0
asl_got:        ldx tmp_zp
                cpx #$20
                bne asl_even
                clc
                adc #1              // $20 offset → odd slot
asl_even:       tax
                jsr get_slot_map_val
                rts

//--------------------------------------------------------------------------------------------------
// arm2sid_print_extra: dynamic config lines for IP_ARMSID info page (called from sip_rc_done).
// Shows emulated SID type + channel; for ARM2SID also shows 8-slot memory map.
// Trashes A, X, Y, buf_zp, x_zp, y_zp, tmp_zp.
//--------------------------------------------------------------------------------------------------
arm2sid_print_extra:
                lda #$0D            // CR: close static text's last line ("ARMSID.COM")
                jsr $FFD2
                lda #$0D            // blank separator
                jsr $FFD2
                // " EMUL: 6581"
                lda #$20
                jsr $FFD2
                lda #$45            // 'E'
                jsr $FFD2
                lda #$4D            // 'M'
                jsr $FFD2
                lda #$55            // 'U'
                jsr $FFD2
                lda #$4C            // 'L'
                jsr $FFD2
                lda #$3A            // ':'
                jsr $FFD2
                lda #$20
                jsr $FFD2
                jsr print_sid_type_4
                // ARM2SID: append "  CH:L" or "  CH:R"
                lda armsid_major
                cmp #$03
                bne ape_no_ch
                lda #$20
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$43            // 'C'
                jsr $FFD2
                lda #$48            // 'H'
                jsr $FFD2
                lda #$3A            // ':'
                jsr $FFD2
                lda armsid_ii_c
                cmp #$4C
                beq ape_ch_ok
                cmp #$52
                beq ape_ch_ok
                lda #$3F
ape_ch_ok:      jsr $FFD2
ape_no_ch:
                lda #$0D
                jsr $FFD2
                // ARM2SID only: mode line "MODE: SID" / "MODE: SFX" / "MODE: SID+SFX"
                lda armsid_major
                cmp #$03
                bne ape_skip_mode      // not ARM2SID → skip mode line
                lda #$20               // ' '
                jsr $FFD2
                lda #$4D               // 'M'
                jsr $FFD2
                lda #$4F               // 'O'
                jsr $FFD2
                lda #$44               // 'D'
                jsr $FFD2
                lda #$45               // 'E'
                jsr $FFD2
                lda #$3A               // ':'
                jsr $FFD2
                lda #$20               // ' '
                jsr $FFD2
                lda armsid_emul_mode
                and #$03
                cmp #$01               // SFX only?
                beq ape_mode_sfx
                cmp #$02               // SFX+SID?
                beq ape_mode_sfxsid
                // mode=0: "SID"
                lda #$53               // 'S'
                jsr $FFD2
                lda #$49               // 'I'
                jsr $FFD2
                lda #$44               // 'D'
                jsr $FFD2
                jmp ape_mode_done
ape_mode_sfx:   // mode=1: "SFX"
                lda #$53               // 'S'
                jsr $FFD2
                lda #$46               // 'F'
                jsr $FFD2
                lda #$58               // 'X'
                jsr $FFD2
                jmp ape_mode_done
ape_mode_sfxsid: // mode=2: "SID+SFX"
                lda #$53               // 'S'
                jsr $FFD2
                lda #$49               // 'I'
                jsr $FFD2
                lda #$44               // 'D'
                jsr $FFD2
                lda #$2B               // '+'
                jsr $FFD2
                lda #$53               // 'S'
                jsr $FFD2
                lda #$46               // 'F'
                jsr $FFD2
                lda #$58               // 'X'
                jsr $FFD2
ape_mode_done:
                lda #$0D
                jsr $FFD2
ape_skip_mode:
                // ARM2SID only: memory map
                lda armsid_major
                cmp #$03
                beq ape_is_arm2
                jmp ape_done        // not ARM2SID → skip map
ape_is_arm2:
                // " MEMORY MAP:"
                lda #$20
                jsr $FFD2
                lda #$4D            // 'M'
                jsr $FFD2
                lda #$45            // 'E'
                jsr $FFD2
                lda #$4D            // 'M'
                jsr $FFD2
                lda #$4F            // 'O'
                jsr $FFD2
                lda #$52            // 'R'
                jsr $FFD2
                lda #$59            // 'Y'
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$4D            // 'M'
                jsr $FFD2
                lda #$41            // 'A'
                jsr $FFD2
                lda #$50            // 'P'
                jsr $FFD2
                lda #$3A            // ':'
                jsr $FFD2
                lda #$0D
                jsr $FFD2
                // 8 slots, 3 per line: " D4xx=SIDL  D4xx=SIDR  D5xx=SID3"
                lda #$20
                jsr $FFD2           // leading space for first row
                ldx #0
ape_map_loop:
                stx x_zp
                lda #$44            // 'D'
                jsr $FFD2
                ldx x_zp
                lda arm2sid_slot_d2,x
                jsr $FFD2           // 2nd hex char
                ldx x_zp
                txa
                and #$01            // even=00, odd=20
                beq ape_even
                lda #$32            // '2'
                jsr $FFD2
                lda #$30            // '0'
                jsr $FFD2
                jmp ape_eq
ape_even:       lda #$30            // '0'
                jsr $FFD2
                lda #$30            // '0'
                jsr $FFD2
ape_eq:         lda #$3D            // '='
                jsr $FFD2
                ldx x_zp
                jsr get_slot_map_val
                jsr print_map_name
                ldx x_zp
                inx
                stx x_zp
                cpx #8
                beq ape_map_cr_done
                txa
                cmp #3
                beq ape_map_nl
                cmp #6
                beq ape_map_nl
                lda #$20            // 2-space separator
                jsr $FFD2
                lda #$20
                jsr $FFD2
                ldx x_zp
                jmp ape_map_loop
ape_map_nl:     lda #$0D
                jsr $FFD2
                lda #$20            // leading space for next row
                jsr $FFD2
                ldx x_zp
                jmp ape_map_loop
ape_map_cr_done:
                lda #$0D
                jsr $FFD2
ape_done:       rts

//--------------------------------------------------------------------------------------------------
// skpico_print_extra: appended to SIDKick-pico info page (IP_SIDKPIC=12, called from sip_rc_done).
// If FM Sound Expander is enabled (config[8] >= 4 and < 6), prints FM status line.
// Trashes A.
//--------------------------------------------------------------------------------------------------
skpico_print_extra:
                lda #$0D
                jsr $FFD2               // CR after last line of ip_sidkpic
                lda skpico_fm
                cmp #$04
                bcs spe_check_max       // >= 4: check upper bound
                rts                     // < 4: no FM
spe_check_max:  cmp #$06
                bcc spe_print_fm        // 4 or 5: FM active (FM_ENABLE = 6 - config[8] > 0)
                rts                     // >= 6: FM_ENABLE=0, not active
spe_print_fm:
                // " FM SOUND EXPANDER AT $DF00"
                lda #$0D
                jsr $FFD2
                lda #$20                // ' '
                jsr $FFD2
                lda #$46                // 'F'
                jsr $FFD2
                lda #$4D                // 'M'
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$53                // 'S'
                jsr $FFD2
                lda #$4F                // 'O'
                jsr $FFD2
                lda #$55                // 'U'
                jsr $FFD2
                lda #$4E                // 'N'
                jsr $FFD2
                lda #$44                // 'D'
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$45                // 'E'
                jsr $FFD2
                lda #$58                // 'X'
                jsr $FFD2
                lda #$50                // 'P'
                jsr $FFD2
                lda #$41                // 'A'
                jsr $FFD2
                lda #$4E                // 'N'
                jsr $FFD2
                lda #$44                // 'D'
                jsr $FFD2
                lda #$45                // 'E'
                jsr $FFD2
                lda #$52                // 'R'
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$41                // 'A'
                jsr $FFD2
                lda #$54                // 'T'
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$24                // '$'
                jsr $FFD2
                lda #$44                // 'D'
                jsr $FFD2
                lda #$46                // 'F'
                jsr $FFD2
                lda #$30                // '0'
                jsr $FFD2
                lda #$30                // '0'
                jsr $FFD2
                lda #$0D
                jsr $FFD2
spe_done:       rts

//--------------------------------------------------------------------------------------------------
// fpgasid_print_extra: appended to FPGASID info pages (IP_FPGA8580=6, IP_FPGA6581=7).
// Prints CPLD and FPGA revision on a new line.
// Trashes A, $FE/$FF.
//--------------------------------------------------------------------------------------------------
fpgasid_print_extra:
                lda #$0D
                jsr $FFD2
                // " CPLD:XX  FPGA:XX"
                lda #$20
                jsr $FFD2
                lda #$43            // 'C'
                jsr $FFD2
                lda #$50            // 'P'
                jsr $FFD2
                lda #$4C            // 'L'
                jsr $FFD2
                lda #$44            // 'D'
                jsr $FFD2
                lda #$3A            // ':'
                jsr $FFD2
                lda fpgasid_cpld_rev
                jsr print_hex
                lda #$20
                jsr $FFD2
                lda #$20
                jsr $FFD2
                lda #$46            // 'F'
                jsr $FFD2
                lda #$50            // 'P'
                jsr $FFD2
                lda #$47            // 'G'
                jsr $FFD2
                lda #$41            // 'A'
                jsr $FFD2
                lda #$3A            // ':'
                jsr $FFD2
                lda fpgasid_fpga_rev
                jsr print_hex
                lda #$0D
                jsr $FFD2
                rts

//--------------------------------------------------------------------------------------------------
// siddetectstart


//**************************************************************************
loop1sek:
                stx  x_zp            // $ad
                sty  y_zp            // $ad
                pha
                ldx #$FF
loop1sekx:       dex       // x--
                nop
                nop
                nop
                nop
                bne loop1sekx // gentag for at blive klar.
                ldx     x_zp            // $ad 
                ldy     y_zp            // $ad 
                pla
                rts
                
//**************************************************************************
//* NAME  print_hex
print_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     ph_skp1
        pla
        and     #$0f
ph_skp1:
        cmp     #$0a
        bcc     ph_skp2
// C = 1
//        adc     #'A'-$0a-"0"-1
        adc     #6
ph_skp2:
// C = 0
        adc     #'0'
        jmp     $ffd2
       rts
//----------------------------------------------------------------------------------------
//http://www.baltissen.org/newhtm/d700.htm
//https://csdb.dk/forums/?roomid=14&topicid=99181&showallposts=1
//you know the VIC-II video chip occupies the $D000/D3FF area in both the C64 and C128. 
//But while the SID sound occupies $D400/D7FF in the C64, in the C128 it only occupies the area $D400/D4FF. 
//$D5xx is occupied by the MMU, $D6xx by the VDC, the second video chip and $D7xx is free. 
//This free $D7xx area is often used for installing a second SID sound chip in the C128. 
//Something where quite some C64 owners were jealous of
// write $00 to $D030 and then read it back, AFAIK you'll then always get $FF on C64 and $FC on C128.
// If $D030 != $FF (could be C128, TC64, or C64+FC3 false positive), use $D0FE as final
// arbiter: $FF=C64, $FC=C128, other=TC64. FC3 cartridge drives $D030 but not $D0FE, so
// the $D0FE open-bus read ($FF) correctly overrides the false C128/TC64 detect.

check128:
      lda #$00
      sta $D030
      lda $d030
      cmp #$FF
      beq check128_c64        // open bus -> definitely C64
      // D030 != $FF: C128, TC64, or C64+FC3.
      // $D0FE arbitrates: $FF=C64, $FC=C128, other=TC64.
      lda $D0FE               // stabilisation read
      lda #$2A
      sta $D0FE
      lda $D0FE
      sta za7
      jmp check128_end
check128_c64:
      sta za7                 // A = $FF
check128_end:
      rts
//--------------------------------
// new swinsidMicrocheck ; 8580=01, 6581=01, ARM=0, SwinsidNano=99 NOSID=99
//--------------------------------
checkswinmicro:
    ldx #$1F //00
    lda #$00
checkswinloop1:
    sta $D400,X
    dex
    bne checkswinloop1
    lda #$00
    sta $D413 // AD
    lda #$F0
    sta $D414 // SR
    lda #$41  // gate bit set, noise set
    sta $D412 // control register
    sta $D40e // Voice 3 Frequency Control (low byte)
    sta $D40f // Voice 3 Frequency Control (high byte)
    lda $D41c //
    cmp #$01
    beq checkswinloop2
    // found micro sid
    stx $d412
    lda #$08
    sta data1
    sta data2
    jmp checkswinend
checkswinloop2:
    lda #$f0
    sta data1
    sta data2
checkswinend:
    rts


//======================
//COLOUR WASHING ROUTINE
//======================
COLWASH:              lda COLOUR+$00 
                     sta COLOUR+$28 
                     ldx #$00 
CYCLE:                lda COLOUR+$01,X 
                     sta COLOUR+$00,X 
                     lda COLOUR,X 
                     sta $D800,X // last line
                     inx 
                     cpx #$28 
                     bne CYCLE 
                     rts

//**************************************************************************
// Funny sid check Decay
//-------------------------------------------------------------------------------
calcandloop:
    ldx NumberInts// set til NumberInts
calcand_bigloop:
    stx ZPbigloop       // save loop counter
    txs                 // save X on stack
    jsr calc_start      // spinner updates once inside calc_start, before sei
    tsx                 // restore X from stack
    dex
    bne calcand_bigloop // or directly: beq frodo
    // calc
    ldx #1
calcand_calcloop:    
    stx ZPArrayPtr
    txs         // flyt a til stack
    jsr ArithmeticMean//
    tsx         // hent a fra stack
    inx 
    cpx #4
    bne calcand_calcloop
    jmp funny_print
    rts  

//----------------
// start test
    
calc_start:
    lda #0
    sta $07E8  // counter lo  — off-screen RAM ($07E8-$07EA is beyond 40×25 = $07E7)
    sta $07E9  // counter mid   same 6-cycle ABS INC as original → calibration preserved
    sta $07EA  // counter hi
    sei
    lda #$1f
    sta $d418 // gem 31 i $d418
calc_loop:
    inc $07E8  // counter lo (6 cycles, absolute — same timing as original inc $0400)
    bne calc_nohi
    inc $07E9  // counter mid; lo-byte just wrapped
    bne calc_spincheck  // if mid didn't wrap, check spinner
    inc $07EA           // both lo and mid wrapped: increment hi byte
    lda $07EA
    cmp #$02
    beq calc_check
calc_spincheck:
    // update spinner every 16th lo-byte wrap (~10 updates per measurement)
    // A, Y free inside sei section; adds ~15 cycles only on 1-in-16 wraps
    lda $07E9
    and #$0F            // fire when $07E9 is a multiple of 16
    bne calc_nohi
    lda tmp_zp
    and #$07
    tay
    lda decay_spinner,y
    sta $0658
    inc tmp_zp
calc_nohi:
    lda $d418 // læs d418
    bne calc_loop
calc_check:
    lda $07E8
    sta data1 // gem d400
    ldx ZPbigloop
    dex
    sta ArrayPtr1,x
    lda $07E9
    sta data2 // gem d401
    ldx ZPbigloop
    dex
    sta ArrayPtr2,x
    lda $07EA
    sta data3 // gem 0402
    ldx ZPbigloop
    dex
    sta ArrayPtr3,x
    rts
    
//---------------------------------------------------------------------    
// new check
//---------------------------------------------------------------------    
checktypeandprint:

//    lda #<slabel 
//    ldy #>slabel 
//    jsr $AB1E
        
    lda data3 // 
    cmp #$02  // hvis 2
    bne nc_Swinsidn
    jmp nc_unknown
    
// 01-02 00 00| Swinsid Nano                   | done
nc_Swinsidn:
    lda data1
    cmp #$01
    bcc nc_ULTIsid     // hvis data1 < cmp gå til nc_FastSid
    cmp #$03
    bcs nc_ULTIsid     // hvis data1 >= cmp gå til nc_FastSid
    lda data2
    bne nc_ULTIsid
    // found         
    lda #<sunknown 
    ldy #>sunknown 
    jsr $AB1E
    jmp exit
// DA-F1 00 00| ULTIsid                        |    
nc_ULTIsid:    
    lda data1
    cmp #$DA
    bcc nc_hoxs     // hvis data1 < cmp gå til nc_FastSid
    cmp #$F2
    bcs nc_hoxs     // hvis data1 >= cmp gå til nc_FastSid
    lda data2
    bne nc_hoxs
    // found         
    lda #<sULTIsid 
    ldy #>sULTIsid 
    jsr $AB1E
    jmp exit 
 // 00 19-19 00| Hoxs                           |
nc_hoxs:
    lda data2
    cmp #$19
    bne nc_Residfp6581d    
    lda data3
    bne nc_Residfp6581d
    // found         
    lda #<shoxs 
    ldy #>shoxs 
    jsr $AB1E
    jmp exit 

// 00 07-07 00| C64 Deb Vice 3.1 RESID-FP 6581 |
nc_Residfp6581d:
    lda data2
    cmp #$07
    bne nc_Fast6581d     // hvis data1 >= cmp gå til nc_FastSid
    lda data3
    bne nc_Fast6581d
    // found         
    lda #<sResidfp6581d 
    ldy #>sResidfp6581d 
    jsr $AB1E
    jmp exit 

// 05-05 00 00| C64 Deb Vice 3.1 fastSID 6581  |
nc_Fast6581d:
    lda data1
    cmp #$05
    bne nc_Resid6581d     // hvis data1 >= cmp gå til nc_FastSid
    lda data2
    bne nc_Resid6581d
    // found         
    lda #<sFast6581d 
    ldy #>sFast6581d 
    jsr $AB1E
    jmp exit 
// 00 03-03 00| C64 Deb Vice 3.1 RESID 6581    |
nc_Resid6581d:
    lda data2
    cmp #$03
    bne nc_Swinsidu     // hvis data1 >= cmp gå til nc_FastSid
    lda data3
    bne nc_Swinsidu
    // found         
    lda #<sResid6581d 
    ldy #>sResid6581d 
    jsr $AB1E
    jmp exit 
    
// 00 16-18 00| Swinsid Ultimate               | done
nc_Swinsidu:
    lda data2
    cmp #$16
    bcc nc_FPGAsid     // hvis data1 < cmp gå til nc_FastSid
    cmp #$19
    bcs nc_FPGAsid     // hvis data1 >= cmp gå til nc_FastSid
    lda data3
    bne nc_FPGAsid
    // found         
    lda #<sSwinsidU 
    ldy #>sSwinsidU 
    jsr $AB1E
    jmp exit 
// 00 05-06 00| FPGAsid
nc_FPGAsid:
    lda data2
    cmp #$05
    bcc nc_Resid8580     // hvis data1 < $B4 gå til nc_FastSid
    cmp #$07
    bcs nc_Resid8580     // hvis data1 >= $B9 gå til nc_FastSid
    lda data3
    bne nc_Resid8580
    // found         
    lda #<sFPGAsid 
    ldy #>sFPGAsid 
    jsr $AB1E
    jmp exit 
// 00 98-98 00| Vice 3.3 RESID fast/ 8580
nc_Resid8580: 
    lda data2
    cmp #$98
    bne nc_Resid6581
    lda data3
    bne nc_Resid6581
    lda #<sResid8580 
    ldy #>sResid8580
    jsr $AB1E 
    jmp exit 
// 00 01-01 00| Vice 3.3 RESID fast/ 6581
nc_Resid6581: 
    lda data2
    cmp #$01
    bne nc_FastSid     // hvis data1 < $B4 gå til nc_FastSid
    lda data3
    bne nc_FastSid
    // found         
    lda #<sResid6581 
    ldy #>sResid6581 
    jsr $AB1E 
    jmp exit 
// 02-05 00 00| Vice 3.3 FastSID 
nc_FastSid:   
    lda data1
    cmp #$02
    bcc nc_nextsid     // hvis data1 < $B4 gå til nc_FastSid
    cmp #$05
    bcs nc_nextsid     // hvis data1 >= $B9 gå til nc_FastSid
    lda data2
    bne nc_nextsid
    // found         
    lda #<sFastSid 
    ldy #>sFastSid 
    jsr $AB1E
    jmp exit 
nc_nextsid:   
    jmp exit 

nc_unknown:
    lda #<sunknown
    ldy #>sunknown
    jsr $AB1E
    lda data1
    jsr $FFD2
    lda data2
    jsr $FFD2
    lda data3
    jsr $FFD2


exit:    
//   lda #13
//   jsr $FFD2
//   lda data1
//   jsr PRBYTE
//   lda data2
//   jsr PRBYTE
//   lda data3
//   jsr PRBYTE
//   jsr $FF81 //Blue border+blue screen clear
//   jmp $E37B // jump to basic
   rts 
    
//-----------------------------------------------------------------------------------
// Calc average of max 255 8 bit values.
ArithmeticMean:
      pha
      tya
      pha   //push accumulator and Y register onto stack
 
 
      lda #0
      sta Temp
      sta Temp+1  //temporary 16-bit storage for total
 
      ldy NumberInts  
      beq Done  //if NumberInts = 0 then return an average of zero
 
      dey   //start with NumberInts-1
AddLoop: 
      lda ZPArrayPtr// hent 1,2,3
      cmp #1 
      beq ArrayPtr1l
      cmp #2 
      beq ArrayPtr2l
      cmp #3 
      beq ArrayPtr3l
      // not needed
      lda ArrayPtr2,Y // 
      jmp CLCloop
ArrayPtr1l:
      lda ArrayPtr1,Y // 
      jmp CLCloop
ArrayPtr2l:
      lda ArrayPtr2,Y // 
      jmp CLCloop
ArrayPtr3l:
      lda ArrayPtr3,Y // 
CLCloop:
      clc
      adc Temp
      sta Temp
      lda Temp+1
      adc #0
      sta Temp+1
      dey
      cpy #255
      bne AddLoop
 
      ldy #-1
DivideLoop:   
      lda Temp
      sec
      sbc NumberInts
      sta Temp
      lda Temp+1
      sbc #0
      sta Temp+1
      iny
      bcs DivideLoop
 
Done: 
      sty ArithMean //store result here
      pla   //restore accumulator and Y register from stack
      tay
      pla
      rts   //return from routine

       
//-------------------------------------------------------------------------
//
//-------------------------------------------------------------------------
// DATA    
//-------------------------------------------------------------------------

swinsidUf:      .text "SWINSID ULTIMATE FOUND" // data1=$04 data2=$04
                .byte 0  
armsidf:        .text "ARMSID FOUND" // data1=$05 data2=$4f
                .byte 0              
nosoundf:       .text "NOSID FOUND" // data1=$f0 data2=$f0
                .byte 0               
fpgasidf_8580u: .text "FPGASID 8580 FOUND" // data1=$06 data2=$3f
                .byte 0      
fpgasidf_6581u: .text "FPGASID 6581 FOUND" // data1=$07 data2=$00
                .byte 0      
l6581f:         .text "6581 FOUND" // data1=$02 data2=$02
                .byte 0             
l8580f:         .text "8580 FOUND" // data1=$01 data2=$01
                .byte 0               
swinsidnanof:   .text "SWINSID NANO FOUND" // data1=$08 data2=$08
                .byte 0        
unknownsid:      .text "UNKNOWN SID FOUND" // data1=$09 data2=$09
                .byte 0        
secondsid:      .text "ANOTHER SID FOUND" // data1=$10 data2=$10
                .byte 0        
// UltiSID filter curve strings: indexed by UCI type byte 0-6 ($20-$26 in sid_list_t)
ultisidf_fc0:   .text "ULTISID 8580 LO"; .byte 0  // UCI type 0
ultisidf_fc1:   .text "ULTISID 8580 HI"; .byte 0  // UCI type 1
ultisidf_fc2:   .text "ULTISID 6581";    .byte 0  // UCI type 2
ultisidf_fc3:   .text "ULTISID 6581 ALT";.byte 0  // UCI type 3
ultisidf_fc4:   .text "ULTISID U2 LO";   .byte 0  // UCI type 4
ultisidf_fc5:   .text "ULTISID U2 MID";  .byte 0  // UCI type 5
ultisidf_fc6:   .text "ULTISID U2 HI";   .byte 0  // UCI type 6
// Pointer tables for indexed lookup ($20-$26 → index × 2)
ultisid_str_lo: .byte <ultisidf_fc0, <ultisidf_fc1, <ultisidf_fc2, <ultisidf_fc3
                .byte <ultisidf_fc4, <ultisidf_fc5, <ultisidf_fc6
ultisid_str_hi: .byte >ultisidf_fc0, >ultisidf_fc1, >ultisidf_fc2, >ultisidf_fc3
                .byte >ultisidf_fc4, >ultisidf_fc5, >ultisidf_fc6      
sidfxu:         .text "SIDFX FOUND" // data1=$30 data2=$30
                .byte 0             
nosidfxu:       .text "NOSIDFX FOUND" // data1=$31 data2=$31
                .byte 0             
pal_text:       .text "PAL-MACHINE FOUND" 
                .byte 0,0
ntsc_text:      .text "NTSC-MACHINE FOUND" 
                .byte 0,0
c64_text:       .text " C64"
                .byte 0,0
c128_text:      .text " C128"
                .byte 0,0
tc64_text:      .text " TC64"
                .byte 0,0
arm2sidf:       .text "ARM2SID FOUND"
                .byte 0
arm2sid_sfxf:   .text "ARM2SID +SFX "   // same width as "ARM2SID FOUND" — used when emul_mode>=1
                .byte 0
pdsidf:         .text "PD SID FOUND"
                .byte 0
backsidf:       .text "BACKSID FOUND"
                .byte 0
skpicof:        .text "SIDKICK-PICO 8580"
                .byte 0
skpicof_6581:   .text "SIDKICK-PICO 6581"
                .byte 0
kungfusidf:     .text "KUNGFUSID FOUND"
                .byte 0
usid64f:        .text "USID64 FOUND"  // data1=$0D
                .byte 0
sidFXf:         .text "SIDFX FOUND"   // data1=$30
                .byte 0
swinsidmicrof:  .text "SWINSID MICRO FOUND"
                .byte 0



data1_old:           .byte 10
                .byte 0
data2_old:           .byte 10
                .byte 0
armsid_major:        .byte 0     // firmware major version (2=ARMSID, 3=ARM2SID, 0=unknown)
armsid_minor:        .byte 0     // firmware minor version (0-99 raw)
armsid_cfgtest:      .byte 0     // D41B read right after config open (should be $4E='N' if working)
armsid_no_c:         .byte 0     // D41C after config entry (expect $4F='O')
armsid_ei_b:         .byte 0     // D41B after 'ei' cmd (expect $53='S')
armsid_ei_c:         .byte 0     // D41C after 'ei' cmd (expect $57='W')
armsid_ii_b:         .byte 0     // D41B after 'ii' cmd (02=ARM2SID, other=ARMSID)
armsid_ii_c:         .byte 0     // D41C after 'ii' cmd ('L'=$4C or 'R'=$52 for ARM2SID)
armsid_sid_type_h:   .byte 0     // D41B after 'fi' cmd ('6'=6581, '8'=8580 emulated)
armsid_auto_sid:     .byte 0     // D41B after 'gi' cmd ('7'=$37 = auto-detected)
armsid_emul_mode:    .byte 0     // D41B after 'mm' cmd (bits 1:0: 0=SID,1=SFX,2=SFX+SID; ARM2SID)
armsid_map_l:        .byte 0     // D41B after 'lm' (slots 0+1 nibble-packed; ARM2SID only)
armsid_map_l2:       .byte 0     // D41C after 'lm' (slots 2+3 nibble-packed; ARM2SID only)
armsid_map_h:        .byte 0     // D41B after 'hm' (slots 4+5 nibble-packed; ARM2SID only)
armsid_map_h2:       .byte 0     // D41C after 'hm' (slots 6+7 nibble-packed; ARM2SID only)
is_u64:              .byte 0     // 1 = running on Ultimate64 (UCI $DF1F != $FF)
fpgasid_sid2_type:   .byte 0     // SID2 type from $82 magic: $3F=8580, $00=6581
fpgasid_cpld_rev:    .byte 0     // CPLD revision (D419 after $81/$65 cookie, D41E=0)
fpgasid_fpga_rev:    .byte 0     // FPGA revision (D41A after $81/$65 cookie, D41E=0)
// ARM2SID lookup tables
arm2sid_mapnames:    .text "----SIDLSIDRSFX-SID3"  // 5 × 4 chars, indexed by map value 0-4
arm2sid_slot_d2:     .byte $34,$34,$35,$35,$45,$45,$46,$46  // 2nd hex digit: '4','4','5','5','E','E','F','F'
arm2sid_shortf:      .text "ARM2SID "
                     .byte 0                         // prefix for stereo SID entries
backsid_d41f:        .byte 0     // D41F readback from checkbacksid ($42 = BackSID present)
skpico_fm:           .byte 0     // config[8] from checkskpico Phase 3: >=4 and <6 → FM at $DF00
MODE6581:     .byte $f0,$f1,$f0,$f0,$f2,$f1,$f2,$f2,$f0,$f1,$f0,$f0,$f0,$f1,$f0,$f0
MODE8580:     .byte $f0,$f0,$f1,$f0,$f0,$f0,$f1,$f0,$f2,$f2,$f1,$f2,$f0,$f0,$f1,$f0
MODEUNKN:     .byte $f0,$f0,$f0,$f0,$f0,$f0,$f0,$f2,$f0,$f0,$f0,$f2,$f0,$f1,$f1,$f0



    //D41E bits 3-0 (SID model) -> D41D bits 2-0 (playback mode)
    //
    //MODELS SID1  SID2  6581  8580
    //
    //0000 NONE  NONE  0 0
    //0001 6581  NONE  1 0 <-- 01
    //0010 8580  NONE  0 1
    //0011 UNKN  NONE  0 0 <-- 03
    //0100 NONE  6581  2 0
    //0101 6581  6581  1 0
    //0110 8580  6581  2 1
    //0111 UNKN  6581  2 0 <-- 07
    //1000 NONE  8580  0 2
    //1001 6581  8580  1 2
    //1010 8580  8580  0 1
    //1011 UNKN  8580  0 2
    //1100 NONE  UNKN  0 0
    //1101 6581  UNKN  1 0
    //1110 8580  UNKN  0 1
    //1111 UNKN  UNKN  0 0
    //
    //Example tables, default mode (0) is selected when requested SID type is not available (recommended)

PNP:    .byte 4,0,0,0,0

screen:
         //0123456789012345678901234567890123456789
    .encoding "screencode_upper"
    .text "SIDDETECTOR V1.3.86 FUNFUN/TRIANGLE 3532" //0  (compact title)
    .text "                                        " //1
    .text "ARMSID.....:                            " //2  (was row 4)
    .text "SWINSID....:                            " //3  (was row 5)
    .text "FPGASID....:                            " //4  (was row 6)
    .text "6581 SID...:                            " //5  (was row 7)
    .text "8580 SID...:                            " //6  (was row 8)
    .text "SIDKICK....:                            " //7
    .text "BACKSID....:                            " //8
    .text "KUNGFUSID..:                            " //9
    .text "PD SID.....:                            " //10
    .text "NOSID......:                            " //11
    .text "SIDFX......:                            " //12
    .text "PAL/NTSC...:                            " //13
    .text "USID64.....:                            " //14
    .text "$D418 DECAY:                            " //15
    .text "STEREO SID.:                            " //16 (was row 18)
    .text "                                        " //17
    .text "                                        " //18
    .text "                                        " //19
    .text "                                        " //20
    .text "                                        " //21
    .text "                                        " //22
    .text "                                        " //23
    .text "I=INFO R=README T=SOUND Q=QUIT SPACE=GO " //24
    .encoding "ascii"

//DATA TABLES FOR COLOURS

COLOUR:       .byte $09,$09,$02,$02,$08 
             .byte $08,$0A,$0A,$0F,$0F 
             .byte $07,$07,$01,$01,$01 
             .byte $01,$01,$01,$01,$01 
             .byte $01,$01,$01,$01,$01 
             .byte $01,$01,$01,$07,$07 
             .byte $0F,$0F,$0A,$0A,$08 
             .byte $08,$02,$02,$09,$09 
             .byte $00,$00,$00,$00,$00    
// ─────────────────────────────────────────────────────────────────────────────
// check_uci_ultisid
// Query UCI CTRL_CMD_GET_HWINFO(device=1) for EMUSID1/EMUSID2 addresses.
// Verifies each via Check 2 (noise test), adds confirmed UltiSIDs to sid_list.
// Called after fiktivloop_d400 when ARM2SID primary on U64 (is_u64 != 0).
// ─────────────────────────────────────────────────────────────────────────────
check_uci_ultisid:
       lda #$04
       sta $DF1D              // target ID = ControlTarget (4)
       lda #$28
       sta $DF1D              // CTRL_CMD_GET_HWINFO
       lda #$01
       sta $DF1D              // device = 1 (SID config)
       lda #$01
       sta $DF1C              // PUSH_CMD
       // Poll DATA_AV (bit 0) or STAT_AV (bit 1) of $DF1C; 64K timeout
       ldx #$00
       ldy #$00
cui_poll:
       lda $DF1C
       and #$03               // DATA_AV | STAT_AV
       bne cui_got_resp
       dex
       bne cui_poll
       dey
       bne cui_poll
       rts                    // timeout – UCI not responding
cui_got_resp:
       sta uci_resp+10        // save $DF1C flags for debug (bit0=DATA_AV, bit1=STAT_AV)
       and #$01               // DATA_AV set?
       beq cui_stat_only      // no – error status only, no data bytes
       // DATA_AV: blast-read 9 bytes from $DF1E.
       // Format: [0]=count [1..4]=EMUSID1(lo,hi,type,flags) [5..8]=EMUSID2(lo,hi,type,flags)
       ldx #$00
cui_read:
       lda $DF1E              // read byte from response FIFO (open-bus=$FF if empty)
       sta uci_resp,x
       inx
       cpx #$09               // read 9 bytes (0..8; resp[10] = $DF1C flags)
       bne cui_read
cui_done_read:
       lda $DF1F              // consume status byte
       sta uci_resp+9         // save status at [9]
       lda #$02
       sta $DF1C              // DATA_ACC – acknowledge
       jmp cui_process
cui_stat_only:
       // STAT_AV only: error response – save status code in uci_resp+9 for debug
       lda $DF1F
       sta uci_resp+9
       lda #$02
       sta $DF1C              // DATA_ACC – acknowledge
       rts
cui_process:
       // Process EMUSID1: resp[1]=addr_lo, resp[2]=addr_hi, resp[3]=type, resp[4]=flags
       lda uci_resp+2         // EMUSID1 high byte
       beq cui_emusid2        // $00 = invalid
       cmp #$D5
       bcc cui_emusid2        // < $D5: not a valid secondary SID page
       lda uci_resp+1
       sta mptr_zp
       lda uci_resp+2
       sta mptr_zp+1
       jsr uci_c2_add         // uci_c2_add calls uci_type_for_addr internally
cui_emusid2:
       // Process EMUSID2: resp[5]=addr_lo, resp[6]=addr_hi, resp[7]=type, resp[8]=flags
       // (status is now at resp[9], no longer overwrites resp[6])
       lda uci_resp+0
       cmp #$02
       bcc cui_rts            // count < 2 – no EMUSID2
       lda uci_resp+6         // EMUSID2 high byte (now correct: not overwritten by status)
       cmp #$D5
       bcc cui_rts            // < $D5: not a valid secondary SID page
       lda uci_resp+5
       sta mptr_zp
       lda uci_resp+6
       sta mptr_zp+1
       jsr uci_c2_add
cui_rts:
       rts

// ─────────────────────────────────────────────────────────────────────────────
// uci_c2_add  –  Check 2 on mptr_zp/mptr_zp+1, add to sid_list as ULTISID.
// Skips if address already present (dedup) or list full (>= 8 entries).
// ─────────────────────────────────────────────────────────────────────────────
uci_c2_add:
       // Patch self-mod addresses: ctrl/silence = mptr+$12, read = mptr+$1B, freq = mptr+$0F
       lda mptr_zp
       clc
       adc #$0F
       sta uca_freq+1
       sta uca_sil1f+1
       sta uca_sil2f+1
       lda mptr_zp+1
       sta uca_freq+2
       sta uca_sil1f+2
       sta uca_sil2f+2
       lda mptr_zp
       clc
       adc #$12
       sta uca_ctrl+1
       sta uca_sil1+1
       sta uca_sil2+1
       lda mptr_zp+1
       sta uca_ctrl+2
       sta uca_sil1+2
       sta uca_sil2+2
       lda mptr_zp
       clc
       adc #$1B
       sta uca_read+1
       lda mptr_zp+1
       sta uca_read+2
       // Dedup: skip if address already in sid_list
       lda sidnum_zp
       beq uca_go
       tax
uca_dup:
       lda sid_list_h,x
       cmp mptr_zp+1
       bne uca_dup_nx
       lda sid_list_l,x
       cmp mptr_zp
       beq uca_rts            // already present
uca_dup_nx:
       dex
       bne uca_dup
uca_go:
       lda #$FF
uca_freq: sta $D40F           // self-mod → mptr+$0F (freq hi)
       lda #$21
uca_ctrl: sta $D412           // self-mod → mptr+$12 (sawtooth+gate; noise LFSR stuck at $000000 on 6581 cold boot)
       ldx #32
uca_lp:
uca_read: lda $D41B           // self-mod → mptr+$1B
       beq uca_next           // $00: no noise yet
       cmp #$FF
       bne uca_found          // non-$00, non-$FF: real SID noise → found
uca_next:                     // $FF = open bus (U64 returns $FF for idle/unconfigured)
       dex
       bne uca_lp
       // All zeros or all $FF: not a real SID – silence and return
       lda #$00
uca_sil1: sta $D412           // self-mod → mptr+$12
uca_sil1f: sta $D40F          // self-mod → mptr+$0F (silence freq)
uca_rts:
       rts
uca_found:
       lda #$00
uca_sil2: sta $D412           // self-mod → mptr+$12
uca_sil2f: sta $D40F          // self-mod → mptr+$0F (silence freq)
       lda sidnum_zp
       cmp #$07
       bcs uca_rts            // list full (slots 1-7 only; slot 0 unused/sentinel)
       inc sidnum_zp
       ldx sidnum_zp
       lda mptr_zp
       sta sid_list_l,x
       lda mptr_zp+1
       sta sid_list_h,x
       // Determine 6581 vs 8580 from U64 UCI filter curve config.
       // uci_type_for_addr queries UCI GET_HWINFO, looks up mptr_zp in the
       // EMUSID entries, and returns $21 (6581) or $20 (8580).
       stx x_zp               // save slot index (uci_type_for_addr trashes X)
       jsr uci_type_for_addr  // A = $21 (ULTISID-6581) or $20 (ULTISID-8580)
       ldx x_zp               // restore slot index
       sta sid_list_t,x
       rts

* = $6000
num_sids:
        .byte    $0,$9,$9,$9,$9,$9,$9,$9
sid_list_l:
        .byte    $0,$0,$0,$0,$0,$0,$0,$0
sid_list_h:
        .byte    $0,$0,$0,$0,$0,$0,$0,$0
sid_list_t:
        .byte    $0,$0,$0,$0,$0,$0,$0,$0

uci_resp:           // 23-byte buffer (GET_HWINFO $04/$28/$01 response, 5 bytes per frame):
                    // [0]=count  [1..5]=F1(lo,hi,sec_hi,sec_lo,type)  [6..10]=F2  [11..15]=F3  [16..20]=F4
                    // [21]=trailing byte from FIFO (the $30 that was causing "Data More")  [22]=status
        .byte    $0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0

sid_map:
        .byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  // D400, D500
        .byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  // D600, D700
        .byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  // 
        .byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  // 
        .byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  // 
        .byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  // DE00, DF00

// data

stringtable:
shoxs:         .text "HOXS64" 
                .byte 0
sreal6581:     .text "REAL 6581" 
                .byte 0
snosound:      .text "NO SOUND" 
                .byte 0
sfrodo:        .text "FRODO" 
                .byte 0
sreal8580:     .text "REAL 8580" 
                .byte 0
sSwinsidn:     .text "SWINSID NANO" 
                .byte 0
sARMSID:       .text "ARMSID" 
                .byte 0 
sSwinsidU:     .text "SWINSID ULTIMATE" 
                .byte 0 
s6581R3:       .text "6581 R3 2084" 
                .byte 0
s6581R4AR:     .text "6581 R4AR 5286" 
                .byte 0
s6581R4:       .text "6581 R4 1886" 
                .byte 0
s6581R2:       .text "6581 R2 5182" 
                .byte 0
sFPGAsid:      .text "FPGASID" 
                .byte 0
sResid8580:    .text "VICE3.3 RESID FS 8580"
                .byte 0
sResid6581:    .text "VICE3.3 RESID FS 6581"
                .byte 0
sFastSid:      .text "VICE3.3 FASTSID"
                .byte 0
sResid6581d:   .text "C64DBG RESID 6581/8580"
                .byte 0
sFast6581d:    .text "C64DBG FASTSID 6581/8580"
                .byte 0
sResidfp6581d: .text "C64DBG RESIDFP 6581/8580"
                .byte 0
sYACE64:       .text "YACE64" 
                .byte 0
semu64:        .text "EMU64" 
                .byte 0
sULTIsid:      .text "ULTISID" 
                .byte 0
sULTIsidno:    .text "U64 NOSID at $D400" 
                .byte 0
sunknown:      .text "UNKNOWNSID" 
                .byte 0
slabel:        .text "$D418 DECAY:" 
                .byte 0
sblank:        .text "     " 
                .byte 0

         
      
Temp:       .byte $00,$00
NumberInts:  .byte $06 // 6 loops
// 8-frame spinner: * + / - * + / - ('+' substitutes for | and \; C64 has no pipe/backslash)
decay_spinner: .byte $2A,$2B,$2F,$2D,$2A,$2B,$2F,$2D
ArithMean:  .byte $00,$00
ArrayPtr:   .byte $00 
ArrayPtr1:   .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
ArrayPtr2:   .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
ArrayPtr3:   .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

data4:       .byte 0,0
sidfx_d41d:  .byte 0     // D41D captured during DETECTSIDFX (SW2/SW1/SCAP/PLY)
sidfx_d41e:  .byte 0     // D41E captured during DETECTSIDFX (SID2/SID1 types)
// SIDFX secondary SID address tables (indexed by SW1: 0=CTR 1=LFT 2=RGT)
sidfx_sec_hi: .byte $D5, $D4, $DE   // CTR→D500  LFT→D420  RGT→DE00
sidfx_sec_lo: .byte $00, $20, $00

// ============================================================
// INFO PAGE POINTER TABLE (17 pages, indices 0-16)
// Each entry is the lo/hi address of the page text.
// Page 0=NOSID  1=6581  2=8580  3=ARMSID  4=SWINU  5=SWINANO
//       6=FPGA8580  7=FPGA6581  8=SIDFX  9=ULTI
//      10=VICE  11=HOXS  12=SIDKPIC  13=PUBDOM  14=BACKSID
//      15=KUNGFUSID  16=UNKNOWN  17=USID64
// ============================================================
info_page_lo:
    .byte <ip_nosid,    <ip_6581,    <ip_8580,     <ip_armsid
    .byte <ip_swinu,    <ip_swinano, <ip_fpga8580,  <ip_fpga6581
    .byte <ip_sidfx,    <ip_ulti,    <ip_vice,     <ip_hoxs
    .byte <ip_sidkpic,  <ip_pubdom,  <ip_backsid,  <ip_kungfusid
    .byte <ip_unknown,  <ip_usid64

info_page_hi:
    .byte >ip_nosid,    >ip_6581,    >ip_8580,     >ip_armsid
    .byte >ip_swinu,    >ip_swinano, >ip_fpga8580,  >ip_fpga6581
    .byte >ip_sidfx,    >ip_ulti,    >ip_vice,     >ip_hoxs
    .byte >ip_sidkpic,  >ip_pubdom,  >ip_backsid,  >ip_kungfusid
    .byte >ip_unknown,  >ip_usid64

// Navigation hint shown at row 24 of all info pages
info_nav_hint:
    .text "W=UP S=DN  B=PREV  M=NEXT  SPACE=BACK "
    .byte 0

// ============================================================
// Debug page string labels
// ============================================================
dbg_s_title:
    .text "    SID DETECTOR - DEBUG INFO   V1.3.86"
    .byte 13, 13, 0
dbg_s_machine:
    .text "MCH:"
    .byte 0
dbg_s_pal:
    .text " PAL:"
    .byte 0
dbg_s_numsids:
    .text " SID:"
    .byte 0
dbg_s_data1:
    .text "D1:"
    .byte 0
dbg_s_data2:
    .text " D2:"
    .byte 0
dbg_s_data3:
    .text " D3:"
    .byte 0
dbg_s_data4:
    .text " D4:"
    .byte 0
dbg_s_armver:
    .text "ARMVER:"
    .byte 0
dbg_s_cfg:
    .text "CFG:"
    .byte 0
dbg_s_arm_ei:
    .text " EI:"
    .byte 0
dbg_s_arm_ii:
    .text " II:"
    .byte 0
dbg_s_fpga_c:
    .text "FPGA:C="
    .byte 0
dbg_s_fpga_f:
    .text " F="
    .byte 0
dbg_s_fpga_t2:
    .text " T2:"
    .byte 0
// SIDFX debug strings  (D41D: SW2=bits7:6, SW1=bits5:4, PLY=bits2:0; D41E: SID2=bits3:2, SID1=bits1:0)
// SW position: 00=Center 01=Left 10=Right 11=Reserved   Playback: 000=auto 001=SID1 010=SID2 011=both
// SID type: 00=NONE 01=6581 02=8580 03=UNKN
dbg_s_sidfx:
    .text "SIDFX SW2:"
    .byte 0
dbg_s_sidfx_sw1:
    .text " SW1:"
    .byte 0
dbg_s_sidfx_ply:
    .text " PLY:"
    .byte 0
dbg_s_sidfx_s1:
    .text "SID1:"
    .byte 0
dbg_s_sidfx_s2:
    .text " SID2:"
    .byte 0
dbg_s_sidfx_adr:
    .text "ADR:"
    .byte 0
dbg_s_adr_lft:
    .text "D400/D420"
    .byte 0
dbg_s_adr_ctr:
    .text " D400/D500"
    .byte 0
dbg_s_adr_rgt:
    .text " D400/DE00"
    .byte 0
// PLY mode labels: 0=AUTO 1=SID1 2=SID2 3=BOTH
dbg_ply_str0:   .text "AUTO"
                .byte 0
dbg_ply_str1:   .text "SID1"
                .byte 0
dbg_ply_str2:   .text "SID2"
                .byte 0
dbg_ply_str3:   .text "BOTH"
                .byte 0
dbg_ply_str_lo: .byte <dbg_ply_str0, <dbg_ply_str1, <dbg_ply_str2, <dbg_ply_str3
dbg_ply_str_hi: .byte >dbg_ply_str0, >dbg_ply_str1, >dbg_ply_str2, >dbg_ply_str3
// SID type labels: 0=NONE 1=6581 2=8580 3=UNKN
dbg_sid_str0:   .text "NONE"
                .byte 0
dbg_sid_str1:   .text "6581"
                .byte 0
dbg_sid_str2:   .text "8580"
                .byte 0
dbg_sid_str3:   .text "UNKN"
                .byte 0
dbg_sid_str_lo: .byte <dbg_sid_str0, <dbg_sid_str1, <dbg_sid_str2, <dbg_sid_str3
dbg_sid_str_hi: .byte >dbg_sid_str0, >dbg_sid_str1, >dbg_sid_str2, >dbg_sid_str3
dbg_s_backsid:
    .text "BSID:"
    .byte 0
dbg_s_uci:
    .text "UCI:DF1F="
    .byte 0
dbg_s_u64:
    .text " U64:"
    .byte 0
dbg_s_d418:
    .text "D418:"
    .byte 0
dbg_s_potx:
    .text " POTX:"
    .byte 0
dbg_s_poty:
    .text " POTY:"
    .byte 0
dbg_s_d41b:
    .text "D41B:"
    .byte 0
dbg_s_d41c:
    .text " D41C:"
    .byte 0
dbg_s_d41d:
    .text " D41D:"
    .byte 0
dbg_s_d41e:
    .text " D41E:"
    .byte 0
dbg_s_d41f:
    .text " D41F:"
    .byte 0
dbg_s_arr1:
    .text "ARR1:"
    .byte 0
dbg_s_arr2:
    .text "ARR2:"
    .byte 0
dbg_s_arr3:
    .text "ARR3:"
    .byte 0
dbg_s_mean:
    .text "D418 DEC:"
    .byte 0
dbg_s_emul:
    .text "EMUL:"
    .byte 0
// emul mode char tables: 0=SID, 1=SFX, 2=BOT (BOTH)
dbg_emul_ch0: .byte $53, $53, $42  // 'S','S','B'
dbg_emul_ch1: .byte $49, $46, $4F  // 'I','F','O'
dbg_emul_ch2: .byte $44, $58, $54  // 'D','X','T'
dbg_s_sidlist:
    .text "SIDS("
    .byte 0
dbg_s_type:
    .text "T:"
    .byte 0
dbg_nav:
    .text "SPACE=BACK"
    .byte 0
dbg_s_uci_resp:
    .text "UCI RESP: "
    .byte 0
dbg_s_t_eq:
    .text " T="
    .byte 0
dbg_s_ultisid_hdr:
    .text "ULTISID FILTER CURVE:"
    .byte 13, 0
dbg_nav_p1:
    .text "D=PAGE 2  SPACE=BACK"
    .byte 0
dbg_nav_p2:
    .text "D=PAGE 1  SPACE=BACK"
    .byte 0
dbg_s_title_p2:
    .text "    SID DETECTOR - DEBUG 2/2"
    .byte 13, 13, 0

// ============================================================
// INFO PAGE TEXT DATA
// Each page: null-terminated PETSCII string.
// $0D = carriage return (next line). Cursor starts at row 0.
// Keep to ~22 lines max (row 24 reserved for nav hint).
// ============================================================

ip_nosid:
    .text "        NO SID DETECTED"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " NO SOUND INTERFACE DEVICE WAS FOUND."
    .byte 13
    .byte 13
    .text " POSSIBLE REASONS:"
    .byte 13
    .text "  - THE SID CHIP IS MISSING OR LOOSE"
    .byte 13
    .text "  - THE SID SOCKET IS DAMAGED"
    .byte 13
    .text "  - THE SID IS TOO DEFECTIVE TO PASS"
    .byte 13
    .text "    THE DETECTION TESTS"
    .byte 13
    .byte 13
    .text " SOME RARE EMULATORS (FRODO, YACE64,"
    .byte 13
    .text " EMU64) ALSO APPEAR HERE AS THEIR"
    .byte 13
    .text " DECAY SIGNATURE IS NOT RECOGNISED."
    .byte 0

ip_6581:
    .text "        MOS 6581 REAL SID CHIP"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE 6581 IS THE ORIGINAL SID CHIP"
    .byte 13
    .text " USED IN THE C64 (1982-1987)."
    .byte 13
    .text " MADE BY MOS TECHNOLOGY / COMMODORE."
    .byte 13
    .byte 13
    .text " IT HAS A WARM AND SLIGHTLY DISTORTED"
    .byte 13
    .text " SOUND CAUSED BY A QUIRK IN THE FILTER"
    .byte 13
    .text " DESIGN. MANY MUSICIANS PREFER THIS"
    .byte 13
    .text " SOUND OVER THE LATER 8580."
    .byte 13
    .byte 13
    .text " KNOWN REVISIONS:"
    .byte 13
    .text "  R2 (5182) - FIRST REVISION"
    .byte 13
    .text "  R3 (2084) - MINOR FIXES"
    .byte 13
    .text "  R4 (1886) - REVISED DESIGN"
    .byte 13
    .text "  R4AR (5286) - LAST 6581 REVISION"
    .byte 13
    .byte 13
    .text " QUIRKS:"
    .byte 13
    .text "  COMBINED WAVEFORMS PRODUCE UNIQUE"
    .byte 13
    .text "  TIMBRES USED IN MANY C64 CLASSICS."
    .byte 13
    .text "  FILTER HAS DC OFFSET - SLIGHT HUM"
    .byte 13
    .text "  WHEN FILTER IS NOT ENGAGED."
    .byte 13
    .text "  OSC3/ENV3 READABLE FOR RNG USE."
    .byte 13
    .byte 13
    .text " FOUND IN: C64 BREADBIN, C64C (EARLY)"
    .byte 0

ip_8580:
    .text "        MOS 8580 REAL SID CHIP"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE 8580 IS THE SECOND-GENERATION SID"
    .byte 13
    .text " USED IN THE C64C AND C128 (1987+)."
    .byte 13
    .text " MADE BY MOS TECHNOLOGY / COMMODORE."
    .byte 13
    .byte 13
    .text " IT HAS A CLEANER SOUND AND CORRECTED"
    .byte 13
    .text " FILTER COMPARED TO THE 6581. THE"
    .byte 13
    .text " DIFFERENT FILTER CHARACTERISTICS MEAN"
    .byte 13
    .text " SOME 6581 MUSIC SOUNDS DIFFERENT."
    .byte 13
    .byte 13
    .text " THE 8580 REQUIRES A 9V POWER SUPPLY"
    .byte 13
    .text " (6581 USES 12V). MIXING THEM WITHOUT"
    .byte 13
    .text " ADJUSTMENT CAN DAMAGE THE CHIP."
    .byte 13
    .byte 13
    .text " VOICE 3 DISCONNECT: D418 BIT 7 MUTES"
    .byte 13
    .text " VOICE 3 FROM AUDIO OUTPUT WHILE"
    .byte 13
    .text " OSC3/ENV3 REMAIN READABLE - USED"
    .byte 13
    .text " FOR SILENT RANDOM NUMBER GENERATION."
    .byte 13
    .byte 13
    .text " COMBINED WAVEFORMS PRODUCE SOFTER,"
    .byte 13
    .text " MORE UNIFORM RESULTS THAN THE 6581."
    .byte 13
    .byte 13
    .text " FOUND IN: C64C (LATE), C128, C128D"
    .byte 0

ip_armsid:
    .text "      ARMSID / ARM2SID REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE ARMSID IS A MODERN SID CHIP"
    .byte 13
    .text " REPLACEMENT BASED ON AN ARM CORTEX"
    .byte 13
    .text " MICROCONTROLLER. IT FITS IN THE SAME"
    .byte 13
    .text " 28-PIN DIP SOCKET AS THE ORIGINAL."
    .byte 13
    .byte 13
    .text " IT CAN EMULATE BOTH 6581 AND 8580"
    .byte 13
    .text " MODES AND IS HIGHLY COMPATIBLE."
    .byte 13
    .byte 13
    .text " ARM2SID IS THE SECOND GENERATION:"
    .byte 13
    .text " TWO ARM CHIPS (L+R) IN ONE PACKAGE,"
    .byte 13
    .text " SUPPORTING STEREO, 3-SID, AND SFX"
    .byte 13
    .text " CARTRIDGE EMULATION. ONLY ARM2SID"
    .byte 13
    .text " SUPPORTS 3-SID AND SFX MODES."
    .byte 13
    .byte 13
    .text " STEREO: MIXSID BOARD SLOTS ARMSID AT"
    .byte 13
    .text " D420 (CS2) ALONGSIDE A REAL SID AT"
    .byte 13
    .text " D400 (CS1). BOTH ARE DETECTED."
    .byte 13
    .byte 13
    .text " MADE BY: ARMSID.COM"
    .byte 13
    .text " FIRMWARE UPDATES: ARMSID.COM"
    .byte 0

ip_swinu:
    .text "      SWINSID ULTIMATE REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE SWINSID ULTIMATE IS AN AVR-BASED"
    .byte 13
    .text " SID REPLACEMENT. BASED ON ATMEL AVR"
    .byte 13
    .text " MICROCONTROLLER RUNNING CUSTOM SID"
    .byte 13
    .text " EMULATION FIRMWARE."
    .byte 13
    .byte 13
    .text " SUPPORTS SWITCHABLE 6581/8580 MODES"
    .byte 13
    .text " WITH GOOD FILTER EMULATION."
    .byte 13
    .byte 13
    .text " DETECTED BY REGISTER ECHO: WRITES"
    .byte 13
    .text " 'D','I','S' TO D41D/D41E/D41F THEN"
    .byte 13
    .text " READS D41B. EXPECTS 'S' (=$53)."
    .byte 13
    .text " REAL SID CHIPS DO NOT ECHO WRITES."
    .byte 0

ip_swinano:
    .text "        SWINSID NANO REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " COMPACT SID REPLACEMENT BASED ON AN"
    .byte 13
    .text " ATMEL AVR (SOIC-28 PACKAGE, FITS DIP"
    .byte 13
    .text " SOCKET WITH ADAPTER). EMULATES 6581"
    .byte 13
    .text " AND 8580 MODES."
    .byte 13
    .byte 13
    .text " DETECTED BY D41B (OSC3) ACTIVITY:"
    .byte 13
    .text " NOISE WAVEFORM, FREQ=$FFFF. READS"
    .byte 13
    .text " D41B 8X IN A ROW. REAL 6581/8580"
    .byte 13
    .text " CHANGE EVERY READ (LFSR AT CPU CLK)."
    .byte 13
    .text " AVR UPDATES AT ~44KHZ - SOME READS"
    .byte 13
    .text " REPEAT. STAGE 1: 3 RETRIES, REJECT"
    .byte 13
    .text " IF ALL GIVE CNT=7 (= REAL SID SPEED)."
    .byte 13
    .text " STAGE 2: CONFIRM ACTIVITY AT 62MS."
    .byte 13
    .byte 13
    .text " CAUTION: NOSID+ULTIMATE II+ (VIRTUAL"
    .byte 13
    .text " SID OFF) ALSO TRIGGERS THIS RESULT."
    .byte 13
    .text " U2+ BUS NOISE IS INDISTINGUISHABLE."
    .byte 0

ip_fpga8580:
    .text "        FPGASID - 8580 MODE"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE FPGASID IS A MODERN SID REPLACEMENT"
    .byte 13
    .text " IMPLEMENTED IN AN ALTERA FPGA."
    .byte 13
    .byte 13
    .text " IT PROVIDES HIGHLY ACCURATE EMULATION"
    .byte 13
    .text " OF BOTH 6581 AND 8580 CHIPS. THE FPGA"
    .byte 13
    .text " ALLOWS FOR VERY PRECISE TIMING AND"
    .byte 13
    .text " FILTER SIMULATION."
    .byte 13
    .byte 13
    .text " THIS UNIT IS CONFIGURED IN 8580 MODE."
    .byte 13
    .text " (D41F=$3F AT DETECTION TIME)"
    .byte 13
    .byte 13
    .text " MADE BY: FPGASID.DE"
    .byte 0

ip_fpga6581:
    .text "        FPGASID - 6581 MODE"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE FPGASID IS A MODERN SID REPLACEMENT"
    .byte 13
    .text " IMPLEMENTED IN AN ALTERA FPGA."
    .byte 13
    .byte 13
    .text " IT PROVIDES HIGHLY ACCURATE EMULATION"
    .byte 13
    .text " OF BOTH 6581 AND 8580 CHIPS. THE FPGA"
    .byte 13
    .text " ALLOWS FOR VERY PRECISE TIMING AND"
    .byte 13
    .text " FILTER SIMULATION."
    .byte 13
    .byte 13
    .text " THIS UNIT IS CONFIGURED IN 6581 MODE."
    .byte 13
    .text " (D41F=$00 AT DETECTION TIME)"
    .byte 13
    .byte 13
    .text " MADE BY: FPGASID.DE"
    .byte 0

ip_sidfx:
    .text "        SIDFX SWITCHER CARTRIDGE"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE SIDFX IS AN EXPANSION CARTRIDGE"
    .byte 13
    .text " THAT INSTALLS BETWEEN THE SID SOCKET"
    .byte 13
    .text " AND THE SID CHIP. IT ALLOWS SWITCHING"
    .byte 13
    .text " BETWEEN TWO SID CHIPS IN SOFTWARE."
    .byte 13
    .byte 13
    .text " DETECTED VIA AN SCI SERIAL PROTOCOL"
    .byte 13
    .text " HANDSHAKE: VENDOR ID $45 $4C $12 $58"
    .byte 13
    .text " IS READ BACK AFTER A PNP LOGIN."
    .byte 13
    .byte 13
    .text " SIDFX CAN HOST BOTH A 6581 AND 8580"
    .byte 13
    .text " SIMULTANEOUSLY FOR DUAL-SID SETUPS."
    .byte 13
    .byte 13
    .text " MORE INFO: SIDFX.DE"
    .byte 0

ip_ulti:
    .text "        ULTISID (ULTIMATE 64)"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE ULTIMATE 64 IS A COMPLETE C64"
    .byte 13
    .text " MOTHERBOARD REPLACEMENT IMPLEMENTED"
    .byte 13
    .text " IN AN FPGA. IT INCLUDES A BUILT-IN"
    .byte 13
    .text " HIGH-QUALITY SID EMULATOR: ULTISID."
    .byte 13
    .byte 13
    .text " ULTISID SUPPORTS MULTIPLE SID MODELS"
    .byte 13
    .text " AND PROVIDES EXCELLENT COMPATIBILITY"
    .byte 13
    .text " WITH REAL HARDWARE BEHAVIOUR."
    .byte 13
    .byte 13
    .text " DETECTED BY ITS CHARACTERISTIC $D418"
    .byte 13
    .text " DECAY VALUE (data1=$DA-$F1)."
    .byte 13
    .byte 13
    .text " MADE BY: ULTIMATE64.COM"
    .byte 0

ip_vice:
    .text "        VICE C64 EMULATOR"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " VICE (VERSATILE COMMODORE EMULATOR)"
    .byte 13
    .text " IS THE MOST WIDELY USED C64 EMULATOR."
    .byte 13
    .byte 13
    .text " TWO SID ENGINES ARE DETECTED HERE:"
    .byte 13
    .byte 13
    .text " RESID: CYCLE-ACCURATE TRANSISTOR-"
    .byte 13
    .text " LEVEL EMULATION. HIGH CPU USAGE BUT"
    .byte 13
    .text " BEST SOUND ACCURACY."
    .byte 13
    .byte 13
    .text " FASTSID: FASTER BUT LESS ACCURATE"
    .byte 13
    .text " APPROXIMATION OF SID BEHAVIOUR."
    .byte 13
    .byte 13
    .text " WEBSITE: VICE-EMU.SOURCEFORGE.NET"
    .byte 0

ip_hoxs:
    .text "        HOXS64 C64 EMULATOR"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " HOXS64 IS A WINDOWS-BASED COMMODORE"
    .byte 13
    .text " 64 EMULATOR WRITTEN BY DAVID HORROCKS."
    .byte 13
    .byte 13
    .text " IT USES ITS OWN SID EMULATION ENGINE"
    .byte 13
    .text " WHICH HAS A DISTINCTIVE $D418 DECAY"
    .byte 13
    .text " SIGNATURE (data2=$19)."
    .byte 13
    .byte 13
    .text " HOXS64 FOCUSES ON ACCURATE EMULATION"
    .byte 13
    .text " OF THE C64 AND C128 HARDWARE INCLUDING"
    .byte 13
    .text " CYCLE-ACCURATE CPU TIMING."
    .byte 13
    .byte 13
    .text " WEBSITE: HOXS64.COM"
    .byte 0

ip_sidkpic:
    .text "           SIDKICK REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " SIDKICK IS A RASPBERRY PI PICO-BASED"
    .byte 13
    .text " SID REPLACEMENT CHIP."
    .byte 13
    .byte 13
    .text " IT USES THE RP2040 MICROCONTROLLER"
    .byte 13
    .text " RUNNING CUSTOM FIRMWARE TO EMULATE"
    .byte 13
    .text " BOTH 6581 AND 8580 SID CHIPS."
    .byte 13
    .byte 13
    .text " THE PICO'S FAST DUAL-CORE PROCESSOR"
    .byte 13
    .text " ENABLES ACCURATE BUS TIMING AND"
    .byte 13
    .text " HIGH-QUALITY AUDIO OUTPUT."
    .byte 13
    .byte 13
    .text " DETECTED VIA VERSION STRING: WRITE"
    .byte 13
    .text " $FF TO D41F, $E0 TO D41E, SKIP 20"
    .byte 13
    .text " BYTES FROM D41D. READS 'S' + 'K'."
    .byte 13
    .byte 13
    .text " OPEN SOURCE PROJECT ON GITHUB"
    .byte 0

ip_pubdom:
    .text "           PD SID REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " THE PDSID IS A FREE/OPEN-SOURCE SID"
    .byte 13
    .text " REPLACEMENT FIRMWARE. IT IDENTIFIES"
    .byte 13
    .text " ITSELF VIA A REGISTER ECHO PROTOCOL."
    .byte 13
    .byte 13
    .text " DETECTED: WRITE 'P' ($50) TO D41D,"
    .byte 13
    .text " 'D' ($44) TO D41E. READ D41E:"
    .byte 13
    .text " EXPECTS 'S' ($53) ECHOED BACK."
    .byte 13
    .text " REAL SID CHIPS DO NOT ECHO WRITES."
    .byte 13
    .byte 13
    .text " QUALITY AND COMPATIBILITY DEPEND ON"
    .byte 13
    .text " THE HARDWARE AND FIRMWARE VERSION."
    .byte 0

ip_backsid:
    .text "        BACKSID REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " BACKSID IS A SID CHIP REPLACEMENT"
    .byte 13
    .text " PROJECT. IT PROVIDES AUTHENTIC C64"
    .byte 13
    .text " AUDIO IN A MODERN FORM FACTOR."
    .byte 13
    .byte 13
    .text " DESIGNED AS AN AFFORDABLE ALTERNATIVE"
    .byte 13
    .text " TO OTHER SID REPLACEMENTS, IT OFFERS"
    .byte 13
    .text " BASIC COMPATIBILITY WITH C64 SOFTWARE."
    .byte 13
    .byte 13
    .text " DETECTED VIA REGISTER ECHO: WRITE"
    .byte 13
    .text " $42 TO D41C, $B5 TO D41D, $1D TO"
    .byte 13
    .text " D41E. READ D41F: EXPECTS $42 BACK."
    .byte 13
    .text " REAL SID CHIPS DO NOT HOLD WRITES."
    .byte 0

ip_kungfusid:
    .text "       KUNGFUSID REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " KUNGFUSID IS AN OPEN-SOURCE ARM"
    .byte 13
    .text " CORTEX-M4 SID REPLACEMENT."
    .byte 13
    .byte 13
    .text " USES STM32F405 OR GD32F405 AT 168MHZ"
    .byte 13
    .text " WITH 12-BIT DAC AND LM321 OP-AMP."
    .byte 13
    .byte 13
    .text " AUTO-DETECTS 6581 OR 8580 MODE FROM"
    .byte 13
    .text " SUPPLY VOLTAGE. PLUGS INTO DIP-28"
    .byte 13
    .text " SOCKET. PCB IS OPEN HARDWARE."
    .byte 13
    .byte 13
    .text " GITHUB: GITHUB.COM/SGW32/KUNGFUSID"
    .byte 0

ip_unknown:
    .text "        UNKNOWN SID / DEVICE"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " A DEVICE WAS DETECTED AT THE SID"
    .byte 13
    .text " ADDRESS BUT COULD NOT BE IDENTIFIED."
    .byte 13
    .byte 13
    .text " THIS CAN HAPPEN WHEN:"
    .byte 13
    .text "  - A NEW OR UNSUPPORTED SID VARIANT"
    .byte 13
    .text "    IS INSTALLED"
    .byte 13
    .text "  - AN EMULATOR WITH AN UNUSUAL $D418"
    .byte 13
    .text "    DECAY SIGNATURE IS RUNNING"
    .byte 13
    .text "  - HARDWARE TIMING DIFFERENCES CAUSE"
    .byte 13
    .text "    THE DETECTION TO BE INCONCLUSIVE"
    .byte 13
    .byte 13
    .text " IF YOU KNOW WHAT THIS IS, PLEASE"
    .byte 13
    .text " REPORT IT TO THE AUTHOR."
    .byte 0

ip_usid64:
    .text "          USID64 REPLACEMENT"
    .byte 13
    .text "----------------------------------------"
    .byte 13
    .text " USID64 IS A COMPACT SID REPLACEMENT"
    .byte 13
    .text " MICROCONTROLLER BOARD. SUPPORTS 6581"
    .byte 13
    .text " AND 8580 EMULATION MODES."
    .byte 13
    .byte 13
    .text " DETECTED VIA D41F CONFIG REGISTER:"
    .byte 13
    .text " UNLOCK SEQUENCE $F0/$10/$63/$00/$FF"
    .byte 13
    .text " IS WRITTEN TO D41F. THEN D41F IS"
    .byte 13
    .text " READ TWICE WITH A ~3MS GAP."
    .byte 13
    .byte 13
    .text " BOTH READS MUST BE IN $E0-$FC RANGE"
    .byte 13
    .text " AND AGREE WITHIN $02 (STABLE VALUE"
    .byte 13
    .text " = REGISTER HOLDS THE CONFIG BYTE)."
    .byte 13
    .byte 13
    .text " A FLOATING NOSID BUS READS $FF OR"
    .byte 13
    .text " DRIFTS MORE THAN $02 BETWEEN READS,"
    .byte 13
    .text " SO IT IS CLEANLY REJECTED."
    .byte 0

// ============================================================
// README TEXT
// Flat text blob for the README viewer. Each line ends with
// $0D (CR). Headings are prefixed with PETSCII $05 (white),
// content lines with $9E (yellow). Blank lines are bare $0D.
// Null byte $00 terminates the text.
// ============================================================

readme_text:
    .byte $05
    .text "SIDDETECTOR V1.3.86 README"
    .byte 13
    .byte 13
    .byte $05
    .text "WHAT IT DETECTS"
    .byte 13
    .byte $9E
    .text "  REAL CHIPS: 6581 R2/R3/R4/R4AR, 8580"
    .byte 13
    .byte $9E
    .text "  FPGA: FPGASID (6581 + 8580 MODE)"
    .byte 13
    .byte $9E
    .text "  MICROCONT: ARMSID  ARM2SID  SWINSID"
    .byte 13
    .byte $9E
    .text "    NANO  SIDFX  ULTISID  SIDKICK"
    .byte 13
    .byte $9E
    .text "    KUNGFUSID  BACKSID  USID64  PDSID"
    .byte 13
    .byte $9E
    .text "  EMU: VICE RESID/FASTSID  HOXS64"
    .byte 13
    .byte $9E
    .text "    FRODO  YACE64  EMU64  C64DBG"
    .byte 13
    .byte 13
    .byte $05
    .text "DETECTION CHAIN"
    .byte 13
    .byte $9E
    .text "  0 REAL SID  OSC3 PRE-CHECK (EARLY)"
    .byte 13
    .byte $9E
    .text "  1 SWINSID NANO  D41B CNT TEST"
    .byte 13
    .byte $9E
    .text "  2 SIDFX   SCI SERIAL PROTOCOL"
    .byte 13
    .byte $9E
    .text "  3 ARMSID/SWINSID-U  REG ECHO DIS"
    .byte 13
    .byte $9E
    .text "  3A PDSID   WRITE P/D READ S AT D41E"
    .byte 13
    .byte $9E
    .text "  3B BACKSID  POLL D41F FOR $42"
    .byte 13
    .byte $9E
    .text "  3C SIDKICK  CFG MODE VERS S+K"
    .byte 13
    .byte $9E
    .text "  4 FPGASID  MAGIC COOKIE $1D/$F5"
    .byte 13
    .byte $9E
    .text "  5 USID64   D41F TWO-READ STABILITY"
    .byte 13
    .byte $9E
    .text "  6 REAL SID  OSC3 SAWTOOTH READBACK"
    .byte 13
    .byte $9E
    .text "  7 2ND SID  NOISE WAVEFORM MIRROR"
    .byte 13
    .byte $9E
    .text "  7A KUNGFUSID  D41D ECHO $A5/$5A"
    .byte 13
    .byte $9E
    .text "  8 EMULATOR  $D418 DECAY TIMING"
    .byte 13
    .byte 13
    .byte $05
    .text "MACHINE + CLOCK"
    .byte 13
    .byte $9E
    .text "  C64:   $D030 = $FF  (OPEN BUS)"
    .byte 13
    .byte $9E
    .text "  C128:  $D0FE RETURNS $FC"
    .byte 13
    .byte $9E
    .text "  TC64:  $D0FE RETURNS OTHER VALUE"
    .byte 13
    .byte $9E
    .text "  PAL:   RASTER LINE $137 = PAL"
    .byte 13
    .byte $9E
    .text "  NTSC:  LINE $137 NOT REACHED"
    .byte 13
    .byte 13
    .byte $05
    .text "STEREO SID SCAN"
    .byte 13
    .byte $9E
    .text "  SCANS D400 D500 D600 D700"
    .byte 13
    .byte $9E
    .text "        DE00-DFFF IN $20 STEPS"
    .byte 13
    .byte $9E
    .text "  CHIP NAME SHOWN IN STEREO SID ROW"
    .byte 13
    .byte 13
    .byte $05
    .text "KEYS"
    .byte 13
    .byte $9E
    .text "  SPACE  RESTART DETECTION"
    .byte 13
    .byte $9E
    .text "  I      CHIP INFO PAGE"
    .byte 13
    .byte $9E
    .text "  D      DEBUG RAW VALUES"
    .byte 13
    .byte $9E
    .text "  R      THIS README"
    .byte 13
    .byte $9E
    .text "  T      SID SOUND TEST"
    .byte 13
    .byte $9E
    .text "  L      TLR SECOND SID DETECTOR"
    .byte 13
    .byte $9E
    .text "  P      TOGGLE SID MUSIC"
    .byte 13
    .byte $9E
    .text "  Q      QUIT TO BASIC"
    .byte 13
    .byte $9E
    .text "  B/M    PREV/NEXT INFO PAGE"
    .byte 13
    .byte $9E
    .text "  W/S    SCROLL INFO/README PAGES"
    .byte 13
    .byte 13
    .byte $05
    .text "BUILD SYSTEM"
    .byte 13
    .byte $9E
    .text "  MAKE ALL      BUILD PRG"
    .byte 13
    .byte $9E
    .text "  MAKE RUN      BUILD + LAUNCH VICE"
    .byte 13
    .byte $9E
    .text "  MAKE CI       HEADLESS TESTS (23)"
    .byte 13
    .byte $9E
    .text "  MAKE RELEASE  FULL PIPELINE + TAG"
    .byte 13
    .byte 13
    .byte $05
    .text "AUTHOR + VERSION HISTORY"
    .byte 13
    .byte $9E
    .text "  ORIGINAL:  FUNFUN/TRIANGLE 3532"
    .byte 13
    .byte $9E
    .text "  CSDB:      RELEASE #176909"
    .byte 13
    .byte $9E
    .text "  V1.3.86 SIDKICK-PICO FM SOUND EXPANDER DETECTION"
    .byte 13
    .byte $9E
    .text "  V1.3.85 ARM2SID SFX MODE ON MAIN + INFO SCREENS"
    .byte 13
    .byte $9E
    .text "  V1.3.84 ARMSID+SIDFX D420 BUS CONTAMINATION FIX"
    .byte 13
    .byte $9E
    .text "  V1.3.83 SIDKICK-PICO D420 SIDFX DETECTION"
    .byte 13
    .byte $9E
    .text "  V1.3.82 RETRY INDICATOR ON MAIN SCREEN"
    .byte 13
    .byte $9E
    .text "  V1.3.81 MULTI-SID FULL MELODY SOUND TEST"
    .byte 13
    .byte $9E
    .text "  V1.3.80 ARMSID+SWINSID STEREO D5XX FIX"
    .byte 13
    .byte $9E
    .text "  V1.3.79 SWINSID FIKTIVLOOP+STEREO FIX"
    .byte 13
    .byte $9E
    .text "  V1.3.78 DEBUG PAGE 1 VERSION STRING"
    .byte 13
    .byte $9E
    .text "  V1.3.77 C25/C26 ARMSID D5XX FIX"
    .byte 13
    .byte $9E
    .text "  V1.3.73 8580+ARMSID MIXSID C09 STEREO"
    .byte 13
    .byte $9E
    .text "  V1.3.45 PDSID BACKSID SKPICO KUNGFUSID"
    .byte 13
    .byte $9E
    .text "  V1.2.17 BACKSID DETECTION POLLING LOOP"
    .byte 13
    .byte $9E
    .text "  V1.2.16 BACKSID MAIN CHAIN + STEREO FIX"
    .byte 13
    .byte $9E
    .text "  V1.2.15 ARM2SID PETSCII FIX + TEST STATUS"
    .byte 13
    .byte $9E
    .text "  V1.2.14 SCREEN ROW REORDER"
    .byte 13
    .byte $9E
    .text "  V1.2.13 ARMSID/ARM2SID FIRMWARE VERSION"
    .byte 13
    .byte $9E
    .text "  V1.2.4  INFO PAGES  B/M KEYS  CI/CD"
    .byte 13
    .byte $9E
    .text "  V1.2.3  SIDKICK/PD SID RENAME"
    .byte 13
    .byte $9E
    .text "  V1.2.2  BACKSID  STEREO DE00-DFFF"
    .byte 13
    .byte $9E
    .text "  V1.2.1  INITIAL RELEASE"
    .byte 13
    .byte 13
    .byte 0                         // null terminator

// Fixed header and navigation hint for README page (screencode_upper)
.encoding "screencode_upper"
readme_header:
    .text "SIDDETECTOR README                      "
    .byte 0
readme_nav_hint:
    .text "W=UP  S=DOWN  SPACE=RESTART             "
    .byte 0
.encoding "ascii"

// ============================================================
// SOUND TEST STRINGS
// null-terminated ASCII strings for dbg_str
// ============================================================

snd_title:
    .text "SID SOUND TEST"
    .byte 13
    .byte 13
    .text "TESTING ALL 3 SID VOICES."
    .byte 13
    .text "SAWTOOTH, TRIANGLE, PULSE WAVEFORMS."
    .byte 13
    .byte 13
    .text "NOW TESTING: "
    .byte 0

snd_now_testing:
    .byte 13
    .text "NOW TESTING: "
    .byte 0

snd_done:
    .byte 13
    .text "SOUND TEST COMPLETE."
    .byte 13
    .text "PRESS SPACE TO RESTART."
    .byte 0

// ============================================================
// SOUND TEST NOTE DATA
// Adapted from Dead Test cartridge sound_test.asm.
// st_sound1/3/5: Freq Hi bytes for voices 1/2/3 (7 notes each)
// st_sound2/4/6: Freq Lo bytes for voices 1/2/3 (7 notes each)
// st_sound7:     Waveform control byte (indexed by outer loop Y=2..0)
// st_sound8:     Pulse width Lo        (indexed by outer loop Y=2..0)
// st_sound9:     Pulse width Hi+ctrl   (indexed by outer loop Y=2..0)
// ============================================================

st_sound1: .byte $11,$15,$19,$22,$19,$15,$11
st_sound2: .byte $25,$9a,$b1,$4b,$b1,$9a,$25
st_sound3: .byte $22,$2b,$33,$44,$33,$2b,$22
st_sound4: .byte $4b,$34,$61,$95,$61,$34,$4b
st_sound5: .byte $44,$56,$66,$89,$66,$56,$44
st_sound6: .byte $95,$69,$c2,$2b,$c2,$69,$95
st_sound7: .byte $45,$11,$25,$81      // pulse+ring+gate, triangle+gate, saw+ring+gate, noise+gate
st_sound8: .byte $00,$00,$00,$00      // pulse width Lo (unused for saw/tri/noise)
st_sound9: .byte $08,$00,$00,$09,$00,$28,$ff,$1f  // pulse width Hi

// fiktivloop_d400: initialise sptr_zp/cnt1_zp/cnt2_zp for a D400-rooted scan
// then tail-call fiktivloop. D400 must already be pre-populated in sid_list[1].
fiktivloop_d400:
       lda #$00
       sta sptr_zp
       sta cnt2_zp
       lda #$D4
       sta sptr_zp+1
       lda #$01
       sta cnt1_zp
       jmp fiktivloop

//-------------------------------------------------------------------------
// backsid_post_fixup: wrapper for sidstereo_print.
// Calls sidstereo_print, then checks if BackSID ($0A) was found in the
// stereo scan (sid_list_t[1..sidnum_zp]). If so:
//   - prints "BACKSID FOUND" on row 8 ("BACKSID....:" label line)
//   - clears "NOSID FOUND" from row 11 with spaces
// BackSID may sit at D560 or another non-D400 address, so the main chain
// (which only checks D400) misses it; this fixup corrects the display.
backsid_post_fixup:
                jsr sidstereo_print
                // scan sid_list_t[1..sidnum_zp] for BackSID type $0A
                ldy #$01
bpf_scan:
                lda sid_list_t,y
                cmp #$0A
                beq bpf_found
                cpy sidnum_zp
                beq bpf_done
                iny
                bne bpf_scan
bpf_found:
                // row 8: print "BACKSID FOUND" at column 13
                ldx #08
                ldy #13
                jsr $E50C
                lda #<backsidf
                ldy #>backsidf
                jsr $AB1E
                // clear "NOSID FOUND" (11 chars) at row 11 col 13
                // screen RAM: $0400 + 11*40 + 13 = $05C5
                lda #$20            // space screencode
                ldx #$00
bpf_clr:
                sta $05C5,x
                inx
                cpx #11
                bne bpf_clr
bpf_done:
                rts

//-------------------------------------------------------------------------
// checkbacksid: detect BackSID. Protocol reverse-engineered from backsid.prg:
//   1. Write D41B=$02, D41C=$01 (echo test), D41D=$B5, D41E=$1D (unlock)
//   2. Poll loop (up to 15 times, ~630ms total):
//      a. Write D41B=$02 again (re-arms echo on each poll, as backsid.prg does)
//      b. Wait ~42ms (2-jiffy window from backsid.prg)
//      c. Read D41F — if echoes $01: BackSID found (data1=$0A)
//   3. If no echo after 15 polls: data1=$F0
// D41C..D41F self-modified for multi-slot scan. D41B hardcoded to $D41B.
checkbacksid:
                stx x_zp
                sty y_zp
                pha
                // patch self-modifying addresses for D41C..D41F (D41B via (sptr_zp),y)
                lda sptr_zp+1
                sta cbs_d41C+2
                sta cbs_d41D+2
                sta cbs_d41E+2
                sta cbs_d41F+2
                sta cbs_pre+2       // also patch the pre-check read
                lda sptr_zp
                clc
                adc #$1C            // $1C = D41C offset
                sta cbs_d41C+1
                adc #$01
                sta cbs_d41D+1
                adc #$01
                sta cbs_d41E+1
                adc #$01
                sta cbs_d41F+1
                sta cbs_pre+1       // same D41F address for pre-check
                // Pre-check: cold read D41F before unlock sequence.
                // NOSID/U64 bus floats to $01 after prior writes; a real BackSID
                // only echoes $01 AFTER the unlock sequence, not before.
cbs_pre:        lda $D41F           // cold read (addr self-modified above)
                cmp #$01
                beq cbs_notfound    // already $01 → NOSID bus artifact, skip
                // Initial unlock: D41B first, then D41C/D/E
                lda #$02
                ldy #$1B
                sta (sptr_zp),y     // base+$1B (sptr_zp-relative; works for D400 or D5xx)
                lda #$01            // echo test value
cbs_d41C:       sta $D41C
                lda #$B5            // unlock key 1
cbs_d41D:       sta $D41D
                lda #$1D            // unlock key 2
cbs_d41E:       sta $D41E
                // Poll: re-arm D41B each time, wait ~42ms, check D41F echo
                // backsid.prg polls for up to 121 jiffies (~2.4s); 15 polls ≈ 630ms
                ldx #15
cbs_poll:
                lda #$02
                ldy #$1B
                sta (sptr_zp),y     // re-arm base+$1B on each poll (rp_delay clobbers Y)
                lda #$0E            // ~42ms per poll
                jsr rp_delay
cbs_d41F:       lda $D41F
                sta backsid_d41f    // save last D41F for debug
                cmp #$01            // echo matches test value?
                beq cbs_found
                dex
                bne cbs_poll
cbs_notfound:   lda #$F0
                sta data1
                jmp cbs_done
cbs_found:
                lda #$0A
                sta data1
cbs_done:
                ldx x_zp
                ldy y_zp
                pla
                rts

//─────────────────────────────────────────────────────────────────────────────
// uci_type_for_addr: determine UltiSID 6581/8580 type via checkrealsid oscillator test.
// Issues GET_HWINFO to populate uci_resp (for debug display), then checks T byte:
//   - T in 0-6: filter curve index → maps to $20-$26 (hypothetical; firmware never returns this)
//   - T = $83/$85 or any other value: falls back to checkrealsid (sawtooth D41B test)
// In practice on current U64 firmware: T byte is ALWAYS $83 or $85 (hardware presence
// codes), never 0-6, so checkrealsid is ALWAYS the actual detection method.
// checkrealsid: $D41B=0 after sawtooth gate → 8580 (data1=$02); $D41B=1 → 6581 (data1=$01).
// Response format (CTRL_CMD_GET_HWINFO $04/$28/$01): [0]=count, then per 5-byte frame:
//   [lo, hi, sec_hi, sec_lo, type]. Frame1 type at resp[5], Frame2 at resp[10].
// Input:  mptr_zp/mptr_zp+1 = SID address to look up
// Output: A = $20 (ULTISID-8580) or $22 (ULTISID-6581); $20 if checkrealsid returns unknown
// Trashes: A, X, Y, x_zp, y_zp, buf_zp, sptr_zp, data1; updates uci_resp[0..22]
// Caller saves slot index in x_zp; restored here via stack on checkrealsid path.
//─────────────────────────────────────────────────────────────────────────────
uci_type_for_addr:
       // Set sptr_zp = mptr_zp for checkrealsid fallback path
       lda mptr_zp
       sta sptr_zp
       lda mptr_zp+1
       sta sptr_zp+1
       // Issue UCI GET_HWINFO to populate uci_resp for debug display + type detection
       lda #$04
       sta $DF1D               // ControlTarget (4)
       lda #$28
       sta $DF1D               // CTRL_CMD_GET_HWINFO
       lda #$01
       sta $DF1D               // device = 1 (SID config)
       lda #$01
       sta $DF1C               // PUSH_CMD
       // Poll STATE bits 4:5 of $DF1C until != $10 (Command Busy); 64K timeout
       ldx #$00
       ldy #$00
utfa_poll:
       lda $DF1C
       and #$30               // STATE bits 4:5: $00=idle $10=busy $20=DataLast $30=DataMore
       cmp #$10               // still Command Busy?
       bne utfa_state_ready
       dex
       bne utfa_poll
       dey
       bne utfa_poll
       jmp utfa_checkrealsid   // timeout → fallback
utfa_state_ready:
       // Check DATA_AV = bit 7 of status register
       lda $DF1C
       bpl utfa_nodata         // bit 7 clear → no data
       ldx #$00
utfa_read:
       lda $DF1E; sta uci_resp,x; inx  // read byte from response FIFO
       cpx #$16; beq utfa_drain        // buffer full at 22 bytes → drain remaining
       lda $DF1C; bmi utfa_read        // DATA_AV bit 7 set → more bytes available
       jmp utfa_status                  // DATA_AV clear → FIFO empty, done
utfa_drain:                             // discard extra bytes until FIFO empty
       lda $DF1C; bpl utfa_status      // DATA_AV clear → done
       lda $DF1E; jmp utfa_drain       // discard, keep draining
utfa_status:
       lda #$02
       sta $DF1C               // DATA_ACC – acknowledge + reset UCI to Idle
       lda $DF1F               // status after reset (should be $00)
       sta uci_resp+22
       // Search Frame 1: resp[1]=lo, resp[2]=hi, resp[5]=type
       lda uci_resp+2          // Frame1 address high byte
       cmp mptr_zp1
       bne utfa_try2
       lda uci_resp+1          // Frame1 address low byte
       cmp mptr_zp
       bne utfa_try2
       lda uci_resp+5          // Frame1 filter curve type byte
       jmp utfa_map
utfa_try2:
       // Search Frame 2: resp[6]=lo, resp[7]=hi, resp[10]=type
       lda uci_resp+0          // count
       cmp #$02
       bcc utfa_checkrealsid   // count < 2 → no Frame2
       lda uci_resp+7          // Frame2 address high byte
       cmp mptr_zp1
       bne utfa_checkrealsid
       lda uci_resp+6          // Frame2 address low byte
       cmp mptr_zp
       bne utfa_checkrealsid
       lda uci_resp+10         // Frame2 filter curve type byte
       jmp utfa_map
utfa_nodata:
       lda $DF1F               // consume status
       sta uci_resp+22
       lda #$02
       sta $DF1C
utfa_checkrealsid:
       // Fallback: UCI address not matched or type out of range.
       // checkrealsid overwrites x_zp; save caller's slot index on stack first.
       lda x_zp
       pha
       jsr checkrealsid       // sptr_zp=mptr_zp; data1=$01(8580)/$02(6581)/$F0
       pla
       sta x_zp               // restore caller's slot index
       lda data1
       cmp #$02
       beq utfa_6581
       lda #$20               // 8580 or unknown → ULTISID 8580
       rts
utfa_6581:
       lda #$22               // 6581 → ULTISID 6581
       rts
utfa_map:
       // UCI type 0-6 → sid_list_t $20-$26
       cmp #$07
       bcc utfa_valid
       jmp utfa_checkrealsid  // out of range → checkrealsid fallback
utfa_valid:
       clc
       adc #$20               // 0-6 → $20-$26
       rts

//─────────────────────────────────────────────────────────────────────────────
// dbg_print_frame: print "Fn:$xxyy T=xx INT 8580 LO\n" etc.
// T byte: $83=UltiSID internal (INT), $85=external HW SID (EXT).
// After INT/EXT, looks up sptr_zp:sptr_zp1 in sid_list and appends curve name if UltiSID.
// Input: buf_zp=frame digit ASCII, sptr_zp/sptr_zp1=addr lo/hi, mptr_zp=T byte
// Trashes: A, X, Y, $FE/$FF, tmp2_zp
//─────────────────────────────────────────────────────────────────────────────
dbg_print_frame:
       lda #$46; jsr $FFD2            // 'F'
       lda buf_zp; jsr $FFD2          // '1' or '2'
       lda #$3A; jsr $FFD2            // ':'
       lda #$24; jsr $FFD2            // '$'
       lda sptr_zp1; jsr print_hex    // addr hi
       lda sptr_zp; jsr print_hex     // addr lo
       lda #<dbg_s_t_eq; sta $FE
       lda #>dbg_s_t_eq; sta $FF
       jsr dbg_str                    // " T="
       lda mptr_zp; jsr print_hex     // T=xx
       lda mptr_zp
       cmp #$83; beq dpf_int
       cmp #$85; bne dpf_lookup       // unknown → skip label, still do lookup
dpf_ext:
       lda #$20; jsr $FFD2            // ' '
       lda #$45; jsr $FFD2            // 'E'
       lda #$58; jsr $FFD2            // 'X'
       jmp dpf_t
dpf_int:
       lda #$20; jsr $FFD2            // ' '
       lda #$49; jsr $FFD2            // 'I'
       lda #$4E; jsr $FFD2            // 'N'
dpf_t:
       lda #$54; jsr $FFD2            // 'T'
dpf_lookup:
       // Search sid_list for sptr_zp:sptr_zp1; if found with UltiSID type, print curve name
       lda #$01; sta tmp2_zp
dpf_lk_lp:
       ldy tmp2_zp
       lda sid_list_h,y
       cmp sptr_zp1; bne dpf_lk_nx
       lda sid_list_l,y
       cmp sptr_zp;  bne dpf_lk_nx
       lda sid_list_t,y               // found: check UltiSID type range $20-$26
       cmp #$20; bcc dpf_lk_nx
       cmp #$27; bcs dpf_lk_nx
       lda #$20; jsr $FFD2            // ' '
       sec; sbc #$20                  // index 0-6
       asl; tax
       lda ultisid_str_lo,x
       ldy ultisid_str_hi,x
       jsr $AB1E                      // print curve name string
       jmp dpf_nl
dpf_lk_nx:
       ldy tmp2_zp
       cpy sidnum_zp
       beq dpf_nl                     // all slots checked → no match
       inc tmp2_zp
       jmp dpf_lk_lp
dpf_nl:
       lda #$0D; jsr $FFD2
       rts

//─────────────────────────────────────────────────────────────────────────────
// dbg_uci_query: issue UCI CTRL_CMD_GET_HWINFO ($04/$28/$01) and populate
// uci_resp[0..11]. Uses STATE-based polling. Trashes: A, X, Y
//─────────────────────────────────────────────────────────────────────────────
dbg_uci_query:
       lda #$04; sta $DF1D        // ControlTarget
       lda #$28; sta $DF1D        // CTRL_CMD_GET_HWINFO
       lda #$01; sta $DF1D        // device = 1
       lda #$01; sta $DF1C        // PUSH_CMD
       ldx #$00; ldy #$00
duq_poll:
       lda $DF1C
       and #$30                   // STATE bits 4:5
       cmp #$10                   // still Command Busy?
       bne duq_state_rdy
       dex; bne duq_poll
       dey; bne duq_poll
       rts                        // timeout: uci_resp unchanged
duq_state_rdy:
       lda $DF1C
       bpl duq_nodata             // bit 7 = DATA_AV; 0 = no data
       ldx #$00
duq_read:
       lda $DF1E; sta uci_resp,x; inx
       cpx #$16; beq duq_drain       // buffer full at 22 bytes → drain remaining
       lda $DF1C; bmi duq_read       // DATA_AV bit 7 set → more bytes to store
       jmp duq_status                // DATA_AV clear → FIFO empty, done
duq_drain:                           // buffer full: discard extra bytes until FIFO empty
       lda $DF1C; bpl duq_status     // DATA_AV clear → done
       lda $DF1E; jmp duq_drain      // discard byte, keep draining
duq_status:
       lda #$02; sta $DF1C           // DATA_ACC — acknowledge + reset UCI state to Idle
       lda $DF1F; sta uci_resp+22    // status after reset (should be $00 = Idle)
       rts
duq_nodata:
       lda #$02; sta $DF1C
       lda $DF1F; sta uci_resp+22
       rts

// Main screen UltiSID display strings
ultisid_8580_int: .text "8580 INT"; .byte 0
ultisid_6581_int: .text "6581 INT"; .byte 0

// eof


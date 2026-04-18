// =============================================================================
// test_suite.asm — Full SID Detector unit test suite  (32 tests)
// =============================================================================
// Covers every detection dispatch scenario in the sequential detection chain.
// Each test presets the relevant zero-page inputs, calls an embedded copy of
// the dispatch logic, and checks the returned result code.  No real SID chip
// or KERNAL side effects are required — all tests are self-contained.
//
// Sections:
//   S1  Machine type  (T01–T03)   za7 → C64 / C128 / TC64
//   S2  SIDFX         (T04–T05)   data1=$30/$31 → found / not found
//   S3  Swinsid/ARMSID(T06–T10)   data1+data2+data3 → Swinsid-U/ARM2SID/ARMSID/none
//   S4  FPGASID       (T11–T13)   data1=$06/$07/$F0 → 8580 / 6581 / none
//   S5  Real SID      (T14–T16)   data1=$01/$02/$F0 → 6581 / 8580 / none
//   S6  Second SID    (T17–T18)   data1=$10/$F0 → second SID / no sound
//   S7  ArithMean     (T19–T22)   pure arithmetic unit tests
//   S8  FPGA Stereo   (T23)       data1=$06 at $D500 → recorded in sid_list
//   S9  New chips     (T24–T27)   PDsid/$09 / BackSID/$0A / SKpico/$0B / KungFu/$0C
//   S10 ARM2SID SFX   (T28–T29)   emul_mode=$01 → SFX only / $02 → SID+SFX
//   S11 SKpico FM     (T30–T31)   skpico_fm=$04/$05 → FM Sound Expander at $DF00
//   S12 FM-YAM OPL2   (T32)       fmyam_detected=$01 → FM-YAM/OPL2 found at $DF40
//
// Pass count written to $07E8 on completion.
// 34 = all tests passed.
// =============================================================================

.encoding "petscii_upper"

// Zero-page registers (same addresses as siddetector.asm)
.const data1       = $A4
.const data2       = $A5
.const data3       = $A6
.const za7         = $A7   // machine type: $FF=C64, $FC=C128, other=TC64
.const zpArrayPtr  = $A2   // ArithMean array selector
.const sidnum_zp   = $F7   // number of SID chips found so far
.const sptr_zp     = $F9   // SID base address low byte
.const sptr_zp1    = $FA   // SID base address high byte

// Result codes returned by embedded dispatch routines
.const RES_NONE       = $00   // no chip matched at this stage
.const RES_C64        = $01
.const RES_C128       = $02
.const RES_TC64       = $03
.const RES_SIDFX_YES  = $04
.const RES_SIDFX_NO   = $05
.const RES_SWINSID_U  = $06
.const RES_ARM2SID    = $07
.const RES_ARMSID     = $08
.const RES_FPGA_8580  = $09
.const RES_FPGA_6581  = $0A
.const RES_SID_6581   = $0B
.const RES_SID_8580   = $0C
.const RES_SECOND_SID = $0D
.const RES_NO_SOUND   = $0E
.const RES_PDSID      = $0F
.const RES_BACKSID    = $10
.const RES_SIDKPIC    = $11
.const RES_KUNGFU     = $12
.const RES_ARM2SFX    = $13   // ARM2SID SFX-only mode (emul_mode=1)
.const RES_ARM2SFXSID = $14   // ARM2SID SFX+SID mode  (emul_mode=2)

// ARM2SID config variables (absolute addresses from siddetector.sym)
.const armsid_emul_mode = $5592  // bits[1:0]: 0=SID,1=SFX,2=SFX+SID
.const armsid_major_var = $5588  // firmware major (2=ARMSID, 3=ARM2SID)

// SIDKick-pico config variables (absolute addresses from siddetector.sym)
.const skpico_fm_var    = $55c1  // config[8] from checkskpico Phase 3: >=4 and <6 → FM at $DF00
.const RES_SKPICO_FM    = $15   // SIDKick-pico FM Sound Expander detected

// FM-YAM Sound Expander variables (absolute addresses from siddetector.sym)
.const fmyam_detected_var = $55c2  // 1 = OPL2 found at $DF00 via timer probe
.const RES_FMYAM          = $16   // FM-YAM / OPL2 Sound Expander at $DF00

// CBM SFX Sound Expander variables (absolute addresses from siddetector.sym)
// (sfxexp_detected_var / RES_SFXEXP removed in V1.4.22 — legacy $DE00 probe retired)

* = $0801
    .word $0801
    .word 0
    .byte $9e
    .text "2061"
    .byte 0
    .word 0

* = $080d

test_start:
    lda #$15
    sta $D018               // uppercase/graphics character set
    jsr $E544               // KERNAL: clear screen
    lda #0
    sta pass_count
    sta row_ctr

// ============================================================
// S1: MACHINE TYPE DISPATCH  (za7 → C64 / C128 / TC64)
// Mirrors check_cbmtype in siddetector.asm
// ============================================================

    // T01: za7=$FF → C64
    lda #$ff
    sta za7
    jsr dispatch_machine
    lda #RES_C64
    jsr assert_eq
    bne t01_fail
    lda #<str_t01_pass
    ldy #>str_t01_pass
    jsr show_result
    inc pass_count
    jmp t02
t01_fail:
    lda #<str_t01_fail
    ldy #>str_t01_fail
    jsr show_result

t02:
    // T02: za7=$FC → C128
    lda #$fc
    sta za7
    jsr dispatch_machine
    lda #RES_C128
    jsr assert_eq
    bne t02_fail
    lda #<str_t02_pass
    ldy #>str_t02_pass
    jsr show_result
    inc pass_count
    jmp t03
t02_fail:
    lda #<str_t02_fail
    ldy #>str_t02_fail
    jsr show_result

t03:
    // T03: za7=$2A (any non-FF/FC value) → TC64
    lda #$2a
    sta za7
    jsr dispatch_machine
    lda #RES_TC64
    jsr assert_eq
    bne t03_fail
    lda #<str_t03_pass
    ldy #>str_t03_pass
    jsr show_result
    inc pass_count
    jmp t04
t03_fail:
    lda #<str_t03_fail
    ldy #>str_t03_fail
    jsr show_result

// ============================================================
// S2: SIDFX DISPATCH  (data1=$30 → found, else → not found)
// Mirrors nosidfxl:/sidfxprint: in siddetector.asm
// ============================================================

t04:
    // T04: data1=$30 → SIDFX found
    lda #$30
    sta data1
    jsr dispatch_sidfx
    lda #RES_SIDFX_YES
    jsr assert_eq
    bne t04_fail
    lda #<str_t04_pass
    ldy #>str_t04_pass
    jsr show_result
    inc pass_count
    jmp t05
t04_fail:
    lda #<str_t04_fail
    ldy #>str_t04_fail
    jsr show_result

t05:
    // T05: data1=$31 → SIDFX not present
    lda #$31
    sta data1
    jsr dispatch_sidfx
    lda #RES_SIDFX_NO
    jsr assert_eq
    bne t05_fail
    lda #<str_t05_pass
    ldy #>str_t05_pass
    jsr show_result
    inc pass_count
    jmp t06
t05_fail:
    lda #<str_t05_fail
    ldy #>str_t05_fail
    jsr show_result

// ============================================================
// S3: SWINSID / ARMSID / ARM2SID DISPATCH
// Mirrors armsid:/armsidlo: in siddetector.asm
// ============================================================

t06:
    // T06: data1=$04 → Swinsid Ultimate  ('S' echo from D41B)
    lda #$04
    sta data1
    lda #$00
    sta data2
    sta data3
    jsr dispatch_armsid
    lda #RES_SWINSID_U
    jsr assert_eq
    bne t06_fail
    lda #<str_t06_pass
    ldy #>str_t06_pass
    jsr show_result
    inc pass_count
    jmp t07
t06_fail:
    lda #<str_t06_fail
    ldy #>str_t06_fail
    jsr show_result

t07:
    // T07: data1=$05 data2=$4F data3=$53 → ARM2SID  ('N','O','R')
    lda #$05
    sta data1
    lda #$4f
    sta data2
    lda #$53
    sta data3
    jsr dispatch_armsid
    lda #RES_ARM2SID
    jsr assert_eq
    bne t07_fail
    lda #<str_t07_pass
    ldy #>str_t07_pass
    jsr show_result
    inc pass_count
    jmp t08
t07_fail:
    lda #<str_t07_fail
    ldy #>str_t07_fail
    jsr show_result

t08:
    // T08: data1=$05 data2=$4F data3=$00 → ARMSID  ('N','O', not 'R')
    lda #$05
    sta data1
    lda #$4f
    sta data2
    lda #$00
    sta data3
    jsr dispatch_armsid
    lda #RES_ARMSID
    jsr assert_eq
    bne t08_fail
    lda #<str_t08_pass
    ldy #>str_t08_pass
    jsr show_result
    inc pass_count
    jmp t09
t08_fail:
    lda #<str_t08_fail
    ldy #>str_t08_fail
    jsr show_result

t09:
    // T09: data1=$05 data2=$00 → data2 not 'O' → no ARMSID match
    lda #$05
    sta data1
    lda #$00
    sta data2
    sta data3
    jsr dispatch_armsid
    lda #RES_NONE
    jsr assert_eq
    bne t09_fail
    lda #<str_t09_pass
    ldy #>str_t09_pass
    jsr show_result
    inc pass_count
    jmp t10
t09_fail:
    lda #<str_t09_fail
    ldy #>str_t09_fail
    jsr show_result

t10:
    // T10: data1=$F0 → no Swinsid/ARMSID match at all
    lda #$f0
    sta data1
    lda #$00
    sta data2
    sta data3
    jsr dispatch_armsid
    lda #RES_NONE
    jsr assert_eq
    bne t10_fail
    lda #<str_t10_pass
    ldy #>str_t10_pass
    jsr show_result
    inc pass_count
    jmp t11
t10_fail:
    lda #<str_t10_fail
    ldy #>str_t10_fail
    jsr show_result

// ============================================================
// S4: FPGASID DISPATCH  (data1=$06/$07 → 8580/6581 mode)
// Mirrors fpgasid:/fpgasidf_6581_l: in siddetector.asm
// ============================================================

t11:
    // T11: data1=$06 → FPGASID 8580 mode  (D41F=$3F after magic-cookie)
    lda #$06
    sta data1
    jsr dispatch_fpgasid
    lda #RES_FPGA_8580
    jsr assert_eq
    bne t11_fail
    lda #<str_t11_pass
    ldy #>str_t11_pass
    jsr show_result
    inc pass_count
    jmp t12
t11_fail:
    lda #<str_t11_fail
    ldy #>str_t11_fail
    jsr show_result

t12:
    // T12: data1=$07 → FPGASID 6581 mode  (D41F=$00 after magic-cookie)
    lda #$07
    sta data1
    jsr dispatch_fpgasid
    lda #RES_FPGA_6581
    jsr assert_eq
    bne t12_fail
    lda #<str_t12_pass
    ldy #>str_t12_pass
    jsr show_result
    inc pass_count
    jmp t13
t12_fail:
    lda #<str_t12_fail
    ldy #>str_t12_fail
    jsr show_result

t13:
    // T13: data1=$F0 → no FPGASID match → falls to real SID check
    lda #$f0
    sta data1
    jsr dispatch_fpgasid
    lda #RES_NONE
    jsr assert_eq
    bne t13_fail
    lda #<str_t13_pass
    ldy #>str_t13_pass
    jsr show_result
    inc pass_count
    jmp t14
t13_fail:
    lda #<str_t13_fail
    ldy #>str_t13_fail
    jsr show_result

// ============================================================
// S5: REAL SID DISPATCH  (data1=$01/$02 → 6581/8580)
// Mirrors checkphysical:/checkphysical_8580: in siddetector.asm
// ============================================================

t14:
    // T14: data1=$01 → real 6581 confirmed
    lda #$01
    sta data1
    jsr dispatch_real_sid
    lda #RES_SID_6581
    jsr assert_eq
    bne t14_fail
    lda #<str_t14_pass
    ldy #>str_t14_pass
    jsr show_result
    inc pass_count
    jmp t15
t14_fail:
    lda #<str_t14_fail
    ldy #>str_t14_fail
    jsr show_result

t15:
    // T15: data1=$02 → real 8580 confirmed
    lda #$02
    sta data1
    jsr dispatch_real_sid
    lda #RES_SID_8580
    jsr assert_eq
    bne t15_fail
    lda #<str_t15_pass
    ldy #>str_t15_pass
    jsr show_result
    inc pass_count
    jmp t16
t15_fail:
    lda #<str_t15_fail
    ldy #>str_t15_fail
    jsr show_result

t16:
    // T16: data1=$F0 → no real SID → falls to second SID scan
    lda #$f0
    sta data1
    jsr dispatch_real_sid
    lda #RES_NONE
    jsr assert_eq
    bne t16_fail
    lda #<str_t16_pass
    ldy #>str_t16_pass
    jsr show_result
    inc pass_count
    jmp t17
t16_fail:
    lda #<str_t16_fail
    ldy #>str_t16_fail
    jsr show_result

// ============================================================
// S6: SECOND SID / NO SOUND DISPATCH
// Mirrors checkphysical2:/nosound: in siddetector.asm
// data1=$10 (second SID found) → UNKNOWN SID
// anything else → NO SOUND  (swinmicro: immediately jmp nosound)
// ============================================================

t17:
    // T17: data1=$10 → second SID detected at a mirror address
    lda #$10
    sta data1
    jsr dispatch_second_nosound
    lda #RES_SECOND_SID
    jsr assert_eq
    bne t17_fail
    lda #<str_t17_pass
    ldy #>str_t17_pass
    jsr show_result
    inc pass_count
    jmp t18
t17_fail:
    lda #<str_t17_fail
    ldy #>str_t17_fail
    jsr show_result

t18:
    // T18: data1=$F0 → no SID at all → NO SOUND
    lda #$f0
    sta data1
    jsr dispatch_second_nosound
    lda #RES_NO_SOUND
    jsr assert_eq
    bne t18_fail
    lda #<str_t18_pass
    ldy #>str_t18_pass
    jsr show_result
    inc pass_count
    jmp t19
t18_fail:
    lda #<str_t18_fail
    ldy #>str_t18_fail
    jsr show_result

// ============================================================
// S7: ARITHMETICMEAN  (pure computation, no SID dependency)
// ============================================================

t19:
    // T19: mean([10, 20, 30]) = 20
    lda #1
    sta zpArrayPtr
    lda #3
    sta numInts
    lda #10
    sta arr1+0
    lda #20
    sta arr1+1
    lda #30
    sta arr1+2
    jsr calcMean
    lda calcResult
    cmp #20
    bne t19_fail
    lda #<str_t19_pass
    ldy #>str_t19_pass
    jsr show_result
    inc pass_count
    jmp t20
t19_fail:
    lda #<str_t19_fail
    ldy #>str_t19_fail
    jsr show_result

t20:
    // T20: mean([5, 5, 5, 5, 5, 5]) = 5
    lda #1
    sta zpArrayPtr
    lda #6
    sta numInts
    lda #5
    sta arr1+0
    sta arr1+1
    sta arr1+2
    sta arr1+3
    sta arr1+4
    sta arr1+5
    jsr calcMean
    lda calcResult
    cmp #5
    bne t20_fail
    lda #<str_t20_pass
    ldy #>str_t20_pass
    jsr show_result
    inc pass_count
    jmp t21
t20_fail:
    lda #<str_t20_fail
    ldy #>str_t20_fail
    jsr show_result

t21:
    // T21: mean([100, 50, 75, 25]) = 62  (250 / 4 = 62 integer)
    lda #2
    sta zpArrayPtr
    lda #4
    sta numInts
    lda #100
    sta arr2+0
    lda #50
    sta arr2+1
    lda #75
    sta arr2+2
    lda #25
    sta arr2+3
    jsr calcMean
    lda calcResult
    cmp #62
    bne t21_fail
    lda #<str_t21_pass
    ldy #>str_t21_pass
    jsr show_result
    inc pass_count
    jmp t22
t21_fail:
    lda #<str_t21_fail
    ldy #>str_t21_fail
    jsr show_result

t22:
    // T22: numInts = 0 → result = 0  (empty input guard)
    lda #1
    sta zpArrayPtr
    lda #0
    sta numInts
    jsr calcMean
    lda calcResult
    cmp #0
    bne t22_fail
    lda #<str_t22_pass
    ldy #>str_t22_pass
    jsr show_result
    inc pass_count
    jmp t23
t22_fail:
    lda #<str_t22_fail
    ldy #>str_t22_fail
    jsr show_result

// ============================================================
// S8: FPGA STEREO DISPATCH  (data1=$06 at $D500 → sid_list entry)
// Mirrors the s_s_ff "found SID" path in sidstereostart.
// Verifies that sidnum_zp is incremented and the address+type are
// recorded in test_sid_h/l/t when data1 < $10.
// ============================================================

t23:
    // T23: data1=$06 sptr=$D500 sidnum=0 → sid_list[1].h=$D5 .t=$06
    lda #$00
    sta sidnum_zp
    sta sptr_zp
    lda #$D5
    sta sptr_zp1
    lda #$06
    sta data1
    // zero the test sid tables
    ldx #$07
t23_clr:
    lda #$00
    sta test_sid_h,x
    sta test_sid_l,x
    sta test_sid_t,x
    dex
    bpl t23_clr
    jsr dispatch_fpga_stereo
    lda #RES_FPGA_8580
    jsr assert_eq
    bne t23_fail
    lda #<str_t23_pass
    ldy #>str_t23_pass
    jsr show_result
    inc pass_count
    jmp t24
t23_fail:
    lda #<str_t23_fail
    ldy #>str_t23_fail
    jsr show_result

// ============================================================
// S9: NEW CHIPS DISPATCH  (T24–T27)
// T24: PDsid     data1=$09 → RES_PDSID
// T25: BackSID   data1=$0A → RES_BACKSID
// T26: SIDKick-pico (8580)  data1=$0B → RES_SIDKPIC
// T27: KungFuSID data1=$0C → RES_KUNGFU
// ============================================================

t24:
    // T24: data1=$09 → PDsid
    lda #$09
    sta data1
    jsr dispatch_pdsid
    lda #RES_PDSID
    jsr assert_eq
    bne t24_fail
    lda #<str_t24_pass
    ldy #>str_t24_pass
    jsr show_result
    inc pass_count
    jmp t25
t24_fail:
    lda #<str_t24_fail
    ldy #>str_t24_fail
    jsr show_result

t25:
    // T25: data1=$0A → BackSID
    lda #$0A
    sta data1
    jsr dispatch_backsid
    lda #RES_BACKSID
    jsr assert_eq
    bne t25_fail
    lda #<str_t25_pass
    ldy #>str_t25_pass
    jsr show_result
    inc pass_count
    jmp t26
t25_fail:
    lda #<str_t25_fail
    ldy #>str_t25_fail
    jsr show_result

t26:
    // T26: data1=$0B → SIDKick-pico 8580
    lda #$0B
    sta data1
    jsr dispatch_sidkpic
    lda #RES_SIDKPIC
    jsr assert_eq
    bne t26_fail
    lda #<str_t26_pass
    ldy #>str_t26_pass
    jsr show_result
    inc pass_count
    jmp t27
t26_fail:
    lda #<str_t26_fail
    ldy #>str_t26_fail
    jsr show_result

t27:
    // T27: data1=$0C → KungFuSID
    lda #$0C
    sta data1
    jsr dispatch_kungfu
    lda #RES_KUNGFU
    jsr assert_eq
    bne t27_fail
    lda #<str_t27_pass
    ldy #>str_t27_pass
    jsr show_result
    inc pass_count
    jmp t28
t27_fail:
    lda #<str_t27_fail
    ldy #>str_t27_fail
    jsr show_result

// ============================================================
// S10: ARM2SID SFX MODE DISPATCH  (T28–T29)
// Mirrors emul_mode check in armsid: (siddetector.asm)
// T28: emul_mode=$01 (SFX only)    → RES_ARM2SFX
// T29: emul_mode=$02 (SFX+SID)     → RES_ARM2SFXSID
// ============================================================

t28:
    // T28: armsid_emul_mode=$01 → SFX only
    lda #$03
    sta armsid_major_var        // ARM2SID major = 3
    lda #$01
    sta armsid_emul_mode
    jsr dispatch_arm2sid_sfx
    lda #RES_ARM2SFX
    jsr assert_eq
    bne t28_fail
    lda #<str_t28_pass
    ldy #>str_t28_pass
    jsr show_result
    inc pass_count
    jmp t29
t28_fail:
    lda #<str_t28_fail
    ldy #>str_t28_fail
    jsr show_result

t29:
    // T29: armsid_emul_mode=$02 → SFX+SID
    lda #$03
    sta armsid_major_var
    lda #$02
    sta armsid_emul_mode
    jsr dispatch_arm2sid_sfx
    lda #RES_ARM2SFXSID
    jsr assert_eq
    bne t29_fail
    lda #<str_t29_pass
    ldy #>str_t29_pass
    jsr show_result
    inc pass_count
    jmp t30
t29_fail:
    lda #<str_t29_fail
    ldy #>str_t29_fail
    jsr show_result

// ============================================================
// S11: SIDKICK-PICO FM SOUND EXPANDER DISPATCH  (T30)
// Mirrors skpico_fm check in cskp_fm_disp (siddetector.asm)
// T30: skpico_fm=$04 (FM_ENABLE=2)  → RES_SKPICO_FM
// ============================================================

t30:
    // T30: skpico_fm=$04 → FM Sound Expander active
    lda #$04
    sta skpico_fm_var
    jsr dispatch_skpico_fm
    lda #RES_SKPICO_FM
    jsr assert_eq
    bne t30_fail
    lda #<str_t30_pass
    ldy #>str_t30_pass
    jsr show_result
    inc pass_count
    jmp t31
t30_fail:
    lda #<str_t30_fail
    ldy #>str_t30_fail
    jsr show_result

// ============================================================
// S11 continued: SKpico FM — second mode (T31)
// T31: skpico_fm=$05 (FM_ENABLE=1) also triggers FM detection
// ============================================================

t31:
    // T31: skpico_fm=$05 → FM still active (FM_ENABLE = 6-5 = 1 > 0)
    lda #$05
    sta skpico_fm_var
    jsr dispatch_skpico_fm
    lda #RES_SKPICO_FM
    jsr assert_eq
    bne t31_fail
    lda #<str_t31_pass
    ldy #>str_t31_pass
    jsr show_result
    inc pass_count
    jmp t32
t31_fail:
    lda #<str_t31_fail
    ldy #>str_t31_fail
    jsr show_result

// ============================================================
// S12: FM-YAM SOUND EXPANDER DISPATCH  (T32)
// Mirrors fmyam_detected check in backsid_post_fixup (siddetector.asm)
// T32: fmyam_detected=$01 → RES_FMYAM
// ============================================================

t32:
    // T32: fmyam_detected=$01 → FM-YAM/OPL2 found
    lda #$01
    sta fmyam_detected_var
    jsr dispatch_fmyam
    lda #RES_FMYAM
    jsr assert_eq
    bne t32_fail
    lda #<str_t32_pass
    ldy #>str_t32_pass
    jsr show_result
    inc pass_count
    jmp test_done
t32_fail:
    lda #<str_t32_fail
    ldy #>str_t32_fail
    jsr show_result

// (T33/T34 CBM SFX dispatch tests removed in V1.4.22 — the live
//  $DE00 probe they mirrored was retired.)

// ============================================================
// SUMMARY
// ============================================================
test_done:
    lda #<str_divider
    ldy #>str_divider
    jsr show_result
    lda pass_count
    cmp #32
    bne td_fail
    lda #<str_all_pass
    ldy #>str_all_pass
    jsr show_result
    jmp td_done
td_fail:
    lda #<str_some_fail
    ldy #>str_some_fail
    jsr show_result
td_done:
    // Write pass_count to $07E8 (off-screen scratch RAM, not in visible screen area)
    // BEFORE the spin loop so the value is stable when VICE breakpoint fires.
    lda pass_count
    sta $07E8
td_spin:
    jmp td_spin             // spin; VICE monitor breaks here: mem $07E8

// ============================================================
// assert_eq: compare dispatch_result against A
// Entry: A = expected value
// Returns: Z=1 (BEQ taken) if equal, Z=0 (BNE taken) if not equal
// ============================================================
assert_eq:
    cmp dispatch_result
    rts

// ============================================================
// show_result: print zero-terminated PETSCII string on next row
// Entry: A = lo byte, Y = hi byte of string address
// ============================================================
show_result:
    sta str_ptr_lo
    sty str_ptr_hi
    ldx row_ctr
    ldy #0
    clc
    jsr $E50C               // KERNAL PLOT: position cursor (X=row, Y=col, C=0)
    inc row_ctr
    lda str_ptr_lo
    ldy str_ptr_hi
    jsr $AB1E               // KERNAL STROUT: print zero-terminated string
    rts

str_ptr_lo: .byte 0
str_ptr_hi: .byte 0

// ============================================================
// DISPATCH ROUTINES
// Each is a direct copy of the branch logic in siddetector.asm
// with all jsr $AB1E / jsr $E50C / jmp end replaced by a
// result-code write to dispatch_result.
// ============================================================

// ---- dispatch_machine ----------------------------------------
// Source: check_cbmtype (lines ~184-202 in siddetector.asm)
// za7=$FF → RES_C64 | za7=$FC → RES_C128 | else → RES_TC64
dispatch_machine:
    lda za7
    cmp #$ff
    bne dmach_not_c64
    lda #RES_C64
    sta dispatch_result
    rts
dmach_not_c64:
    cmp #$fc
    bne dmach_tc64
    lda #RES_C128
    sta dispatch_result
    rts
dmach_tc64:
    lda #RES_TC64
    sta dispatch_result
    rts

// ---- dispatch_sidfx ------------------------------------------
// Source: nosidfxl:/sidfxprint: (lines ~222-242 in siddetector.asm)
// data1=$30 → RES_SIDFX_YES | else → RES_SIDFX_NO
dispatch_sidfx:
    ldx data1
    cpx #$30
    bne dsfx_no
    lda #RES_SIDFX_YES
    sta dispatch_result
    rts
dsfx_no:
    lda #RES_SIDFX_NO
    sta dispatch_result
    rts

// ---- dispatch_armsid -----------------------------------------
// Source: armsid:/armsidlo: (lines ~264-300 in siddetector.asm)
// data1=$04              → RES_SWINSID_U
// data1=$05+d2=$4F+d3=$53 → RES_ARM2SID
// data1=$05+d2=$4F+d3≠$53 → RES_ARMSID
// else                   → RES_NONE
dispatch_armsid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$04                // Swinsid Ultimate: 'S' echo in D41B
    bne darm_check05
    lda #RES_SWINSID_U
    sta dispatch_result
    rts
darm_check05:
    cpx #$05                // ARMSID family: 'N' echo in D41B
    bne darm_exit           // not $04 or $05 → no match
    ldx data2
    cpx #$4f                // 'O' in D41C required for both ARMSID variants
    bne darm_exit
    ldx data3
    cpx #$53                // 'R' in D41D → ARM2SID; else → plain ARMSID
    bne darm_plain
    lda #RES_ARM2SID
    sta dispatch_result
    rts
darm_plain:
    lda #RES_ARMSID
    sta dispatch_result
darm_exit:
    rts

// ---- dispatch_fpgasid ----------------------------------------
// Source: fpgasid:/fpgasidf_6581_l: (lines ~305-335 in siddetector.asm)
// data1=$06 → RES_FPGA_8580 | data1=$07 → RES_FPGA_6581 | else → RES_NONE
dispatch_fpgasid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$06                // FPGASID 8580: D41F=$3F after magic-cookie config
    bne dfpga_6581
    lda #RES_FPGA_8580
    sta dispatch_result
    rts
dfpga_6581:
    cpx #$07                // FPGASID 6581: D41F=$00 after magic-cookie config
    bne dfpga_exit
    lda #RES_FPGA_6581
    sta dispatch_result
dfpga_exit:
    rts

// ---- dispatch_real_sid ---------------------------------------
// Source: checkphysical:/checkphysical_8580: (lines ~340-370 in siddetector.asm)
// data1=$01 → RES_SID_6581 | data1=$02 → RES_SID_8580 | else → RES_NONE
dispatch_real_sid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$01                // 6581 confirmed via sawtooth D41B readback
    bne dreal_8580
    lda #RES_SID_6581
    sta dispatch_result
    rts
dreal_8580:
    cpx #$02                // 8580 confirmed
    bne dreal_exit
    lda #RES_SID_8580
    sta dispatch_result
dreal_exit:
    rts

// ---- dispatch_second_nosound ---------------------------------
// Source: checkphysical2:/swinmicro:/nosound: (lines ~372-415 in siddetector.asm)
// data1=$10 → RES_SECOND_SID | else → RES_NO_SOUND
// (swinmicro: is disabled via unconditional jmp nosound in the real code)
dispatch_second_nosound:
    ldx data1
    cpx #$10                // noise-mirror scan found a second SID slot
    bne dsn_nosound
    lda #RES_SECOND_SID
    sta dispatch_result
    rts
dsn_nosound:
    lda #RES_NO_SOUND
    sta dispatch_result
    rts

// ---- dispatch_fpga_stereo ------------------------------------
// Mirrors the s_s_ff "found SID" path in sidstereostart for FPGASID.
// Entry: data1, sptr_zp, sptr_zp1, sidnum_zp pre-loaded by test.
// If data1 < $10: increments sidnum_zp, writes into test_sid_h/l/t[sidnum],
//   then sets dispatch_result = RES_FPGA_8580 if test_sid_h[1]=$D5 and
//   test_sid_t[1]=$06 (both bytes correct → stereo entry recorded properly).
// If data1 >= $10: dispatch_result = RES_NONE.
dispatch_fpga_stereo:
    lda #RES_NONE
    sta dispatch_result
    lda data1
    cmp #$10
    bcs dfps_exit           // data1 >= $10 → not found, exit
    // add entry to test_sid tables (mirrors s_s_add in sidstereostart)
    ldx sidnum_zp
    inx
    stx sidnum_zp
    lda data1
    sta test_sid_t,x
    lda sptr_zp
    sta test_sid_l,x
    lda sptr_zp1
    sta test_sid_h,x
    // verify: sidnum_zp=1, test_sid_h[1]=$D5, test_sid_t[1]=$06
    lda sidnum_zp
    cmp #$01
    bne dfps_exit
    lda test_sid_h+1
    cmp #$D5
    bne dfps_exit
    lda test_sid_t+1
    cmp #$06
    bne dfps_exit
    lda #RES_FPGA_8580
    sta dispatch_result
dfps_exit:
    rts

// ---- dispatch_pdsid ------------------------------------------
// Source: checkpdsid_step (siddetector.asm ~line 533)
// data1=$09 → RES_PDSID | else → RES_NONE
dispatch_pdsid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$09                // PDsid: 'S' echo in D41E
    bne dpds_exit
    lda #RES_PDSID
    sta dispatch_result
dpds_exit:
    rts

// ---- dispatch_backsid ----------------------------------------
// Source: checkbacksid_step (siddetector.asm ~line 555)
// data1=$0A → RES_BACKSID | else → RES_NONE
dispatch_backsid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$0A                // BackSID: D41F echoes $42
    bne dbsid_exit
    lda #RES_BACKSID
    sta dispatch_result
dbsid_exit:
    rts

// ---- dispatch_sidkpic ----------------------------------------
// Source: checkskpico_step (siddetector.asm ~line 577)
// data1=$0B (8580) or $0E (6581) → RES_SIDKPIC | else → RES_NONE
dispatch_sidkpic:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$0B                // SIDKick-pico 8580: 'S'+'K' VERSION_STR
    beq dskp_match
    cpx #$0E                // SIDKick-pico 6581
    bne dskp_exit
dskp_match:
    lda #RES_SIDKPIC
    sta dispatch_result
dskp_exit:
    rts

// ---- dispatch_kungfu -----------------------------------------
// Source: swinmicro (siddetector.asm ~line 730)
// data1=$0C → RES_KUNGFU | else → RES_NONE
dispatch_kungfu:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$0C                // KungFuSID: $5A ACK from D41D
    bne dkfu_exit
    lda #RES_KUNGFU
    sta dispatch_result
dkfu_exit:
    rts

// ---- dispatch_fmyam ------------------------------------------
// Source: fmyam_detected check in backsid_post_fixup (siddetector.asm)
// Reads fmyam_detected (absolute $55C2): non-zero → RES_FMYAM
dispatch_fmyam:
    lda #RES_NONE
    sta dispatch_result
    lda fmyam_detected_var
    beq dfmy_exit           // $00 → not found
    lda #RES_FMYAM
    sta dispatch_result
dfmy_exit:
    rts

// (dispatch_sfxexp removed in V1.4.22 along with the $DE00 probe.)

// ---- dispatch_skpico_fm --------------------------------------
// Source: cskp_fm_disp in siddetector.asm
// Reads skpico_fm (absolute $5545):
//   >= 4 and < 6 → RES_SKPICO_FM (FM Sound Expander active)
//   else → RES_NONE
dispatch_skpico_fm:
    lda #RES_NONE
    sta dispatch_result
    lda skpico_fm_var
    cmp #$04
    bcs dsfm_chk_max    // >= 4
    rts                 // < 4: no FM
dsfm_chk_max:
    cmp #$06
    bcc dsfm_found      // 4 or 5: FM active
    rts                 // >= 6: FM_ENABLE=0
dsfm_found:
    lda #RES_SKPICO_FM
    sta dispatch_result
    rts

// ---- dispatch_arm2sid_sfx ------------------------------------
// Source: armsid: SFX mode check (siddetector.asm)
// Reads armsid_emul_mode (absolute $5375) bits[1:0]:
//   1 → RES_ARM2SFX    (SFX only)
//   2 → RES_ARM2SFXSID (SFX+SID)
//   else → RES_NONE
dispatch_arm2sid_sfx:
    lda #RES_NONE
    sta dispatch_result
    lda armsid_emul_mode
    and #$03
    cmp #$01
    bne dasfx_chk2
    lda #RES_ARM2SFX
    sta dispatch_result
    rts
dasfx_chk2:
    cmp #$02
    bne dasfx_exit
    lda #RES_ARM2SFXSID
    sta dispatch_result
dasfx_exit:
    rts

// ============================================================
// calcMean — embedded copy of ArithmeticMean from siddetector.asm
// Reads: zpArrayPtr ($A2), numInts, arr1/arr2
// Writes: calcResult
// ============================================================
calcMean:
    pha
    tya
    pha
    lda #0
    sta tmp16
    sta tmp16+1
    ldy numInts
    beq cmean_done          // numInts=0 → skip, result=0
    dey
cmean_add:
    lda zpArrayPtr
    cmp #1
    beq cmean_arr1
    lda arr2,y              // zpArrayPtr=2 (or any other)
    jmp cmean_acc
cmean_arr1:
    lda arr1,y
cmean_acc:
    clc
    adc tmp16
    sta tmp16
    lda tmp16+1
    adc #0
    sta tmp16+1
    dey
    cpy #$ff
    bne cmean_add
    ldy #$ff
cmean_div:
    lda tmp16
    sec
    sbc numInts
    sta tmp16
    lda tmp16+1
    sbc #0
    sta tmp16+1
    iny
    bcs cmean_div
cmean_done:
    sty calcResult
    pla
    tay
    pla
    rts

// ============================================================
// Data
// ============================================================
dispatch_result: .byte 0
pass_count:      .byte 0
row_ctr:         .byte 0
numInts:         .byte 0
calcResult:      .byte 0
tmp16:           .byte 0, 0
arr1:            .byte 0,0,0,0,0,0,0,0,0,0,0
arr2:            .byte 0,0,0,0,0,0,0,0,0,0,0
test_sid_h:      .byte 0,0,0,0,0,0,0,0   // sid_list high-byte scratch (slots 0-7)
test_sid_l:      .byte 0,0,0,0,0,0,0,0   // sid_list low-byte scratch
test_sid_t:      .byte 0,0,0,0,0,0,0,0   // sid_list type scratch

// ============================================================
// Strings  (zero-terminated PETSCII uppercase, max 39 chars)
// ============================================================
str_t01_pass: .text "T01 PASS: ZA7=$FF -> C64"
              .byte 0
str_t01_fail: .text "T01 FAIL: ZA7=$FF -> C64"
              .byte 0
str_t02_pass: .text "T02 PASS: ZA7=$FC -> C128"
              .byte 0
str_t02_fail: .text "T02 FAIL: ZA7=$FC -> C128"
              .byte 0
str_t03_pass: .text "T03 PASS: ZA7=$2A -> TC64"
              .byte 0
str_t03_fail: .text "T03 FAIL: ZA7=$2A -> TC64"
              .byte 0
str_t04_pass: .text "T04 PASS: D1=$30 -> SIDFX FOUND"
              .byte 0
str_t04_fail: .text "T04 FAIL: D1=$30 -> SIDFX FOUND"
              .byte 0
str_t05_pass: .text "T05 PASS: D1=$31 -> NO SIDFX"
              .byte 0
str_t05_fail: .text "T05 FAIL: D1=$31 -> NO SIDFX"
              .byte 0
str_t06_pass: .text "T06 PASS: D1=$04 -> SWINSID ULTIMATE"
              .byte 0
str_t06_fail: .text "T06 FAIL: D1=$04 -> SWINSID ULTIMATE"
              .byte 0
str_t07_pass: .text "T07 PASS: $05/$4F/$53 -> ARM2SID"
              .byte 0
str_t07_fail: .text "T07 FAIL: $05/$4F/$53 -> ARM2SID"
              .byte 0
str_t08_pass: .text "T08 PASS: $05/$4F/$00 -> ARMSID"
              .byte 0
str_t08_fail: .text "T08 FAIL: $05/$4F/$00 -> ARMSID"
              .byte 0
str_t09_pass: .text "T09 PASS: D1=$05 D2=$00 -> NO MATCH"
              .byte 0
str_t09_fail: .text "T09 FAIL: D1=$05 D2=$00 -> NO MATCH"
              .byte 0
str_t10_pass: .text "T10 PASS: D1=$F0 -> NO MATCH"
              .byte 0
str_t10_fail: .text "T10 FAIL: D1=$F0 -> NO MATCH"
              .byte 0
str_t11_pass: .text "T11 PASS: D1=$06 -> FPGASID 8580"
              .byte 0
str_t11_fail: .text "T11 FAIL: D1=$06 -> FPGASID 8580"
              .byte 0
str_t12_pass: .text "T12 PASS: D1=$07 -> FPGASID 6581"
              .byte 0
str_t12_fail: .text "T12 FAIL: D1=$07 -> FPGASID 6581"
              .byte 0
str_t13_pass: .text "T13 PASS: D1=$F0 -> NO FPGASID"
              .byte 0
str_t13_fail: .text "T13 FAIL: D1=$F0 -> NO FPGASID"
              .byte 0
str_t14_pass: .text "T14 PASS: D1=$01 -> 6581 FOUND"
              .byte 0
str_t14_fail: .text "T14 FAIL: D1=$01 -> 6581 FOUND"
              .byte 0
str_t15_pass: .text "T15 PASS: D1=$02 -> 8580 FOUND"
              .byte 0
str_t15_fail: .text "T15 FAIL: D1=$02 -> 8580 FOUND"
              .byte 0
str_t16_pass: .text "T16 PASS: D1=$F0 -> NO REAL SID"
              .byte 0
str_t16_fail: .text "T16 FAIL: D1=$F0 -> NO REAL SID"
              .byte 0
str_t17_pass: .text "T17 PASS: D1=$10 -> SECOND SID"
              .byte 0
str_t17_fail: .text "T17 FAIL: D1=$10 -> SECOND SID"
              .byte 0
str_t18_pass: .text "T18 PASS: D1=$F0 -> NO SOUND"
              .byte 0
str_t18_fail: .text "T18 FAIL: D1=$F0 -> NO SOUND"
              .byte 0
str_t19_pass: .text "T19 PASS: MEAN(10,20,30)=20"
              .byte 0
str_t19_fail: .text "T19 FAIL: MEAN(10,20,30)=20"
              .byte 0
str_t20_pass: .text "T20 PASS: MEAN(5X6)=5"
              .byte 0
str_t20_fail: .text "T20 FAIL: MEAN(5X6)=5"
              .byte 0
str_t21_pass: .text "T21 PASS: MEAN(100,50,75,25)=62"
              .byte 0
str_t21_fail: .text "T21 FAIL: MEAN(100,50,75,25)=62"
              .byte 0
str_t22_pass: .text "T22 PASS: MEAN(EMPTY)=0"
              .byte 0
str_t22_fail: .text "T22 FAIL: MEAN(EMPTY)=0"
              .byte 0
str_t23_pass: .text "T23 PASS: FPGA $D500 -> SID_LIST[1]"
              .byte 0
str_t23_fail: .text "T23 FAIL: FPGA $D500 -> SID_LIST[1]"
              .byte 0
str_t24_pass: .text "T24 PASS: D1=$09 -> PDSID"
              .byte 0
str_t24_fail: .text "T24 FAIL: D1=$09 -> PDSID"
              .byte 0
str_t25_pass: .text "T25 PASS: D1=$0A -> BACKSID"
              .byte 0
str_t25_fail: .text "T25 FAIL: D1=$0A -> BACKSID"
              .byte 0
str_t26_pass: .text "T26 PASS: D1=$0B -> SIDKICK-PICO"
              .byte 0
str_t26_fail: .text "T26 FAIL: D1=$0B -> SIDKICK-PICO"
              .byte 0
str_t27_pass: .text "T27 PASS: D1=$0C -> KUNGFUSID"
              .byte 0
str_t27_fail: .text "T27 FAIL: D1=$0C -> KUNGFUSID"
              .byte 0
str_t28_pass: .text "T28 PASS: EMUL=$01 -> SFX ONLY"
              .byte 0
str_t28_fail: .text "T28 FAIL: EMUL=$01 -> SFX ONLY"
              .byte 0
str_t29_pass: .text "T29 PASS: EMUL=$02 -> SID+SFX"
              .byte 0
str_t29_fail: .text "T29 FAIL: EMUL=$02 -> SID+SFX"
              .byte 0
str_t30_pass: .text "T30 PASS: FM=$04 -> SKPICO FM"
              .byte 0
str_t30_fail: .text "T30 FAIL: FM=$04 -> SKPICO FM"
              .byte 0
str_t31_pass: .text "T31 PASS: FM=$05 -> SKPICO FM"
              .byte 0
str_t31_fail: .text "T31 FAIL: FM=$05 -> SKPICO FM"
              .byte 0
str_t32_pass: .text "T32 PASS: FMYAM=$01 -> FM-YAM"
              .byte 0
str_t32_fail: .text "T32 FAIL: FMYAM=$01 -> FM-YAM"
              .byte 0
str_divider:  .text "--------------------------------------"
              .byte 0
str_all_pass: .text "ALL 32 TESTS PASSED"
              .byte 0
str_some_fail:.text "SOME TESTS FAILED - CHECK ABOVE"
              .byte 0

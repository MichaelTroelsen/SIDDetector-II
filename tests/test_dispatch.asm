// =============================================================================
// test_dispatch.asm — Unit tests for ARMSID, ARM2SID and FPGASID dispatch logic
// =============================================================================
// Tests the branch conditions that map data1/data2/data3 register-echo values
// to chip identification results.  The dispatch routines embedded here are
// direct copies of the logic in siddetector.asm (labels armsid:/fpgasid:),
// with jsr $AB1E / jsr $E50C replaced by a result-code write so the tests
// run without needing real SID hardware or KERNAL side effects.
//
// Test cases:
//   ARMSID / Swinsid dispatch (dispatch_armsid):
//     T1  data1=$04                    → SWINSID ULTIMATE
//     T2  data1=$05  data2=$4F  data3=$53  → ARM2SID
//     T3  data1=$05  data2=$4F  data3=$00  → ARMSID
//     T4  data1=$05  data2=$00  data3=$00  → NO MATCH (falls to FPGASID)
//     T5  data1=$F0                    → NO MATCH (falls to FPGASID)
//
//   FPGASID dispatch (dispatch_fpgasid):
//     T6  data1=$06  → FPGASID 8580
//     T7  data1=$07  → FPGASID 6581
//     T8  data1=$F0  → NO MATCH (falls to real-SID check)
//
// Pass count written to $0600.
// =============================================================================

.encoding "petscii_upper"

// Zero-page detection scratch (same addresses as siddetector.asm)
.const data1 = $A4
.const data2 = $A5
.const data3 = $A6

// Result codes returned by the embedded dispatch routines
.const RES_NONE       = $00   // no chip matched — fell through
.const RES_SWINSID_U  = $01   // data1=$04
.const RES_ARM2SID    = $02   // data1=$05, data2=$4F, data3=$53
.const RES_ARMSID     = $03   // data1=$05, data2=$4F, data3 != $53
.const RES_FPGA_8580  = $04   // data1=$06
.const RES_FPGA_6581  = $05   // data1=$07

* = $0801
    .word $0801
    .word 0
    .byte $9e
    .text "2061"
    .byte 0
    .word 0

* = $080d

// ------------------------------------------------------------
// ENTRY
// ------------------------------------------------------------
test_start:
    lda #$15
    sta $D018           // uppercase character set
    jsr $E544           // clear screen
    lda #0
    sta pass_count
    sta row_ctr

    // ==== ARMSID / SWINSID DISPATCH TESTS ====

    // T1: data1=$04 → Swinsid Ultimate
    lda #$04
    sta data1
    lda #$00
    sta data2
    sta data3
    jsr dispatch_armsid
    lda dispatch_result
    cmp #RES_SWINSID_U
    bne t1_fail
    lda #<str_t1_pass
    ldy #>str_t1_pass
    jsr show_result
    inc pass_count
    jmp t2
t1_fail:
    lda #<str_t1_fail
    ldy #>str_t1_fail
    jsr show_result

t2:
    // T2: data1=$05, data2=$4F, data3=$53 → ARM2SID
    lda #$05
    sta data1
    lda #$4f
    sta data2
    lda #$53
    sta data3
    jsr dispatch_armsid
    lda dispatch_result
    cmp #RES_ARM2SID
    bne t2_fail
    lda #<str_t2_pass
    ldy #>str_t2_pass
    jsr show_result
    inc pass_count
    jmp t3
t2_fail:
    lda #<str_t2_fail
    ldy #>str_t2_fail
    jsr show_result

t3:
    // T3: data1=$05, data2=$4F, data3=$00 → plain ARMSID
    lda #$05
    sta data1
    lda #$4f
    sta data2
    lda #$00
    sta data3
    jsr dispatch_armsid
    lda dispatch_result
    cmp #RES_ARMSID
    bne t3_fail
    lda #<str_t3_pass
    ldy #>str_t3_pass
    jsr show_result
    inc pass_count
    jmp t4
t3_fail:
    lda #<str_t3_fail
    ldy #>str_t3_fail
    jsr show_result

t4:
    // T4: data1=$05, data2=$00 → data2 != 'O' so no match (falls to FPGASID)
    lda #$05
    sta data1
    lda #$00
    sta data2
    sta data3
    jsr dispatch_armsid
    lda dispatch_result
    cmp #RES_NONE
    bne t4_fail
    lda #<str_t4_pass
    ldy #>str_t4_pass
    jsr show_result
    inc pass_count
    jmp t5
t4_fail:
    lda #<str_t4_fail
    ldy #>str_t4_fail
    jsr show_result

t5:
    // T5: data1=$F0 → no ARMSID match at all
    lda #$f0
    sta data1
    lda #$00
    sta data2
    sta data3
    jsr dispatch_armsid
    lda dispatch_result
    cmp #RES_NONE
    bne t5_fail
    lda #<str_t5_pass
    ldy #>str_t5_pass
    jsr show_result
    inc pass_count
    jmp t6
t5_fail:
    lda #<str_t5_fail
    ldy #>str_t5_fail
    jsr show_result

    // ==== FPGASID DISPATCH TESTS ====

t6:
    // T6: data1=$06 → FPGASID 8580
    lda #$06
    sta data1
    jsr dispatch_fpgasid
    lda dispatch_result
    cmp #RES_FPGA_8580
    bne t6_fail
    lda #<str_t6_pass
    ldy #>str_t6_pass
    jsr show_result
    inc pass_count
    jmp t7
t6_fail:
    lda #<str_t6_fail
    ldy #>str_t6_fail
    jsr show_result

t7:
    // T7: data1=$07 → FPGASID 6581
    lda #$07
    sta data1
    jsr dispatch_fpgasid
    lda dispatch_result
    cmp #RES_FPGA_6581
    bne t7_fail
    lda #<str_t7_pass
    ldy #>str_t7_pass
    jsr show_result
    inc pass_count
    jmp t8
t7_fail:
    lda #<str_t7_fail
    ldy #>str_t7_fail
    jsr show_result

t8:
    // T8: data1=$F0 → no FPGASID match
    lda #$f0
    sta data1
    jsr dispatch_fpgasid
    lda dispatch_result
    cmp #RES_NONE
    bne t8_fail
    lda #<str_t8_pass
    ldy #>str_t8_pass
    jsr show_result
    inc pass_count
    jmp test_done
t8_fail:
    lda #<str_t8_fail
    ldy #>str_t8_fail
    jsr show_result

// ------------------------------------------------------------
// SUMMARY
// ------------------------------------------------------------
test_done:
    lda pass_count
    sta $0600           // $0600 = pass count; 8 means all passed
    lda #<str_divider
    ldy #>str_divider
    jsr show_result
    lda pass_count
    cmp #8
    bne td_fail
    lda #<str_all_pass
    ldy #>str_all_pass
    jsr show_result
    jmp td_spin
td_fail:
    lda #<str_some_fail
    ldy #>str_some_fail
    jsr show_result
td_spin:
    jmp td_spin         // spin; VICE monitor can break here, read $0600

// ------------------------------------------------------------
// show_result: print zero-terminated string on next screen row
// Entry: A = lo, Y = hi of string address
// ------------------------------------------------------------
show_result:
    sta str_ptr_lo
    sty str_ptr_hi
    ldx row_ctr
    ldy #0
    clc
    jsr $E50C           // KERNAL PLOT: set cursor (X=row, Y=col, C=0)
    inc row_ctr
    lda str_ptr_lo
    ldy str_ptr_hi
    jsr $AB1E           // KERNAL STROUT: print zero-terminated string
    rts

str_ptr_lo: .byte 0
str_ptr_hi: .byte 0

// ------------------------------------------------------------
// dispatch_armsid
// Mirrors the armsid:/armsidlo: branch logic from siddetector.asm.
// Reads data1, data2, data3 from zero-page; writes dispatch_result.
//
//   data1=$04                     → RES_SWINSID_U
//   data1=$05, data2=$4F, data3=$53  → RES_ARM2SID
//   data1=$05, data2=$4F, data3≠$53 → RES_ARMSID
//   anything else                 → RES_NONE (caller proceeds to FPGASID)
// ------------------------------------------------------------
dispatch_armsid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$04            // Swinsid Ultimate: data1='S' code
    bne da_check05
    lda #RES_SWINSID_U
    sta dispatch_result
    rts
da_check05:
    cpx #$05            // ARMSID family: data1='N' code
    bne da_exit         // no match → RES_NONE
    ldx data2
    cpx #$4f            // data2 must be 'O' for both ARMSID variants
    bne da_exit         // no match → RES_NONE
    ldx data3
    cpx #$53            // data3='R' → ARM2SID; else plain ARMSID
    bne da_plain_armsid
    lda #RES_ARM2SID
    sta dispatch_result
    rts
da_plain_armsid:
    lda #RES_ARMSID
    sta dispatch_result
da_exit:
    rts

// ------------------------------------------------------------
// dispatch_fpgasid
// Mirrors the fpgasid:/fpgasidf_6581_l: branch logic from siddetector.asm.
// Reads data1 from zero-page (set by checkfpgasid); writes dispatch_result.
//
//   data1=$06 → RES_FPGA_8580
//   data1=$07 → RES_FPGA_6581
//   anything else → RES_NONE
// ------------------------------------------------------------
dispatch_fpgasid:
    lda #RES_NONE
    sta dispatch_result
    ldx data1
    cpx #$06            // FPGASID 8580 mode
    bne df_check07
    lda #RES_FPGA_8580
    sta dispatch_result
    rts
df_check07:
    cpx #$07            // FPGASID 6581 mode
    bne df_exit
    lda #RES_FPGA_6581
    sta dispatch_result
df_exit:
    rts

// ------------------------------------------------------------
// Data
// ------------------------------------------------------------
dispatch_result: .byte 0
pass_count:      .byte 0
row_ctr:         .byte 0

// ------------------------------------------------------------
// Strings (zero-terminated PETSCII uppercase, max 39 chars)
// ------------------------------------------------------------
str_t1_pass: .text "T1 PASS: D1=$04 -> SWINSID ULTIMATE"
             .byte 0
str_t1_fail: .text "T1 FAIL: D1=$04 -> SWINSID ULTIMATE"
             .byte 0
str_t2_pass: .text "T2 PASS: D1=$05 D2=$4F D3=$53 -> ARM2SID"
             .byte 0
str_t2_fail: .text "T2 FAIL: D1=$05 D2=$4F D3=$53 -> ARM2SID"
             .byte 0
str_t3_pass: .text "T3 PASS: D1=$05 D2=$4F D3=$00 -> ARMSID"
             .byte 0
str_t3_fail: .text "T3 FAIL: D1=$05 D2=$4F D3=$00 -> ARMSID"
             .byte 0
str_t4_pass: .text "T4 PASS: D1=$05 D2=$00 -> NO MATCH"
             .byte 0
str_t4_fail: .text "T4 FAIL: D1=$05 D2=$00 -> NO MATCH"
             .byte 0
str_t5_pass: .text "T5 PASS: D1=$F0 -> NO MATCH"
             .byte 0
str_t5_fail: .text "T5 FAIL: D1=$F0 -> NO MATCH"
             .byte 0
str_t6_pass: .text "T6 PASS: D1=$06 -> FPGASID 8580"
             .byte 0
str_t6_fail: .text "T6 FAIL: D1=$06 -> FPGASID 8580"
             .byte 0
str_t7_pass: .text "T7 PASS: D1=$07 -> FPGASID 6581"
             .byte 0
str_t7_fail: .text "T7 FAIL: D1=$07 -> FPGASID 6581"
             .byte 0
str_t8_pass: .text "T8 PASS: D1=$F0 -> NO MATCH (FPGASID)"
             .byte 0
str_t8_fail: .text "T8 FAIL: D1=$F0 -> NO MATCH (FPGASID)"
             .byte 0
str_divider:  .text "--------------------------------------"
              .byte 0
str_all_pass: .text "ALL 8 TESTS PASSED"
              .byte 0
str_some_fail:.text "SOME TESTS FAILED"
              .byte 0

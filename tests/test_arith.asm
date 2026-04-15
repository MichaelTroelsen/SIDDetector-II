// =============================================================================
// test_arith.asm — Unit tests for the ArithmeticMean routine
// =============================================================================
// Runs 4 test cases and displays PASS/FAIL on screen.
// Final pass count written to $0600 for automated checking via moncommands.
//
// Test cases:
//   1. mean([10, 20, 30])           = 20
//   2. mean([5, 5, 5, 5, 5, 5])    = 5
//   3. mean([100, 50, 75, 25])      = 62  (250/4 = 62 integer)
//   4. numInts = 0                  = 0   (empty → zero result)
// =============================================================================

.encoding "petscii_upper"

.const zpArrayPtr = $A2  // zero-page slot: 1=arr1, 2=arr2

* = $0801
    .word $0801         // BASIC line link (end-of-program)
    .word 0             // BASIC line number
    .byte $9e           // SYS token
    .text "2061"        // SYS 2061 = $080D
    .byte 0             // end-of-line
    .word 0             // end-of-BASIC

* = $080d

// ------------------------------------------------------------
// ENTRY
// ------------------------------------------------------------
test_start:
    lda #$15
    sta $D018           // uppercase/graphics character set
    jsr $E544           // KERNAL: clear screen

    lda #$00
    sta pass_count
    sta row_ctr

    // ---- Test 1: mean([10, 20, 30]) should = 20 ----
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
    bne t1_fail
    lda #<str_t1_pass
    ldy #>str_t1_pass
    jsr show_result
    inc pass_count
    jmp test2
t1_fail:
    lda #<str_t1_fail
    ldy #>str_t1_fail
    jsr show_result

test2:
    // ---- Test 2: mean([5,5,5,5,5,5]) should = 5 ----
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
    bne t2_fail
    lda #<str_t2_pass
    ldy #>str_t2_pass
    jsr show_result
    inc pass_count
    jmp test3
t2_fail:
    lda #<str_t2_fail
    ldy #>str_t2_fail
    jsr show_result

test3:
    // ---- Test 3: mean([100, 50, 75, 25]) should = 62 ----
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
    bne t3_fail
    lda #<str_t3_pass
    ldy #>str_t3_pass
    jsr show_result
    inc pass_count
    jmp test4
t3_fail:
    lda #<str_t3_fail
    ldy #>str_t3_fail
    jsr show_result

test4:
    // ---- Test 4: numInts = 0 should yield result = 0 ----
    lda #1
    sta zpArrayPtr
    lda #0
    sta numInts
    jsr calcMean
    lda calcResult
    cmp #0
    bne t4_fail
    lda #<str_t4_pass
    ldy #>str_t4_pass
    jsr show_result
    inc pass_count
    jmp test_done
t4_fail:
    lda #<str_t4_fail
    ldy #>str_t4_fail
    jsr show_result

// ------------------------------------------------------------
// SUMMARY
// ------------------------------------------------------------
test_done:
    lda pass_count
    sta $0600           // export pass count for moncommands ($0600 = 4 means all pass)
    lda #<str_divider
    ldy #>str_divider
    jsr show_result
    lda pass_count
    cmp #4
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
    jmp td_spin         // spin; VICE monitor can break here and inspect $0600

// ------------------------------------------------------------
// show_result: print string on next screen row
// Entry: A = string address lo, Y = string address hi (zero-terminated PETSCII)
// ------------------------------------------------------------
show_result:
    sta str_ptr_lo
    sty str_ptr_hi
    ldx row_ctr
    ldy #0
    clc
    jsr $E50C           // KERNAL PLOT: position cursor (X=row, Y=col, C=0)
    inc row_ctr
    lda str_ptr_lo
    ldy str_ptr_hi
    jsr $AB1E           // KERNAL STROUT: print zero-terminated string
    rts

str_ptr_lo: .byte 0
str_ptr_hi: .byte 0

// ------------------------------------------------------------
// calcMean — embedded copy of the ArithmeticMean routine
// Reads: zpArrayPtr ($A2), numInts, arr1/arr2
// Writes: calcResult
// ------------------------------------------------------------
calcMean:
    pha
    tya
    pha
    lda #0
    sta tmp16
    sta tmp16+1
    ldy numInts
    beq cm_done         // numInts = 0 → skip, result = 0
    dey
cm_add:
    lda zpArrayPtr
    cmp #1
    beq cm_use_arr1
    lda arr2,y          // default / zpArrayPtr=2
    jmp cm_accumulate
cm_use_arr1:
    lda arr1,y
cm_accumulate:
    clc
    adc tmp16
    sta tmp16
    lda tmp16+1
    adc #0
    sta tmp16+1
    dey
    cpy #$ff            // wrapped past 0?
    bne cm_add
    ldy #$ff            // start quotient at -1
cm_divide:
    lda tmp16
    sec
    sbc numInts
    sta tmp16
    lda tmp16+1
    sbc #0
    sta tmp16+1
    iny
    bcs cm_divide       // keep subtracting while no borrow
cm_done:
    sty calcResult
    pla
    tay
    pla
    rts

// ------------------------------------------------------------
// Data
// ------------------------------------------------------------
numInts:    .byte 0
calcResult: .byte 0
tmp16:      .byte 0, 0
pass_count: .byte 0
row_ctr:    .byte 0
arr1:       .byte 0,0,0,0,0,0,0,0,0,0,0
arr2:       .byte 0,0,0,0,0,0,0,0,0,0,0

// ------------------------------------------------------------
// Strings (zero-terminated PETSCII uppercase)
// ------------------------------------------------------------
str_t1_pass:  .text "TEST 1 PASS: MEAN(10,20,30)=20"
              .byte 0
str_t1_fail:  .text "TEST 1 FAIL: MEAN(10,20,30)!=20"
              .byte 0
str_t2_pass:  .text "TEST 2 PASS: MEAN(5,5,5,5,5,5)=5"
              .byte 0
str_t2_fail:  .text "TEST 2 FAIL: MEAN(5,5,5,5,5,5)!=5"
              .byte 0
str_t3_pass:  .text "TEST 3 PASS: MEAN(100,50,75,25)=62"
              .byte 0
str_t3_fail:  .text "TEST 3 FAIL: MEAN(100,50,75,25)!=62"
              .byte 0
str_t4_pass:  .text "TEST 4 PASS: MEAN(EMPTY)=0"
              .byte 0
str_t4_fail:  .text "TEST 4 FAIL: MEAN(EMPTY)!=0"
              .byte 0
str_divider:  .text "--------------------------------"
              .byte 0
str_all_pass: .text "ALL 4 TESTS PASSED"
              .byte 0
str_some_fail:.text "SOME TESTS FAILED"
              .byte 0

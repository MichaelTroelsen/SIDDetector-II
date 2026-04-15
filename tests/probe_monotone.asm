// probe_monotone.asm — test if D41B sequence is monotone non-decreasing
// SwinSID Nano: oscillator only increments → diffs always 0 or +1 → 0 decreases
// NOSID+U2+: bus noise goes up AND down → some decreases
// Reads 16 D41B values back-to-back (unrolled, ~7 cycles between reads).
// Reports: dec_count (decreases), chg_count (total non-zero diffs), sample values
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_monotone.asm -o tests/probe_monotone.prg

.const zp_ptr = $FB
.const data2  = $A5

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    cli
    lda #$18
    jsr rp_delay        // 31ms interrupt context
    sei

    lda #$00
    ldx #$1F
rst: sta $D400,x
    dex
    bpl rst

    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81            // noise + gate=1
    sta $D412

    lda #$0A
    jsr rp_delay        // 12ms

    // Read 16 D41B values back-to-back (unrolled, ~7 cycles each)
    lda $D41B
    sta buf+0
    lda $D41B
    sta buf+1
    lda $D41B
    sta buf+2
    lda $D41B
    sta buf+3
    lda $D41B
    sta buf+4
    lda $D41B
    sta buf+5
    lda $D41B
    sta buf+6
    lda $D41B
    sta buf+7
    lda $D41B
    sta buf+8
    lda $D41B
    sta buf+9
    lda $D41B
    sta buf+10
    lda $D41B
    sta buf+11
    lda $D41B
    sta buf+12
    lda $D41B
    sta buf+13
    lda $D41B
    sta buf+14
    lda $D41B
    sta buf+15

    lda #$00
    sta $D412

    // Count decreases and total changes in 15 pairs
    ldy #$00            // dec_count
    ldx #$00            // change_count (use data2)
    sta data2           // chg_count = 0
    ldx #$0E            // 14 pairs (indices 0..14)
chk:
    lda buf+1,x         // buf[i+1]
    cmp buf,x           // compare with buf[i]
    beq same            // equal: no change
    inc data2           // different: count change
    bcs no_dec          // if buf[i+1] >= buf[i] (carry set): no decrease
    iny                 // decrease: count it
no_dec:
same:
    dex
    bpl chk

    // Print results
    cli
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    // Print decrease count
    lda #<l_dec
    sta zp_ptr
    lda #>l_dec
    sta zp_ptr+1
    jsr pl
    tya
    jsr prhex
    lda #13
    jsr $FFD2

    // Print change count
    lda #<l_chg
    sta zp_ptr
    lda #>l_chg
    sta zp_ptr+1
    jsr pl
    lda data2
    jsr prhex
    lda #13
    jsr $FFD2

    // Print first 8 values as hex
    lda #<l_vals
    sta zp_ptr
    lda #>l_vals
    sta zp_ptr+1
    jsr pl
    ldx #$00
pv: lda buf,x
    jsr prhex
    lda #$20
    jsr $FFD2
    inx
    cpx #$08
    bne pv
    lda #13
    jsr $FFD2

    rts

rp_delay:
    cmp #$00
    beq rp_done
    tay
    txa
    pha
    tya
    tax
rp_outer:
    ldy #$ff
rp_inner:
    dey
    bne rp_inner
    dex
    bne rp_outer
    pla
    tax
rp_done:
    rts

pl: ldy #$00
pll: lda (zp_ptr),y
    beq pldone
    jsr $FFD2
    iny
    bne pll
pldone: rts

prhex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr prnib
    pla
    and #$0F
prnib:
    cmp #$0A
    bcc prdig
    adc #$06
prdig:
    adc #$30
    jmp $FFD2

l_dec:  .text "DEC:  "
        .byte 0
l_chg:  .text "CHG:  "
        .byte 0
l_vals: .text "VALS: "
        .byte 0

buf:    .fill 16, 0

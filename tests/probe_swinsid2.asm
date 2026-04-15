// probe_swinsid2.asm — test sawtooth+gate $D41B at slow/fast freq
// Tests: slow($0001)/fast($FFFF) with sawtooth+gate ($21)
// Also tests: with/without gate at slow freq
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid2.asm -o tests/probe_swinsid2.prg

.const zp_ptr = $FB
.const rp_delay_addr = $0953  // rp_delay routine address in siddetector (approx)

// Simple delay: A * ~3ms using the same loop as the main program
// We'll inline a simple delay loop: X=0, loop 256 times per "unit"

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    // Silence all SID ($D400-$D418)
    lda #$00
    ldx #$18
sil:    sta $D400,x
        dex
        bpl sil
    // Also clear extended regs
    sta $D41B
    sta $D41C
    sta $D41D
    sta $D41E
    sta $D41F
    cli

    // T1/T2: sawtooth+gate ($21), freq=$0001, no prior setup
    lda #$01
    sta $D40E       // freq lo
    lda #$00
    sta $D40F       // freq hi  → freq=$0001
    lda #$21        // sawtooth + gate
    sta $D412
    jsr delay6ms
    lda $D41B
    sta t1
    jsr delay6ms
    lda $D41B
    sta t2

    // T3/T4: sawtooth+gate ($21), freq=$FFFF
    lda #$FF
    sta $D40E
    sta $D40F       // freq=$FFFF
    jsr delay6ms
    lda $D41B
    sta t3
    jsr delay6ms
    lda $D41B
    sta t4

    // T5/T6: sawtooth NO gate ($20), freq=$0001
    lda #$00
    sta $D412       // off
    jsr delay6ms    // let oscillator settle
    lda #$01
    sta $D40E
    lda #$00
    sta $D40F
    lda #$20        // sawtooth, NO gate
    sta $D412
    jsr delay6ms
    lda $D41B
    sta t5
    jsr delay6ms
    lda $D41B
    sta t6

    // T7/T8: sawtooth+gate ($21), freq=$0001, but D41F=$FF first
    lda #$00
    sta $D412
    lda #$FF
    sta $D41F       // simulate uSID64 write
    lda #$00
    sta $D41F       // then reset (like checkswinsidnano does)
    jsr delay3ms
    lda #$01
    sta $D40E
    lda #$00
    sta $D40F
    lda #$21
    sta $D412
    jsr delay6ms
    lda $D41B
    sta t7
    jsr delay6ms
    lda $D41B
    sta t8

    // Silence
    lda #$00
    sta $D412

    // --- Print results ---
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    ldx #$00
ploop:
    cpx #$08
    beq pdone
    lda label_lo,x
    sta zp_ptr
    lda label_hi,x
    sta zp_ptr+1
    ldy #$00
prlbl:  lda (zp_ptr),y
        beq prval
        jsr $FFD2
        iny
        bne prlbl
prval:
    lda t1,x
    jsr prhex
    lda #13
    jsr $FFD2
    inx
    jmp ploop
pdone:
    rts

// delay6ms: ~8 × 768 cycles ≈ 6.3ms at PAL
delay6ms:
    ldy #$08
dly_outer:
    ldx #$00
dly_inner:
    inx
    bne dly_inner
    dey
    bne dly_outer
    rts

// delay3ms: ~4 × 768 cycles ≈ 3ms at PAL
delay3ms:
    ldy #$04
dly3_outer:
    ldx #$00
dly3_inner:
    inx
    bne dly3_inner
    dey
    bne dly3_outer
    rts

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

l1: .text "T1 SAW+GT SLOW1:"
    .byte 0
l2: .text "T2 SAW+GT SLOW2:"
    .byte 0
l3: .text "T3 SAW+GT FAST1:"
    .byte 0
l4: .text "T4 SAW+GT FAST2:"
    .byte 0
l5: .text "T5 SAW-GT SLOW1:"
    .byte 0
l6: .text "T6 SAW-GT SLOW2:"
    .byte 0
l7: .text "T7 FFWRITE SLOW1:"
    .byte 0
l8: .text "T8 FFWRITE SLOW2:"
    .byte 0

label_lo: .byte <l1,<l2,<l3,<l4,<l5,<l6,<l7,<l8
label_hi: .byte >l1,>l2,>l3,>l4,>l5,>l6,>l7,>l8

t1: .byte 0
t2: .byte 0
t3: .byte 0
t4: .byte 0
t5: .byte 0
t6: .byte 0
t7: .byte 0
t8: .byte 0

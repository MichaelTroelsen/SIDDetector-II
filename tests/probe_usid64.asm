// probe_usid64.asm — D41F/D41B/D41C read-back probe
// Runs 8 tests and prints results. Works on any SID variant.
// Build: java -jar KickAss.jar probe_usid64.asm -o probe_usid64.prg

.const zp_ptr = $FB     // 2-byte ZP pointer ($FB/$FC)

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    // Silence all SID write registers ($D400-$D418)
    lda #$00
    ldx #$18
sil:    sta $D400,x
        dex
        bpl sil
    cli

    // T1: cold read $D41F (no write)
    lda $D41F
    sta t1

    // T2: write $F0 → read $D41F
    lda #$F0
    sta $D41F
    lda $D41F
    sta t2

    // T3: write $55 → read $D41F
    lda #$55
    sta $D41F
    lda $D41F
    sta t3

    // T4: write $AA → read $D41F
    lda #$AA
    sta $D41F
    lda $D41F
    sta t4

    // T5: write $F0,$10,$63 (unlock seq) → read $D41F
    lda #$F0
    sta $D41F
    lda #$10
    sta $D41F
    lda #$63
    sta $D41F
    lda $D41F
    sta t5

    // T6: full config seq $F0,$10,$63,$00,$FF (mode=auto) → read $D41F
    lda #$F0
    sta $D41F
    lda #$10
    sta $D41F
    lda #$63
    sta $D41F
    lda #$00
    sta $D41F
    lda #$FF
    sta $D41F
    lda $D41F
    sta t6

    // T7: read $D41B (OSC3 waveform output)
    lda $D41B
    sta t7

    // T8: read $D41C (ENV3 output)
    lda $D41C
    sta t8

    // --- Print results ---
    lda #147            // PETSCII CLR
    jsr $FFD2
    lda #13             // CR → move to row 1
    jsr $FFD2

    ldx #$00
ploop:
    cpx #$08
    beq pdone

    // Print label
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

    // Print result as hex
prval:
    lda t1,x
    jsr prhex
    lda #13
    jsr $FFD2
    inx
    jmp ploop
pdone:
    rts

// prhex: print byte in A as two hex chars
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
    adc #$06        // carry set from cmp: +6+1=+7 → lands A-F
prdig:
    adc #$30
    jmp $FFD2

// Labels (PETSCII, null-terminated, 14 chars each for alignment)
l1: .text "T1 COLD D41F: "
    .byte 0
l2: .text "T2 WR F0 D41F: "
    .byte 0
l3: .text "T3 WR 55 D41F: "
    .byte 0
l4: .text "T4 WR AA D41F: "
    .byte 0
l5: .text "T5 F01063 D41F: "
    .byte 0
l6: .text "T6 SEQFULL D41F: "
    .byte 0
l7: .text "T7 COLD D41B: "
    .byte 0
l8: .text "T8 COLD D41C: "
    .byte 0

label_lo: .byte <l1,<l2,<l3,<l4,<l5,<l6,<l7,<l8
label_hi: .byte >l1,>l2,>l3,>l4,>l5,>l6,>l7,>l8

// Result storage (consecutive for ,X indexing)
t1: .byte $00
t2: .byte $00
t3: .byte $00
t4: .byte $00
t5: .byte $00
t6: .byte $00
t7: .byte $00
t8: .byte $00

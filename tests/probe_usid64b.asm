// probe_usid64b.asm — test checkusid64 two-read stability with delays
// Runs full config sequence, then reads D41F at t=0, 1ms, 3ms, 10ms, 30ms.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_usid64b.asm -o tests/probe_usid64b.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    lda #$00
    sta $D418

    // Full config sequence
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

    // Read at t=0 (immediate)
    lda $D41F
    sta r0

    // Read at t~1ms (rp_delay A=1 = ~255*3 = 765 cycles ~0.76ms PAL)
    ldx #$01
d1: ldy #$FF
d1i:dey
    bne d1i
    dex
    bne d1
    lda $D41F
    sta r1

    // Read at t~3ms more (rp_delay A=2)
    ldx #$02
d3: ldy #$FF
d3i:dey
    bne d3i
    dex
    bne d3
    lda $D41F
    sta r3

    // Read at t~10ms more (rp_delay A=8)
    ldx #$08
d10:ldy #$FF
d10i:dey
    bne d10i
    dex
    bne d10
    lda $D41F
    sta r10

    // Read at t~30ms more (rp_delay A=23)
    ldx #$17
d30:ldy #$FF
d30i:dey
    bne d30i
    dex
    bne d30
    lda $D41F
    sta r30

    // Print results
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l0
    sta zp_ptr
    lda #>l0
    sta zp_ptr+1
    jsr pl
    lda r0
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l1
    sta zp_ptr
    lda #>l1
    sta zp_ptr+1
    jsr pl
    lda r1
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l3
    sta zp_ptr
    lda #>l3
    sta zp_ptr+1
    jsr pl
    lda r3
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l10
    sta zp_ptr
    lda #>l10
    sta zp_ptr+1
    jsr pl
    lda r10
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l30
    sta zp_ptr
    lda #>l30
    sta zp_ptr+1
    jsr pl
    lda r30
    jsr prhex
    lda #13
    jsr $FFD2

    rts

pl: ldy #$00
pll:lda (zp_ptr),y
    beq pldone
    jsr $FFD2
    iny
    bne pll
pldone:rts

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

l0:  .text "T=0MS:  "
          .byte 0
l1:  .text "T=1MS:  "
          .byte 0
l3:  .text "T=4MS:  "
          .byte 0
l10: .text "T=12MS: "
          .byte 0
l30: .text "T=42MS: "
          .byte 0

r0:  .byte 0
r1:  .byte 0
r3:  .byte 0
r10: .byte 0
r30: .byte 0

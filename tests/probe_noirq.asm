// probe_noirq.asm — D41B count with SEI throughout (no interrupt-induced bus noise)
// Tests whether NOSID is calm with zero interrupt activity vs SwinSID Nano (always oscillates)
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_noirq.asm -o tests/probe_noirq.prg

.const zp_ptr = $FB
.const data2  = $A5

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei                 // keep interrupts disabled throughout

    // Reset all SID regs
    lda #$00
    ldx #$1F
rst: sta $D400,x
    dex
    bpl rst

    // Setup: freq=$FFFF, noise, gate=1
    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81
    sta $D412

    // Wait 12ms (no interrupts, tight loop only)
    ldx #$04
d1: ldy #$FF
d1i:dey
    bne d1i
    dex
    bne d1

    // Count changes in 8 reads
    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
rd: lda $D41B
    cmp data2
    beq sk
    iny
    sta data2
sk: dex
    bne rd
    sty cnt_noirq

    lda #$00
    sta $D412

    // Print (uses KERNAL CHROUT — re-enable interrupts briefly only for output)
    cli
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2
    sei

    lda #<l_noirq
    sta zp_ptr
    lda #>l_noirq
    sta zp_ptr+1
    cli
    jsr pl
    lda cnt_noirq
    jsr prhex
    lda #13
    jsr $FFD2
    sei

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

l_noirq: .text "NOIRQ: "
         .byte 0

cnt_noirq: .byte 0

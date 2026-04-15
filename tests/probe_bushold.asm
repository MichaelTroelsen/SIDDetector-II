// probe_bushold.asm — immediate vs delayed D41B read
// Tests whether D41B changes right after $D412 write (bus hold test).
// NOSID: bus holds $81 (last written byte) → cnt_imm=0
// SwinSID Nano: LFSR independent of writes → cnt_imm>0
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_bushold.asm -o tests/probe_bushold.prg

.const zp_ptr = $FB
.const data2  = $A5

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    // simulate checkpalntsc context: enable IRQs + 31ms delay
    cli
    lda #$18
    jsr rp_delay

    sei

    // ---- Reset voice 3 ----
    lda #$00
    ldx #$1F
rst1: sta $D400,x
    dex
    bpl rst1

    // ---- Setup: freq=$FFFF, noise waveform, gate=1 ----
    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81            // noise + gate=1 — this is the last write before reads
    sta $D412

    // ---- Immediate reads (no delay) ----
    // Bus holds $81 on NOSID; LFSR active on SwinSID Nano
    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
ri: lda $D41B
    cmp data2
    beq si
    iny
    sta data2
si: dex
    bne ri
    sty cnt_imm

    // ---- Wait 12ms ----
    lda #$04
    jsr rp_delay

    // ---- Delayed reads ----
    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
rd: lda $D41B
    cmp data2
    beq sd
    iny
    sta data2
sd: dex
    bne rd
    sty cnt_12ms

    lda #$00
    sta $D412

    // Print results
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l_imm
    sta zp_ptr
    lda #>l_imm
    sta zp_ptr+1
    jsr pl
    lda cnt_imm
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_12ms
    sta zp_ptr
    lda #>l_12ms
    sta zp_ptr+1
    jsr pl
    lda cnt_12ms
    jsr prhex
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

l_imm:  .text "IMM:  "
        .byte 0
l_12ms: .text "12MS: "
        .byte 0

cnt_imm:  .byte 0
cnt_12ms: .byte 0

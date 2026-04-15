// probe_pot.asm — test $D419 (POTX) and $D41A (POTY) stability
// SwinSID Nano AVR has no physical POT inputs → might return stable $FF or $00.
// NOSID+U2+: bus float → noisy.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_pot.asm -o tests/probe_pot.prg

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
    lda #$81
    sta $D412           // noise + gate=1

    lda #$0A
    jsr rp_delay        // 12ms

    // --- Test D41B (OSC3) ---
    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
rb: lda $D41B
    cmp data2
    beq sb
    iny
    sta data2
sb: dex
    bne rb
    sty cnt_osc3
    lda $D41B
    sta val_osc3        // one sample

    // --- Test D419 (POTX) ---
    lda $D419
    sta data2
    ldy #$00
    ldx #$07
rp: lda $D419
    cmp data2
    beq sp
    iny
    sta data2
sp: dex
    bne rp
    sty cnt_potx
    lda $D419
    sta val_potx        // one sample

    // --- Test D41A (POTY) ---
    lda $D41A
    sta data2
    ldy #$00
    ldx #$07
rq: lda $D41A
    cmp data2
    beq sq
    iny
    sta data2
sq: dex
    bne rq
    sty cnt_poty
    lda $D41A
    sta val_poty

    lda #$00
    sta $D412

    // Print
    cli
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l_osc3
    sta zp_ptr
    lda #>l_osc3
    sta zp_ptr+1
    jsr pl
    lda cnt_osc3
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val_osc3
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_potx
    sta zp_ptr
    lda #>l_potx
    sta zp_ptr+1
    jsr pl
    lda cnt_potx
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val_potx
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_poty
    sta zp_ptr
    lda #>l_poty
    sta zp_ptr+1
    jsr pl
    lda cnt_poty
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val_poty
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

l_osc3: .text "OSC3: "
        .byte 0
l_potx: .text "POTX: "
        .byte 0
l_poty: .text "POTY: "
        .byte 0

cnt_osc3: .byte 0
val_osc3: .byte 0
cnt_potx: .byte 0
val_potx: .byte 0
cnt_poty: .byte 0
val_poty: .byte 0

// probe_freq0.asm — compare D41B count at freq=$FFFF vs freq=$0000
// At freq=0: real SID/SwinSID LFSR stops advancing → count=0.
// NOSID floating bus: still changes from U2+ noise → count>0.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_freq0.asm -o tests/probe_freq0.prg

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

    // ---- Test 1: freq=$FFFF (standard SwinSID Nano test) ----
    lda #$00
    ldx #$1F
rst1: sta $D400,x
    dex
    bpl rst1
    lda #$05
    jsr rp_delay        // 6ms settle

    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81            // noise + gate=1
    sta $D412
    lda #$0A
    jsr rp_delay        // 12ms

    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
rd1: lda $D41B
    cmp data2
    beq s1
    iny
    sta data2
s1: dex
    bne rd1
    sty cnt_ffff

    // ---- Test 2: freq=$0000 (oscillator stopped on real chip) ----
    lda #$00
    ldx #$1F
rst2: sta $D400,x
    dex
    bpl rst2
    lda #$05
    jsr rp_delay        // 6ms settle

    // freq=0 but noise+gate=1
    lda #$00
    sta $D40E
    sta $D40F
    lda #$81
    sta $D412
    lda #$0A
    jsr rp_delay        // 12ms

    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
rd2: lda $D41B
    cmp data2
    beq s2
    iny
    sta data2
s2: dex
    bne rd2
    sty cnt_zero

    lda #$00
    sta $D412

    // Print results
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l_ffff
    sta zp_ptr
    lda #>l_ffff
    sta zp_ptr+1
    jsr pl
    lda cnt_ffff
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_zero
    sta zp_ptr
    lda #>l_zero
    sta zp_ptr+1
    jsr pl
    lda cnt_zero
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

l_ffff: .text "FFFF: "
        .byte 0
l_zero: .text "ZERO: "
        .byte 0

cnt_ffff: .byte 0
cnt_zero: .byte 0

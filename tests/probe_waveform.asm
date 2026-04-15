// probe_waveform.asm — D41B count with noise waveform vs no waveform
// Tests if SwinSID Nano D41B is quiet when CR3=$00 (AVR idle?)
// vs NOSID which is always noisy from U2+ bus activity.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_waveform.asm -o tests/probe_waveform.prg

.const zp_ptr = $FB
.const data2  = $A5

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei

    // ---- Test 1: noise waveform + gate=1 (standard test) ----
    lda #$00
    ldx #$1F
rst1: sta $D400,x
    dex
    bpl rst1

    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81            // noise + gate=1
    sta $D412

    ldx #$04
d1: ldy #$FF
d1i:dey
    bne d1i
    dex
    bne d1

    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
r1: lda $D41B
    cmp data2
    beq s1
    iny
    sta data2
s1: dex
    bne r1
    sty cnt_noise

    // ---- Test 2: no waveform, gate=0 (voice completely off) ----
    lda #$00
    ldx #$1F
rst2: sta $D400,x
    dex
    bpl rst2
    // CR3=$00: no waveform, gate=0 (already done by reset, just be explicit)
    sta $D412           // $00: no waveform, gate=0

    ldx #$04
d2: ldy #$FF
d2i:dey
    bne d2i
    dex
    bne d2

    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
r2: lda $D41B
    cmp data2
    beq s2
    iny
    sta data2
s2: dex
    bne r2
    sty cnt_off

    // ---- Test 3: triangle waveform, gate=1 ----
    lda #$00
    ldx #$1F
rst3: sta $D400,x
    dex
    bpl rst3

    lda #$FF
    sta $D40E
    sta $D40F
    lda #$11            // triangle + gate=1
    sta $D412

    ldx #$04
d3: ldy #$FF
d3i:dey
    bne d3i
    dex
    bne d3

    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
r3: lda $D41B
    cmp data2
    beq s3
    iny
    sta data2
s3: dex
    bne r3
    sty cnt_tri

    lda #$00
    sta $D412

    // Print
    cli
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l_noise
    sta zp_ptr
    lda #>l_noise
    sta zp_ptr+1
    jsr pl
    lda cnt_noise
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_off
    sta zp_ptr
    lda #>l_off
    sta zp_ptr+1
    jsr pl
    lda cnt_off
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_tri
    sta zp_ptr
    lda #>l_tri
    sta zp_ptr+1
    jsr pl
    lda cnt_tri
    jsr prhex
    lda #13
    jsr $FFD2

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

l_noise: .text "NOISE: "
         .byte 0
l_off:   .text "OFF:   "
         .byte 0
l_tri:   .text "TRI:   "
         .byte 0

cnt_noise: .byte 0
cnt_off:   .byte 0
cnt_tri:   .byte 0

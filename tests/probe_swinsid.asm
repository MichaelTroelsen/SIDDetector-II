// probe_swinsid.asm — test dual-frequency $D41B behavior
// Mirrors checkswinsidnano logic: reset D41F, then slow($0001) and fast($FFFF)
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid.asm -o tests/probe_swinsid.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    // Silence all SID
    lda #$00
    ldx #$18
sil:    sta $D400,x
        dex
        bpl sil
    cli

    // Reset extended registers
    lda #$00
    sta $D41B
    sta $D41C
    sta $D41D
    sta $D41E
    sta $D41F

    // --- T1/T2: slow ($0001), noise+gate ($81) ---
    lda #$01
    sta $D40E
    lda #$00
    sta $D40F
    lda #$81
    sta $D412
    // wait ~6ms (A=2 × 255 × 3 cycles)
    ldx #$00
dly1a:  inx
        bne dly1a       // 256*3 = 768 cycles ≈ 0.78ms
    ldx #$00
dly1b:  inx
        bne dly1b
    ldx #$00
dly1c:  inx
        bne dly1c
    ldx #$00
dly1d:  inx
        bne dly1d
    ldx #$00
dly1e:  inx
        bne dly1e
    ldx #$00
dly1f:  inx
        bne dly1f
    ldx #$00
dly1g:  inx
        bne dly1g
    ldx #$00
dly1h:  inx
        bne dly1h   // 8 × 768 ≈ 6ms
    lda $D41B
    sta t1
    // wait ~6ms more
    ldx #$00
dly2a:  inx
        bne dly2a
    ldx #$00
dly2b:  inx
        bne dly2b
    ldx #$00
dly2c:  inx
        bne dly2c
    ldx #$00
dly2d:  inx
        bne dly2d
    ldx #$00
dly2e:  inx
        bne dly2e
    ldx #$00
dly2f:  inx
        bne dly2f
    ldx #$00
dly2g:  inx
        bne dly2g
    ldx #$00
dly2h:  inx
        bne dly2h
    lda $D41B
    sta t2

    // --- T3/T4: fast ($FFFF), noise+gate ($81) ---
    lda #$FF
    sta $D40E
    sta $D40F
    // settle 6ms
    ldx #$00
dly3a:  inx
        bne dly3a
    ldx #$00
dly3b:  inx
        bne dly3b
    ldx #$00
dly3c:  inx
        bne dly3c
    ldx #$00
dly3d:  inx
        bne dly3d
    ldx #$00
dly3e:  inx
        bne dly3e
    ldx #$00
dly3f:  inx
        bne dly3f
    ldx #$00
dly3g:  inx
        bne dly3g
    ldx #$00
dly3h:  inx
        bne dly3h
    lda $D41B
    sta t3
    // wait 6ms more
    ldx #$00
dly4a:  inx
        bne dly4a
    ldx #$00
dly4b:  inx
        bne dly4b
    ldx #$00
dly4c:  inx
        bne dly4c
    ldx #$00
dly4d:  inx
        bne dly4d
    ldx #$00
dly4e:  inx
        bne dly4e
    ldx #$00
dly4f:  inx
        bne dly4f
    ldx #$00
dly4g:  inx
        bne dly4g
    ldx #$00
dly4h:  inx
        bne dly4h
    lda $D41B
    sta t4

    // --- T5/T6: repeat but first run uSID64 config sequence to simulate interference ---
    lda #$00
    sta $D412   // voice off
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
    // Now reset (like checkswinsidnano does)
    lda #$00
    sta $D41F
    sta $D412
    sta $D40E
    sta $D40F
    // settle 3ms
    ldx #$00
dly5a:  inx
        bne dly5a
    ldx #$00
dly5b:  inx
        bne dly5b
    ldx #$00
dly5c:  inx
        bne dly5c
    ldx #$00
dly5d:  inx
        bne dly5d
    // slow test ($0001)
    lda #$01
    sta $D40E
    lda #$00
    sta $D40F
    lda #$81
    sta $D412
    ldx #$00
dly6a:  inx
        bne dly6a
    ldx #$00
dly6b:  inx
        bne dly6b
    ldx #$00
dly6c:  inx
        bne dly6c
    ldx #$00
dly6d:  inx
        bne dly6d
    ldx #$00
dly6e:  inx
        bne dly6e
    ldx #$00
dly6f:  inx
        bne dly6f
    ldx #$00
dly6g:  inx
        bne dly6g
    ldx #$00
dly6h:  inx
        bne dly6h
    lda $D41B
    sta t5
    ldx #$00
dly7a:  inx
        bne dly7a
    ldx #$00
dly7b:  inx
        bne dly7b
    ldx #$00
dly7c:  inx
        bne dly7c
    ldx #$00
dly7d:  inx
        bne dly7d
    ldx #$00
dly7e:  inx
        bne dly7e
    ldx #$00
dly7f:  inx
        bne dly7f
    ldx #$00
dly7g:  inx
        bne dly7g
    ldx #$00
dly7h:  inx
        bne dly7h
    lda $D41B
    sta t6

    // disable voice 3
    lda #$00
    sta $D412

    // --- Print results ---
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    ldx #$00
ploop:
    cpx #$06
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

l1: .text "T1 SLOW1 D41B: "
    .byte 0
l2: .text "T2 SLOW2 D41B: "
    .byte 0
l3: .text "T3 FAST1 D41B: "
    .byte 0
l4: .text "T4 FAST2 D41B: "
    .byte 0
l5: .text "T5 AFTERU64CFG SLOW1: "
    .byte 0
l6: .text "T6 AFTERU64CFG SLOW2: "
    .byte 0

label_lo: .byte <l1,<l2,<l3,<l4,<l5,<l6
label_hi: .byte >l1,>l2,>l3,>l4,>l5,>l6

t1: .byte 0
t2: .byte 0
t3: .byte 0
t4: .byte 0
t5: .byte 0
t6: .byte 0

// probe_swinsid7.asm — probe OSC3 idle state and extended read count
// Tests what $D41B returns:
//   A) Immediately after full SID reset (gate=0, freq=0) — "idle" value
//   B) gate=1+noise+freq=$FFFF + 12ms: 16 reads, count changes
//   C) Same but after 62ms total: 16 reads, count changes
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid7.asm -o tests/probe_swinsid7.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei

    // Full SID reset
    lda #$00
    ldx #$1F
rst_loop: sta $D400,x
          dex
          bpl rst_loop

    // Wait ~6ms
    ldx #$05
w1_out: ldy #$00
w1_in:  dey
        bne w1_in
        dex
        bne w1_out

    // === A: Read idle state (gate=0, no waveform, freq=0) ===
    lda $D41B
    sta idle_val

    // === Set gate=1+noise+freq=$FFFF ===
    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81        // noise + gate=1
    sta $D412

    // Wait 12ms
    ldx #$0A
w2_out: ldy #$00
w2_in:  dey
        bne w2_in
        dex
        bne w2_out

    // === B: Count changes in 16 reads (15 pairs) ===
    lda $D41B
    sta last_val
    ldy #$00
    ldx #$0F        // 15 more reads
b_loop:
    lda $D41B
    cmp last_val
    beq b_same
    iny
    sta last_val
b_same:
    dex
    bpl b_loop
    sty cnt_12ms

    // Wait 50ms more (62ms total)
    ldx #$28
w3_out: ldy #$00
w3_in:  dey
        bne w3_in
        dex
        bne w3_out

    // === C: Count changes in 16 reads (15 pairs) ===
    lda $D41B
    sta last_val
    ldy #$00
    ldx #$0F
c_loop:
    lda $D41B
    cmp last_val
    beq c_same
    iny
    sta last_val
c_same:
    dex
    bpl c_loop
    sty cnt_62ms

    // Silence
    lda #$00
    sta $D412

    // === Print results ===
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    // "IDLE: XX"
    lda #<lbl_idle
    sta zp_ptr
    lda #>lbl_idle
    sta zp_ptr+1
    jsr print_label
    lda idle_val
    jsr prhex
    lda #13
    jsr $FFD2

    // "12MS CNT: XX"
    lda #<lbl_12ms
    sta zp_ptr
    lda #>lbl_12ms
    sta zp_ptr+1
    jsr print_label
    lda cnt_12ms
    jsr prhex
    lda #13
    jsr $FFD2

    // "62MS CNT: XX"
    lda #<lbl_62ms
    sta zp_ptr
    lda #>lbl_62ms
    sta zp_ptr+1
    jsr print_label
    lda cnt_62ms
    jsr prhex
    lda #13
    jsr $FFD2

    rts

print_label:
    ldy #$00
pl_loop: lda (zp_ptr),y
         beq pl_done
         jsr $FFD2
         iny
         bne pl_loop
pl_done: rts

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

lbl_idle: .text "IDLE: "
          .byte 0
lbl_12ms: .text "12MS CNT: "
          .byte 0
lbl_62ms: .text "62MS CNT: "
          .byte 0

idle_val: .byte 0
last_val: .byte 0
cnt_12ms: .byte 0
cnt_62ms: .byte 0

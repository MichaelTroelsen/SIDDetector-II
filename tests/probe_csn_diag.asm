// probe_csn_diag.asm — diagnose checkswinsidnano counts in siddetector context
// Simulates checkpalntsc timing (IRQs enabled, ~30ms elapsed), then runs
// the EXACT same 2-stage test as checkswinsidnano and prints both counts.
// rp_delay equivalent: A * 255 * 5 cycles ≈ A * 1.3ms
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_csn_diag.asm -o tests/probe_csn_diag.prg

.const zp_ptr = $FB
.const data2  = $A5         // same as siddetector

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    // Simulate checkpalntsc: enable IRQs (it ends with CLI)
    cli
    // Simulate ~30ms of checkpalntsc + check128 elapsed time
    lda #$18        // 24 * 1.3ms ≈ 31ms
    jsr rp_delay

    // === Exact copy of checkswinsidnano body ===
    lda #$00
    ldx #$1F
csn_rst_loop: sta $D400,x
    dex
    bpl csn_rst_loop
    lda #$05
    jsr rp_delay            // ~6ms settle

    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81
    sta $D412
    lda #$0A
    jsr rp_delay            // ~12ms

    // Stage 1: count changes in 8 reads (7 pairs)
    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
csn_rd1:
    lda $D41B
    cmp data2
    beq csn_s1
    iny
    sta data2
csn_s1:
    dex
    bne csn_rd1
    // Y = cnt_12ms
    sty cnt_12ms

    // Don't gate on the bcs yet — just record and continue to stage 2
    lda #$27
    jsr rp_delay            // ~50ms

    // Stage 2: count changes in 8 reads (7 pairs)
    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
csn_rd2:
    lda $D41B
    cmp data2
    beq csn_s2
    iny
    sta data2
csn_s2:
    dex
    bne csn_rd2
    // Y = cnt_62ms
    sty cnt_62ms

    lda #$00
    sta $D412               // silence

    // === Print results ===
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<lbl_12ms
    sta zp_ptr
    lda #>lbl_12ms
    sta zp_ptr+1
    jsr print_label
    lda cnt_12ms
    jsr prhex
    lda #13
    jsr $FFD2

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

// rp_delay: A * 255 * 5 cycles ≈ A * 1.3ms (matches siddetector)
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

lbl_12ms: .text "CNT12: "
          .byte 0
lbl_62ms: .text "CNT62: "
          .byte 0

cnt_12ms: .byte 0
cnt_62ms: .byte 0

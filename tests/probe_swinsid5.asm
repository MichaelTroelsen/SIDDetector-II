// probe_swinsid5.asm — test write-to-read-register behavior
// Key test: write $5A to $D41B (read-only on real SID), then read back.
// SwinSID Nano (active chip) should drive its own value ($FF from LFSR).
// NOSID (empty socket): bus holds written $5A (capacitance) or FPGA drives $FF.
//
// Also test: write $AA, read $D41B; write $00, read $D41B.
// If NOSID returns written value → NOSID.  If returns $FF → chip present.
//
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid5.asm -o tests/probe_swinsid5.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    // Simulate full detector chain up to checkswinsidnano:
    // Write uSID64 sequence to $D41F (same as checkusid64)
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
    // Also simulate checkskpico: write $FF to $D41F
    lda #$FF
    sta $D41F

    // Full SID reset (same as checkswinsidnano)
    lda #$00
    ldx #$1F
rst_loop: sta $D400,x
          dex
          bpl rst_loop
    cli
    jsr delay6ms    // 6ms settle

    // Set noise+gate+freq=$FFFF (same as current checkswinsidnano)
    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81
    sta $D412
    jsr delay12ms

    // Read $D41B 4 times (baseline, current behavior)
    lda $D41B
    sta base1
    lda $D41B
    sta base2
    lda $D41B
    sta base3
    lda $D41B
    sta base4

    // TEST A: write $5A to $D41B, read back
    lda #$5A
    sta $D41B       // write to read-only reg (ignored by real SID)
    lda $D41B
    sta rd_5a

    // TEST B: write $AA to $D41B, read back
    lda #$AA
    sta $D41B
    lda $D41B
    sta rd_aa

    // TEST C: write $00 to $D41B, read back
    lda #$00
    sta $D41B
    lda $D41B
    sta rd_00

    // TEST D: write $FF to $D41B, read back
    lda #$FF
    sta $D41B
    lda $D41B
    sta rd_ff

    // TEST E: silence, then write $5A, read $D41B (no noise running)
    lda #$00
    sta $D412       // gate=0
    jsr delay3ms
    lda #$5A
    sta $D41B
    lda $D41B
    sta rd_5a_mute
    lda #$AA
    sta $D41B
    lda $D41B
    sta rd_aa_mute

    // === Print results ===
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    // "BASE: XX XX XX XX"
    lda #<lbl_base
    sta zp_ptr
    lda #>lbl_base
    sta zp_ptr+1
    jsr print_label
    lda base1
    jsr prhex
    lda #$20
    jsr $FFD2
    lda base2
    jsr prhex
    lda #$20
    jsr $FFD2
    lda base3
    jsr prhex
    lda #$20
    jsr $FFD2
    lda base4
    jsr prhex
    lda #13
    jsr $FFD2

    // "WR5A: XX  WRAA: XX  WR00: XX  WRFF: XX"
    lda #<lbl_w5a
    sta zp_ptr
    lda #>lbl_w5a
    sta zp_ptr+1
    jsr print_label
    lda rd_5a
    jsr prhex
    lda #$20
    jsr $FFD2

    lda #<lbl_waa
    sta zp_ptr
    lda #>lbl_waa
    sta zp_ptr+1
    jsr print_label
    lda rd_aa
    jsr prhex
    lda #$20
    jsr $FFD2

    lda #<lbl_w00
    sta zp_ptr
    lda #>lbl_w00
    sta zp_ptr+1
    jsr print_label
    lda rd_00
    jsr prhex
    lda #$20
    jsr $FFD2

    lda #<lbl_wff
    sta zp_ptr
    lda #>lbl_wff
    sta zp_ptr+1
    jsr print_label
    lda rd_ff
    jsr prhex
    lda #13
    jsr $FFD2

    // "MUTE 5A: XX  MUTE AA: XX"
    lda #<lbl_m5a
    sta zp_ptr
    lda #>lbl_m5a
    sta zp_ptr+1
    jsr print_label
    lda rd_5a_mute
    jsr prhex
    lda #$20
    jsr $FFD2

    lda #<lbl_maa
    sta zp_ptr
    lda #>lbl_maa
    sta zp_ptr+1
    jsr print_label
    lda rd_aa_mute
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

delay3ms:
    ldy #$04
d3_out: ldx #$00
d3_in:  inx
        bne d3_in
        dey
        bne d3_out
    rts

delay6ms:
    ldy #$08
d6_out: ldx #$00
d6_in:  inx
        bne d6_in
        dey
        bne d6_out
    rts

delay12ms:
    ldy #$10
d12_out: ldx #$00
d12_in:  inx
         bne d12_in
         dey
         bne d12_out
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

lbl_base: .text "BASE: "
          .byte 0
lbl_w5a:  .text "W5A: "
          .byte 0
lbl_waa:  .text "WAA: "
          .byte 0
lbl_w00:  .text "W00: "
          .byte 0
lbl_wff:  .text "WFF: "
          .byte 0
lbl_m5a:  .text "MUTE5A: "
          .byte 0
lbl_maa:  .text "MUTAA: "
          .byte 0

base1: .byte 0
base2: .byte 0
base3: .byte 0
base4: .byte 0
rd_5a: .byte 0
rd_aa: .byte 0
rd_00: .byte 0
rd_ff: .byte 0
rd_5a_mute: .byte 0
rd_aa_mute: .byte 0

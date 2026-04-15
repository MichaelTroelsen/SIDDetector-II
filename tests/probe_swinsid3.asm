// probe_swinsid3.asm — compare gate=0 vs gate=1 consecutive read counts
// Tests D41B change rate with gate=OFF and gate=ON
// Also tests D41F behavior and individual D41B values
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid3.asm -o tests/probe_swinsid3.prg

.const zp_ptr = $FB
.const data2   = $A5

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
    cli

    // Wait 6ms
    jsr delay6ms

    // === TEST A: gate=0 (sawtooth, no gate, freq=$0001) ===
    // 8 consecutive reads, count changes
    lda #$01
    sta $D40E
    lda #$00
    sta $D40F
    lda #$20        // sawtooth, gate=0
    sta $D412
    jsr delay6ms    // settle

    lda $D41B
    sta data2
    ldy #$00        // change count
    ldx #$07
ta_loop:
    lda $D41B
    cmp data2
    beq ta_same
    iny
    sta data2
ta_same:
    dex
    bne ta_loop
    sty count_gate0

    // === TEST B: gate=1 (noise+gate, freq=$FFFF) ===
    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81        // noise+gate
    sta $D412
    jsr delay12ms   // 12ms settle

    lda $D41B
    sta data2
    ldy #$00
    ldx #$07
tb_loop:
    lda $D41B
    cmp data2
    beq tb_same
    iny
    sta data2
tb_same:
    dex
    bne tb_loop
    sty count_gate1

    // === TEST C: 8 individual D41B values with gate=1 ===
    lda $D41B
    sta val1
    lda $D41B
    sta val2
    lda $D41B
    sta val3
    lda $D41B
    sta val4
    lda $D41B
    sta val5
    lda $D41B
    sta val6
    lda $D41B
    sta val7
    lda $D41B
    sta val8

    // === TEST D: gate=0 then gate=1 (D412 write effect) ===
    // Write gate=0, then immediately read D41B
    lda #$00
    sta $D412
    lda $D41B
    sta val_gate0_imm    // immediate read after gate=0

    // Write gate=1, then immediately read D41B
    lda #$81
    sta $D412
    lda $D41B
    sta val_gate1_imm    // immediate read after gate=1

    // silence
    lda #$00
    sta $D412

    // === Print results ===
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    // Print "GATE0 CNT: XX"
    lda #<lbl_g0
    sta zp_ptr
    lda #>lbl_g0
    sta zp_ptr+1
    jsr print_label
    lda count_gate0
    jsr prhex
    lda #13
    jsr $FFD2

    // Print "GATE1 CNT: XX"
    lda #<lbl_g1
    sta zp_ptr
    lda #>lbl_g1
    sta zp_ptr+1
    jsr print_label
    lda count_gate1
    jsr prhex
    lda #13
    jsr $FFD2

    // Print "V1-V8: XX XX XX XX XX XX XX XX"
    lda #<lbl_v
    sta zp_ptr
    lda #>lbl_v
    sta zp_ptr+1
    jsr print_label
    lda val1
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val2
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val3
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val4
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val5
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val6
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val7
    jsr prhex
    lda #$20
    jsr $FFD2
    lda val8
    jsr prhex
    lda #13
    jsr $FFD2

    // Print "G0IMM: XX  G1IMM: XX"
    lda #<lbl_imm0
    sta zp_ptr
    lda #>lbl_imm0
    sta zp_ptr+1
    jsr print_label
    lda val_gate0_imm
    jsr prhex
    lda #$20
    jsr $FFD2
    lda #<lbl_imm1
    sta zp_ptr
    lda #>lbl_imm1
    sta zp_ptr+1
    jsr print_label
    lda val_gate1_imm
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

lbl_g0:  .text "GATE0 CNT: "
         .byte 0
lbl_g1:  .text "GATE1 CNT: "
         .byte 0
lbl_v:   .text "V1-V8: "
         .byte 0
lbl_imm0: .text "G0IMM: "
          .byte 0
lbl_imm1: .text " G1IMM: "
          .byte 0

count_gate0: .byte 0
count_gate1: .byte 0
val1: .byte 0
val2: .byte 0
val3: .byte 0
val4: .byte 0
val5: .byte 0
val6: .byte 0
val7: .byte 0
val8: .byte 0
val_gate0_imm: .byte 0
val_gate1_imm: .byte 0

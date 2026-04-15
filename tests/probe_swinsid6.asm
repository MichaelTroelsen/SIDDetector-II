// probe_swinsid6.asm — test consecutive reads after checkarmsid-style D41F write
// Simulates only what runs BEFORE checkswinsidnano if moved to after checkbacksid:
//   - checkarmsid writes 'D'=$44 to $D41F, 'I'=$49 to $D41E, 'S'=$53 to $D41D
//   - Then writes $00 to D41E, D41F cleanup
//   - checkpdsid writes 'P'=$50 to $D41D, 'D'=$44 to $D41E (not $D41F)
//   - checkbacksid writes D41B=$02, D41C=$01, D41D=$B5, D41E=$1D (reads $D41F, no writes)
// After this sim, do the gate=0 + slow freq consecutive-reads test.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid6.asm -o tests/probe_swinsid6.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei

    // === Simulate checkarmsid D41F writes ===
    lda #$44        // 'D' - what checkarmsid writes to D41F
    sta $D41F
    lda #$49        // 'I' - what checkarmsid writes to D41E
    sta $D41E
    lda #$53        // 'S' - what checkarmsid writes to D41D
    sta $D41D
    lda #$00        // cleanup writes (checkarmsid cleanup)
    sta $D418
    sta $D41D
    sta $D41E
    sta $D41F

    // === Simulate checkpdsid D41D/E writes ===
    lda #$50        // 'P' to D41D
    sta $D41D
    lda #$44        // 'D' to D41E
    sta $D41E

    // === Simulate checkbacksid writes ===
    lda #$02
    sta $D41B
    lda #$01
    sta $D41C
    lda #$B5
    sta $D41D
    lda #$1D
    sta $D41E
    // (reads $D41F but no writes)

    // === Now run the checkswinsidnano test ===
    // Full SID reset (same as checkswinsidnano)
    lda #$00
    ldx #$1F
rst_loop: sta $D400,x
          dex
          bpl rst_loop
    cli
    jsr delay6ms    // 6ms settle

    // TEST A: gate=0, sawtooth, freq=$0001 (slow - oscillator barely advances)
    lda #$01
    sta $D40E       // freq lo
    lda #$00
    sta $D40F       // freq hi
    lda #$20        // sawtooth, gate=0
    sta $D412
    jsr delay6ms    // settle

    lda $D41B
    sta last_val
    ldy #$00
    ldx #$07
ta_loop:
    lda $D41B
    cmp last_val
    beq ta_same
    iny
    sta last_val
ta_same:
    dex
    bne ta_loop
    sty count_a     // count_a = changes in 7 pairs

    // TEST B: gate=1, noise, freq=$FFFF (same as current checkswinsidnano)
    lda #$FF
    sta $D40E
    sta $D40F
    lda #$81        // noise + gate
    sta $D412
    jsr delay12ms

    lda $D41B
    sta last_val
    ldy #$00
    ldx #$07
tb_loop:
    lda $D41B
    cmp last_val
    beq tb_same
    iny
    sta last_val
tb_same:
    dex
    bne tb_loop
    sty count_b

    // Silence
    lda #$00
    sta $D412

    // === Print results ===
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<lbl_a
    sta zp_ptr
    lda #>lbl_a
    sta zp_ptr+1
    jsr print_label
    lda count_a
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<lbl_b
    sta zp_ptr
    lda #>lbl_b
    sta zp_ptr+1
    jsr print_label
    lda count_b
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

lbl_a: .text "GATE0 SAW SLOW: "
       .byte 0
lbl_b: .text "GATE1 NSE FAST: "
       .byte 0

last_val: .byte 0
count_a:  .byte 0
count_b:  .byte 0

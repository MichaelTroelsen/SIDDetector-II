// probe_swinsid4.asm — test ENV3 ($D41C) advancement for SwinSID Nano detection
// Simulates the full detector context: runs uSID64 D41F sequence, then resets
// and checks if ENV3 advances from 0 after gate=1 + fastest attack
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_swinsid4.asm -o tests/probe_swinsid4.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei

    // === Simulate detector context: run uSID64 D41F sequence ===
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

    // Full SID reset (same as checkswinsidnano in detector)
    lda #$00
    ldx #$1F
rst_loop: sta $D400,x
          dex
          bpl rst_loop

    cli
    jsr delay6ms    // 6ms settle (same as detector)

    // === TEST A: ENV3 after fastest attack (gate=0 baseline) ===
    // Set voice 3: fastest attack+decay, sustain=0, release=fastest
    lda #$00
    sta $D413       // ATDCY3 = 0 (attack=2ms, decay=6ms)
    sta $D414       // SUREL3 = 0 (sustain=0, release=6ms)
    lda #$00
    sta $D412       // CR3: gate=0, no waveform

    jsr delay12ms   // wait for envelope to decay to 0

    lda $D41C       // baseline ENV3 (should be ~0 on SwinSID, bus noise on NOSID)
    sta env_base

    // === TEST B: gate=1, check ENV3 advancement ===
    lda #$01
    sta $D412       // CR3: gate=1, no waveform (attack starts)

    jsr delay6ms    // ~6ms — with 2ms attack, ENV3 should be near max

    // Read ENV3 multiple times to see advancement
    lda $D41C
    sta env_r1
    jsr delay3ms
    lda $D41C
    sta env_r2
    jsr delay3ms
    lda $D41C
    sta env_r3
    jsr delay3ms
    lda $D41C
    sta env_r4

    // === TEST C: gate=0 again, watch decay ===
    lda #$00
    sta $D412       // gate=0: decay/release starts
    jsr delay6ms
    lda $D41C
    sta env_decay1
    jsr delay6ms
    lda $D41C
    sta env_decay2

    // === TEST D: OSC3 ($D41B) with gate=1 after uSID64 context ===
    // This tests if the disturbed state matters for OSC3
    lda #$FF
    sta $D40E
    sta $D40F       // freq=$FFFF
    lda #$81        // noise + gate
    sta $D412
    jsr delay12ms

    lda $D41B
    sta osc3_base
    ldy #$00
    ldx #$07
osc_loop:
    lda $D41B
    cmp osc3_base
    beq osc_same
    iny
    sta osc3_base
osc_same:
    dex
    bne osc_loop
    sty osc3_count

    // Silence
    lda #$00
    sta $D412

    // === Print results ===
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    // "ENV BASE: XX"
    lda #<lbl_base
    sta zp_ptr
    lda #>lbl_base
    sta zp_ptr+1
    jsr print_label
    lda env_base
    jsr prhex
    lda #13
    jsr $FFD2

    // "ENV R1-R4: XX XX XX XX"
    lda #<lbl_r
    sta zp_ptr
    lda #>lbl_r
    sta zp_ptr+1
    jsr print_label
    lda env_r1
    jsr prhex
    lda #$20
    jsr $FFD2
    lda env_r2
    jsr prhex
    lda #$20
    jsr $FFD2
    lda env_r3
    jsr prhex
    lda #$20
    jsr $FFD2
    lda env_r4
    jsr prhex
    lda #13
    jsr $FFD2

    // "ENV DEC: XX XX"
    lda #<lbl_dec
    sta zp_ptr
    lda #>lbl_dec
    sta zp_ptr+1
    jsr print_label
    lda env_decay1
    jsr prhex
    lda #$20
    jsr $FFD2
    lda env_decay2
    jsr prhex
    lda #13
    jsr $FFD2

    // "OSC3 CNT: XX"
    lda #<lbl_osc
    sta zp_ptr
    lda #>lbl_osc
    sta zp_ptr+1
    jsr print_label
    lda osc3_count
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

lbl_base: .text "ENV BASE: "
          .byte 0
lbl_r:    .text "ENV R1-R4: "
          .byte 0
lbl_dec:  .text "ENV DEC: "
          .byte 0
lbl_osc:  .text "OSC3 CNT: "
          .byte 0

env_base:   .byte 0
env_r1:     .byte 0
env_r2:     .byte 0
env_r3:     .byte 0
env_r4:     .byte 0
env_decay1: .byte 0
env_decay2: .byte 0
osc3_base:  .byte 0
osc3_count: .byte 0

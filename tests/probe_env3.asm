// probe_env3.asm — test ENV3 advancement for SwinSID Nano detection
// Resets voice 3 (gate=0, max sustain, fastest attack+release), waits 15ms,
// reads D41C baseline. Then gate=1, waits 5ms, reads D41C again.
// SwinSID Nano: baseline≈0, after≈255. NOSID: both random bus values.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_env3.asm -o tests/probe_env3.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    lda #$00
    sta $D418           // volume=0

    // Reset voice 3: gate=0, fastest attack (2ms), slowest decay, max sustain, fastest release
    sta $D412           // gate=0, no waveform
    lda #$0F            // ATDCY3: attack=0 (2ms), decay=F (24s, irrelevant with max sustain)
    sta $D413
    lda #$F0            // SUREL3: sustain=F (max=255), release=0 (6ms)
    sta $D414

    // Wait ~18ms for release to reach 0
    lda #$06
    jsr rp_delay        // 6 * ~3ms

    // Read baseline ENV3 (should be 0 on SwinSID Nano; bus residue on NOSID)
    lda $D41C
    sta r_base

    // Set gate=1: start attack
    lda #$01
    sta $D412

    // Wait ~6ms (3x attack time — ENV3 should be at 255)
    lda #$02
    jsr rp_delay

    // Read ENV3 after attack
    lda $D41C
    sta r_after

    // Silence
    lda #$00
    sta $D412

    // Print results
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l_base
    sta zp_ptr
    lda #>l_base
    sta zp_ptr+1
    jsr pl
    lda r_base
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_after
    sta zp_ptr
    lda #>l_after
    sta zp_ptr+1
    jsr pl
    lda r_after
    jsr prhex
    lda #13
    jsr $FFD2

    // Also compute delta
    lda r_after
    sec
    sbc r_base
    sta r_delta
    lda #<l_delta
    sta zp_ptr
    lda #>l_delta
    sta zp_ptr+1
    jsr pl
    lda r_delta
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

l_base:  .text "BASE: "
         .byte 0
l_after: .text "AFTR: "
         .byte 0
l_delta: .text "DELT: "
         .byte 0

r_base:  .byte 0
r_after: .byte 0
r_delta: .byte 0

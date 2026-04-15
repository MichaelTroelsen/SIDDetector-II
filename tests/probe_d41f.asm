// probe_d41f.asm — D41F register behavior after writing non-FF values
// Tests whether D41F holds written value, returns $FF, or drifts to noise.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_d41f.asm -o tests/probe_d41f.prg

.const zp_ptr = $FB
.const data2  = $A5

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    // simulate checkpalntsc context
    cli
    lda #$18
    jsr rp_delay
    sei

    // Reset all SID regs
    lda #$00
    ldx #$1F
rst: sta $D400,x
    dex
    bpl rst

    // Test 1: Read D41F right after reset (all $00 written)
    lda $D41F
    sta r_rst

    // Test 2: Write $5A, wait 10ms, read
    lda #$5A
    sta $D41F
    lda #$03
    jsr rp_delay        // ~9ms
    lda $D41F
    sta r_5a

    // Test 3: Write $A5, wait 10ms, read
    lda #$A5
    sta $D41F
    lda #$03
    jsr rp_delay
    lda $D41F
    sta r_a5

    // Test 4: Write $55, wait 10ms, read twice for stability
    lda #$55
    sta $D41F
    lda #$03
    jsr rp_delay
    lda $D41F
    sta r_55a
    lda #$01
    jsr rp_delay        // ~3ms more
    lda $D41F
    sta r_55b

    // Print results
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    lda #<l_rst
    sta zp_ptr
    lda #>l_rst
    sta zp_ptr+1
    jsr pl
    lda r_rst
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_5a
    sta zp_ptr
    lda #>l_5a
    sta zp_ptr+1
    jsr pl
    lda r_5a
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_a5
    sta zp_ptr
    lda #>l_a5
    sta zp_ptr+1
    jsr pl
    lda r_a5
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_55a
    sta zp_ptr
    lda #>l_55a
    sta zp_ptr+1
    jsr pl
    lda r_55a
    jsr prhex
    lda #13
    jsr $FFD2

    lda #<l_55b
    sta zp_ptr
    lda #>l_55b
    sta zp_ptr+1
    jsr pl
    lda r_55b
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

l_rst: .text "RST:  "
       .byte 0
l_5a:  .text "W5A:  "
       .byte 0
l_a5:  .text "WA5:  "
       .byte 0
l_55a: .text "W55A: "
       .byte 0
l_55b: .text "W55B: "
       .byte 0

r_rst: .byte 0
r_5a:  .byte 0
r_a5:  .byte 0
r_55a: .byte 0
r_55b: .byte 0

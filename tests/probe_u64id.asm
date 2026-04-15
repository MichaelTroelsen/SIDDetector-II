// probe_u64id.asm — read Ultimate II+ identification from $DF00-$DF1F
// The Ultimate II+ exposes API registers via the I/O2 area ($DF00-$DFFF).
// This probes for identification bytes that can detect the cartridge.
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_u64id.asm -o tests/probe_u64id.prg

.const zp_ptr = $FB

* = $0801
    .byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  // 10 SYS 2061

entry:
    sei
    cli

    // Read $DF00-$DF1F (32 bytes) and print as hex
    lda #147
    jsr $FFD2
    lda #13
    jsr $FFD2

    // Print "DF00: " header
    lda #<lbl_df00
    sta zp_ptr
    lda #>lbl_df00
    sta zp_ptr+1
    jsr print_label

    ldx #$00
df_loop:
    lda $DF00,x
    jsr prhex
    lda #$20
    jsr $FFD2
    inx
    cpx #$10
    bne df_loop
    lda #13
    jsr $FFD2

    // Print "DF10: " header
    lda #<lbl_df10
    sta zp_ptr
    lda #>lbl_df10
    sta zp_ptr+1
    jsr print_label

    ldx #$10
df_loop2:
    lda $DF00,x
    jsr prhex
    lda #$20
    jsr $FFD2
    inx
    cpx #$20
    bne df_loop2
    lda #13
    jsr $FFD2

    // Also read $DE00-$DE0F (I/O1)
    lda #<lbl_de00
    sta zp_ptr
    lda #>lbl_de00
    sta zp_ptr+1
    jsr print_label

    ldx #$00
de_loop:
    lda $DE00,x
    jsr prhex
    lda #$20
    jsr $FFD2
    inx
    cpx #$10
    bne de_loop
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

lbl_df00: .text "DF00: "
          .byte 0
lbl_df10: .text "DF10: "
          .byte 0
lbl_de00: .text "DE00: "
          .byte 0

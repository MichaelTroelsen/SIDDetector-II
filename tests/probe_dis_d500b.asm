// probe_dis_d500b.asm — why does s_s_arm_chk's cross-read call $D500 a mirror?
//
// The trace showed the D500 candidate is rejected by the oscillator cross-read
// in s_s_arm_chk, before sfx_probe_dis_echo is ever reached — even though
// probe_dis_d500 proved the ARMSID personality answers 'N' at $D51B, and even
// though a monitor read at the rejection point shows $D51B = $00.
//
// So the loop must catch a transient non-zero. This replicates the cross-read
// byte for byte and records ALL 24 reads so the transient is visible.
//
// s_s_arm_chk does:
//     ldy #$12 / lda #$00 / sta (sptr),y     silence candidate voice 3
//     lda #$FF / sta $D40F                   primary voice 3 freq hi = max
//     lda #$21 / sta $D412                   primary voice 3 saw + gate
//     ldy #$1B / ldx #$18
//   loop: lda (sptr),y / bne MIRROR / dex / bne loop
//
// Results:
//   $5000       = D51B read once before any of this (baseline)
//   $5010..5027 = the 24 successive D51B reads, in order
//   $5030       = D51C after the loop (config-mode tell: $4F = 'O')
//   $5031       = D41B after the loop (primary OSC3, expected non-zero)
//
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_dis_d500b.asm -o tests/probe_dis_d500b.prg
// Run:   x64sc -autostart tests/probe_dis_d500b.prg -sidextra 1 -sid2address 54528 -sidvariant2 armsid

.const sptr = $f9

* = $0801
    .word $0801
    .word 2024
    .byte $9e
    .text "2061"
    .byte 0

* = $080d
    sei
    lda #$7f
    sta $dc0d
    lda $dc0d

    // sptr = $D500, exactly as the scan has it at this candidate
    lda #$00
    sta sptr
    lda #$d5
    sta sptr+1

    // Quiesce both slots the way the detection chain leaves them: checkrealsid's
    // stoprealsid zeroes voice 3 ctrl and freq-hi on the slot it probed.
    lda #$00
    sta $d418
    sta $d40e
    sta $d40f
    sta $d412
    sta $d538
    sta $d50e
    sta $d50f
    sta $d512
    ldx #$ff
dly0: dex
    bne dly0

    lda $d51b
    sta $5000               // baseline

    // ---- s_s_arm_chk cross-read, verbatim ---------------------------------
    ldy #$12
    lda #$00
    sta (sptr),y            // silence candidate voice 3
    lda #$ff
    sta $d40f               // primary voice 3 freq hi = max
    lda #$21
    sta $d412               // primary voice 3 sawtooth + gate
    ldy #$1b
    ldx #$00                // index into the log (loop below runs 24 times)
rdlp:
    lda (sptr),y            // read candidate + $1B
    sta $5010,x
    inx
    cpx #$18
    bne rdlp

    lda $d51c
    sta $5030
    lda $d41b
    sta $5031

    // leave the primary quiet again
    lda #$00
    sta $d412
    sta $d40f

spin:
    jmp spin

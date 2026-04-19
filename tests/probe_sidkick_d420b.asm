// probe_sidkick_d420b.asm — SIDKick-pico probe at D420, NO prior SIDFX handshake
// Tests whether SIDFX interference (post-PNP) is the reason config mode fails.
//
// Results at $5000:
//   $5000 = D43D byte[0] (expect 'S'=$53 if config mode works)
//   $5001 = D43D byte[1] (expect 'K'=$4B)
//   $5002 = D43B after Phase 2 auto-detect (expect 2=8580 or 3=6581)
//
// Read: ./bin/c64u machine read-mem 5000 --length 3

* = $0801
    .word $0801
    .word 2024
    .byte $9e
    .text "2061"
    .byte 0

* = $080d
    sei
    lda #$7f
    sta $dc0d       // disable CIA timer IRQ
    lda $dc0d

    // Silence SID1 voice 3
    lda #$00
    sta $d412
    sta $d40e
    sta $d40f

    // ---- Phase 1: config mode at D420, no prior SIDFX handshake ----
    lda #$ff
    sta $d43f       // D420+$1F: enter config mode

    ldx #$ff        // wait ~1ms
dly1:
    dex
    bne dly1

    lda #$e0
    sta $d43e
    ldx #$40
dly2:
    dex
    bne dly2
    lda $d43d
    sta $5000

    lda #$e1
    sta $d43e
    ldx #$40
dly3:
    dex
    bne dly3
    lda $d43d
    sta $5001

    // Exit config
    lda #$00
    sta $d438

    ldx #$ff
dly4:
    dex
    bne dly4

    // ---- Phase 2: auto-detect ----
    lda #$00
    sta $d438       // vol=0, ensure normal mode
    lda #$ff
    sta $d42e       // voice 3 freq lo
    sta $d42f       // voice 3 freq hi
    sta $d432       // ctrl = all waveforms
    lda #$20
    sta $d432       // trigger: SAW, gate off
    ldx #$10
dly5:
    dex
    bne dly5
    lda $d43b       // model: 2=8580, 3=6581
    sta $5002
    lda #$00
    sta $d432

spin:
    jmp spin

// probe_sidkick_d420.asm — SIDKick-pico probe at D420 (SIDFX LFT slot)
//
// Phase 1: config mode via $FF→D43F, read VERSION_STR at D43D
// Phase 2: auto-detect via voice-3 trigger, read model from D43B
//
// Results at $5000:
//   $5000 = D43D byte[0] after config entry (expect 'S'=$53)
//   $5001 = D43D byte[1] (expect 'K'=$4B)
//   $5002 = D43B after Phase 2 auto-detect (expect 2=8580 or 3=6581)
//   $5003 = D43B raw before any setup (baseline)
//
// Read: ./bin/c64u machine read-mem 5000 --length 4

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
    lda $dc0d       // ack any pending

    // Baseline: read D43B before anything
    lda $d43b
    sta $5003

    // Silence SID1 voice 3 (minimise OSC3 bleed)
    lda #$00
    sta $d412       // voice 3 ctrl = off
    sta $d40e       // freq lo = 0
    sta $d40f       // freq hi = 0

    // ---- Phase 1: config mode at D420 ----
    lda #$ff
    sta $d43f       // D420+$1F: enter config mode

    // Wait ~1ms
    ldx #$ff
dly1:
    dex
    bne dly1

    lda #$e0
    sta $d43e       // VERSION_STR pointer → byte 0
    ldx #$40
dly2:
    dex
    bne dly2
    lda $d43d
    sta $5000       // byte[0] (expect 'S'=$53)

    lda #$e1
    sta $d43e       // pointer → byte 1
    ldx #$40
dly3:
    dex
    bne dly3
    lda $d43d
    sta $5001       // byte[1] (expect 'K'=$4B)

    // Exit config mode
    lda #$00
    sta $d438       // D420+$18: any non-config write exits config

    // Delay after exit
    ldx #$ff
dly4:
    dex
    bne dly4

    // ---- Phase 2: auto-detect via voice-3 at D420 ----
    // Preconditions: voice 3 freq hi/lo = $FF, then write $20 to ctrl
    lda #$ff
    sta $d42e       // D420+$0E: voice 3 freq lo = $FF
    sta $d42f       // D420+$0F: voice 3 freq hi = $FF
    sta $d432       // D420+$12: voice 3 ctrl = $FF (gate on + all waveforms)
    lda #$20
    sta $d432       // D420+$12: ctrl = $20 (triangle, gate off) → auto-detect trigger
    lda #$04
    sta $d418       // D420+$18: volume = 4 (non-zero, normal mode)

    // Short delay
    ldx #$40
dly5:
    dex
    bne dly5

    lda $d43b       // D420+$1B: read model (2=8580, 3=6581)
    sta $5002

    // Stop voice 3
    lda #$00
    sta $d432

spin:
    jmp spin

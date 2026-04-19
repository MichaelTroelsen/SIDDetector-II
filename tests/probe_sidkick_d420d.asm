// probe_sidkick_d420d.asm — Check if SIDKick Pico at D420 echoes D43D writes
// in normal mode (no config mode). Also check ENV3 (D43C) for unique behavior.
//
// Results at $5000:
//   $5000 = D43D readback after writing $42 (echo test)
//   $5001 = D43C (ENV3 at D420) with voice 3 envelope active
//   $5002 = D43B (OSC3 at D420) with voice 3 running
//   $5003 = D43D readback after $FF config-try then $00 D43E (not $E0/$E1)
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
    sta $dc0d
    lda $dc0d

    // Silence everything first
    lda #$00
    sta $d418
    sta $d438

    // Test A: write $42 to D43D, read back
    lda #$42
    sta $d43d
    ldx #$20
dly1: dex
    bne dly1
    lda $d43d
    sta $5000

    // Test B: set voice 3 at D420 running, read ENV3 and OSC3
    lda #$ff
    sta $d42e       // voice 3 freq lo = $FF
    sta $d42f       // voice 3 freq hi = $FF
    lda #$41        // gate on, triangle
    sta $d432       // voice 3 ctrl
    lda #$f0        // max attack/decay
    sta $d433       // attack/decay
    lda #$f0        // max sustain/release
    sta $d434       // sustain/release
    lda #$0f        // volume = 15
    sta $d438
    ldx #$ff        // wait for envelope to rise
dly2: dex
    bne dly2
    lda $d43c       // ENV3 at D420
    sta $5001
    lda $d43b       // OSC3 at D420
    sta $5002

    // Test C: try config entry with $FF to D43F, then pointer $00 (not $E0)
    // Some firmware uses reg $1E=0 as the byte-0 selector instead of $E0
    lda #$00
    sta $d432       // stop voice 3
    sta $d438       // silence
    lda #$ff
    sta $d43f       // config entry
    ldx #$ff
dly3: dex
    bne dly3
    lda #$00        // pointer = 0 (alternative selector)
    sta $d43e
    ldx #$40
dly4: dex
    bne dly4
    lda $d43d
    sta $5003
    lda #$00
    sta $d438

spin:
    jmp spin

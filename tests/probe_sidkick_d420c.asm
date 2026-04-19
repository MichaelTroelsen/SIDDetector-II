// probe_sidkick_d420c.asm — Try triggering SIDKick Pico config mode via CS1 (D41F)
// then reading from D420 (D43D).
// Hypothesis: SIDKick Pico firmware at D420 monitors all SID bus writes regardless of CS.
//
// Also tests Phase 2 trigger from D400 addresses: maybe the auto-detect reads D41B
// regardless of which socket the chip is in.
//
// Results at $5000:
//   $5000 = D43D byte[0] after $FF→D41F (CS1 trigger, read from CS2)
//   $5001 = D43D byte[1]
//   $5002 = D41B after Phase 2 via D400 addresses (auto-detect on CS1 path)
//   $5003 = D43B after Phase 2 via D400 addresses (same trigger, read from D420)
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

    lda #$00
    sta $d412       // silence SID1 voice 3
    sta $d40e
    sta $d40f

    // ---- Test A: trigger config via CS1 (D41F), read from D43D ----
    lda #$ff
    sta $d41f       // CS1 config mode trigger (SID1's register $1F)

    ldx #$ff        // ~1ms delay
dly1:
    dex
    bne dly1

    lda #$e0
    sta $d43e       // D420+$1E: VERSION_STR pointer → byte 0
    ldx #$40
dly2:
    dex
    bne dly2
    lda $d43d       // D420+$1D: read byte[0] — expect 'S' if SKPico monitors CS1
    sta $5000

    lda #$e1
    sta $d43e
    ldx #$40
dly3:
    dex
    bne dly3
    lda $d43d
    sta $5001

    // Exit config (write to D438 / D418)
    lda #$00
    sta $d438
    sta $d418

    ldx #$ff
dly4:
    dex
    bne dly4

    // ---- Test B: Phase 2 trigger via D400, read from D41B AND D43B ----
    lda #$00
    sta $d418
    lda #$ff
    sta $d40e       // SID1 voice 3 freq lo = $FF
    sta $d40f       // SID1 voice 3 freq hi = $FF
    sta $d412       // SID1 voice 3 ctrl = $FF
    lda #$20
    sta $d412       // trigger via D400
    ldx #$10
dly5:
    dex
    bne dly5
    lda $d41b       // read D41B (CS1 path model value)
    sta $5002
    lda $d43b       // read D43B (CS2 path — same chip if it monitors both?)
    sta $5003
    lda #$00
    sta $d412

spin:
    jmp spin

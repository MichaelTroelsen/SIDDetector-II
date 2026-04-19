// probe_d41d_holdover.asm — Test D43D bus holdover vs real echo.
// Real 6581 reg $1D is unmapped: reading after write returns bus-holdover value.
// SIDKick Pico latches reg $1D and returns it even after intervening bus writes.
//
// Strategy: write $B5 to D43D, then write $00 to D438 (intervening D420 write),
// then read D43D. If SIDKick Pico: still $B5. If 6581 holdover: bus was driven
// $00 by the D438 write, so D43D may return $00.
//
// Results at $5000:
//   $5000 = D43D immediate read after $B5 write (no intervening write)
//   $5001 = D43D read after $00→D438 intervening write (discriminating test)
//   $5002 = D43D read after long delay (~2ms) with no intervening writes
//   $5003 = D43D read after $FF→D418 intervening write (SID1 domain)
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

    // Silence SID volumes
    lda #$00
    sta $d418
    sta $d438

    // Short settle
    ldx #$40
dly0: dex
    bne dly0

    // Test A: write $B5 to D43D, read back immediately (0 extra cycles)
    lda #$B5
    sta $d43d
    lda $d43d   // immediate read — bus holdover or PICO echo
    sta $5000

    // Test B: write $B5 to D43D, then $00 to D438, then read D43D
    lda #$B5
    sta $d43d
    lda #$00
    sta $d438   // intervening write to different D420 register
    lda $d43d   // PICO: $B5 (latched); 6581: $00 (bus driven $00 by D438 write)
    sta $5001

    // Test C: write $B5 to D43D, wait ~2ms, read D43D (no intervening writes)
    lda #$B5
    sta $d43d
    ldx #$ff
dly1: dex
    bne dly1
    ldx #$ff
dly2: dex
    bne dly2
    lda $d43d   // PICO: $B5; 6581: bus may have decayed
    sta $5002

    // Test D: write $B5 to D43D, then $FF to D418 (SID1 volume write), read D43D
    lda #$B5
    sta $d43d
    lda #$ff
    sta $d418   // intervening write to SID1 (different CS, different address)
    lda #$00
    sta $d418   // restore
    lda $d43d   // PICO: $B5; 6581: may return $FF or $00 from SID1 bus activity
    sta $5003

spin:
    jmp spin

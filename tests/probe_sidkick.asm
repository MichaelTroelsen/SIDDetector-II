// probe_sidkick.asm — SIDKick-pico VERSION_STR probe
// Enters config mode ($FF→D41F, $E0→D41E), reads 32 bytes from D41D,
// stores raw bytes to $0400 (screen), then spins.
// Read results with: ./bin/c64u machine read-mem 0400 --length 32

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

    // Enter config mode
    lda #$ff
    sta $d41f

    // Short delay (~300 cycles) so pico can process config mode entry
    ldx #$64
dly1:
    dex
    bne dly1

    // Set VERSION_STR pointer
    lda #$e0
    sta $d41e

    // Short delay (~300 cycles) before reading
    ldx #$64
dly2:
    dex
    bne dly2

    // Read 32 bytes: advance pointer manually via D41E ($E0, $E1, $E2, ...)
    ldx #$00
read_loop:
    txa
    clc
    adc #$e0        // D41E value = $E0 + byte index
    sta $d41e       // set pointer to byte X
    lda $d41d       // read that byte
    sta $0400,x
    inx
    cpx #$20
    bne read_loop

spin:
    jmp spin

// probe_armsid_d420e.asm — Check where ARMSID at D420 echoes DIS response.
// Hypothesis: ARMSID firmware hardcodes echo to D41B (CS1 $1B), not D43B (CS2 $1B).
//
// Results at $5000:
//   $5000 = D43B after DIS to D43F/D43E/D43D (CS2 DIS → expect $4E if CS2 echo)
//   $5001 = D41B after DIS to D43F/D43E/D43D (CS2 DIS → expect $4E if hardcoded CS1 echo)
//   $5002 = D43B after DIS to D41F/D41E/D41D (CS1 DIS → does ARMSID at D420 snoop CS1?)
//   $5003 = D41B after DIS to D41F/D41E/D41D (CS1 DIS via D41x — 8580 primary won't echo)
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
    sta $d418
    sta $d438

    // ---- Test A: DIS to CS2 (D43F/D43E/D43D), read D43B and D41B ----
    lda #$00
    sta $d43d
    ldx #$20
dly0: dex
    bne dly0

    lda #$44
    sta $d43f
    lda #$49
    sta $d43e
    lda #$53
    sta $d43d

    ldx #$ff
dly1: dex
    bne dly1
    ldx #$ff
dly2: dex
    bne dly2

    lda $d43b       // CS2 echo — ARMSID at D420 CS2 output?
    sta $5000
    lda $d41b       // CS1 — does ARMSID at D420 drive D41B?
    sta $5001

    // Cleanup A
    lda #$00
    sta $d43d
    sta $d43e
    sta $d43f

    ldx #$ff
dly3: dex
    bne dly3

    // ---- Test B: DIS to CS1 (D41F/D41E/D41D), read D43B and D41B ----
    // Tests whether ARMSID at D420 snoops CS1 writes
    lda #$00
    sta $d41d
    ldx #$20
dly4: dex
    bne dly4

    lda #$44
    sta $d41f
    lda #$49
    sta $d41e
    lda #$53
    sta $d41d

    ldx #$ff
dly5: dex
    bne dly5
    ldx #$ff
dly6: dex
    bne dly6

    lda $d43b       // CS2 — ARMSID at D420 snooped CS1 DIS?
    sta $5002
    lda $d41b       // CS1 — 8580 at D400 won't echo; ARMSID at D420 via CS1 decode?
    sta $5003

    // Cleanup B
    lda #$00
    sta $d41d
    sta $d41e
    sta $d41f

spin:
    jmp spin

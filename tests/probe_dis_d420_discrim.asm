// probe_dis_d420_discrim.asm — Discriminate what drives D43B=$4E after DIS.
//
// Tests various partial DIS sequences to isolate the source of the $4E response:
// - If primary ARMSID (D400) drives: partial DIS via D4xx should trigger it.
// - If secondary ARMSID (D420): would also trigger on D4xx CS2 writes.
// - If CS1-specific: only D41x writes would trigger it.
//
// Results at $5000:
//   $5000 = D43B after FULL DIS to D43F/D43E/D43D (current behavior, expect $4E)
//   $5001 = D43B after 'S' only written to D43D (partial DIS — minimal trigger)
//   $5002 = D43B after FULL DIS to D41F/D41E/D41D (CS1 DIS — triggers primary ARMSID D41B)
//   $5003 = D41B after FULL DIS to D41F/D41E/D41D (primary ARMSID echo, expect $4E)
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

    // ---- Test A: full DIS to CS2 (D43F/D43E/D43D), read D43B ----
    lda #$00
    sta $d43d           // pre-clear
    ldx #$20
dly0: dex
    bne dly0

    lda #$44            // 'D' → D43F (CS2)
    sta $d43f
    lda #$49            // 'I' → D43E
    sta $d43e
    lda #$53            // 'S' → D43D
    sta $d43d

    ldx #$ff            // wait ~loop1sek×2
dly1: dex
    bne dly1
    ldx #$ff
dly2: dex
    bne dly2

    lda $d43b           // read D43B
    sta $5000

    // Cleanup A
    lda #$00
    sta $d43d
    sta $d43e
    sta $d43f

    ldx #$ff
dly3: dex
    bne dly3

    // ---- Test B: ONLY 'S' written to D43D (partial DIS), read D43B ----
    lda #$00
    sta $d43d           // pre-clear
    ldx #$20
dly4: dex
    bne dly4

    lda #$53            // 'S' only → D43D (no 'D'/'I' setup)
    sta $d43d

    ldx #$ff
dly5: dex
    bne dly5
    ldx #$ff
dly6: dex
    bne dly6

    lda $d43b           // read D43B — if ARMSID triggered by partial DIS?
    sta $5001

    // Cleanup B
    lda #$00
    sta $d43d

    ldx #$ff
dly7: dex
    bne dly7

    // ---- Test C: full DIS to CS1 (D41F/D41E/D41D), read D43B (not D41B) ----
    lda #$00
    sta $d41d           // pre-clear CS1
    ldx #$20
dly8: dex
    bne dly8

    lda #$44            // 'D' → D41F (CS1 — primary ARMSID)
    sta $d41f
    lda #$49            // 'I' → D41E
    sta $d41e
    lda #$53            // 'S' → D41D
    sta $d41d

    ldx #$ff
dly9: dex
    bne dly9
    ldx #$ff
dlya: dex
    bne dlya

    lda $d43b           // D43B after CS1 DIS (primary ARMSID echo is at D41B, not D43B)
    sta $5002
    lda $d41b           // D41B after CS1 DIS — primary ARMSID echo
    sta $5003

    // Cleanup C
    lda #$00
    sta $d41d
    sta $d41e
    sta $d41f

spin:
    jmp spin

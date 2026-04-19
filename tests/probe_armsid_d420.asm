// probe_armsid_d420.asm — Check if ARMSID at D420 (SIDFX LFT slot) echoes DIS sequence
// at D43B (base+$1B), and whether SID1 OSC3 interferes via D43B.
//
// SIDFX isolates D420 from SID1, so D43B should reflect ARMSID's state, not SID1 OSC3.
//
// Results at $5000:
//   $5000 = D43B baseline (before any writes — SID1 isolation check)
//   $5001 = D43B after DIS sequence: 'N'=$4E expected for ARMSID
//   $5002 = D43B after cleanup (echo cleared?)
//   $5003 = D41B (SID1 OSC3 for comparison — should differ from D43B if SIDFX isolates)
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

    // Silence SID1 voice 3 so it doesn't actively drive D41B/D43B
    lda #$00
    sta $d418       // SID1 volume = 0
    sta $d40e       // SID1 voice 3 freq lo = 0
    sta $d40f       // SID1 voice 3 freq hi = 0
    sta $d412       // SID1 voice 3 ctrl = 0 (gate off)
    sta $d438       // D420 volume = 0

    // Wait ~1ms for SID1 to settle
    ldx #$ff
dly0: dex
    bne dly0

    // Test A: read D43B baseline (is SID1 OSC3 leaking through SIDFX?)
    lda $d43b
    sta $5000

    // Also capture SID1 OSC3 for comparison
    lda $d41b
    sta $5003

    // Test B: write DIS sequence to D420 registers, read D43B echo
    // Pre-clear base+$1D (D43D) — reset ARMSID echo state
    lda #$00
    sta $d43d

    ldx #$20
dly1: dex
    bne dly1

    // DIS sequence: 'D'=$44→D43F, 'I'=$49→D43E, 'S'=$53→D43D
    lda #$44        // 'D'
    sta $d43f
    lda #$49        // 'I'
    sta $d43e
    lda #$53        // 'S'
    sta $d43d

    // Wait ~2×loop1sek (same as sfx_probe_dis_echo)
    ldx #$ff
dly2: dex
    bne dly2
    ldx #$ff
dly3: dex
    bne dly3

    // Read D43B — ARMSID echoes 'N'=$4E here; SwinSID U echoes 'S'=$53
    lda $d43b
    sta $5001

    // Cleanup: write $00 to D43F/D43E/D43D
    lda #$00
    sta $d43f
    sta $d43e
    sta $d43d

    ldx #$40
dly4: dex
    bne dly4

    // Test C: read D43B after cleanup (should be clear again)
    lda $d43b
    sta $5002

spin:
    jmp spin

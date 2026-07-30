// probe_dis_d500.asm — does an ARMSID / SwinSID U at $D500 answer the DIS probe?
//
// CODE-REVIEW.md P0-5: with the ULTISID mislabel fixed, an ARMSID at $D420 is
// now named correctly (that path calls Checkarmsid directly), but one at $D500
// still falls back to "8580 FOUND". The D5xx path relies on sfx_probe_dis_echo
// reading the DIS echo from base+$1B, and the echo was not coming back.
//
// Reading ../vice-sidvariant/src/sid/sid-variant-armsid.c says it SHOULD:
// the personality is slot-relative (reg is a slot-local offset, state is
// per-slot), and a base+$1B read while in config mode with no sub-command
// latched returns 'N' ($4E). So either that reasoning is wrong, or something
// in siddetector's sequence differs from what this probe does.
//
// This probe replicates sfx_probe_dis_echo against $D500 exactly, step by step,
// and records what each step actually returns.
//
// Results at $5000:
//   $5000 = D51B baseline, before any writes  (idle -> ResID OSC3, expect $00)
//   $5001 = D51B after DIS written to D51F/D51E/D51D  ('N'=$4E if it answered)
//   $5002 = D51C after DIS                             ('O'=$4F if it answered)
//   $5003 = D51B after the D41B primary ACK read (what sfx_probe_dis_echo sees)
//   $5004 = D41B for comparison (primary slot, must not be the source)
//   $5005 = D51B after cleanup writes                  (echo cleared?)
//   $5006 = D51D read after DIS  (plain ARMSID returns 'R'=$52 per the source)
//
// Build: java -jar C:/debugger/kickasm/KickAss.jar tests/probe_dis_d500.asm -o tests/probe_dis_d500.prg
// Run:   x64sc -autostart tests/probe_dis_d500.prg -sidextra 1 -sid2address 54528 -sidvariant2 armsid

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

    // Quiesce both slots' voice 3 so OSC3 reads are not driven by ResID.
    lda #$00
    sta $d418       // primary volume
    sta $d40e
    sta $d40f
    sta $d412       // primary voice 3 ctrl = 0 -> OSC3 reads 0
    sta $d538       // D500 volume
    sta $d50e
    sta $d50f
    sta $d512       // D500 voice 3 ctrl = 0

    ldx #$ff
dly0: dex
    bne dly0

    // --- baseline -----------------------------------------------------------
    lda $d51b
    sta $5000

    // --- DIS entry cookie, exactly as sfx_probe_dis_echo writes it ----------
    lda #$00
    sta $d51d       // pre-clear base+$1D
    lda #$44        // 'D'
    sta $d51f
    lda #$49        // 'I'
    sta $d51e
    lda #$53        // 'S'
    sta $d51d

    // settle: 2x loop1sek equivalent (~5.6 ms), well inside the personality's
    // ~100 ms idle timeout
    ldx #$ff
dly1: dex
    nop
    nop
    nop
    nop
    bne dly1
    ldx #$ff
dly2: dex
    nop
    nop
    nop
    nop
    bne dly2

    // --- what does the secondary answer now? --------------------------------
    lda $d51b
    sta $5001
    lda $d51c
    sta $5002
    lda $d51d
    sta $5006

    // --- the primary ACK read that sfx_probe_dis_echo performs first --------
    lda $d41b
    sta $5004
    lda $d51b       // ...then the echo read it actually returns
    sta $5003

    // --- cleanup, as sfx_probe_dis_echo does on exit ------------------------
    lda #$00
    sta $d51d
    sta $d51e
    sta $d51f
    lda $d51b
    sta $5005

spin:
    jmp spin

const fs = require('fs');
let src = fs.readFileSync('siddetector.asm', 'utf8');
let changed = 0;

function rep(a, b) {
  if (src.includes(a)) { src = src.replace(a, b); changed++; console.log('OK: ' + a.substring(0,50).replace(/\n/g,'\\n')); }
  else { console.log('XX: ' + a.substring(0,50).replace(/\n/g,'\\n')); }
}

// ── basend / start ───────────────────────────────────────────────────────────
rep(
`basend: \n    .word 0 \n    *=$080d`,
`basend:                     // end-of-BASIC marker (two zero bytes)
    .word 0
    *=$080D             // code origin: $080D = decimal 2061 = SYS target`
);

rep(
`start:           sei     \n                ldx #$00\n                lda #$00\ninit_sid_list:\n                sta sid_list_h,x\n                sta sid_list_l,x\n                sta sid_list_t,x\n                inx\n                cpx #$08\n                bne init_sid_list `,
`// ============================================================
// ENTRY POINT - invoked by SYS 2061; re-entered when SPACE pressed.
// Order: init tables -> draw screen -> PAL/NTSC -> machine type -> detection chain
// ============================================================
start:
                sei                     // disable IRQ during initialisation
                ldx #$00
                lda #$00
init_sid_list:                          // zero the 8-slot SID result tables
                sta sid_list_h,x        // SID address high byte ($D4/$D5 ...)
                sta sid_list_l,x        // SID address low byte  ($00/$20 ...)
                sta sid_list_t,x        // chip type code for this slot
                inx
                cpx #$08               // 8 slots; slot 0 unused, slots 1-7 active
                bne init_sid_list`
);

// ── PAL/NTSC ─────────────────────────────────────────────────────────────────
rep(
`                jsr printscreen\n                jsr checkpalntsc\n                lda $02a6 // pal/ntsc\n                beq cntsc                    // if accu=0, then go to NTSC`,
`                jsr printscreen         // blit static 25x40 UI to screen RAM $0400

                // checkpalntsc patches NMI vector to RTI then checks if a
                // raster IRQ at line $137 fires; result written to $02A6:
                //   1 = PAL  (~50 Hz, 312 raster lines)
                //   0 = NTSC (~60 Hz, 263 raster lines)
                // All timing loops below depend on this value.
                jsr checkpalntsc
                lda $02a6               // read KERNAL PAL/NTSC variable
                beq cntsc               // 0 = NTSC`
);

rep(
`                txs\n                ldx #12    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<pal_text\n                ldy #>pal_text           // otherwise print PAL-text\n                jsr  $AB1E                   // and go back.\n                jmp check_cbmtype\ncntsc:\n                txs\n                ldx #12    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<ntsc_text\n                ldy #>ntsc_text          // print NTSC-text\n                jsr  $AB1E                   // and go back.`,
`                txs                     // KERNAL cursor call uses X/Y; TXS preserves X
                ldx #12                 // row 12 = "pal/ntsc..:" screen line
                ldy #13                 // col 13 = result field
                jsr $E50C               // KERNAL $E50C: position cursor (row=X, col=Y)
                tsx
                lda #<pal_text
                ldy #>pal_text
                jsr  $AB1E              // KERNAL $AB1E: print zero-terminated PETSCII string
                jmp check_cbmtype
cntsc:
                txs
                ldx #12
                ldy #13
                jsr $E50C
                tsx
                lda #<ntsc_text
                ldy #>ntsc_text
                jsr  $AB1E`
);

// ── Machine type ─────────────────────────────────────────────────────────────
rep(
`check_cbmtype:\n                jsr check128\n                txs\n                ldx #12    // Select row \n                ldy #30    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda za7\n                cmp #$FF\n                bne c128_c128\n                lda #<c64_text\n                ldy #>c64_text          // print c64-text\n                jsr  $AB1E                   // and go back.\n                jmp ibegin\nc128_c128:\n                lda za7\n                cmp #$FC\n                bne c128_tc64\n                lda #<c128_text\n                ldy #>c128_text          // print c128-text\n                jsr  $AB1E                   // and go back.\n                jmp ibegin\nc128_tc64:\n                lda #<tc64_text\n                ldy #>tc64_text          // print tc64-text\n                jsr  $AB1E                   // and go back.`,
`// check128 probes $D030 (C128 speed register; open bus on C64 -> $FF).
// Then writes $2A to $D0FE to distinguish TC64 from a real C128. Result -> za7:
//   $FF = C64,  $FC = C128,  other = TC64 (Turbo Chameleon 64 cartridge)
check_cbmtype:
                jsr check128
                txs
                ldx #12                 // same row as PAL/NTSC; col 30 for machine label
                ldy #30
                jsr $E50C
                tsx
                lda za7
                cmp #$FF
                bne c128_c128           // not $FF -> check C128 vs TC64
                lda #<c64_text          // $FF = standard Commodore 64
                ldy #>c64_text
                jsr  $AB1E
                jmp ibegin
c128_c128:
                lda za7
                cmp #$FC               // $FC = Commodore 128
                bne c128_tc64
                lda #<c128_text
                ldy #>c128_text
                jsr  $AB1E
                jmp ibegin
c128_tc64:                             // za7 != $FF and != $FC -> Turbo Chameleon 64
                lda #<tc64_text
                ldy #>tc64_text
                jsr  $AB1E`
);

// ── ibegin / iloop ───────────────────────────────────────────────────────────
rep(
`ibegin:                \n                lda #$ff    // make sure the check is not done on a bad line\niloop1:          cmp $d012   // Don't run it on a badline.\n                bne iloop1\n                ldx #$00    //wait for SIDFX to finish initialization (>1200us)\niloop2:          inx\n                bne iloop2`,
`// ============================================================
// Detection sequence
// ============================================================
ibegin:
                // VIC "bad lines" (raster=$FF): CPU stolen ~43 cycles -> corrupt SID writes.
                lda #$ff
iloop1:          cmp $d012               // spin until raster line != $FF
                bne iloop1
                // Busy-wait ~1300 us (256 x ~5 cycles at 1 MHz PAL) so the
                // SIDFX cartridge completes its power-on SCI state-machine init.
                ldx #$00
iloop2:          inx
                bne iloop2`
);

// ── SIDFX result dispatch ────────────────────────────────────────────────────
rep(
`                jsr DETECTSIDFX\n\n                ldx data1\n                cpx #$30 // \n                bne nosidfxl\n                txs\n                ldx #09    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<sidfxu \n                ldy #>sidfxu \n                jmp sidfxprint \nnosidfxl:\n                txs\n                ldx #09    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<nosidfxu \n                ldy #>nosidfxu`,
`                // --- Step 1: SIDFX ---
                // Sends SCI "PNP" login ($80 $50 $4E $50) via D41E/D41F serial pins.
                // Reads back 4 vendor/product ID bytes; checks for $45 $4C $12 $58.
                // data1=$30 = SIDFX found,  data1=$31 = not found.
                jsr DETECTSIDFX

                ldx data1
                cpx #$30               // $30 = SIDFX confirmed
                bne nosidfxl
                txs
                ldx #09                // row 9 = "sidfx......:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<sidfxu
                ldy #>sidfxu
                jmp sidfxprint
nosidfxl:
                txs
                ldx #09
                ldy #13
                jsr $E50C
                tsx
                lda #<nosidfxu
                ldy #>nosidfxu`
);

// ── Checkarmsid call + Swinsid dispatch ──────────────────────────────────────
rep(
`sidfxprint:\n                jsr $AB1E\n                lda     #$00\n                sta     sptr_zp         // store lowbyte 00 (Sidhome)\n                lda     #$D4            // load highbyte D4  (Sidhome)\n                sta     sptr_zp+1       // store highbyte D4 (Sidhome)\n                jsr Checkarmsid     \n                ldx data1\n                cpx #04 // S\n                bne armsid\n                // swinddectect\n                txs\n                ldx #05    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<swinsidUf \n                ldy #>swinsidUf \n                jsr $AB1E\n                jmp end `,
`sidfxprint:
                jsr $AB1E
                // --- Step 2: ARMSID / ARM2SID / Swinsid Ultimate ---
                // Set sptr_zp:sptr_zp+1 to $D400 (primary SID base).
                // Checkarmsid writes "DIS" to voice-3 registers then reads back
                // the echo: 'S'=$53 -> Swinsid Ult, 'N'=$4E -> ARMSID/ARM2SID.
                lda     #$00
                sta     sptr_zp         // SID base low byte = $00
                lda     #$D4            // SID base high byte = $D4
                sta     sptr_zp+1
                jsr Checkarmsid
                ldx data1
                cpx #04                // $04 = 'S' in D41B -> Swinsid Ultimate
                bne armsid
                txs
                ldx #05                // row 5 = "swinsid...:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<swinsidUf
                ldy #>swinsidUf
                jsr $AB1E
                jmp end `
);

// ── ARMSID / ARM2SID dispatch ────────────────────────────────────────────────
rep(
`armsid:\n                ldx data1\n                cpx #05 // N\n                bne fpgasid\n                ldx data2\n                cpx #$4f // O\n                bne fpgasid\n                ldx data3\n                cpx #$53 // R\n                bne armsidlo\n                // arm2sid detect\n                txs\n                ldx #04    // Select row\n                ldy #13    // Select column\n                jsr $E50C   // Set cursor\n                lda #<arm2sidf\n                ldy #>arm2sidf\n                jsr $AB1E\n                jmp end\n                tsx\narmsidlo:\n                // armsid detect\n                txs\n                ldx #04    // Select row\n                ldy #13    // Select column\n                jsr $E50C   // Set cursor\n                tsx\n                lda #<armsidf\n                ldy #>armsidf\n                jsr $AB1E\n                jmp end`,
`armsid:
                // data1=$05 -> 'N' echo detected -> ARMSID family.
                // Use data2 and data3 to distinguish ARM2SID from plain ARMSID:
                //   ARMSID  echoes "NOQ" across D41B/D41C/D41D
                //   ARM2SID echoes "NOR" across D41B/D41C/D41D
                ldx data1
                cpx #05                // $05 = 'N' -> ARMSID family; else try FPGASID
                bne fpgasid
                ldx data2
                cpx #$4f               // 'O'=$4F must be in D41C for both variants
                bne fpgasid
                ldx data3
                cpx #$53               // 'R'=$53 in D41D -> ARM2SID confirmed
                bne armsidlo
                // ARM2SID confirmed (data1=$05, data2=$4F, data3=$53)
                txs
                ldx #04                // row 4 = "armsid....:" line
                ldy #13
                jsr $E50C
                lda #<arm2sidf
                ldy #>arm2sidf
                jsr $AB1E
                jmp end
                tsx                    // unreachable; kept for padding
armsidlo:
                // Plain ARMSID (data3 != 'R')
                txs
                ldx #04
                ldy #13
                jsr $E50C
                tsx
                lda #<armsidf
                ldy #>armsidf
                jsr $AB1E
                jmp end`
);

// ── FPGASID dispatch ─────────────────────────────────────────────────────────
rep(
`fpgasid:\n                lda #$00\n                sta sptr_zp         // store lowbyte 00 (Sidhome)\n                lda #$d4            // load highbyte D4  (Sidhome)\n                sta sptr_zp+1       // store highbyte D4 (Sidhome)\n                jsr checkfpgasid\n                ldx data1\n                cpx #$06\n                bne fpgasidf_6581_l // hvis ikke 3F hop til \n                txs\n                ldx #06    // Select row \n                ldy #13    // Select column \n                tsx\n                jsr $E50C   // Set cursor \n                lda #<fpgasidf_8580u \n                ldy #>fpgasidf_8580u\n                jsr $AB1E\n                jmp end  \nfpgasidf_6581_l:\n                ldx data1\n                cpx #$07\n                bne checkphysical   // hvis ikke 0 so nosound\n                txs\n                ldx #06    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<fpgasidf_6581u \n                ldy #>fpgasidf_6581u \n                jsr $AB1E \n                jmp end`,
`// --- Step 3: FPGASID ---
// Writes magic cookie $81/$65 to D419/D41A to enter config mode,
// sets D41E bit 7, then reads back D419/D41A expecting $1D/$F5 ($F51D).
// D41F=$3F -> 8580 mode (data1=$06); D41F=$00 -> 6581 mode (data1=$07).
fpgasid:
                lda #$00
                sta sptr_zp             // point sptr_zp at $D400
                lda #$d4
                sta sptr_zp+1
                jsr checkfpgasid
                ldx data1
                cpx #$06               // $06 = FPGASID in 8580 mode
                bne fpgasidf_6581_l
                txs
                ldx #06                // row 6 = "fpgasid...:" line
                ldy #13
                tsx
                jsr $E50C
                lda #<fpgasidf_8580u
                ldy #>fpgasidf_8580u
                jsr $AB1E
                jmp end
fpgasidf_6581_l:
                ldx data1
                cpx #$07               // $07 = FPGASID in 6581 mode
                bne checkphysical
                txs
                ldx #06
                ldy #13
                jsr $E50C
                tsx
                lda #<fpgasidf_6581u
                ldy #>fpgasidf_6581u
                jsr $AB1E
                jmp end`
);

// ── Real SID dispatch ─────────────────────────────────────────────────────────
rep(
`checkphysical:\n                lda     #$00\n                sta     sptr_zp         // store lowbyte 00 (Sidhome)\n                lda     #$d4            // load highbyte D4  (Sidhome)\n                sta     sptr_zp+1       // store highbyte D4 (Sidhome)\n                jsr checkrealsid\n                ldx data1\n                cpx #$01\n                bne checkphysical_8580   // hvis ikke 0 so nosound\n                txs\n                ldx #07    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<l6581f \n                ldy #>l6581f \n                jsr $AB1E \n                jmp end                \ncheckphysical_8580:\n                ldx data1\n                cpx #$02\n                bne checkphysical2   // hvis ikke 0 so nosound\n                txs\n                ldx #08    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<l8580f \n                ldy #>l8580f \n                jsr $AB1E \n                jmp end`,
`// --- Step 4: Real SID ---
// Activates sawtooth waveform on voice 3, then reads D41B (OSC3 register).
// Real SIDs return specific values; emulators/no-SID fail the check.
// data1=$01 -> 6581,  data1=$02 -> 8580
checkphysical:
                lda     #$00
                sta     sptr_zp
                lda     #$d4
                sta     sptr_zp+1
                jsr checkrealsid
                ldx data1
                cpx #$01               // $01 = 6581 confirmed
                bne checkphysical_8580
                txs
                ldx #07                // row 7 = "6581 sid..:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<l6581f
                ldy #>l6581f
                jsr $AB1E
                jmp end
checkphysical_8580:
                ldx data1
                cpx #$02               // $02 = 8580 confirmed
                bne checkphysical2
                txs
                ldx #08                // row 8 = "8550 sid..:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<l8580f
                ldy #>l8580f
                jsr $AB1E
                jmp end`
);

// ── checkphysical2 / swinmicro / nosound ─────────────────────────────────────
rep(
`checkphysical2:\n                lda #$00\n                sta mptr_zp         // store lowbyte 00 (Sidhome)\n                lda #$d4            // load highbyte D4  (Sidhome)\n                sta mptr_zp+1       // store highbyte D4 (Sidhome)\n                jsr checksecondsid\n                ldx data1\n                cpx #$10\n                bne swinmicro   // hvis ikke 0 so nosound\n                txs\n                ldx #10    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<unknownsid \n                ldy #>unknownsid \n                jsr $AB1E\n                jmp end\nswinmicro:\n                //jsr checkswinmicro    // false detect in boards with no sid.\n                jmp nosound\n                ldx data1\n                cpx #$08\n                bne nosound   // hvis ikke 0 so nosound\n                txs\n                ldx #05    // Select row\n                ldy #13    // Select column\n                jsr $E50C   // Set cursor\n                tsx\n                lda #<swinsidnanof\n                ldy #>swinsidnanof\n                jsr $AB1E\n                jmp end\nnosound:\n                txs\n                ldx #10    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                tsx\n                lda #<nosoundf \n                ldy #>nosoundf \n                jsr $AB1E`,
`// --- Step 5: second SID scan ---
// Use noise-waveform mirror trick: real SID at $D41B generates non-zero values,
// while a mirrored address always reads 0.  data1=$10 if a second slot is found.
checkphysical2:
                lda #$00
                sta mptr_zp             // start mirror scan at $D400
                lda #$d4
                sta mptr_zp+1
                jsr checksecondsid
                ldx data1
                cpx #$10               // $10 = second SID slot detected
                bne swinmicro
                txs
                ldx #10                // row 10 = "nosid......:" (shows UNKNOWN here)
                ldy #13
                jsr $E50C
                tsx
                lda #<unknownsid
                ldy #>unknownsid
                jsr $AB1E
                jmp end
swinmicro:
                // checkswinmicro disabled: causes false positives on boards with no SID.
                //jsr checkswinmicro
                jmp nosound
                // Dead code below (after unconditional JMP) - kept for possible re-enable:
                ldx data1
                cpx #$08               // $08 = Swinsid Micro type code
                bne nosound
                txs
                ldx #05
                ldy #13
                jsr $E50C
                tsx
                lda #<swinsidnanof
                ldy #>swinsidnanof
                jsr $AB1E
                jmp end
nosound:                               // no SID chip detected
                txs
                ldx #10                // row 10 = "nosid......:" line
                ldy #13
                jsr $E50C
                tsx
                lda #<nosoundf
                ldy #>nosoundf
                jsr $AB1E`
);

// ── end: / stereo scan / IRQ setup ───────────────────────────────────────────
rep(
`end:\n                // call for armsid\n                // sidnum_zp\n                lda #$00\n                sta sidnum_zp // num_sids = 0\n                \n                lda #$05            // armsid or swinsid\n                sta sidtype    \n                jsr sidstereostart\n \n                lda #$06            // FPGAsid\n                sta sidtype    \n                jsr sidstereostart\n              \n                lda #$01            // 6581 or 8580\n                sta sidtype    \n                jsr sidstereostart\n              // print\n                jsr sidstereo_print       \n              // funny decay check\n                jsr calcandloop\nfunny_print:    \n                ldx #11    // Select row \n                ldy #13    // Select column \n                jsr $E50C   // Set cursor \n                jsr checktypeandprint\n                // sæt farve sort\n                lda #01     // black\n                sta $0286   // text color\n                ldx #00    // Select row \n                ldy #00    // Select column \n                jsr $E50C   // Set cursor \n                lda #<sblank \n                ldy #>sblank \n                jsr $AB1E `,
`// ============================================================
// Post-detection: multi-SID scan, decay fingerprint, IRQ loop
// ============================================================
end:
                lda #$00
                sta sidnum_zp           // reset found-SID counter before multi-SID scan

                // Scan all SID address slots (D4xx..DFxx in $20 increments)
                // for each chip family; record results in sid_list_h/l/t.
                lda #$05                // $05 = ARMSID / Swinsid Ultimate family
                sta sidtype
                jsr sidstereostart

                lda #$06                // $06 = FPGAsid family
                sta sidtype
                jsr sidstereostart

                lda #$01                // $01 = real 6581/8580 family
                sta sidtype
                jsr sidstereostart

                jsr sidstereo_print     // print all found SIDs at rows 14+

                // --- Step 6: $D418 decay fingerprint ---
                // Sets volume register D418=$1F and counts cycles until it reaches 0.
                // The decay rate differs between emulators and hardware.
                // calcandloop samples 6 times, computes average via ArithmeticMean,
                // then checktypeandprint maps the result to a known emulator name.
                jsr calcandloop
funny_print:
                ldx #11                 // row 11 = "$d418 decay:" line
                ldy #13
                jsr $E50C
                jsr checktypeandprint   // classify and print the decay fingerprint

                lda #01                 // set text colour to black
                sta $0286
                ldx #00                 // move cursor to home (top-left, hides it)
                ldy #00
                jsr $E50C
                lda #<sblank
                ldy #>sblank
                jsr $AB1E               // write blanks to hide cursor artefact`
);

// ── readkey2 / IRQ ────────────────────────────────────────────────────────────
rep(
`readkey2:              \n           ldx #<IRQ\n           ldy #>IRQ\n           lda #$00\n           stx $0314  // Vector to IRQ Interrupt Routine\n           sty $0315  // Vector to IRQ Interrupt Routine\n           sta $D012  // Read Current Raster Scan Line\n           lda #$7F\n           sta $DC0D  // Interrupt Control Register\n           lda #$1B\n           sta $D011  // Vertical Fine Scrolling and Control Register\n           lda #$01\n           sta $D01A  // IRQ Mask Register\n           cli        // clear interupt\n           jmp *      // jmp til sig selv?\n\nIRQ:        inc $D019 // VIC Interrupt Flag Register\n           lda #$00\n           sta $D012 // Read Current Raster Scan Line\n           jsr COLWASH \n           jsr SPACEBARPROMPT //As always an intro should have a spacebar prompt           \n           jmp $EA7E`,
`// Install a raster IRQ at line 0 for the colour-wash animation and
// spacebar detection.  The IRQ fires once per frame (~50/60 Hz).
readkey2:
           ldx #<IRQ
           ldy #>IRQ
           lda #$00
           stx $0314               // CIA1 IRQ vector low byte  -> our IRQ handler
           sty $0315               // CIA1 IRQ vector high byte
           sta $D012               // trigger raster IRQ at line 0
           lda #$7F
           sta $DC0D               // CIA1: disable all CIA interrupts (use VIC raster only)
           lda #$1B
           sta $D011               // VIC ctrl: enable display, select raster IRQ source
           lda #$01
           sta $D01A               // VIC IRQ mask: enable raster IRQ (bit 0)
           cli                     // re-enable interrupts
           jmp *                   // spin forever; all action happens in IRQ below

// Called every raster frame at line 0:
IRQ:
           inc $D019               // acknowledge VIC IRQ (clears raster flag, bit 0)
           lda #$00
           sta $D012               // keep triggering at line 0 next frame
           jsr COLWASH             // advance one step of colour-wash animation
           jsr SPACEBARPROMPT      // restart if user pressed SPACE
           jmp $EA7E               // KERNAL: finish IRQ (restore regs, RTI)`
);

// ── SPACEBARPROMPT ────────────────────────────────────────────────────────────
rep(
`//Setup and allow the space bar to be pressed in order\n//to exit the intro and run a code reloc/transfer subroutine\n\nSPACEBARPROMPT:\n                lda $DC01\n                cmp #$EF\n                bne NOSPACEBARPRESSED\n                lda $d012 //load the current raster line into the accumulator\n                cmp $d012 //check if it has changed\n                beq *-3\n                jmp start \nNOSPACEBARPRESSED:\n                rts`,
`// ============================================================
// SPACEBARPROMPT -- spacebar restarts the full detection run.
// Called from IRQ every frame.
// CIA1 keyboard matrix: $DC01 reads column bits for row selected by $DC00.
// Row mask $EF selects the row containing SPACE; bit 4 low = pressed.
// ============================================================
SPACEBARPROMPT:
                lda $DC01               // read keyboard matrix column bits
                cmp #$EF               // $EF = SPACE key pressed (bit 4 low)
                bne NOSPACEBARPRESSED
                // Wait for a stable raster position to avoid re-entering start
                // mid-frame (which could land on a bad line).
                lda $d012               // read current raster line
                cmp $d012               // if line changed, try again
                beq *-3
                jmp start               // restart: re-init tables and run detection
NOSPACEBARPRESSED:
                rts`
);

// ── EXITINTRO ─────────────────────────────────────────────────────────────────
rep(
`EXITINTRO:\n           jsr $E544 //clear the screen\n           lda #$81\n           stx $0314\n           sty $0315\n           sta $DC0D\n           sta $DD0D\n           lda #$00\n           sta $D019\n           sta $D01A\n           jsr $FF81 //Blue border+blue screen clear\n           jmp $E37B // jump to basic`,
`// EXITINTRO: no longer called in v1.2 (SPACE now restarts detection instead
// of exiting to BASIC).  Kept for reference.
EXITINTRO:
           jsr $E544               // KERNAL: clear screen
           lda #$81
           stx $0314               // restore CIA1 IRQ vector to KERNAL default
           sty $0315
           sta $DC0D               // re-enable CIA1 interrupts
           sta $DD0D               // re-enable CIA2 interrupts
           lda #$00
           sta $D019               // clear VIC IRQ flags
           sta $D01A               // disable VIC IRQ mask
           jsr $FF81               // KERNAL: reset screen colours (blue border+screen)
           jmp $E37B               // KERNAL: warm-start BASIC`
);

// ── printscreen ──────────────────────────────────────────────────────────────
rep(
`//-------------------------------------------------------------------------\nprintscreen:\n    jsr $E544 //clear the screen\n    lda #00     // black\n    sta $D020\n    sta $D021\n    lda #07     // yellow\n    sta $0286   // text color\n    \n\n    ldx #0\nlp:\n    lda screen,x\n    sta $0400,x\n    lda screen+$0100,x\n    sta $0500,x\n    lda screen+$0200,x\n    sta $0600,x\n    lda screen+$02e8,x\n    sta $06e8,x\n    lda #1\n    sta $d800,x\n    sta $d900,x\n    sta $da00,x\n    sta $dae8,x\n    inx\n    bne lp\n    rts`,
`// ============================================================
// printscreen -- copies the 1000-byte screen table to video RAM
// and initialises colour RAM to white (1).
// Screen RAM: $0400-$07E7  (4 x 256-byte pages + 232 bytes)
// Colour RAM: $D800-$DBE7  (same layout)
// ============================================================
printscreen:
    jsr $E544               // KERNAL: clear screen (fills screen RAM with spaces)
    lda #00                 // colour 0 = black
    sta $D020               // VIC border colour register
    sta $D021               // VIC background colour register
    lda #07                 // colour 7 = yellow
    sta $0286               // KERNAL text colour variable

    ldx #0
lp:
    lda screen,x            // copy screen data page 0 ($0000-$00FF of table)
    sta $0400,x             // -> video RAM $0400-$04FF
    lda screen+$0100,x
    sta $0500,x             // -> video RAM $0500-$05FF
    lda screen+$0200,x
    sta $0600,x             // -> video RAM $0600-$06FF
    lda screen+$02e8,x      // last partial page (232 bytes)
    sta $06e8,x             // -> video RAM $06E8-$07CF
    lda #1                  // colour 1 = white
    sta $d800,x             // colour RAM $D800-$D8FF
    sta $d900,x             // colour RAM $D900-$D9FF
    sta $da00,x             // colour RAM $DA00-$DAFF
    sta $dae8,x             // colour RAM $DAE8-$DB CF
    inx
    bne lp
    rts`
);

fs.writeFileSync('siddetector.asm', src);
console.log('\nDone. ' + changed + ' replacements applied.');

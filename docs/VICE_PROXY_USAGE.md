# Using the WinVICE 3.9 SidVariant proxy

The patched WinVICE 3.9 (build recipe: `docs/VICE_PROXY_BUILD.md`, design
rationale: `docs/ARMSID_PROXY_PLAN.md`) adds a pluggable chip-personality
layer on top of ResID.  Each emulated SID slot (up to 8) can wear a
different personality that responds to that chip family's detection
*magic-cookie* protocol — no hardware required.

## Window title

While any variant is active, the Gtk3 window title shows the current
personality name:

```
VICE (C64SC)  [SidVariant=armsid]
```

The `[SidVariant=none]` suffix is present even for the default so you
always know whether the patched binary is the one running.

## Command-line flags

| Flag | Effect |
|---|---|
| `-sidvariant <name>` | set personality on SID #1 (`$D400` primary) |
| `-sidvariant2 <name>` | set personality on SID #2 (`$D420` when `-sidextra 1`) |
| `-sidvariant3..8 <name>` | SID #3..#8 personalities (stereo / tri-SID) |

Persistent equivalents in `vicerc`:

```
SidVariant=armsid
SidVariant2=none
...
```

## Variant catalogue

| Name | Emulates | Detected at |
|---|---|---|
| `none` | *(no personality — plain ResID)* | — |
| `armsid` | ARMSID firmware 2.xx | row 17 stereo (when at D420) |
| `arm2sid` | ARM2SID firmware 3.xx | row 17 stereo |
| `swinu` | SwinSID Ultimate | row 3 |
| `swinnano` | SwinSID Nano (AVR) | row 3 |
| `fpgasid8580` | FPGASID in 8580 mode | row 4 |
| `fpgasid6581` | FPGASID in 6581 mode | row 4 |
| `pdsid` | PDsid 'P/D/S' echo | row 10 |
| `kungfusid-new` | KungFuSID new firmware ($A5→$5A ACK) | row 9 |
| `kungfusid-old` | KungFuSID old firmware ($A5 echo) | *(not detectable by siddetector 1.4.x)* |
| `backsid` | BackSID unlock + $01 echo | row 8 |
| `skpico-8580` | SIDKick-pico in 8580 mode | row 7 |
| `skpico-6581` | SIDKick-pico in 6581 mode | row 7 |
| `sidfx` | SIDFX via SCI PNP handshake | row 12 |
| `usid64` | uSID64 5-byte unlock | row 14 |

Anything not listed is a typo; unknown names are rejected at CLI parse
time with a full list of valid options.

## `make` shortcuts

```
make run                          # plain 8580 baseline
make sfx                          # stock VICE SFX Sound Expander
make run-none / stereo-off        # 8580 + SidVariant=none explicit

# Single personality at D400
make run-armsid        make run-arm2sid       make run-swinu        make run-swinnano
make run-fpgasid8580   make run-fpgasid6581   make run-pdsid        make run-kungfusid
make run-backsid       make run-usid64        make run-sidfx        make run-skpico8580
make run-skpico6581

# MixSID: 8580 @ D400 + personality @ D420
make stereo-armsid     make stereo-arm2sid    make stereo-swinu
make stereo-fpgasid    make stereo-sidfx

# MIDI cartridges (codebase.c64.org/doku.php?id=base:c64_midi_interfaces).
# Per the reference + hardware, only ONE MIDI cart can be attached at a time.
# Detection result lands on row 11 (the NOSID line).
# Requires VICE built with --enable-midi.
make run-midi-sequential   # SCI/Namesoft @ $DE00/$DE02
make run-midi-passport     # Passport/Sentech @ $DE08
make run-midi-datel        # DATEL/Siel/JMS @ $DE04/$DE06
make run-midi-namesoft     # Namesoft (NMI variant of Sequential, indistinguishable)
make run-midi-maplin       # Maplin @ $DF00

# Regression harnesses
make ci                # 32-case unit tests in VICE monitor (~30 s)
make ci-full           # above + golden-diff across all 14 variants (~4 min)
make test-variants     # standalone variant-only sweep
make update-variant-goldens    # after intentional UI / personality change
```

## Typical workflows

### Local development loop

```
vim src/sid/sid-variant-skpico.c       # hack
make -C /path/to/vice-sidvariant       # rebuild the emulator
cp /path/to/vice-sidvariant/src/x64sc.exe \
   /path/to/GTK3VICE-3.9-win64/bin/   # deploy
make run-skpico8580                    # see it in the GUI
make test-variants                      # full sweep
```

### Verifying a detection change before touching hardware

```
# Change siddetector.asm
make                                   # rebuild siddetector.prg
make ci-full                           # 32 + 14 tests pass?  Good → HW test
make hw_test SCENARIO=fpgasid_stereo   # run the real-rig test
```

### Authoring a new variant

1. Create `src/sid/sid-variant-<name>.c` with `observe_write` / `try_read` / `reset`.
2. Add to the enum in `src/sid/sid-variant.h`.
3. Add a `known_names[]` entry and dispatch case in `src/sid/sid-variant.c`.
4. List the file in `src/sid/Makefile.am`.
5. Rebuild: `automake --no-force src/sid/Makefile && make -j$(nproc)`.
6. Test: `-sidvariant <name>` at the VICE CLI.
7. Golden it: add a case to `CASES` in `scripts/variant_smoke.py`, run
   `make update-variant-goldens`, commit the new `.txt`.

## How a golden diff reads

On success:

```
  PASS  sidfx   r12: SIDFX......: SIDFX FOUND
```

On regression:

```
  FAIL  sidfx   r12: SIDFX......: SIDFX FOUND  (golden diff:)
    -golden  r12: SIDFX......: SIDFX FOUND
    +actual  r12: SIDFX......: WRONG BANNER
```

The first line shows the sanity-check substring match; the lines below
list the per-row differences against the stored golden in
`tests/variant_goldens/<name>.txt`.  Either an intentional change has
happened (re-run `make update-variant-goldens`) or a regression slipped
in — in which case investigate before updating the golden.

## Limitations / known quirks

| Quirk | Why |
|---|---|
| Plain `-sidvariant armsid` at D400 shows as `8580 FOUND` | Same as real hardware — siddetector's Step 2 sees 8580 via ResID during the CS2-DIS window; the ARMSID-specific banner only lights up in MixSID configs where the DIS echo succeeds |
| `kungfusid-old` ends up as `SWINSID NANO` | siddetector 1.4.x dropped the `$A5` echo recognition (real SIDs echo `$A5` too, causing false positives); the old-firmware variant is kept for historical completeness |
| PDsid / SwinNano stereo row (r16) shows `UNKNOWN SID` | siddetector-side gap: `end_pre_d400` doesn't recognise `data4=$08` or `data4=$09` as primaries, so it falls back to the UNKNOWN entry.  Detection itself (r03 / r10) is correct |
| FPGASID detection required a 1-char siddetector fix | original code was `lda %10000000` (no `#`) which assembled as LDA $80 zero-page, not immediate $80.  On real HW, ZP $80 happened to contain $80 at that moment; on VICE it didn't.  Now `lda #%10000000` |

## See also

- `docs/ARMSID_PROXY_PLAN.md` — design doc, per-chip protocol tables, phase breakdown.
- `docs/VICE_PROXY_BUILD.md` — how to reproduce the patched binary.
- `patches/vice-sidvariant-v1.patch` — source diff against vanilla VICE 3.9.
- `tests/variant_goldens/*.txt` — reference screen fingerprints.
- `scripts/variant_smoke.py` — the harness that runs the sweep.

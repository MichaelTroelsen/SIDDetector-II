# SID-Variant Proxy for WinVICE — Ultraplan

**Goal.** Patch WinVICE so its SID emulator can wear a chip "personality" — ARMSID, ARM2SID, SwinSID U, SwinSID Nano, FPGASID, PDsid, KungFuSID, BackSID, SIDKick-pico, SIDFX, uSID64 — and respond to the *detection* protocol each chip uses. With this, `siddetector.prg` can be exercised in CI against every supported chip family without hardware, catching regressions before real-HW rounds.

**Not goals.**
- No audio-accurate synthesis — ResID already handles 6581/8580.
- No filter/envelope behaviour beyond what detection reads.
- Not a replacement for real-HW verification of the final release.

---

## 1. Why this exists

Today `make ci` runs 32 unit tests and `make run` brings up VICE with a plain 8580 at `$D400` (and optionally `$D420`). Every other chip family — ARMSID, FPGASID, SIDFX, etc. — can only be validated on real hardware via the U64 pipeline (`make hw_test`). That round-trip is slow, serialised, and gated on a running C64.

Most detection bugs don't need an audio-accurate chip. They need the chip to **answer the detection protocol correctly** — the "magic cookie" exchange siddetector uses to fingerprint hardware. If VICE can reply to those protocols, we can:
- Run the full test matrix in CI (pre-commit, pre-PR, pre-release).
- Diff detection output against a known-good baseline for every chip.
- Catch regressions introduced by refactors that only manifest on one chip family.
- Write unit tests for *detection* (not sound) with zero physical rig.

---

## 2. Architecture options

| Option | Idea | Pros | Cons |
|---|---|---|---|
| **A. Patch VICE SID module** | Add a `SidVariant` resource; intercept `sid_store`/`sid_read` to inject chip-specific state machine | Integrates cleanly; cycle-consistent; one binary does everything | Requires tracking upstream VICE |
| B. External proxy via remote monitor | Python process traps SID reads, edits memory | No source changes | Too slow (monitor RTT ≫ 1 cycle); unreliable under raster IRQs |
| C. Custom cartridge | Map a "SID-variant" device into `$D400` space | Reuses VICE cart infrastructure | SID space is not cartridge-routed on stock C64 — not reachable from `-cart*` |
| D. LD_PRELOAD / DLL-inject resid.dll | Hook read/write at binary level | No rebuild needed | Fragile, Win-only, undermines all verification |

**Decision: Option A.** It's the only path that gives cycle-accurate behaviour, survives VICE updates cleanly (as a patch series), and lets a `SidVariant=armsid` resource live alongside existing `SidModel=8580`.

---

## 3. Architectural sketch (grounded in VICE 3.9 source)

VICE 3.9 lives at `C:\Users\mit\Downloads\vice-3.9`. Everything below references exact files/lines there.

### 3.1 Files

```
src/sid/
  sid.c                    # EXISTING — 1248 lines; add 2 dispatch calls
  sid-resources.c          # EXISTING — add SidVariant + SidVariantN resources
  sid-cmdline-options.c    # EXISTING — add -sidvariant{N} CLI flags
  sid-variant.h            # NEW — variant VTABLE + state struct
  sid-variant.c            # NEW — registry + resource glue (SidVariant)
  sid-variant-armsid.c     # NEW — ARMSID + ARM2SID personality
  sid-variant-swinsid.c    # NEW — SwinSID U + SwinSID Nano
  sid-variant-fpgasid.c    # NEW — FPGASID 6581 / 8580
  sid-variant-pdsid.c      # NEW
  sid-variant-kungfu.c     # NEW — KungFuSID old + new firmware
  sid-variant-backsid.c    # NEW
  sid-variant-skpico.c     # NEW — SIDKick-pico 6581 / 8580
  sid-variant-sidfx.c      # NEW — SCI state machine + PNP handshake
  sid-variant-usid64.c     # NEW
src/sid/Makefile.am        # EXISTING — add the new sources
```

### 3.2 Hook points in `sid.c` (concrete diff)

The right hook is **`sid_read_chip()` / `sid_store_chip()`** (static, inside `sid.c`, around lines ~174 and ~243), *not* the public `sid_read()`. Those are per-chip, get a `chipno` argument, and already mask `addr & 0x1f` down to the register index — so each of up to 8 emulated SIDs can carry its own personality.

```c
/* sid.c — sid_read_chip(), around line 200 (after clock fixup, before
   lastsidread = val;) */

    /* --- sid-variant proxy layer --- */
    {
        uint8_t vval;
        if (sid_variant_try_read(chipno, addr, &vval)) {
            val = vval;         /* variant claimed the read */
        }
    }
    /* --- /sid-variant --- */

    lastsidread = val;
    return val;
```

```c
/* sid.c — sid_store_chip(), around line 258, just before sid_store_func */
    sid_variant_observe_write(chipno, addr, byte);
    sid_store_func(addr, byte, chipno);
```

Both hook points run **after** VICE's existing `siddata[chipno][addr] = byte` bookkeeping, so ResID still sees every write and the variant layer has `maincpu_clk` available for time-gated responses.

**Important detail: VICE's existing fallback.** When sound is off, `sid_read_chip` already returns `0xFF` for `$19/$1A`, `maincpu_clk % 256` for `$1B/$1C`, and `0` for everything else (sid.c:217-228). The variant layer runs *before* that fallback is baked into `val`, so a variant can override those defaults — exactly what's needed for the `$1B`/`$1D`/`$1E`/`$1F` echo responses that every chip personality uses.

### 3.3 Variant interface

```c
/* sid-variant.h */
typedef struct sid_variant_s sid_variant_t;

typedef struct {
    const char *name;
    void    (*reset)(sid_variant_t *v);
    void    (*observe_write)(sid_variant_t *v, uint16_t reg, uint8_t val);
    int     (*try_read)(sid_variant_t *v, uint16_t reg, uint8_t *out);
} sid_variant_ops_t;

struct sid_variant_s {
    const sid_variant_ops_t *ops;
    uint8_t  state[64];        /* per-variant scratch: DIS mode, cfg page… */
    CLOCK    last_write_clk;   /* for time-gated readiness (ARMSID >100 ms) */
    int      chipno;           /* which SID slot this personality sits on */
};

/* Public hooks called from sid.c */
int  sid_variant_try_read(int chipno, uint16_t reg, uint8_t *out);
void sid_variant_observe_write(int chipno, uint16_t reg, uint8_t val);
void sid_variant_reset_all(void);   /* called from machine reset */
```

Per-chip variants support: `SidVariant` (chip 0), `SidVariant2…SidVariant8`. `"none"` means the whole layer no-ops on that chip.

### 3.4 Resource & CLI

Add to `sid-resources.c` — follow the existing `SidModel` pattern (line 417):

```c
static resource_string_t variant_resources_string[] = {
    { "SidVariant",  "none", RES_EVENT_SAME, NULL,
      &sid_variant_name[0], set_sid_variant, (void*)0 },
    { "SidVariant2", "none", RES_EVENT_SAME, NULL,
      &sid_variant_name[1], set_sid_variant, (void*)1 },
    /* …through SidVariant8 */
    RESOURCE_STRING_LIST_END
};
```

CLI options in `sid-cmdline-options.c`:

```
-sidvariant <name>        variant on chip 0 (D400)
-sidvariant2 <name>        variant on chip 1 (D420 or whatever SID2 address)
…through -sidvariant8
```

Variant names: `none`, `armsid`, `arm2sid`, `swinu`, `swinnano`, `fpgasid6581`, `fpgasid8580`, `pdsid`, `kungfusid-old`, `kungfusid-new`, `backsid`, `skpico-8580`, `skpico-6581`, `sidfx`, `usid64`.

### 3.5 Build wiring

Add to `src/sid/Makefile.am`:
```
libsid_a_SOURCES += \
    sid-variant.c sid-variant-armsid.c sid-variant-swinsid.c \
    sid-variant-fpgasid.c sid-variant-pdsid.c sid-variant-kungfu.c \
    sid-variant-backsid.c sid-variant-skpico.c sid-variant-sidfx.c \
    sid-variant-usid64.c
```

No new external dependencies. Patch touches `src/sid/` only — no changes to `src/c64`, `src/core`, or the VICE-wide machine glue.

---

## 4. Per-chip protocol summary ("magic cookies")

Exact addresses as siddetector reads them (from `siddetector.asm` and `Checkarmsid`/`armsid_get_version`). All PETSCII codes.

### 4.1 ARMSID / ARM2SID (`data1=$05`)

| Trigger (write sequence) | State → | Read-side echo |
|---|---|---|
| `$D41F='d'($44)`, `$D41E='i'($49)`, `$D41D='s'($53)` | enter config | `$D41B='n'($4E)`, `$D41C='o'($4F)` |
| In config: `$D41F='e'($45)`, `$D41E='i'($49)` | EI probe | `$D41B='s'($53)`, `$D41C='w'($57)` |
| `$D41F='i'($49)`, `$D41E='i'($49)` | II probe | `$D41B=2` (ARM2SID) / other (ARMSID); `$D41C='l'($4C)` / `'r'($52)` |
| `$D41F='v'($56)`, `$D41E='i'($49)` | version | `$D41B`=major (2/3), `$D41C`=minor |
| `$D41F='f'($46)`, `$D41E='i'($49)` | SID-type query | `$D41B='6'($36)` or `'8'($38)` |
| `$D41F='g'($47)`, `$D41E='i'($49)` | auto-detect | `$D41B='7'($37)` |
| `$D41F='m'($4D)`, `$D41E='m'($4D)` | mode | `$D41B` bits 1:0 = mode |
| Sequential `$D41D` reads after `'d','i','s'` | auto-inc cfg map | ARM2SID: 4 nibble-packed slot-map bytes |
| Any non-config write to `$D418` | exit config | state → idle |

**Personality state:** `mode` (idle / config / EI / II / map), `auto_inc_addr`, `major`, `minor`, `map[4]`, `emul_mode`.

### 4.2 SwinSID Ultimate (`data1=$04`)

Identical DIS entry as ARMSID but:
- `$D41B='s'($53)` instead of `'n'($4E)`
- `$D41C='w'($57)` instead of `'o'($4F)`
- No config state-machine — single echo.

### 4.3 SwinSID Nano (`data1=$08`)

Detected via **noise LFSR quirk**: with noise + two different `freq_hi` values (`$00FF` vs `$FF00`), an AVR-based Nano produces a *recognisable non-zero pattern* at `$D41B`.

Emulation: when `voice3.ctrl=$81` (noise), return a fixed pseudo-random byte keyed on `voice3.freq` so two different freqs give two different bytes. (Simpler than real AVR LFSR; siddetector only tests discriminability.)

### 4.4 FPGASID 8580 / 6581 (`data1=$06` / `$07`)

Magic-cookie unlock:
- `$D419=$82`, `$D41A=$65` → "identify" state
- Read `$D41F` → `$3F` (8580 mode) or `$00` (6581 mode)
- Reset out: `$D419=0`, `$D41A=0`

**Personality state:** `unlocked` bit, `variant_model`.

### 4.5 PDsid (`data1=$09`)

- `$D41D='P'($50)`, `$D41E='D'($44)` → arm
- Read `$D41E` returns `'S'($53)`

### 4.6 KungFuSID (`data1=$0C`)

- Write `$A5` to `$D41D`
- Read `$D41D` → `$A5` (old fw) or `$5A` (new fw)

Two separate variants: `kungfusid-old`, `kungfusid-new`.

### 4.7 BackSID (`data1=$0A`)

- Any write to `$D41F` → read-back returns the same byte (full register echo).

### 4.8 SIDKick-pico 8580 / 6581 (`data1=$0B` / `$0E`)

- Config entry: `$D41F=$FF`, `$D41E=$E0`
- Sequential `$D41D` reads: 1st='S'($53), 2nd='K'($4B), 3rd…='i','d','p','i','c','o' (version string)
- Auto-detect: `$D418=0`, `$D40E=$FF`, `$D40F=$FF`, `$D412=$FF`, `$D412=$20` → read `$D41B` returns 2 (8580) / 3 (6581)

### 4.9 SIDFX (`data1=$30`)

Needs a small **SCI** (serial-control interface) state machine on `$D41E` (sync) + `$D41F` (data). PNP handshake returns vendor/product ID, then routes writes to emulate secondary SID at configured address (`D420`/`D500`/`DE00` per `SW1`).

| PNP request bytes | Response bytes |
|---|---|
| `$80,$50,$4E,$50` (write "PNP") | `$45,$2A,$0A,??` (vendor ID etc.) |

**Personality state:** SCI shift register, bit counter, PNP response FIFO, SW1/SW2 simulated DIP switches (a resource: `SidVariantSidfxSw1="LFT"|"CTR"|"RGT"`).

### 4.10 uSID64 (`data1=$0D`)

Two consecutive reads of `$D41F` — the uSID64 returns a specific non-volatile config byte that is stable across reads; real SIDs return bus noise that differs between reads.

Emulation: return a fixed byte (e.g. `$55`) for reads of `$D41F` when armed.

### 4.11 FM-YAM / SFX Sound Expander

**Not this patch.** VICE already has `-sfxse` / `-sfxsetype 3812` — already exercised in tests T41/T42/T44. Leave untouched.

### 4.12 ULTISID (U64 UCI)

Lives at `$DF1C-$DF1F` — outside SID space. Out of scope for this patch; would need a separate "U64 proxy" (own plan).

---

## 5. Phase plan

Each phase ends with a verification step that must pass before starting the next.

### Phase 0 — Baseline and environment (½ day)

- Fork VICE trunk at a known commit (pin commit hash in `winvice-siddetector-proxy/VERSION`).
- Reproduce existing `make ci` against an unmodified build.
- Wire up a `scripts/build_vice.sh` that produces a relocatable `x64sc.exe` from the fork.

**Verify:** `make ci` uses the custom binary and all 32 tests still pass.

### Phase 1 — Infrastructure (1 day)

- Add `SidVariant` resource + `-sidvariant` CLI flag, strings only, no behaviour yet.
- Add `sid-variant.h/c` with a null variant (all reads pass through, all writes ignored).
- Wire dispatch in `sid.c`.
- Add `SidVariant="none"` default in `vicerc`.

**Verify:** `-sidvariant none` produces byte-identical detection output to today; `-sidvariant armsid` compiles and runs but behaves like `none`.

### Phase 2 — ARMSID / ARM2SID personality (2 days)

- Implement `sid-variant-armsid.c` per §4.1.
- State machine covers DIS entry, EI/II probes, version query, map-query, config exit.
- Two sub-variants differ only in `major` constant (2 vs 3) and map presence.

**Verify (new make target `test-armsid`):**
```
x64sc -sidvariant armsid -autostart siddetector.prg
```
siddetector row 2 shows `ARMSID V2.xx`. Row 16 lists `$D400 ARMSID`. All of `test_suite.asm` dispatch tests T06–T10 pass.

### Phase 3 — Single-register variants (1 day)

Group the simpler echo-only chips together:
- PDsid (§4.5)
- KungFuSID old + new (§4.6)
- BackSID (§4.7)
- uSID64 (§4.10)

Each adds its own `.c` file, ≤ 40 lines.

**Verify:** `make test-pdsid`, `make test-kungfusid-old`, `make test-kungfusid-new`, `make test-backsid`, `make test-usid64` all pass (exit 0 from `hw_test.py` style scenario).

### Phase 4 — SwinSID variants (1 day)

- SwinSID Ultimate (§4.2)
- SwinSID Nano (§4.3) — needs LFSR pseudo-random generator keyed on freq register.

**Verify:** `make test-swinu`, `make test-swinnano`.

### Phase 5 — FPGASID + SIDKick-pico (1–2 days)

- FPGASID 8580 / 6581 (§4.4) — magic-cookie unlock + SID2 type reporting.
- SIDKick-pico 8580 / 6581 (§4.8) — config-mode VERSION_STR + auto-detect trigger.

**Verify:** `make test-fpgasid-8580`, `make test-fpgasid-6581`, `make test-skpico-8580`, `make test-skpico-6581`.

### Phase 6 — SIDFX (3–4 days, largest)

- SCI bit-banging on `$D41E`/`$D41F` (§4.9).
- PNP handshake FIFO.
- Simulated DIP switches (new resource `SidVariantSidfxSw1`).
- Secondary-SID routing to `D420`/`D500`/`DE00`.

**Verify:** Recreate hardware scenarios C30–C34 from `docs/teststatus.md` under WinVICE. SIDFX + 6581 + 8580 at LFT/CTR/RGT all detect correctly.

### Phase 7 — Multi-SID make targets (½ day)

Once variants exist, add convenience targets for the common combinations:

```
make stereo-d420-armsid    # 8580@D400 + ARMSID@D420 (C07)
make stereo-d420-fpga      # 8580@D400 + FPGASID@D420 (C10)
make mixsid-c06            # ARMSID@D400 + 6581@D420 (C06)
make tri-sid-dE00          # 8580@D400 + ARMSID@D420 + 8580@DE00
make sidfx-lft             # SIDFX secondary at D420
make novice-sid            # 8580@D400 only, no stereo, no SFX
```

Each target sets appropriate VICE flags (`-sidextra`, `-sid2addr`, `-sidvariant`, …).

### Phase 8 — CI integration (½ day)

- Extend `scripts/ci_test.sh` to loop over all variants.
- Each variant has an expected detection-result fingerprint in `tests/hw/scenarios/<variant>.cfg`.
- CI fails if any variant produces a different `sid_list_t/l/h` or `data4` than baseline.

### Phase 9 — Release, docs, upstream proposal (1 day)

- Package the patch as a single `vice-sidvariant-v1.patch` against the pinned commit.
- Pre-built `x64sc-sidvariant.exe` in a GitHub release.
- Short `docs/VICE_PROXY_BUILD.md` covering how to rebuild.
- Optional: submit upstream to the VICE team (GPL, so license compatible).

---

## 6. Test strategy

### 6.1 Per-variant fingerprint

Each `tests/hw/scenarios/<variant>.cfg` captures:
- `data4` (detected primary type)
- Each `sid_list_t[i]` / `sid_list_h[i]` / `sid_list_l[i]`
- Row texts that should appear (ARMSID V?.??, SwinSID FOUND, …)

These are the same fields already used by `scripts/hw_test.py`, so the existing harness drop-in works.

### 6.2 Negative tests

Every variant runs a partner test with the expected chip **swapped for a different one** and confirms siddetector does *not* match. E.g. `SidVariant=armsid` must not produce `SwinSID FOUND`.

### 6.3 Cross-variant combos

Multi-SID scenarios lean on VICE's native `-sidextra N -sid2addr X` layered with `-sidvariant`. The proxy layer should work independently per SID chip. Stretch goal: per-SID variants (different personality on D400 vs D420).

### 6.4 Regression diff

`make ci` dumps the decoded screen for every scenario and byte-diffs against a golden file. Any divergence flags a failure and prints `diff` output so the offending row is obvious.

---

## 7. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| VICE upstream changes `sid_store()` signature | Medium | Pin commit; rebase patch periodically; keep hook additions narrow |
| Some detection needs cycle-precise timing (e.g. ARMSID "wait ≥100 ms after reset") | Medium | Use VICE's `maincpu_clk` for gated responses; siddetector already calls `loop1sek` for timing |
| Detection uses SID voice3 OSC3 output (real audio path) | Low | Keep ResID's OSC3 path intact; variant only overrides D41D/E/F-style echoes |
| VICE's `-sidenginemodel` matrix grows (fastsid + resid + residfp) | Low | Variant is orthogonal: it runs on top of any engine |
| GPL licensing on fork | Low | VICE is GPLv2; fork stays GPLv2; upstream proposal at the end |
| Cycle budget vs real HW (VICE too fast/slow) | Medium | Existing `check_cbmtype` / `loop1sek` calibration already works; variants reuse same timers |

---

## 8. Deliverables

1. **Forked VICE source** at a pinned commit, with `vice-sidvariant-v1.patch`.
2. **`x64sc-sidvariant.exe`** pre-built for Win64, installed into `C:/winvice/bin/` (same path `Makefile` expects).
3. **`docs/VICE_PROXY_BUILD.md`** — reproducible build instructions.
4. **`docs/VICE_PROXY_USAGE.md`** — catalogue of `-sidvariant` names with examples.
5. **`tests/hw/scenarios/*.cfg`** — one per variant, for `hw_test.py`.
6. **New `make` targets** for multi-SID permutations (Phase 7).
7. **CI pass** — all 32 existing tests + N new variant scenarios green.

---

## 9. Success criteria

- `make test-armsid` → siddetector reports `ARMSID FOUND V2.xx` on row 2, within 5 s, 100/100 times.
- `make test-fpgasid-8580` → row 4 shows `FPGASID 8580 FOUND`, 100/100.
- `make ci-full` (new aggregate) → every variant green, runtime under 8 min on a modern laptop.
- A detection regression introduced by a deliberate 1-byte code change in `siddetector.asm` is caught by CI *before* real-HW tests run.
- Zero changes to real-HW `make hw_test` flow — the proxy is additive, real HW remains authoritative.

---

## 10. Effort

- Engineering: 10–12 focused days (one developer).
- Review/polish: 2 days.
- Upstream proposal (optional): 2 days.
- Total: ~3 working weeks end-to-end if done serially.

Phases 0–5 alone (≈ 5 days) unlock 80 % of the testing value; Phase 6 (SIDFX) is the long pole and can ship later as "phase 2 of the proxy".

---

## Appendix A — ARMSID state machine reference

```
  idle ─── write D→D41F, I→D41E, S→D41D ──► config_open
  config_open:
      read D41B → 'n' ($4E)
      read D41C → 'o' ($4F)
      read D41D → sequential map bytes (ARM2SID only)
  config_open ─── write 'e','i' ──► ei_mode
  ei_mode:
      read D41B → 's' ($53)
      read D41C → 'w' ($57)
  config_open ─── write 'i','i' ──► ii_mode
  ii_mode:
      read D41B → 2 (ARM2SID) or arbitrary (ARMSID)
      read D41C → 'l'/'r' (ARM2SID only)
  config_open ─── write 'v','i' ──► version_mode
      read D41B → major ($02/$03)
      read D41C → minor (BCD)
  config_open ─── write 'f','i' / 'g','i' / 'm','m' ──► sid_type / auto_detect / mode
  any mode ─── write non-command to D418 or long silence ──► idle
```

## Appendix B — Register decode cheat sheet (SID2 at `$D420`)

| Addr | Register | Writable | Readable (real SID) | Notes |
|---|---|---|---|---|
| $D420-$D41C | Voice 1/2/3 regs | Yes | OSC3=$D41B, ENV3=$D41C | |
| $D41D-$D41F | Unused on stock SID | No-op | Open bus | **Used by all chip variants** for magic cookies |
| $D420-$D43F | SID2 if stereo | — | — | Same layout as $D400-$D41F |

## Appendix C — Build constraints

- **Source base: VICE 3.9** — unpacked tree already present at `C:\Users\mit\Downloads\vice-3.9`. Pin this as the fork's baseline (reference to a point release is cleaner than tracking trunk).
- Build toolchain on Windows: mingw-w64 (recommended — matches the currently installed `C:/winvice/bin/x64sc.exe` style) or Visual Studio 2022.
- Configure + build:
  ```
  cd vice-3.9
  ./autogen.sh
  ./configure --enable-native-gtk3ui --disable-debug \
              --enable-ethernet=no --disable-cpuhistory
  make -j8
  ```
  (Standard Gtk3 SDL build; add `--enable-sdl2ui` if the SDL binary is preferred.)
- The produced `src/c64sc/x64sc.exe` replaces `C:/winvice/bin/x64sc.exe`.
- No new external runtime deps; patch stays within libc + VICE utilities (`resources.c`, `cmdline.c`, `maincpu_clk`).
- **License:** VICE is GPLv2+; fork inherits GPLv2+. Upstream contribution path is open.

## Appendix D — Authoritative docs & source pointers

- **VICE 3.9 reference manual** (chapter 12 — SID Settings): <https://vice-emu.sourceforge.io/vice_12.html>
- **Command-line options** (chapter 7): <https://vice-emu.sourceforge.io/vice_7.html>
- **Resource file format** (chapter 6): <https://vice-emu.sourceforge.io/vice_6.html>
- **Full TOC:** <https://vice-emu.sourceforge.io/vice_toc.html>
- Local source: `C:\Users\mit\Downloads\vice-3.9` — key files for this plan:
  - `src/sid/sid.c` (1248 lines) — `sid_read_chip` line ~174, `sid_store_chip` line ~243
  - `src/sid/sid-resources.c` (656 lines) — resource registration pattern at line 403-419
  - `src/sid/sid-cmdline-options.c` (629 lines) — string-to-int CLI pattern (`engine_match[]`)
  - `src/sid/sid.h` — public API (`sid_read`, `sid_store`, `sid_peek`)
  - `src/sid/resid.cc` — ResID wrapper (engine that feeds `sid_read_func`/`sid_store_func`)

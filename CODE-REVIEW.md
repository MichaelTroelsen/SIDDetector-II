# Code Review — SID Detector II (V1.5.05)

**Reviewed:** 2026-07-30 · **Reviewer:** Claude (Fable 5) · **Baseline commit:** `63659cd`
**Scope:** full read of `siddetector.asm` (11,921 lines), `tests/test_suite.asm`, `Makefile`,
`scripts/ci_test.sh`, `scripts/vice_monitor.py`, `scripts/variant_smoke.py`,
`scripts/check_memorymap.py`, `scripts/hw_test.py`, `scripts/release.sh`,
`scripts/bump_version.sh`, `.gitignore`, `TODO.md`, and cross-check against `DOC-AUDIT.md`.

**How to use this document (instructions for the implementing model):**

- Work findings in ID order within a priority tier; finish P1 before P2.
- Each finding has a **Fix** and a **Verify** step. Do not mark a finding done
  without running its Verify step. `make ci` must pass after every change to
  `siddetector.asm` or `tests/test_suite.asm`; run `make ci-full` before any release.
- Several P1 items change timing-sensitive 6502 code. Change ONE finding per
  commit so a golden-diff regression can be bisected.
- Anything touching detection behaviour (marked ⚠ HW) can only be *fully*
  verified on real hardware via `make hw_test` — implement conservatively and
  flag those commits for the user to hardware-test.
- Do NOT re-verify or re-litigate items marked "already known" — they are
  cross-references, not new work.

Line numbers refer to the files as of commit `63659cd`.

**Update 2026-07-30 — implementation pass.** Most findings below have been
fixed and verified; see `## Status` at the end for the per-item table. Running
the tests surfaced one defect that static reading had missed, recorded as P0-1
immediately below. It is deliberately **not** fixed — it changes detection
semantics and needs a decision plus U64 hardware validation.

---

## P0 — Found by testing

**P0-1 is now FIXED using option 2, as chosen by the user.** The section below
is kept as the rationale; the implementation is described in
`### P0-1 implementation` immediately after it. P0-4 is fixed too; only P0-5
remains open, because it needs real hardware.

### P0-1 · `u64_fingerprint_scan` mislabels every $D4xx–$D7xx secondary SID as ULTISID
**File:** `siddetector.asm` — call site in `end:` (`lda data4 / cmp #$01 / beq end_run_u64fp`), routine `u64_fingerprint_scan`, store at `ufs_t_store`

**Severity: high — affects real hardware, not just the emulator.**

The scan runs whenever the primary is a real SID (`data4` ∈ {$01,$02}) with
**no `is_u64` gate**. It walks $D420–$D7E0, and every independent slot it finds
is stored with an ULTISID type code ($20 = 8580 curve, $22 = 6581 curve) —
unconditionally, even on a plain C64. Because it runs *before* the
family-specific `sidstereostart` sweeps, the dedup in those sweeps then finds
the address already present and never refines it, so the slot permanently
keeps the wrong identity.

**Proof (no chip personality involved at all).** Variant case
`tri-D500+DE00-plain-8580` is a plain emulated C64 with ordinary 8580s at
D400, D500 and DE00:

```
r16: STEREO SID.: D400 8580 FOUND
r17:              D500 8580 INT     <-- inside the scan range -> stamped ULTISID
r18:              DE00 8580 FOUND   <-- outside it ($DE) -> typed correctly
```

The only difference between rows 17 and 18 is that the scan stops at $D8.

**Consequences observed across the sweep:**

| Actual hardware at D5xx | Reported |
|---|---|
| plain 8580 | `D500 8580 INT` (should be `8580 FOUND`) |
| ARMSID | `D500 8580 INT` (should be `ARMSID FOUND`) |
| SwinSID Ultimate | `D500 8580 INT` (should be `SWINSID ULTIMATE`) |

So on a real C64 with any stereo cartridge in $D4xx–$D7xx, the second chip
loses its identity and is reported as a U64 UltiSID — on a machine that has no
U64 in it.

**Why it is like this.** `TODO.md` records that the `is_u64` gate was dropped
deliberately in V1.4.37, because U64 configs with UCI disabled return
`$DF1F = $FF` and so fail the `is_u64` probe while genuinely having 8 SIDs.
That change was hardware-verified for the "Tuneful Eight" case (3/3 runs). A
naive revert of the gate would regress that verified feature, which is exactly
why I have not touched it.

**Options (pick one — this is the decision I need from you):**

1. *Type honestly, label by machine.* `ufs_t_store` already has the real answer
   in `data1` from its own `checkrealsid` call ($01/$02). Store $01/$02 when
   `is_u64` is clear and the ULTISID codes only when it is set. Smallest change;
   the risk is U64-with-UCI-disabled boxes (where `is_u64` is still 0 at that
   point — the `sidnum>=4` retro-detect happens *after* the loop) would show
   `8580 FOUND` instead of `8580 INT`. Arguably fine, but it does change the
   Tuneful Eight display.
2. *Let the family scans refine.* Keep the scan for discovery but do not let it
   claim the type — record the slot with a "provisional" code that the later
   `sidstereostart` sweeps and `dedupe_sid_list` are allowed to overwrite (the
   $11 TLR-baseline mechanism already implements exactly this pattern).

Option 2 matches the existing design intent best. Either way it needs a
`make hw_test` run on the U64 to confirm the Tuneful Eight case still reports
8 SIDs.

### P0-1 implementation (option 2) — discover provisionally, refine in place

Four coordinated changes, because "record a provisional type and let the family
scans refine it" could not work as-is: **every** add path deduped by address and
*skipped* matches, so a refined entry could never be written.

1. **`u64_fingerprint_scan` no longer claims the type.** It stores what its own
   `checkrealsid` actually measured ($01/$02/$F0 — never an ULTISID code) and
   sets a new per-slot flag `sid_prov` marking the type as refinable.
2. **The dedups refine instead of skipping.** `s_s_dup_lp` (sidstereostart)
   overwrites `sid_list_t` in place when `sid_prov` is set; `fll_dup_lp`
   (fiktivloop) falls into the identification path at a new `fll_refine` entry
   point with `X` already pointing at the existing slot. Refining *in place*
   rather than appending a duplicate for `dedupe_sid_list` to collapse is
   deliberate: appending would need up to 8 extra slots and would break the
   8-SID Tuneful Eight list.
3. **U64 keeps its curve labels.** At `ufs_chk_u64` (after the existing
   `sidnum >= 4` retro-detect), if `is_u64` is set the provisional entries are
   converted to $20/$22 and the flags cleared, because on a U64 nothing
   downstream *can* refine them — `fiktivloop`'s noise-mirror checks reject
   UltiSID slots, which is why this scan exists at all. Tuneful Eight behaviour
   is therefore unchanged. ⚠ HW: still worth a `make hw_test` confirmation.
4. **Two self-comparison bugs fixed, exposed by the above.** With the slot now
   typed $01/$02 instead of $20, both mirror checks began testing the candidate
   *against itself* — driving its own voice 3 and reading its own OSC3 always
   returns non-zero, so the slot rejected itself as a mirror. `s_s_arm_mir_test`
   and `fll_mlp` now skip any list entry whose address equals the candidate's.
   (Two branches went out of range as a result and became long jumps.)

**Measured effect:**

| Case | Before | After |
|---|---|---|
| plain 8580 at D500 | `D500 8580 INT` | **`D500 8580 FOUND`** |
| ARMSID at D420 | `D420 8580 INT` | **`D420 ARMSID FOUND`** |
| ARMSID at D500 | `D500 8580 INT` | `D500 8580 FOUND` (see P0-5) |
| U64 Tuneful Eight | ULTISID curves | unchanged (converted at `ufs_chk_u64`) |

### P0-5 · ARMSID / SwinSID U at $D5xx-$D7xx are still not identified by name
**File:** `siddetector.asm` — `s_s_try_dis` → `sfx_probe_dis_echo`

With P0-1 fixed, an ARMSID at **D420** is now correctly named (the D4xx path
calls `Checkarmsid` directly). An ARMSID or SwinSID Ultimate at **D500** still
reports as `8580 FOUND`: that path relies on `sfx_probe_dis_echo` reading the
DIS echo from `candidate+$1B`, and the echo is not coming back in the VICE
proxy. This is pre-existing — the stored goldens show these cases have never
been identified — and it is *not* a regression: the result went from actively
wrong (`8580 INT`, claiming a U64 UltiSID) to honest (`8580 FOUND`, which is
exactly what an ARMSID in 8580 mode emulates, and matches the documented
WONTFIX for the SIDFX+ARMSID@D420 case).

I did not chase it further because it is a chip-protocol question: either the
patched VICE's `-sidvariant2` personality does not implement DIS at a secondary
base, or the probe needs a different sequence there. Deciding that needs the
real ARMSID hardware, not the emulator. The `CASES` row checks still demand
`ARMSID FOUND` / `SWINSID ULTIMATE`, so the sweep keeps flagging it — leave
them as the record of intent.

### P0-2 · The variant goldens were regenerated *over* P0-1, so the golden diff is green on wrong output
**Files:** `tests/variant_goldens/*.txt` vs the `expected` column in `scripts/variant_smoke.py:CASES`

The stored goldens record `D500 8580 INT` etc. — i.e. they were captured with
`--update` after the P0-1 behaviour appeared. The per-row substring checks in
`CASES` still demand `ARMSID FOUND`. The two halves of the harness therefore
contradict each other and the sweep **cannot** go green: 8 of 30 cases fail
this way in every run, and they have been failing for some time (verified
identical on pristine `63659cd`).

Worse, two cases *pass* while showing the P0-1 symptom, because their expected
substring is a prefix that matches anyway (`"D500 8580"` matches
`"D500 8580 INT"`). The substring check is the only assertion still objecting
to P0-1, and it only objects by accident.

**FIXED.** With P0-1 settled the goldens were re-captured once (`--update`,
30/30 written, no SKIPs) and every change reviewed by eye. The whole diff is 8
files / 11 lines, and every line is an improvement:

```
stereo-D500-armsid        r17: D500 8580 INT  ->  D500 8580 FOUND
stereo-D500-fpgasid8580   r17: D500 8580 INT  ->  D500 8580 FOUND
stereo-D500-swinu         r17: D500 8580 INT  ->  D500 8580 FOUND
tri-D420-armsid+D500-8580 r17: D420 8580 INT  ->  D420 ARMSID FOUND
                          r18: D500 8580 INT  ->  D500 8580 FOUND
tri-D420-armsid+D500-armsid   (same two rows)
tri-D420-armsid+D500-fpgasid  (same two rows)
tri-D420-armsid+DE00-8580 r17: D420 8580 INT  ->  D420 ARMSID FOUND
tri-D500+DE00-plain-8580  r17: D500 8580 INT  ->  D500 8580 FOUND
armsid-d420 / arm2sid-d420 r17: DE00 8580 FOUND -> D420 ARMSID FOUND  (P0-3)
```

The other 22 goldens are byte-identical, which is the evidence that the change
is confined to the mislabelling it was meant to fix.

### P0-4 · The goldens capture the `checkrealsid` retry star, so they are nondeterministic under host load
**Files:** `siddetector.asm` (`print_retry_star`) vs `scripts/variant_smoke.py` (`decode`, `render_golden`)

On the third full sweep the `sidfx` case failed with this diff:

```
-golden  r06: 8580 SID...: 8580 FOUND
+actual  r06: 8580 SID...: 8580 FOUND.
```

The extra character is the `*` that `print_retry_star` appends when
`retry_zp > 0` — i.e. when `checkrealsid` needed a second or third attempt
because VIC bad-line DMA stole cycles on the first. That is expected program
behaviour and is *deliberately* surfaced to the user, but it depends on raster
timing and host load, so it is not stable enough to belong in a byte-exact
golden. It appeared on run 3 and not on runs 1-2 of the same binary.

It also shows the P2-10 decoder gap from the other side: `*` ($2A) is not in
`decode`'s table, so it renders as `.` and the diff is needlessly cryptic.

**Fix:** in `render_golden`, strip (or normalise to a fixed marker) the retry
star before comparing — e.g. drop a trailing `*` from the `6581 FOUND` /
`8580 FOUND` rows. Add `*` to the decoder at the same time so any future
occurrence reads as `*` rather than `.`. Do not simply re-`--update` the
golden: whichever variant you capture will fail on the next run with the
opposite timing.

### P0-3 · Two variant cases never place the chip where their name says
**File:** `scripts/variant_smoke.py:70-71`

```python
("armsid-d420",  ["-sidextra", "1", "-sidvariant2", "armsid"],  17, "ARMSID FOUND"),
("arm2sid-d420", ["-sidextra", "1", "-sidvariant2", "arm2sid"], 17, "ARMSID FOUND"),
```

Neither passes `-sid2address`, so VICE puts SID #2 at its **default** address,
not $D420 — the captured screens say `DE00 8580 FOUND`. Every other stereo
case passes an explicit `-sid2address`. These two used to work by accident, on
a stale `Sid2AddressStart=$D420` leaking in from the user's `vice.ini`; adding
`-default` (to fix a *different* leak, per the comment in `_launch_and_capture`)
removed that crutch and exposed them.

**FIXED** as part of the P0-1 change: both cases now pass
`"-sid2address", "54304"` and their goldens read `D420 ARMSID FOUND`, so they
finally test what their names claim. (Fixing this in isolation would have been
pointless — before P0-1 they would merely have reported `D420 8580 INT`
instead.)

---

## P1 — Bugs / correctness

### P1-1 · IRQ vector installed without SEI — restart-time crash race
**File:** `siddetector.asm:1166-1187` (`readkey2`)

`readkey2` writes the two IRQ vector bytes non-atomically while interrupts are
still enabled:

```asm
readkey2:  ldx #$FF
           txs
           ldx #<IRQ
           ldy #>IRQ
           lda #$00
           stx $0314      ; <-- KERNAL CIA timer IRQ is still live here
           sty $0315      ; <-- race window between these two writes
```

The detection chain ends with interrupts enabled (`checkrealsid` does an
explicit `cli` at `loop2`, `palntsc` ends with `cli`), and CIA1 timer IRQs are
only disabled *after* the vector store (`sta $DC0D` with `#$7F` comes later).
An IRQ landing between `stx $0314` and `sty $0315` vectors through
`<IRQ / $EA` — a wild jump. Low probability per run, but this executes on
every SPACE restart; it is the classic C64 vector-install bug.

**Fix:** wrap the vector install in `sei` / re-enable via the existing `cli` at
the end of the block (move `sei` before `stx $0314`; the block already ends in
`cli`). Also disable CIA IRQs (`lda #$7F / sta $DC0D`) *before* touching
`$0314/$0315` for belt-and-braces.

**Verify:** `make ci` + `make ci-full` (goldens unaffected — no visible
behaviour change). Optional: soak-test with `scripts/vice_restart_test.py`.

---

### P1-2 · `Makefile` `readresult` target is broken twice
**File:** `Makefile:117-130`

1. The awk extracts the wrong field. `siddetector.vs` lines look like
   `al C:59e0 .backsid_d41f`, so `awk '{print $1}'` yields `al`, not the
   address. (`ci_test.sh:56` correctly uses `$2` on the same file format.)
   The subsequent `read-mem al` call fails.
2. The hard-coded addresses in the comment and commands are stale:
   `num_sids`/`sid_list_t` moved to the `$6000` data segment long ago, but the
   target still reads `$2900`/`$2918` (and the comment cites `backsid_d41f=$244D`).

**Fix:** use `awk '{print $2}' | sed 's/C://'` and resolve `num_sids` /
`sid_list_t` from `siddetector.vs` the same way instead of hard-coding
addresses (pattern already exists in `hw_test.py:sym()`).

**Verify:** with a U64 online: `make remote && make readresult` prints
plausible values. Without hardware: dry-check that the awk pipeline yields a
4-hex-digit address (`grep ' \.backsid_d41f' siddetector.vs | awk '{print $2}' | sed 's/C://'`).

---

### P1-3 · `hw_test.py` snapshot misses SID slot 8 (8-SID "Tuneful Eight" configs)
**File:** `scripts/hw_test.py:172-198`

`sid_list_*` has 9 entries; slots **1–8** are active (the U64 Tuneful Eight
fills all 8). `read_snapshot` and `snapshots_equal` iterate `range(8)` —
indices 0–7 — so the 8th detected SID (index 8) is invisible to the baseline
and to stability checks. The docstring also says "slots 1-7 hold detected
SIDs", which is wrong.

**Fix:** iterate `range(9)` (or `range(1, 9)` and drop the unused slot 0
entirely); update the docstring; update `check_stable`'s diff loop to match.

**Verify:** `python -c` unit-style check on the changed functions with a fake
9-entry list, then `make hw_test` on real hardware in the tuneful-eight
scenario (⚠ HW).

---

### P1-4 · Dead-but-assembled routines contain latent bugs (`cmp $07` without `#`)
**File:** `siddetector.asm:6074-6167` (`checksecondFPGA`), `5938-6071` (`checkanothersid`), `7848-7877` (`checkswinmicro`)

None of these three routines is called any more (all call sites are commented
out or bypassed), but they still assemble into the binary. `checksecondFPGA`
compares against **zero page** instead of immediates:

```asm
       cmp $07        ; line 6094 — reads ZP $07, intended cmp #$07
       ...
       cmp $06        ; line 6099 — same bug
```

If anyone re-enables these paths, detection silently depends on whatever ZP
$06/$07 hold. `checkanothersid` also uses a different sid_list bounds
constant (`#$07` at 6042) than the live code (`#$08`).

**Fix:** delete all three routines (and `swinsidmicrof` if it becomes
unreferenced). This recovers a few hundred bytes and removes the trap. If the
user prefers to keep them for reference, fix the `#` typos and add a
`// DEAD CODE — not called` banner.

**Verify:** `make ci-full` (binary shrinks; goldens must be unchanged).

---

### P1-5 · `jsr s_s_l3` no-ops disguise the sidstereostart control flow
**File:** `siddetector.asm:5476, 5484, 5492` (inside `sidstereostart`)

`s_s_l3` is a bare `rts`. `jsr s_s_l3` therefore does nothing except burn 12
cycles, then execution **falls through** to the next family's compare — and,
for the `sidtype=$01` path, falls through into the `s_s_E000` block
(5495-5511), which is what actually terminates the scan by forging
`scnt_zp=$2F`. The code reads as "exit here" but doesn't exit; the real
control flow is fall-through + a magic state override. This exact confusion
already produced one historical bug (see the long comment at 5459-5467).

**Fix (behaviour-preserving refactor):**
- Replace each `jsr s_s_l3` with either nothing (document the fall-through) or
  an explicit `jmp` to the intended continuation.
- Give `s_s_E000` a comment stating it is the *terminator* for the real-SID
  path (reached by fall-through from `s_s_l6581`), or restructure so the
  `sidtype=$01` path ends with an explicit `jmp s_s_l3` after `fiktivloop`
  if the forged-counter exit is equivalent (check first: `s_s_E000` also sets
  `mcnt_zp=5` and `sptr` to `$DFE0`, which `s_s_next` uses — a plain exit IS
  equivalent since `cpx #$30` then ends the loop; confirm by golden diff).

**Verify:** `make ci-full` — all 30 variant goldens must be byte-identical.
This is a refactor with zero intended behaviour change; if any golden moves,
revert and study why.

---

### P1-6 · Main-screen decay classifier and info-page classifier disagree (SwinSID Nano)
**File:** `siddetector.asm:7994-8006` (`checktypeandprint` → `nc_Swinsidn`) vs `3797-3807` (`get_emu_page`)

Both routines decode the same decay signature `data1∈{$01,$02}, data2=$00`.
`get_emu_page` maps it to the SwinSID Nano info page (IP_SWINANO), but
`checktypeandprint` prints `sunknown` ("UNKNOWNSID") for the identical
signature — the comment above it still says `| Swinsid Nano | done`. So the
user sees "UNKNOWNSID" on row 15, presses I, and gets a confident SwinSID
Nano page. One of the two is wrong; they must agree.

**Fix:** decide the intended label (likely "UNKNOWNSID" both places, since
Step 0.5 now detects Nano directly and the decay signature alone is ambiguous
with NOSID+U2+ per `docs/FINDINGS.md`) and make `get_emu_page` return
IP_UNKNOWN for it — or vice versa. Longer term: both routines are parallel
decision trees over (data1,data2,data3); derive both from one table the way
`sid_type_index` unified the name tables.

**Verify:** `make ci`; run `make run-none` style checks in stock VICE ResID /
FastSID to confirm emulator classification unchanged.

---

### P1-7 · Q page vs main screen disagree on ULTISID types $21/$24/$25/$26
**File:** `siddetector.asm:11848-11864` (`quality_print_chiptype`) vs `6384-6399` (`ssp_skp16`)

Main screen: `$20/$21/$24/$25/$26` → "8580 INT", `$22/$23` → "6581 INT".
Q page: only `$20` → `ULTI85`; **everything else in $20-$26 → `ULTI65`**.
Today `uci_type_for_addr` only emits `$20`/`$22`, so the mismatch is latent —
but `utfa_map` (10934-10942) can return the full `$20-$26` range from the UCI
type byte, at which point `$21/$24/$25/$26` would show 8580 on the main screen
and 6581 on the Q page.

**Fix:** in `quality_print_chiptype`, use the same 6581-set as `ssp_skp16`
($22/$23 → 6581, everything else in range → 8580). The `sec/sbc #$22/cmp #$02`
trick from `ssp_skp16` can be reused verbatim.

**Verify:** `make ci` (T33-T43 untouched); manual Q-page check with
`scripts/q_page_smoke.py`.

---

### P1-8 · `Checkarmsid` data3 read is never address-patched (`cas_d41d7`)
**File:** `siddetector.asm:4107`

Every other SID-register access in `Checkarmsid` is self-modified from
`sptr_zp`, but `cas_d41d7: lda $D41D` (the ARM2SID data3/'R' read) is
hard-coded to `$D41D` and missing from the patch list at 4008-4044. When
`Checkarmsid` runs at a non-D400 slot (called from `s_s_arm_detect`, D4xx
window scan), `data3` is read from the wrong chip. Impact is currently low —
the live ARM2SID discriminator is `armsid_major`, not `data3` — but the test
suite (`dispatch_armsid`, T07) still models data3 as the discriminator, so
the code, the patch list, and the tests are mutually inconsistent.

**Fix:** either add `cas_d41d7+1/+2` to the patch block, or (better, see
P2-6) delete the data3 read if it is truly unused and update the test suite's
obsolete ARM2SID model at the same time.

**Verify:** `make ci` (adjust T07 if the data3 model is removed) +
`make run-arm2sid` golden.

---

## P2 — Robustness / fragility

### P2-1 · `taskkill /F /IM x64sc.exe` kills the user's interactive VICE too
**Files:** `scripts/ci_test.sh:38,60,67,73`, `scripts/variant_smoke.py:312,332`

Every CI/smoke run force-kills *all* x64sc.exe processes on the machine,
including an interactive `make run-armsid` session the user may have open.

**Fix:** track and kill only the PID the script itself spawned
(`subprocess.Popen(...).pid` / `$VICE_PID`); keep one initial "stale process"
sweep behind an explicit `--kill-stale` flag (or keep current behaviour but
print a loud warning). In `variant_smoke.py`, `proc.kill()` +
`proc.wait()` replaces the post-run taskkill entirely.

**Verify:** run `make test-variants` while a second, manually-started VICE is
open — the manual instance must survive; the sweep must still pass.

---

### P2-2 · `variant_smoke.py` uses a fixed monitor port (6502) and fixed 30 s sleeps
**File:** `scripts/variant_smoke.py:30-33, 323-331`

- `ci_test.sh` deliberately picks a free port to avoid TIME_WAIT collisions;
  `variant_smoke.py` hard-codes 6502 and will collide with anything else
  bound there (including a parallel smoke run).
- Each of the 30 cases sleeps a flat `WAIT = 30.0` s before the first dump,
  then relies on up to 2 full retries. Best-case runtime ≈ 16 minutes; the
  docs still claim "~4 min" (see P4-2). The readiness heuristic
  (`_is_basic_loading_screen`) already exists — it just isn't used to poll.

**Fix:**
1. Pick a free port the same way `ci_test.sh` does and pass it through.
2. Replace the flat sleep with a poll loop: dump the screen every 2-3 s (the
   monitor pauses the emulated machine only for milliseconds per dump) until
   `_is_basic_loading_screen()` returns False or a 45 s deadline passes. This
   typically cuts a passing sweep from ~16 min to ~5-6 min and removes most
   retry noise.

**Verify:** `python scripts/variant_smoke.py none swinu sidfx` passes; then a
full `make test-variants` (all 30 PASS), twice back-to-back to prove no port
collision/TIME_WAIT issue.

---

### P2-3 · `release.sh` pre-flight dirty check filters away almost everything
**File:** `scripts/release.sh:47`

```bash
DIRTY=$(git status --porcelain | grep -v '^\?\?' | grep -v '^[ M]' || true)
```

`grep -v '^[ M]'` drops every line whose first column is a space **or `M`** —
i.e. both unstaged *and staged* modifications — and `^??` drops untracked.
Net effect: `DIRTY` is empty for essentially every real working-tree state,
so the "continue anyway?" guard never fires and releases can silently include
or omit uncommitted work.

**Fix:** decide the actual policy. Recommended: warn on **anything**
porcelain reports except the files release.sh itself will regenerate
(`siddetector.prg/.dbg/.sym/.vs`, `tests/test_suite.*`). Implement as a
whitelist, not the current broken blacklist.

**Verify:** with a scratch edit to `README.md`, run `bash scripts/release.sh x`
in a throwaway branch — it must prompt. (Abort before the push stage.)

---

### P2-4 · Tool paths duplicated across 3+ files (proven drift source)
**Files:** `Makefile:1-8`, `scripts/ci_test.sh:28-30`, `scripts/variant_smoke.py:28`

KickAss and the patched-VICE path are each hard-coded in multiple places;
commit `63659cd` ("fix: correct stale Python path in ci_test.sh") is direct
evidence this drifts. `hw_test.py` additionally never passes `--ip` to the
`c64u` binary (only to `u64remote`), so it silently depends on
`bin/u64remote.ini` matching the CLI argument.

**Fix:** single source of truth — e.g. a `paths.mk` / `.env` file consumed by
the Makefile and read by the Python/bash scripts (`os.environ` /
`VICE=${VICE:-default}`), with the Makefile exporting `VICE` and `KICKASS`
when invoking scripts. For `hw_test.py`, pass `--ip` through to c64u if the
binary supports it, or assert at startup that the ini host matches `--ip`.

**Verify:** temporarily rename the VICE directory; every entry point must fail
with the *same* clear message from one config location; restore and run
`make ci`.

---

### P2-5 · Expected pass-count (43) hard-coded in three places
**Files:** `scripts/ci_test.sh:31`, `tests/test_suite.asm:1027` (`cmp #43`) and `:1676` ("ALL 43 TESTS PASSED"), plus header comments

Adding a test requires touching all of them; forgetting the shell constant
makes CI fail with a confusing count mismatch (forgetting the asm one makes
the on-screen summary lie).

**Fix:** have the test suite write **two** bytes: pass count at `$07E8`
(existing) and total-tests at `$07E9` (new `.const TEST_TOTAL` used by both
the `cmp` and the summary string is harder for strings — at minimum define
`TEST_TOTAL` in the asm and have `ci_test.sh` derive EXPECTED_PASS by reading
`$07E9` from the saved region, i.e. save `$07E8-$07E9` and compare the two
bytes for equality instead of against a shell constant).

**Verify:** `make ci` passes; then deliberately break one test locally and
confirm CI fails with a clear `42/43` message; revert.

---

### P2-6 · Test suite tests *copies* of production logic, and one copy is obsolete
**File:** `tests/test_suite.asm:1117-1148` (`dispatch_armsid`), `:1399-1431` (`dispatch_sid_index` + `tb_sid_code_to_slot`)

Two structural problems:

1. **Obsolete model:** `dispatch_armsid` discriminates ARM2SID via
   `data3=='R'($53)` — production stopped doing that; it now queries firmware
   (`armsid_get_version` → `armsid_major==3`). T07/T08 therefore validate
   logic that no longer exists, giving false confidence. (Note: T07's comment
   also mislabels `$53` as 'R'; $53 is 'S'.)
2. **No drift protection:** `dispatch_sid_index` embeds its own copy of
   `sid_code_to_slot` and asserts against literal expected slots. If the
   *production* table changes, the test still passes — despite the in-file
   comment claiming the opposite. The comments also claim the
   `armsid_emul_mode = $5592`-style constants come "from siddetector.sym";
   they are actually just scratch RAM in the standalone test image and drift
   silently with every build (harmless today, but the comment invites someone
   to "fix" them).

**Fix:**
1. Rewrite S3 to model the current dispatch: `data1=$05 && data2=$4F` →
   ARMSID family; ARM2SID split on `armsid_major` (a variable the test can
   set), not data3.
2. Move `sid_code_to_slot` into a shared include file (`tests/` and main asm
   both `.import`/`#import` it), so there is physically one table. Same for
   the qbands byte pairs if practical.
3. Replace the fake `$55xx` absolute constants with local test labels and
   delete the misleading comments.

**Verify:** `make ci` (still 43/43 — or the new count if tests were
added/renamed; update per P2-5 mechanism).

---

### P2-7 · `txs`/`tsx` register-save trick runs with IRQs enabled during detection
**File:** `siddetector.asm` — pervasive in `start:`'s print dispatch (e.g. 231-239, 364-372, 388-394, 526-535, …)

The pattern `txs / ldx #row / ldy #col / jsr $E50C / tsx` uses the stack
pointer as a one-byte register save. During the detection chain interrupts
are frequently **enabled** (`palntsc` ends in `cli`; `checkrealsid` does
`cli`), so an IRQ can fire while SP holds a screen row number (as low as 2).
The push sequence then wraps within page 1. It happens to survive because
nothing else owns page 1, but it is one KERNAL change or one added `jsr` away
from corruption, and it is the reason `readkey2` needs its `ldx #$FF / txs`
repair. `x_zp`/`y_zp` save slots already exist and are used elsewhere in the
very same file.

**Fix (mechanical, low risk):** replace the `txs … tsx` pairs around
`jsr $E50C` with `stx x_zp … ldx x_zp` (or `pha/pla` where A is free). Do it
in one sweep; there are ~25 sites, all identical in shape.

**Verify:** `make ci-full` — goldens must be byte-identical (screen output
unchanged). This also removes the need for the readkey2 SP reset, but KEEP
that reset anyway as defence in depth.

---

### P2-8 · `checkkungfusid` / `checkusid64` headers promise slot-relative probing they don't do
**File:** `siddetector.asm:4292-4350`

`checkkungfusid`'s comment says "Uses (sptr_zp),Y indirect so stereo scan can
call it at any SID slot", but the body uses absolute `$D41D`. `checkusid64`
likewise hard-codes `$D41F/$D418`. Both are currently only called for D400,
so behaviour is correct — but the comments actively invite a future caller to
pass another slot and silently probe the wrong chip. (The SIDFX secondary
path already re-implements the KungFu probe inline with `(sptr_zp),y` at
6825-6840 because of this.)

**Fix:** either convert both to `(sptr_zp),y` addressing (and collapse the
duplicated inline KungFu probe at 6825-6840 into the shared routine), or
correct the comments to say "D400 only".

**Verify:** `make ci-full`; `make run-kungfusid` and `make run-usid64`
goldens unchanged.

---

### P2-9 · `check_memorymap.py` never fails on unresolved symbols
**File:** `scripts/check_memorymap.py:69-102`

Rows whose symbol vanished from `siddetector.sym` (e.g. after a rename) are
reported as "unresolved" but exit code stays 0 — the drift guard passes while
the doc points at a dead label. Only address *mismatches* fail.

**Fix:** add `--strict` (exit 1 when non-ZP unresolved symbols exist) and use
it in the `ci` target; keep default lenient behaviour for local use.

**Verify:** rename a symbol in a scratch copy of MEMORYMAP.md → `make ci`
fails; restore → passes.

---

### P2-10 · `variant_smoke.py` golden decoder swallows characters
**Files:** `scripts/variant_smoke.py:240-251` vs `scripts/hw_test.py:114-129`

Two hand-rolled screen-code decoders exist with different character coverage
(`hw_test` handles `()=-`, `variant_smoke` doesn't; neither handles `*`,
`$`, `[`, `]`). Unknown codes become `.` in goldens, weakening the diff (any
character change within the unmapped set is invisible). The Q page and
tracker use `*`, `[`, `]`, `$` heavily, so future goldens for those screens
would be blind.

**Fix:** factor a single `decode_screen()` into e.g. `scripts/c64screen.py`
with a full screencode→ASCII table (0x00-0x3F at minimum), import it from
both scripts (and `screendump.py` if it has a third copy). Regenerate goldens
with `--update` once, in the same commit, and eyeball the diff — only `.`→real
characters should change.

**Verify:** `make test-variants` passes against the regenerated goldens.

---

### P2-11 · `arm2sid_populate_sid_list` has no sid_list bounds guard
**File:** `siddetector.asm:6591-6699`

Every other list writer (`s_s_add`, `fll_found_ok`, `uca_found`,
`tls_no_append`) checks `sidnum_zp` against 8 before storing;
`arm2sid_populate_sid_list` increments blindly for up to 7 slots. Today the
arithmetic exactly fits (1 pre-populated + 7 = 8), but a future extra
pre-populate (the SIDFX path adds 2) or a firmware returning unexpected map
nibbles would overrun `sid_list_*` into `uci_resp` — the exact corruption
described in the `s_s_add` comment.

**Fix:** add the same `lda sidnum_zp / cmp #$08 / bcs skip` guard before each
store (or wrap the store in a small shared `sid_list_append` helper — see
P3-4).

**Verify:** `make ci`; `make run-arm2sid` golden unchanged.

---

## P3 — Maintainability / cleanup

### P3-1 · Delete dead code and stray artifacts
**Files / lines:**
- `siddetector.asm:7918` — unreachable `rts` after `jmp funny_print`.
- `siddetector.asm:583` — `tsx` marked "unreachable; kept for padding".
- `siddetector.asm:9180 + 9208` — `scope_plot`'s dead `lda scope_col_lo,x`
  ("skip for now") and the 40-byte `scope_col_lo` placeholder table.
- `siddetector.asm:8349-8352` — `data1_old`/`data2_old` (written nowhere,
  read nowhere as far as this review found — confirm with the .sym before
  deleting).
- `scripts/hw_test.py:47` — unused `KBDLOOP_ORIG` constant.
- Root: `monlog_out.txt` is untracked debug output → add `/monlog_out.txt`
  to `.gitignore` (which is already modified but uncommitted — commit it).

**Verify:** `make ci-full` byte-identical goldens; `git status` clean.

### P3-2 · Copy-paste comment noise in self-mod patch blocks
**File:** `siddetector.asm:4029-4066` (and the same pattern in `checkrealsid`, `checksecondsid`)

Every patched offset is annotated "Voice 3 control at D418" even when the
offset is `$1B/$1C/$1D/$1E/$1F`, and every line carries the identical
"timing issue requieres runtime mod of upcodes." string. Replace with one
block comment per routine ("operand bytes patched from sptr_zp so the routine
can probe any SID slot") and correct per-line register names. Zero code bytes
change.

### P3-3 · Magic constants for info-page count
**File:** `siddetector.asm:1790-1810`

`#18` (last page index) appears twice in wrap logic and must match the
pointer tables at 9617-9629. Introduce `.const INFO_PAGE_MAX = 18` next to the
tables, with a comment that it must equal (table length − 1).

### P3-4 · Extract a `sid_list_append` helper
Six near-identical "bounds-check + inx + store l/h/t" sequences exist
(`s_s_add`, `fll_*`, `uca_found`, `tls_no_append`, `ccas_writesidl`(dead),
`arm2sid_populate_sid_list`). A single helper taking A=type, addr in
`mptr_zp` (or params in ZP) removes ~80 bytes and makes the bounds policy
(P2-11) uniform. Do this *after* P1-4/P2-11 so the diff stays reviewable.

### P3-5 · `checktypeandprint` / `get_emu_page` should be table-driven
Both walk the same ~10 signature checks in sequence (see P1-6). A table of
`(field, lo, hi, string/page)` rows evaluated by one matcher removes the
drift class entirely. Medium effort; only worth doing together with P1-6.

### P3-6 · `tests/` directory hygiene
Generated artifacts (`*.prg/.dbg/.vs/.sym` for probes) are ignored, but
`tests/hw_test_result_*.txt` reports are written into the repo tree at every
hw run (ignored, good) and `tests/test.mon`-family monitor scripts overlap
(`ci.mon`, `ci_run.mon`, `ci_debug.mon`, `ci_debug2.mon`, `diag.mon` — only
`test*.mon`, `debug.mon` are referenced by the Makefile; `ci.mon` is
referenced only by a stale Makefile comment, see P4-1). Move truly unused
`.mon` files to `tests/attic/` or delete them.

---

## P4 — Documentation / consistency drift

### P4-1 · Stale Makefile comments
**File:** `Makefile`
- Line 161-162: "full test suite … (35 tests …) `$23`=35" → **43 / `$2B`**.
- Line 169: "gate on pass count (all 23 must pass)" → **43**.
- Lines 170-172: claims CI "runs tests/test_suite.prg **with tests/ci.mon**,
  saves tests/ci_result.bin" — `ci_test.sh` actually uses the remote monitor
  via `scripts/vice_monitor.py`; `ci.mon` is not involved.
- Line 118: comment cites stale absolute addresses (see P1-2).

### P4-2 · "14-case sweep / ~4 min" claims vs 30 actual cases
**Files:** `CLAUDE.md` ("14-case headless sweep", "make ci-full … ~4 min
(30 s unit tests + 14 variant launches)"), `Makefile:179` ("~4 min"),
`docs/VICE_PROXY_USAGE.md` (verify while editing).
`variant_smoke.py` has **30** cases; a full sweep at WAIT=30 s takes ≈16 min.
Update the numbers — or implement P2-2 first and then write the new true
numbers.

### P4-3 · `TODO.md` drift (partially known)
- Line 120 "35 tests" → 43. *(Already reported as DOC-AUDIT P2-1 — fix both
  in one commit.)*
- Line 23: BackSID protocol description ("write $42 to D41C … read D41F; if
  D41F==$42") does not match the implemented protocol
  (`D41B=$02, D41C=$01, D41D=$B5, D41E=$1D`, poll `D41F` for `$01` —
  `siddetector.asm:10748-10806`). Rewrite the TODO line from the code.

### P4-4 · In-source comment drift
**File:** `siddetector.asm`
- Lines 17-24 (file header): result-code table and memory layout are the
  V1.x originals — `$080D main program`, `$1D00 result tables` are wrong
  (now `$2400` / `$6000`); the code list omits $08-$0E/$11/$20-$26 types.
  Rewrite the header from `docs/MEMORYMAP.md` + `sid_code_to_slot`.
- Line 8265: `unknownsid` comment "data1=$09" — $09 is PDsid now.
- Lines 8377 & 10804: `backsid_d41f` comment "$42 = BackSID present" — the
  code compares `#$01`.
- Lines 11386-11389: `tlr_sweep` header says the gate is
  "data4 ∈ {$00,$01,$02}"; the actual call-site gate (line 967-969) and the
  design record are **$00 only**. Fix the header.
- Line 1177: `$0314/$0315` described as "CIA1 IRQ vector" — it is the KERNAL
  IRQ vector.
- Line 61-99: the "V1.20 / V1.00 todo / test case" block is a fossil;
  either delete or move to TODO.md.
- `tests/test_suite.asm:224` — "$53" annotated as 'R' (it is 'S'); moot if
  P2-6 rewrites S3.

### P4-5 · `uci_resp` layout is described three different ways
**File:** `siddetector.asm:9517-9520` (data), `9360-9403` (`check_uci_ultisid`
writes 9+2 bytes, format `[1..4]=EMUSID1(lo,hi,type,flags)`),
`10829-10911` (`uci_type_for_addr` reads 22 bytes, format
`[lo,hi,sec_hi,sec_lo,type]`, Frame1 type at [5]).
`check_uci_ultisid` reads EMUSID2 fields from `resp[5..8]` while
`uci_type_for_addr` reads Frame2 from `resp[6..10]` — different frame sizes
(4 vs 5 bytes) for the same command's response. One of the two parsers is
working by accident, or they target different firmware revisions; either way
the data-layout comment at 9517 matches only the second. Reconcile against
the actual UCI GET_HWINFO response format (`docs/UCI.md`) and make both
parsers share offsets via `.const` definitions. ⚠ HW to fully verify
(needs U64).

---

## Noted, no action required

- `vice_monitor.py` is solid: dynamic port, PC-verified breakpoint, bounded
  retries — good reference implementation for P2-2.
- The `qrec()` assemble-time patch-site list for the sidcheck port is an
  excellent pattern; the ZP placement of `qc_pt_ptr` (KickAsm `(zp),y`
  truncation trap) is correctly handled and documented.
- `calcandloop`'s `txs` tail-call trick is already documented as
  memory/`calcandloop_txs_tail_call_trick`; `calcandloop_q` correctly avoids
  it. No change needed (P2-7 covers the *other* txs pattern).
- `u64_fingerprint_scan`'s write-coupling approach and its bounded UCI drain
  loops are sound; the `sidnum>=4 → is_u64` heuristic is a reasonable
  behavioural fallback.
- `checkfmyam`'s T2-then-T1 dual-timer verification with PHP/SEI/PLP framing
  is careful, correct work.
- `dedupe_sid_list` bounds and compaction verified correct, including the
  `bcc/beq` inclusive loop ends.
- DOC-AUDIT.md (2026-07-18) already covers general doc health; this review
  found only the additional doc items in P4 above.

## Status — implementation pass, 2026-07-30

Verification used on every change: `bash scripts/ci_test.sh` (**46/46**),
`python scripts/check_memorymap.py --strict` (0 drift, 0 dead symbols),
`python tests/test_hw_snapshot.py` + `python tests/test_variant_render.py`
(**12/12**, both positive-controlled), and four full 30-case variant sweeps.

`make` is **not installed on this machine**, so the Makefile targets were
exercised by running the scripts they wrap; the Makefile edits were verified by
hand-expanding the recipes in a shell.

### Per-item status

| ID | Item | Status |
|---|---|---|
| P0-1 | `u64_fingerprint_scan` ULTISID mislabel | **fixed (option 2)** - provisional type + in-place refinement; 2 self-mirror bugs fixed en route. HW: re-confirm Tuneful Eight |
| P0-2 | Goldens regenerated over P0-1 | **fixed** - re-captured once, 30/30 written, 8-file / 11-line diff reviewed line by line |
| P0-3 | 2 variant cases missing `-sid2address` | **fixed** - both now place the chip at $D420, and both pass |
| P0-4 | Retry star made goldens nondeterministic | **fixed** - `*` decodes as `*`, `strip_retry_star()` normalises it out of the golden; 8 new tests |
| P0-5 | D5xx ARMSID / SwinSID U not named | **OPEN** - chip-protocol question, needs the real hardware |
| P1-1 | IRQ vector installed without SEI | fixed - `sei` + CIA mask/ack before the vector swap |
| P1-2 | `readresult` awk field + stale addresses | fixed - resolves every symbol from `.vs` at run time |
| P1-3 | hw_test blind to sid_list slot 8 | fixed - `NSLOTS = 9`; new `tests/test_hw_snapshot.py` |
| P1-4 | Dead routines with latent `cmp $07` bugs | fixed - 3 routines + dead data removed (273 lines, ~364 bytes) |
| P1-5 | `jsr s_s_l3` no-ops hiding control flow | fixed - explicit `jmp s_s_next`; fall-through documented |
| P1-6 | Decay classifier vs info page disagree | fixed - `get_emu_page` returns IP_UNKNOWN, matching `checktypeandprint` |
| P1-7 | Q page vs main screen ULTISID split | fixed - same `sbc #$22 / cmp #$02` test; guarded by T44-T46 |
| P1-8 | `cas_d41d7` not address-patched | fixed - added to the `Checkarmsid` patch list |
| P2-1 | `taskkill /IM` killed the user's VICE | fixed in **both** scripts (ci_test.sh did it in 4 places) |
| P2-2 | Fixed port 6502 + flat 30 s sleeps | fixed - ephemeral port + readiness polling from 22 s |
| P2-3 | `release.sh` dirty guard never fired | fixed - whitelist of staged files; refuses when non-interactive |
| P2-5 | Pass count hard-coded in 3 places | fixed - suite reports its own total at `$07E9`; caught 3 dead tests immediately |
| P2-6 | Test suite modelled retired ARM2SID rule | fixed - T07/T08 drive `armsid_major`; fake `$55xx` constants replaced |
| P2-8 | Headers promised slot-relative probing | fixed - corrected to "PRIMARY SID ONLY" |
| P2-9 | Drift guard ignored dead symbols | fixed - `--strict`, wired into `make ci` |
| P2-11 | `arm2sid_populate_sid_list` bounds guard | **fixed** - all 7 slot stores guard on `sidnum_zp >= 8` |
| P3-1 | Dead code / stray artifacts | fixed - unreachable `rts`, `scope_col_lo`, `KBDLOOP_ORIG`, `monlog_out.txt` |
| P4-1/2/3/4 | Doc + comment drift | fixed - counts corrected across 9 files; source header, BackSID protocol, `tlr_sweep` gate rewritten from the code |
| P2-4 | Tool paths duplicated in 3 files | **not done** - wants a `paths.mk` / env decision |
| P2-7 | `txs`/`tsx` register-save with IRQs on | **not done** - ~25 sites, timing-sensitive, no active bug |
| P2-10 | Two divergent screen decoders | **not done** - would change golden text; only the `*` mapping was added (P0-4) |
| P3-2..P3-6 | Comment noise, magic constants, helpers | **not done** - pure cleanup |

**Variant sweep - before and after the P0-1 fix:**

| Stage | Result | Failures |
|---|---|---|
| Pristine `63659cd` (baseline) | 21/30 | 8 systematic (P0-1 / P0-3) + 1 flake |
| After the P1/P2 fixes, before P0-1 | 20-21/30 | same 8 systematic + flakes |
| **After P0-1 option 2 + regenerated goldens** | **28/30** | only `stereo-D500-armsid` and `stereo-D500-swinu` (P0-5) |

The 8 systematic failures were confirmed pre-existing by stashing every change,
rebuilding pristine `63659cd` and re-running: byte-identical failure text. Seven
of the eight are now fixed. The two that remain are the D5xx ARMSID / SwinSID U
naming gap (P0-5) - a chip-protocol question that needs real hardware - and they
now report an honest `8580 FOUND` instead of the wrong `8580 INT`.

Both intermittent cases seen mid-pass have been dealt with: `sidfx` was the
retry star (P0-4, now normalised out of the golden and covered by tests) and
`stereo-DE00-swinu` was the 12-second-poll perturbation (P0-4's sibling, fixed
by raising MIN_WAIT to 22 s).

### Two things the test pass taught me (worth keeping in mind)

**Screen dumps perturb detection.** My first cut of the P2-2 polling change set
`MIN_WAIT = 12 s`, i.e. it dumped the screen while the detection chain was
still running. The `fpgasid8580` case then grew a phantom `DF40 SFX/FM FOUND`
row on all three attempts: a monitor dump pauses the emulated machine, and
`checkfmyam` reads `$DF60` open bus, whose value in VICE is the VIC-II fetch
byte — so a pause/resume changes what it reads. `MIN_WAIT` is now 22 s, past
the end of the chain. **Do not lower it**, and treat "poll the screen to see if
we're ready" as unsafe during any timing-sensitive probe.

**The old CI gate could report green while tests never ran.** When I added
T44-T46, T43's success path still ended in `jmp test_done`, so the three new
tests were skipped entirely. The new pass-vs-total comparison caught it
immediately (`43 / 46`). The previous `EXPECTED_PASS=43` constant would have
compared 43 against 43 and passed — silently, with three tests dead. That is
the concrete payoff of P2-5, and it is worth remembering when adding a test:
**chain the previous test's success `jmp` to the new label.**

### Remaining order

1. **`make hw_test` on the U64** - re-confirm Tuneful Eight still reports 8/8
   after the P0-1 change. `ufs_chk_u64` is designed to keep it byte-identical,
   but only hardware can prove it. This is the one item gating a release.
2. **P0-5** - D5xx ARMSID / SwinSID U naming. Needs the real ARMSID: either the
   proxy does not implement DIS at a secondary base, or the probe needs a
   different sequence there. Not answerable from the emulator.
3. P2-7 (`txs`/`tsx` sweep) as a single commit gated on a full golden run. ~25
   sites in timing-sensitive code with no active bug behind it, so it is
   deliberately last: the downside of getting it wrong exceeds the upside.
4. P2-4 (one source for tool paths), P2-10 (one shared screen decoder),
   P3-2/3/4/5/6 (comment noise, magic constants, `sid_list_append` helper).

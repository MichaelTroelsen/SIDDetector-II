# Handoff — SID Detector II code review + fixes

**Session ended:** 2026-07-30 · **Repo:** `C:\Users\mit\claude\c64server\siddetector2`
**Branch:** `master` · **HEAD:** `99d214d` · **origin/master:** `99d214d` (in sync)
**Working tree:** clean. Everything described here is committed and pushed.
**Baseline this session started from:** `63659cd`

---

<original_task>
Two requests, in order:

1. **"Do a full code review of the whole tool chain and the code and come back
   with a list of suggestions or any other improvement and put them into an MD
   for sonnet or opus to fix."** — i.e. review `siddetector.asm` (the 6502
   source), the test suites, the Makefile, and all the CI / release / harness
   scripts, and write the findings into a Markdown file structured so a later
   session could implement them. The user added: *"before we start implementing
   are there anything else you have discovered during your review or audit? any
   suggested improvements? fable model will soon disappear"* — i.e. capture as
   much as possible now.

2. **"please fix and make sure we test"** — implement the findings and verify
   them. Then, across several follow-ups: `commit and push`, `continue`,
   `go with option 2 for the ULTISID typing`, `do 2`, `do 3`,
   `no hw_test possible. it will take me days to setup`, `go on`.

The review document is `CODE-REVIEW.md` (committed). It is the primary artifact
and is far more detailed than this handoff — **read it first**.
</original_task>

---

<work_completed>

## The deliverable

`CODE-REVIEW.md` (repo root, ~900 lines). Contains every finding with
`file:line`, a fix, a verification step, a per-item status table, the reviewed
golden diff, measurements, and the reasoning behind what was deliberately *not*
done. **This handoff is a summary; that file is the source of truth.**

## Commits (8, all pushed)

| Commit | Summary |
|---|---|
| `2f537af` | **fix:** stop mislabelling `$D4xx-$D7xx` secondary SIDs as U64 UltiSID (P0-1, option 2) |
| `6982bce` | **test:** suite reports its own total; ULTISID + slot-8 guards |
| `83928c7` | **chore:** release guard, scoped VICE kills, doc counts |
| `1b777a6` | **fix:** ARM2SID bounds guard; retry star no longer flakes goldens |
| `02dfd3b` | **docs:** root-cause P0-5 with two probe programs |
| `fd4959c` | **refactor:** stop parking X in the stack pointer across KERNAL PLOT |
| `925e21e` | **chore:** one source for tool paths, one screen decoder, comment cleanup |
| `99d214d` | **docs:** P0-5 fix attempted, measured, reverted — record why |

## Files created

```
CODE-REVIEW.md              the review + status + measurements  <-- READ FIRST
toolpaths.env               single source of truth for tool paths
scripts/toolpaths.py        parses toolpaths.env for Python harnesses
scripts/c64screen.py        shared C64 screen-code decoder
tests/test_hw_snapshot.py   4 tests - hw_test sid_list slot-8 guard
tests/test_variant_render.py 8 tests - golden render / retry-star normalisation
tests/test_c64screen.py     11 tests - decoder + both-harnesses-agree
tests/probe_dis_d500.asm    proves the VICE ARMSID personality answers DIS at D500
tests/probe_dis_d500b.asm   proves the cross-read reads all-zero in isolation
tests/attic/README.md       why 6 retired .mon recipes were moved there
```

## Findings fixed (detail in CODE-REVIEW.md)

**P0-1 — `u64_fingerprint_scan` mislabelled every `$D4xx-$D7xx` secondary as
ULTISID.** The scan ran for any real-SID primary with **no `is_u64` gate** and
stamped ULTISID curve codes (`$20`/`$22`) on every independent slot. Because it
runs *before* the family sweeps, their address dedup locked the wrong answer in.
On a plain C64 an ordinary second 8580, an ARMSID or a SwinSID U all reported as
a U64 UltiSID. Proven with `tri-D500+DE00-plain-8580` (no chip personality at
all): D500 read `8580 INT`, DE00 — outside the scan range — read `8580 FOUND`.

Fixed with the user's chosen **option 2** (discover provisionally, refine later),
which required four coordinated changes because refinement was *impossible* as
written — every add path deduped by address and **skipped** matches:

1. The scan stores the type its own `checkrealsid` measured (`$01`/`$02`/`$F0`)
   plus a new per-slot `sid_prov` flag (9 bytes, in the `$C020` segment).
2. `s_s_dup_lp` (sidstereostart) overwrites the type **in place** when
   `sid_prov` is set; `fll_dup_lp` (fiktivloop) enters the identification path at
   a new `fll_refine` label with `X` already on the existing slot. In-place, not
   append-then-collapse, because appending would need up to 8 extra slots and
   break the 8-SID Tuneful Eight list.
3. `ufs_chk_u64` converts provisional entries to `$20`/`$22` and clears the flags
   when `is_u64` is set (probe **or** the existing `sidnum >= 4` heuristic),
   because on a U64 nothing downstream can refine them — `fiktivloop`'s
   noise-mirror checks reject UltiSID slots, which is why the scan exists.
4. **Two self-comparison bugs fixed, exposed by the above:** once a slot carried
   a real `$01`/`$02` type, both mirror checks began testing the candidate
   *against itself* (driving its own voice 3, reading its own OSC3 → always
   non-zero → rejected itself). `s_s_arm_mir_test` and `fll_mlp` now skip any
   entry at the candidate's own address. Two branches went out of range and
   became long jumps.

**Other fixes** (all with `file:line` in CODE-REVIEW.md):

- **P1-1** IRQ vector installed without SEI in `readkey2` — a genuine crash race
  on every SPACE restart. Now masks interrupts and the CIA before the vector swap.
- **P1-2** `make readresult` read the wrong awk field (`$1` = the literal `al`
  instead of `$2`) and used addresses stale since the tables moved to `$6000`.
- **P1-3** `hw_test.py` read only 8 of 9 `sid_list` slots — the 8th SID of a
  Tuneful Eight was invisible to every stability comparison.
- **P1-4** Deleted 3 dead routines with latent `cmp $07` bugs (zero-page compare
  where `#$07` was meant): `checkanothersid`, `checksecondFPGA`, `checkswinmicro`
  (273 lines, ~364 bytes).
- **P1-5** `jsr s_s_l3` no-ops (jsr to a bare `rts`) that hid fall-through control
  flow — replaced with explicit `jmp`s.
- **P1-6/P1-7** Two classifier inconsistencies (decay page vs info page; Q page
  vs main screen ULTISID split).
- **P1-8** `cas_d41d7` was missing from `Checkarmsid`'s self-mod patch list.
- **P2-1** `taskkill /F /IM x64sc.exe` killed *every* VICE on the machine
  including the user's interactive session — fixed in `ci_test.sh` (4 places) and
  `variant_smoke.py`.
- **P2-2** Fixed monitor port 6502 → ephemeral; flat 30 s sleeps → readiness poll.
- **P2-3** `release.sh`'s dirty-tree guard never fired (`grep -v '^[ M]'` dropped
  all modified *and* staged files). Now whitelists what the release stages, and
  refuses when non-interactive. It immediately surfaced that `docs/MEMORYMAP.md`
  was missing from the staged list — added.
- **P2-4** Tool paths: the review said "3+ files"; it was **17**. One
  `toolpaths.env` now feeds the Makefile (`include`), `ci_test.sh` (`.`) and
  `scripts/toolpaths.py`.
- **P2-5** Pass count was hard-coded in 3 places. The suite now writes its own
  `TEST_TOTAL` to `$07E9` and CI compares the pair.
- **P2-6** Test suite modelled a **retired** ARM2SID rule (`data3=='R'`);
  production branches on `armsid_major`. Also replaced fake `$55xx` "addresses
  from siddetector.sym" (they were unrelated scratch RAM) with real labels.
- **P2-7** `txs`/`tsx` parked X in the **stack pointer** across `jsr $E50C` at 19
  sites, while interrupts were often enabled. Now uses a `plot_x_save` byte.
- **P2-9** `check_memorymap.py --strict` (dead symbols now fail).
- **P2-10** Two divergent screen decoders unified into `scripts/c64screen.py`.
- **P2-11** `arm2sid_populate_sid_list` was the only list writer with no bounds
  guard — all 7 slot stores now guard on `sidnum_zp >= 8`.
- **P0-4** Retry star (`print_retry_star`) made goldens nondeterministic under
  host load. `*` now decodes as `*` and `strip_retry_star()` normalises it out.
- **P3-1/2/3/6** Dead code, 78 duplicated comments, **21 actively wrong** register
  comments, magic `#18` → `INFO_PAGE_MAX` + `.errorif`, 6 dead `.mon` files.
- **P4** Doc drift across 9 files (test counts 35→43→46, sweep 14→30 cases,
  BackSID protocol description that never matched the code).

## Test results at HEAD

| Check | Before | Now |
|---|---|---|
| Unit suite (VICE, `test_suite.asm`) | 43/43 | **46/46** |
| Python host tests | none | **23** (4 + 8 + 11) |
| MEMORYMAP drift | 0, dead symbols ignored | **0 drift, 0 dead symbols** |
| Variant sweep | 21/30 (permanently red) | **28/30** |

The 2 remaining sweep failures are `stereo-D500-armsid` and `stereo-D500-swinu`
(P0-5, below). Both now report an honest `D500 8580 FOUND` instead of the
previously wrong `D500 8580 INT`.

## Goldens

Regenerated **once**, after P0-1 was settled, and reviewed line by line: 8 files
/ 11 lines changed, every change `8580 INT → 8580 FOUND` or `→ ARMSID FOUND`,
with the other 22 goldens byte-identical. `armsid-d420` / `arm2sid-d420` were
regenerated separately after P0-3.
</work_completed>

---

<work_remaining>

## 1. `make hw_test` on the U64 — the one release gate

**Blocked:** user reports the rig takes days to set up.

**Why it matters:** P0-1 changed how `u64_fingerprint_scan` types slots.
`ufs_chk_u64` is *designed* to leave the U64 path byte-identical (it converts
provisional entries back to `$20`/`$22` whenever `is_u64` is set), but that is
design reasoning, not a measurement. It is the only significant claim in this
work resting on reasoning rather than a test result.

**What to check:** Tuneful Eight still reports **8 SIDs** at
`D400 D420 D480 D4A0 D500 D520 D580 D5A0` (the configuration TODO.md records as
verified 3/3 pre-change).

**Command:** `python scripts/hw_test.py --ip 192.168.1.64`
(the Makefile target is `make hw_test`, but see the `make` note in Critical
Context). Note `hw_test.py` now reads 9 slots, so the report will include slot 8
for the first time.

## 2. P0-5 — ARMSID / SwinSID U at `$D5xx-$D7xx` are not identified by name

**Status: FIXED in V1.5.08. Sweep is 30/30.** The rest of this section is the
description from when it was still open — kept because it is what made the fix
possible, and because the hardware confirmation it asks for is still outstanding.

What shipped: the baseline-vs-change described below, with the baseline read
placed **before** the reference oscillator is started, so the instruction
sequence between that start and the first candidate read is byte-for-byte
unchanged. That is the difference from v6/v7 — both of those put the baseline
read *inside* the sample window, which is what moved the reported `$D4xx` mirror.
Measured: `D500 ARMSID FOUND`, `D500 SWINSID ULTIMATE FOUND`,
`tri-D420-armsid+D500-armsid` r18 corrected, other 27 goldens byte-identical, and
no `D460` row in the full sweep or in 24 targeted runs of the six single-SID
cases that reach this code.

**Still to confirm on the rig:** a real FPGASID must still report SID2 at `$D420`
(not `$D460`), and a stereo ARMSID at `$D500` should be named on hardware.

Original write-up follows.

Full write-up in CODE-REVIEW.md under `### P0-5`. Short version:

- The VICE ARMSID personality **does** answer DIS at a secondary base — proven by
  `tests/probe_dis_d500.asm` (`$D51B=$4E 'N'`, `$D51C=$4F 'O'`, `$D51D=$52 'R'`).
  So the `ARMSID FOUND` row expectation is achievable, not aspirational.
- siddetector never reaches the probe: `s_s_arm_chk`'s cross-read rejects the
  candidate first, and then `s_s_arm_mir_test` does. Both compare OSC3 against
  **zero** when the question is "does this SID's oscillator appear here" — and
  OSC3 retains residue after a voice is silenced (measured `A=$AA` and `A=$D8`
  with `X=$18`, i.e. the *first* read, on two different runs).
- Replacing the zero-comparison with baseline-then-look-for-change **works**:
  `D500 ARMSID FOUND`, `D500 SWINSID ULTIMATE FOUND`, plus a third correct
  improvement in `tri-D420-armsid+D500-armsid` r18.
- **Blocker:** it destabilises the `$D4xx` window scan. In single-SID configs
  every `$D4xx` address mirrors `$D400` and which mirror is reported is
  timing-sensitive. `D460 8580 FOUND` appeared 0/0/0 times in the three sweeps
  before the change and once in each of the two after (different case each time:
  `fpgasid6581`, then `pdsid`). A real FPGASID genuinely has SID2 at `$D420`, so
  reporting `$D460` would be **wrong on hardware**.

**Concrete instruction for the next attempt (needs the FPGASID/MixSID rig):**
implement the baseline compare **without changing instruction counts on the
`$D4xx` path** — e.g. baseline unconditionally *before* the silence write so the
same instructions execute either way. A `$D4xx` carve-out is **not** sufficient:
the v7 attempt kept `$D4xx` semantically identical (baseline forced to 0, so
`cmp` behaves exactly like the old `bne`) and the wander still happened, because
the ~20 extra cycles of the baseline read shift which mirror wins.
Then confirm on hardware that FPGASID still reports SID2 at `$D420` **and** a
stereo ARMSID at `$D500` is named.

## 3. Known but not done (no blocker, just judgement)

- **P3-4 — extract a `sid_list_append` helper.** Six near-identical
  "bounds-check, inx, store l/h/t" sequences; would save ~80 bytes. Skipped
  deliberately: those sites are the most delicate code in the program and their
  bounds policy is already uniform since P2-11, so the remaining benefit is
  tidiness against real risk. Reasoning is in CODE-REVIEW.md. Worth doing in a
  session that *starts* with it.
- **16 ad-hoc scripts still call `taskkill /F /IM x64sc.exe`** — the same
  "kills every VICE on the machine" problem fixed under P2-1, but in one-off
  debug tools. Each needs its `Popen` handle threaded to the kill, which is why
  it was not done mechanically. Full list in CODE-REVIEW.md:
  `debug_04aa.py eight_sid_smoke.py main_screen_dump.py midi_debug.py
  pdsid_probe.py q_page_smoke.py tracker_exit_test.py tracker_smoke.py
  tracker_switch_smoke.py tracker_timelapse.py u64_tuneful_eight_test.py
  vice_banner_direct.py vice_banner_snap.py vice_coldboot_test.py
  vice_diag_space.py vice_restart_test.py`

## Verification to run after ANY change

```bash
# 1. build
java -jar C:/debugger/kickasm/KickAss.jar siddetector.asm -o siddetector.prg
# 2. unit suite in VICE (must print 46 / 46)
bash scripts/ci_test.sh
# 3. host tests (no emulator needed)
python tests/test_hw_snapshot.py && python tests/test_variant_render.py \
  && python tests/test_c64screen.py
# 4. doc-drift guard (regenerate with --fix if code size changed)
python scripts/check_memorymap.py --fix ; python scripts/check_memorymap.py --strict
# 5. full golden sweep - REQUIRED to gate any siddetector.asm change (~15-20 min)
python -u scripts/variant_smoke.py        # expect 28/30
```

For a comment-only change, prove it: compare the `siddetector.prg` md5 before and
after. Several commits this session used that as the verification.
</work_remaining>

---

<attempted_approaches>

## Failed / reverted

**P0-5 baseline-vs-change, two versions — both reverted.** Detailed above and in
CODE-REVIEW.md. v6 applied it everywhere; v7 carved out `$D4xx`. Both fixed the
D500 naming and both introduced the `D420 → D460` wander. Do not simply re-apply;
read the instruction in *Work Remaining §2* first.

**`s_s_arm_chk` settle delay.** Added the same ~1280-cycle delay that
`s_s_arm_mir_wait` uses (for ResID's write batching) on the hypothesis that the
first read caught a stale value. **Measured: does not help** — the residue is
genuine, not write latency. Reverted; a comment at the loop records the negative
result so it is not retried.

**`MIN_WAIT = 12 s` polling in `variant_smoke.py`.** My own regression: dumping
the screen pauses the emulated machine, and pausing *inside* the detection chain
perturbs probes that read open bus. `fpgasid8580` reproducibly grew a phantom
`DF40 SFX/FM FOUND` row on all three attempts, because `checkfmyam` reads `$DF60`
whose value in VICE is the VIC-II fetch byte. **`MIN_WAIT` is now 22 s — do not
lower it.**

**KickAssembler cannot forward-reference a label-derived `.const`.** Tried
`INFO_PAGE_COUNT = info_page_hi_end - info_page_hi` and using it earlier in the
file: `Error: Reference to not yet defined symbol`. Solution: declare the
constant in the top equates block and add an `.errorif` beside the table that
fails the build if they disagree (positive-controlled).

**Branch-range failures.** Four separate `relative address is illegal (jump
distance is too far)` errors while editing `sidstereostart`. Any insertion into
`s_s_arm_mir_lp`'s body pushes its loop-back and entry branches out of ±127.
Fix pattern: invert the condition and use a `jmp`.

## Dead ends worth not repeating

- **VICE monitor reads of SID registers disagree with CPU reads.** At the same
  breakpoint the monitor reported `$D51B = $00` while the CPU had just read
  `$D8` — the monitor peeks I/O without clocking ResID. This nearly sent the
  P0-5 investigation down a wrong path. **Debug SID reads by having the 6502
  record them** (the `tests/probe_*.asm` convention), never with monitor `m`.
- Reasoning about which VICE slot owns an unmapped `$D4xx`/`$D5xx` address was
  unproductive; writing a probe program that records the actual reads settled it
  in one run.

## Considered but not pursued

- Restoring the `is_u64` gate on `u64_fingerprint_scan` (the naive P0-1 fix) —
  would regress the hardware-verified Tuneful Eight detection. The user chose
  option 2 instead.
- Appending a refined duplicate for `dedupe_sid_list` to collapse (the documented
  `$11` TLR pattern) — rejected because it needs up to 8 extra slots and would
  break the 8-SID list. In-place refinement chosen instead.
</attempted_approaches>

---

<critical_context>

## Environment

- **`make` is available as of 2026-07-31.** It was previously missing entirely,
  which is why the earlier session ran the scripts the Makefile wraps and
  hand-expanded the recipes. Fixed by installing GNU Make 4.4.1 into the MSYS2
  tree that was already on the machine for the VICE build
  (`C:/msys64/usr/bin/pacman.exe -S --noconfirm --needed make`, no admin
  required) and appending `C:\msys64\usr\bin` to the **user** `PATH`. Verified:
  `make clean`, `make all`, `make ci` (46/46 + MEMORYMAP drift check). This also
  unblocks `scripts/release.sh`, whose stages 2 and 5 call bare `make`.
  *(A new shell must be opened for the PATH change to take effect.)*
- Java and Python 3.14 are present. KickAssembler at
  `C:/debugger/kickasm/KickAss.jar`; patched VICE at
  `C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe`.
  **Both now come from `toolpaths.env` — change them there, nowhere else.**
- Repo is **public**: https://github.com/MichaelTroelsen/SIDDetector-II
- Direct-to-`master` is this project's convention (`release.sh` requires master
  and pushes it), which is why commits went there rather than to a branch.
- `TOKENSAVE_DISABLE_GREP_HOOK=1` is needed to use `grep` in Bash here; a hook
  otherwise redirects symbol-like patterns to the tokensave MCP tools.

## Non-obvious behaviours discovered

- **OSC3 retains residue.** A silenced SID voice does *not* read 0 at `+$1B`.
  This invalidates the premise of both mirror tests and is the root of P0-5.
- **Screen dumps perturb detection** (see MIN_WAIT above).
- **The monitor lies about SID registers** (see above).
- **Which `$D4xx` mirror gets reported is timing-sensitive** in single-SID
  configs — a ~20-cycle change moved it from `$D420` to `$D460`.
- **`calcandloop`'s `txs`/`tsx` is safe and must stay**: it tail-calls out via
  `jmp funny_print` and never returns, so its SP clobber cannot hurt anyone.
  `readkey2`'s `ldx #$FF / txs` is a real SP reset, also kept. Only the 19
  print-dispatch sites were converted. *(There is a memory on this:
  `calcandloop-txs-tail-call-trick`.)*
- **The old CI gate could report green while tests never ran.** Adding T44-T46
  left T43's success path jumping to `test_done`, skipping them; the new
  pass-vs-total comparison caught it as `43 / 46` instantly. **When adding a
  test, chain the previous test's success `jmp` to the new label.**
- **`.mon` monitor files are not used by CI** — `scripts/vice_monitor.py` drives
  the remote monitor. The Makefile comment claiming otherwise was stale.

## Constraints / policy applied

- Anything that changes detection semantics and cannot be validated here was
  **not shipped** — P0-5 (reverted), and P3-4 (not attempted). Both are
  documented rather than silently skipped.
- Every asm change was gated on the full 30-case golden sweep. Comment-only
  changes were proven by md5-identical binaries.
- Goldens were regenerated **once**, only after the behaviour they capture was
  correct, and the diff was reviewed line by line. Do not run
  `variant_smoke.py --update` casually — the previous maintainer's regeneration
  over a regression is what made the sweep permanently red (P0-2).

## Memory-space notes

Segment map at HEAD (main segment has ~405 bytes of headroom before `$5B00`):

```
$0801-$080a  BASIC stub          $5b00-$5cb4  tlr_sweep / dedupe
$0a00-$0bea  TLR sid-detect2     $6000-$9115  tables + screen + strings
$1800-$2387  Triangle Intro      $9200-$9f9e  tracker view
$2400-$596a  main program        $a000-$b399  Delirious 9
$c020-$c25a  tune sel + ufs + sid_prov        $c300-$c821  Quality page
```

Useful symbols (shift with code size — resolve from `siddetector.vs`, field 2):
`s_s_arm_chk $44C8`, `s_s_arm_mir_test $4520`, `fll_refine $484E`,
`u64_fingerprint_scan $C136`, `ufs_chk_u64 $C220`, `sid_prov $C252`,
`plot_x_save $5939`.
</critical_context>

---

<current_state>

## Deliverables

| Item | Status |
|---|---|
| `CODE-REVIEW.md` | **Complete** — 28 findings, status table, measurements, handoff notes |
| P0-1 ULTISID mislabel | **Fixed** (option 2), emulator-verified. ⚠ wants U64 hw_test |
| P0-2 goldens | **Fixed** — regenerated once, diff reviewed |
| P0-3 variant case addresses | **Fixed** |
| P0-4 retry-star flake | **Fixed** + 8 tests |
| P0-5 D5xx ARMSID naming | **Fixed in V1.5.08** — sweep 30/30. ⚠ wants FPGASID rig to confirm SID2 stays at `$D420` |
| P1-1..P1-8 | **All fixed** |
| P2-1,2,3,4,5,6,7,9,10,11 | **All fixed** |
| P3-1,2,3,6 | **Fixed** |
| P3-4 `sid_list_append` | **Not done, deliberately** |
| U64 `make hw_test` | **Not run** — hardware unavailable (days to set up) |

## Repo state

- `HEAD = 99d214d`, `origin/master = 99d214d`, **0 files dirty**.
- No temporary changes, no workarounds, no stashes left behind.
- `siddetector.prg` is the build of the committed `siddetector.asm` (verified).
- The P0-5 experiment was reverted with `git checkout` and the rebuilt binary
  confirmed byte-identical to `925e21e`.

## Open questions for the user

1. **Is the U64 hw_test worth the days of setup now**, or should it wait for the
   next time that rig is up? It gates a release, not the code.
2. **P0-5:** worth pursuing on the FPGASID/MixSID rig, or accept
   `D500 8580 FOUND` as the answer for a D5xx ARMSID? (It is honest — an ARMSID
   in 8580 mode *is* an 8580 emulation — and matches the documented WONTFIX for
   the SIDFX+ARMSID@D420 case.)
3. **P3-4** and the **16 taskkill scripts** are open cleanups with no blocker.

## Sweep expectation for the next session

`python -u scripts/variant_smoke.py` should report **30/30** as of V1.5.08.
Anything failing is new and should be investigated before making changes. Two
cases are known-flaky under host load: `sidfx` (the retry star — should now be
normalised away) and `stereo-DE00-swinu`. A `D460 8580 FOUND` row in any
single-SID case is the specific regression to watch for when touching either
stereo mirror test — see CODE-REVIEW.md § P0-5.
</current_state>

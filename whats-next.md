# Handoff — SID Detector II code review + fixes

**Refreshed:** 2026-07-31 (post-V1.5.09) · **Repo:** `C:\Users\mit\claude\c64server\siddetector2`
**Branch:** `master` · **HEAD:** `0962f4d` · **origin/master:** `0962f4d` (in sync)
**Latest tag:** `v1.5.09` (`d9bc9b4`) — HEAD is 3 commits ahead, **all tooling and
docs; `siddetector.prg` is unchanged since the tag, so nothing is pending release**
**Working tree:** clean at the time this was written.
**Baseline the review work started from:** `63659cd`

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

`CODE-REVIEW.md` (repo root, ~1085 lines). Contains every finding with
`file:line`, a fix, a verification step, a per-item status table, the reviewed
golden diff, measurements, and the reasoning behind what was deliberately *not*
done. **This handoff is a summary; that file is the source of truth.**

## Commit history (all pushed)

The original review pass (8 commits, `2f537af` … `99d214d`) is described in
`CODE-REVIEW.md`. Since then, in order:

| Commit | Summary |
|---|---|
| `677f534` | **docs:** add `whats-next.md` session handoff |
| `11d0fcb` | **fix:** stop the ad-hoc probe scripts killing every VICE on the machine |
| `27f734d` | **release:** V1.5.06 — ULTISID fix + code review, docs updated |
| `49c01bf` | **docs+goldens:** P0-5 fix — D5xx ARMSID / SwinSID U now named |
| `e82b4e2` | **release:** V1.5.08 ← **tag `v1.5.08` points here** |
| `e666770` | **fix:** release.sh left the variant goldens out of the release |
| `d3946cc` | **fix:** release.sh also left the project docs out of the release |
| `61c350b` | **fix:** release.sh whitelist — add `DOC-AUDIT.md` |
| `e5a9e8a` | **release:** cover the whole `docs/` tree in the release whitelist |
| `0e3d056` | **refactor:** fold the seven duplicated ARM2SID appends into `a2spl_add` (P3-4) |
| `09f80c7` | **docs:** refresh `whats-next.md` to the post-V1.5.08 state |
| `69426eb` | **refactor:** drive both decay classifiers from one table (P3-5) |
| `d9bc9b4` | **release:** V1.5.09 — table-driven classifiers ← **tag `v1.5.09` points here** |
| `eb33279` | **fix:** MEMORYMAP header was the drift guard's blind spot |
| `f7a11a1` | **fix:** release.sh shipped a stale MEMORYMAP every time |
| `0962f4d` | **fix:** stop release.sh asserting a co-author that was not involved ← **HEAD** |

The three commits after the `v1.5.09` tag are tooling and documentation only —
`siddetector.prg` is unchanged since the tag, so there is nothing to release.

## P0-5 — FIXED and shipped in V1.5.08

The long-standing "ARMSID / SwinSID U at `$D5xx-$D7xx` are not identified by
name" finding is closed. Both stereo mirror tests (`s_s_arm_chk` and
`s_s_arm_mir_test`) now **baseline the candidate's OSC3 while nothing is driving
it and look for a *change***, instead of comparing against zero. OSC3 retains
residue after a voice is silenced, so "non-zero" never meant "mirror" — that
false premise was the root cause.

**Why this attempt worked where v6 and v7 were reverted.** The baseline read is
placed **before the reference oscillator is started**, so the instruction
sequence between that start and the first candidate read is byte-for-byte
identical to the old code. That window is what decides which `$D4xx` mirror wins
in a single-SID config; v6 and v7 both put the baseline read *inside* it and both
produced a `D420 → D460` wander.

Measured:

```
stereo-D500-armsid           D500 8580 FOUND  ->  D500 ARMSID FOUND
stereo-D500-swinu            D500 8580 FOUND  ->  D500 SWINSID ULTIMATE FOUND
tri-D420-armsid+D500-armsid  r18 8580 FOUND   ->  r18 D500 ARMSID FOUND
```

Other 27 goldens byte-identical. No `D460 8580 FOUND` row in the full sweep or in
24 targeted runs of the six single-SID cases that reach this code. **Variant
sweep went 28/30 → 30/30.** New byte `osc_base` (`$58F4`, beside `plot_x_save`).

Full write-up: `CODE-REVIEW.md` § `P0-5` → `#### FIXED IN V1.5.08`.

## V1.5.08 released

- Tag `v1.5.08`, pushed to `master`.
- GitHub release *SID Detector II v1.5.08* created with `siddetector.prg`
  attached (49187 bytes, published 2026-07-31).
- **The version went 1.5.06 → 1.5.08, skipping 1.5.07.** A manual version bump
  had already produced 1.5.07 before it was understood that `release.sh` bumps
  the version itself (stage 4, `scripts/bump_version.sh`). The 1.5.07 artefacts
  were stripped before the release; **1.5.07 was never tagged or published** and
  no reference to it remains in the tree (verified by grep).
- Note `release.sh` ends with `rm -f .version`, so **there is no `.version` file
  in a clean tree** — the version of record is the header comment on
  `siddetector.asm:2` and the top row of `docs/debug.md`'s changelog table.

## `make` now exists

Previously **not installed at all**, which is why earlier sessions ran the
scripts the Makefile wraps and hand-expanded the recipes. Fixed 2026-07-31:
GNU Make 4.4.1 installed into the MSYS2 tree that was already on the machine for
the VICE build —

```
C:/msys64/usr/bin/pacman.exe -S --noconfirm --needed make
```

(no admin required) — and `C:\msys64\usr\bin` appended to the **user** `PATH`.
**A new shell is needed to pick the PATH change up.** Verified working:
`make clean`, `make all`, `make ci`. This is what unblocked `scripts/release.sh`,
whose stages 2 and 5 call bare `make clean` / `make all`.

## `scripts/release.sh` whitelist fixed (4 commits)

P2-3 gave `release.sh` a whitelist-based dirty-tree guard that refuses to run in
a non-interactive shell when anything outside the whitelist is dirty. The
whitelist itself was wrong, in two compounding ways:

1. **Entries were exact-match only.** `is_release_path()` now treats an entry
   ending in `/` as a directory prefix and everything else as an exact match.
2. **Things the release must ship were missing.** Added: `tests/variant_goldens/`
   (the goldens *certify* the detection output a release ships — without them a
   fresh clone fails `make ci-full`), `docs/` (replacing four per-file entries),
   `CLAUDE.md`, `CODE-REVIEW.md`, `DOC-AUDIT.md`, `whats-next.md`.

Before the fix the guard would refuse to run at all (non-interactive) whenever
any of these were dirty, *and* — had it run — would have shipped detection
changes without the goldens that certify them.

**Trade-off worth recording:** `docs/` is now a prefix on both the guard *and*
the `git add` list. Anything that lands under `docs/` is therefore staged into a
release commit **silently**, rather than being flagged as an unexpected dirty
path. That is deliberate but it is a loosening.

`whats-next.md` is staged with `git add whats-next.md 2>/dev/null || true` — it
is a per-session artifact and may legitimately not exist at release time.

## P3-4 partly done (`0e3d056`)

`a2spl_add` replaces **seven byte-identical 27-byte append tails** in
`arm2sid_populate_sid_list`. `A` = address low, `Y` = address high, type always
`$05`, no-op when the list is full. Saves **101 bytes**: main segment
`$2400-$598B` → `$2400-$5926` (headroom before `$5B00`: 373 → 474).

The `.prg` is still 49187 bytes — **do not use `.prg` size as the metric**, the
file extent is set by the `$C300` segment, not by main-segment code size.

**The other five sites named in P3-4 were left inline**, and the original
reasoning ("they're delicate") was replaced with a better one: they are
*structurally different*, not merely risky. `CODE-REVIEW.md` tabulates it —
`fll_no_dup`/`fll_refine` reserve the slot before the chip is identified across a
`jsr` that trashes X; `uca_found` stores the address before the type is known;
`s_s_add` takes its address from `sptr_zp` and falls through into the fiktiv-loop
setup instead of returning; `tls_no_append` has its own overflow target and sweep
state. Folding those in means restructuring control flow for roughly 20 bytes.

The real win was not bytes: the P2-11 bounds guard now exists in **one** place in
that routine instead of seven copies.

## P3-5 done (`69426eb`) — both decay classifiers now share one table

`checktypeandprint` (main screen) and `get_emu_page` (info page) were two
hand-written decision trees over the same `(data1,data2,data3)` decay
measurement. They had already drifted once — that was P1-6. Both are now thin
wrappers over `emu_class_tab` + `emu_class_match`, so the drift class is gone
rather than re-synchronised.

The finding assumed a `(field, lo, hi, string/page)` row. The trees turned out to
share a tighter invariant: **every rule is "one field within an inclusive range
AND the *next* field zero"** — `data1`-rules need `data2=0`, `data2`-rules need
`data3=0`, true for all 11 rules in both. So a row names only which pair it uses:
selector, lo, hi, page, string pointer = 6 bytes.

Saves **256 bytes**: `$2400-$5926` → `$2400-$5826`.

Two things a future session must not undo:

- **Row order is load-bearing.** The UNKNOWNSID row (`data1 $01-$02`) and the
  VICE FastSID row (`data1 $02-$04`) overlap at exactly `$02`; first-match-wins
  is what reproduces the old fall-through. Do not sort the table.
  `tests/test_emu_classifier.py` pins that case specifically.
- **`IP_*` and `EMUTAB_*` constants live in the top equates block**, not beside
  the table, because `get_emu_page` is ~4000 lines earlier and KickAssembler
  cannot forward-reference a `.const`. The table carries an `.errorif` on its
  length so a hand-edited row that gains or loses a byte fails the build instead
  of silently shifting every later row.

**The variant sweep is weak evidence for this routine** — the emulator cases
mostly identify real chips through `checkrealsid` and never reach the decay
classifier at all. That is why `tests/test_emu_classifier.py` exists: it parses
`emu_class_tab` out of the asm and checks it against both original trees
(transcribed from the pre-refactor source) **exhaustively**. Both trees compare
`data3` only against `$02` and zero, so `data3 ∈ {$00,$02,other}` covers its whole
behaviour and `data1`/`data2` sweep 0..255 — 196,608 cases, the entire input
space, not a sample. The test was then falsified to prove it is not vacuous
(narrowing a bound, and reordering the table — both caught).

## Test results at HEAD

| Check | Before the review | Now |
|---|---|---|
| Unit suite (VICE, `test_suite.asm`) | 43/43 | **46/46** |
| Python host tests | none | **26** (`test_hw_snapshot` 4 + `test_variant_render` 8 + `test_c64screen` 11 + `test_emu_classifier` 3) |
| MEMORYMAP drift | 0, dead symbols ignored | **0 drift, 0 dead symbols, 0 header** (`--strict`) |
| Variant sweep | 21/30 (permanently red) | **30/30** (30 goldens in `tests/variant_goldens/`) |

## Goldens

Regenerated **once** after P0-1 was settled and reviewed line by line (8 files /
11 lines, every change `8580 INT → 8580 FOUND` or `→ ARMSID FOUND`, other 22
byte-identical); `armsid-d420` / `arm2sid-d420` re-captured separately after
P0-3; three rows re-captured for the P0-5 fix in `49c01bf`.
</work_completed>

---

<work_remaining>

## 1. Nothing is pending release

**V1.5.09 is out** (tag `v1.5.09` at `d9bc9b4`, GitHub release published with
`siddetector.prg` attached). It shipped P3-4, P3-5 and the release-script
whitelist fixes. Unlike v1.5.08, `git rev-parse v1.5.09:siddetector.prg` and
`HEAD:siddetector.prg` are the **same blob** — the published asset is the code on
master.

The three commits after the tag (`eb33279`, `f7a11a1`, `0962f4d`) are tooling and
documentation only. `siddetector.prg` is unchanged since the tag, so there is
nothing to cut a release for.

When there is: `make release MSG="<description>"` (or
`bash scripts/release.sh "<description>"`). Two things that have already cost a
session each —

- It **bumps the version itself**. Do not bump manually first; that is exactly
  what created the skipped-and-discarded 1.5.07.
- Keep `MSG` to **28 characters or fewer**. It becomes the in-app scroller line
  `  Vx.y.zz DESCRIPTION`, which has to fit the C64's 40-column screen.

The whitelist has now been exercised end to end: the V1.5.09 bump dirtied
`docs/CHIPS.md`, `docs/debug.md` and `docs/teststatus.md`, and the `docs/` prefix
staged all three. Stage 1 flagged nothing.

## 2. Hardware confirmation queue — three items, all blocked

All three need `make hw_test` (`python scripts/hw_test.py --ip 192.168.1.64`) on
rigs the user reports take days to set up. None blocks the code; they gate
confidence.

1. **FPGASID must still report SID2 at `$D420`, not `$D460`.** This is the
   specific regression the P0-5 fix *could* cause — it is the exact failure that
   reverted v6 and v7. The emulator evidence is strong (0 wanders in a full sweep
   + 24 targeted runs) but it is still the emulator, and a real FPGASID genuinely
   has SID2 at `$D420`, so a `$D460` report would be wrong on hardware rather
   than cosmetic.
2. **Tuneful Eight must still report 8 SIDs** at
   `D400 D420 D480 D4A0 D500 D520 D580 D5A0` (P0-1; TODO.md records it verified
   3/3 pre-change; **unverified since V1.5.06**). `ufs_chk_u64` is *designed* to
   leave the U64 path byte-identical, but that is design reasoning, not a
   measurement. `hw_test.py` now reads 9 slots (P1-3), so the report will include
   slot 8 for the first time.
3. **The ARM2SID+U64 multi-slot map path from P3-4.** `arm2sid_populate_sid_list`
   only runs with an ARM2SID primary, which the emulator reaches through exactly
   one variant case (`arm2sid-d420`). The multi-slot map path is hardware-only —
   **no emulator case covers it.** The sweep shows the covered path is unbroken,
   not that the uncovered one is.

## 3. Every P0/P1/P2/P3 item in CODE-REVIEW.md is now closed

P3-5 landed in `69426eb`. The per-item status table in `CODE-REVIEW.md` is the
authority; nothing there is left open. What remains below is new work, not
review backlog.

## 4. Available cleanups, no blocker

- **Make `tests/test_suite.asm` link against the production routines.** The suite
  currently verifies **embedded copies** of dispatch logic rather than calling the
  real code. That is what allowed **P2-6** (the suite happily modelled an ARM2SID
  rule production had already retired) and it is why P3-4 got **no unit test at
  all** — a test there would have exercised a transcription of `a2spl_add` rather
  than `a2spl_add` itself, so a before/after extraction of the slot→(lo,hi)
  mapping was done instead. **This is the highest-leverage testing improvement
  available**, and it is a project rather than a session task.

  Note the P3-5 work shows the alternative when a routine is a pure function:
  `tests/test_emu_classifier.py` parses the real table out of `siddetector.asm`
  and proves it exhaustively on the host. That pattern sidesteps the embedded-copy
  problem entirely and is worth reaching for wherever it fits.

### Recently closed, listed so they are not re-reported as open

- ~~`docs/MEMORYMAP.md` header stale~~ — fixed in `eb33279`, and the *guard's
  blind spot* was fixed with it: `check_memorymap.py` now derives the version
  from the `SIDDETECTOR` screen title in `siddetector.asm` and the segment
  extents from the `<Block>` START/END pairs in `siddetector.dbg` (KickAssembler's
  own memory map, rewritten every build). Header drift now fails like address
  drift and `--fix` rewrites it. The build line lists all ten segments, and an
  unrecognised block start is reported as `segment @ $XXXX` rather than dropped.
- ~~`release.sh` shipped a stale MEMORYMAP every release~~ — fixed in `f7a11a1`.
  The bump shifts every symbol after it, and nothing between the bump and the
  commit ever looked; V1.5.09 went out with three rows drifted +3 bytes. Stage 5
  now regenerates the map after the final build, and stage 3 gained
  `make python_tests` plus a `--strict` doc-drift gate. **Do not move that gate
  after stage 4** — an abort post-bump leaves a bumped-but-uncommitted tree and
  re-running would bump twice.
- ~~`release.sh` hardcoded a co-author~~ — fixed in `0962f4d`. The trailer is now
  opt-in via `RELEASE_COAUTHOR='Name <email>'`; unset means no trailer, which is
  the honest outcome for a mechanical bump.

## Verification to run after ANY change

`make` now exists, so the wrapped forms work. The raw script forms are kept
because they are what actually got run during the review pass and they still
work if the PATH change has not been picked up by the current shell.

```bash
# 1. build
make all
#    raw: java -jar C:/debugger/kickasm/KickAss.jar siddetector.asm -o siddetector.prg

# 2+3+4. host tests + unit suite in VICE (must print 46 / 46) + MEMORYMAP drift
make ci
#    raw: python tests/test_hw_snapshot.py && python tests/test_variant_render.py \
#           && python tests/test_c64screen.py && python tests/test_emu_classifier.py
#         bash scripts/ci_test.sh
#         python scripts/check_memorymap.py --strict
#    (if code size changed, run --fix first, then --strict — --fix now also
#     rewrites the MEMORYMAP header, which is derived from siddetector.dbg)

# 5. full golden sweep — REQUIRED to gate any siddetector.asm change (~10-16 min)
make ci-full          # = make ci + the 30-case sweep
#    raw: python -u scripts/variant_smoke.py     # expect 30/30
```

For a comment-only change, prove it: compare the `siddetector.prg` md5 before and
after. Several commits in this work used exactly that as the verification.
</work_remaining>

---

<attempted_approaches>

## Failed / reverted

**P0-5 baseline-vs-change, versions v6 and v7 — both reverted.** v6 applied the
baseline compare everywhere; v7 carved out `$D4xx`. Both fixed the D500 naming
and **both introduced the `D420 → D460` wander** (v6: `fpgasid6581`; v7:
`pdsid` — a different case each time, so a wander rather than a deterministic
break). v7 kept `$D4xx` *semantically* identical (baseline forced to 0, so `cmp`
behaves exactly like the old `bne`) and it still happened: the ~20 extra cycles
of the baseline read shift which mirror wins. **The lesson that made V1.5.08
work: the fix is not about which addresses you change, it is about not adding
cycles between "start the reference oscillator" and "first read of the
candidate".**

**`s_s_arm_chk` settle delay.** Added the same ~1280-cycle delay
`s_s_arm_mir_wait` uses (for ResID's write batching) on the hypothesis that the
first read caught a stale value. **Measured: does not help** — the residue is
genuine, not write latency. Reverted; a comment at the loop records the negative
result so it is not retried.

**`MIN_WAIT = 12 s` polling in `variant_smoke.py`.** A self-inflicted regression:
dumping the screen pauses the emulated machine, and pausing *inside* the
detection chain perturbs probes that read open bus. `fpgasid8580` reproducibly
grew a phantom `DF40 SFX/FM FOUND` row on all three attempts, because
`checkfmyam` reads `$DF60`, whose value in VICE is the VIC-II fetch byte.
**`MIN_WAIT` is now 22 s — do not lower it.**

**KickAssembler cannot forward-reference a label-derived `.const`.** Tried
`INFO_PAGE_COUNT = info_page_hi_end - info_page_hi` used earlier in the file:
`Error: Reference to not yet defined symbol`. Solution: declare the constant in
the top equates block and add an `.errorif` beside the table that fails the build
if they disagree (positive-controlled).

**Branch-range failures.** Repeated `relative address is illegal (jump distance
is too far)` errors while editing `sidstereostart`. Any insertion into
`s_s_arm_mir_lp`'s body pushes its loop-back and entry branches out of ±127. The
P0-5 fix produced two more. Fix pattern: invert the condition and use a `jmp`.

## Dead ends worth not repeating

- **VICE monitor reads of SID registers disagree with CPU reads.** At the same
  breakpoint the monitor reported `$D51B = $00` while the CPU had just read
  `$D8` — the monitor peeks I/O without clocking ResID. This nearly sent the
  P0-5 investigation down a wrong path. **Debug SID reads by having the 6502
  record them** (the `tests/probe_*.asm` convention), never with monitor `m`.
- Reasoning about which VICE slot owns an unmapped `$D4xx`/`$D5xx` address was
  unproductive; writing a probe program that records the actual reads settled it
  in one run.
- **Bumping the version by hand before running `release.sh`** — `release.sh`
  stage 4 bumps it itself. Doing both burns a version number (this is how 1.5.07
  vanished).

## Considered but not pursued

- Restoring the `is_u64` gate on `u64_fingerprint_scan` (the naive P0-1 fix) —
  would regress the hardware-verified Tuneful Eight detection. The user chose
  option 2 instead.
- Appending a refined duplicate for `dedupe_sid_list` to collapse (the documented
  `$11` TLR pattern) — rejected because it needs up to 8 extra slots and would
  break the 8-SID list. In-place refinement chosen instead.
- Folding the five structurally-different `sid_list` append sites into
  `a2spl_add` — see P3-4 above; ~20 bytes for a control-flow restructure in the
  most delicate code in the program.
</attempted_approaches>

---

<critical_context>

## Environment

- **`make` is available as of 2026-07-31** (GNU Make 4.4.1, MSYS2 — see
  Work Completed). *A new shell must be opened for the PATH change to take
  effect;* if `make` is not found, the raw script forms in the verification block
  still work.
- Java and Python are present. KickAssembler at `C:/debugger/kickasm/KickAss.jar`;
  patched VICE at
  `C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe`.
  **Both come from `toolpaths.env` — change them there, nowhere else** (they were
  previously copy-pasted into 17 files and drifted).
- Repo is **public**: https://github.com/MichaelTroelsen/SIDDetector-II
- Direct-to-`master` is this project's convention (`release.sh` requires master
  and pushes it), which is why commits go there rather than to a branch.
- `TOKENSAVE_DISABLE_GREP_HOOK=1` is needed to use `grep` in Bash here; a hook
  otherwise redirects symbol-like patterns to the tokensave MCP tools.

## Non-obvious behaviours discovered

- **OSC3 retains residue.** A silenced SID voice does *not* read 0 at `+$1B`
  (measured `A=$AA` and `A=$D8` on the *first* read, on two different runs). That
  false premise was the root of P0-5. Both mirror tests now baseline-and-compare
  instead.
- **Which `$D4xx` mirror gets reported is timing-sensitive.** In single-SID
  configs every `$D4xx` address mirrors `$D400`, and ~20 extra cycles was measured
  to move the report from `$D420` to `$D460`. **Do not add or move instructions
  between "start the reference oscillator" and "first read of the candidate"** in
  `s_s_arm_chk` / `s_s_arm_mir_test`. A `D460 8580 FOUND` row in any single-SID
  case is the specific regression to watch for.
- **Screen dumps perturb detection** — pausing the machine changes open-bus
  reads. `MIN_WAIT` must stay at 22 s (see above).
- **The VICE monitor lies about SID register reads** — debug with
  `tests/probe_*.asm`, never with monitor `m` (see above).
- **`calcandloop`'s `txs`/`tsx` is safe and must stay**: it tail-calls out via
  `jmp funny_print` and never returns, so its SP clobber cannot hurt anyone.
  `readkey2`'s `ldx #$FF / txs` is a real SP reset, also kept. Only the 19
  print-dispatch sites were converted to `plot_x_save`. *(There is a memory on
  this: `calcandloop-txs-tail-call-trick`.)*
- **The old CI gate could report green while tests never ran.** Adding T44-T46
  left T43's success path jumping to `test_done`, skipping them; the new
  pass-vs-total comparison (P2-5) caught it as `43 / 46` instantly. **When adding
  a test, chain the previous test's success `jmp` to the new label.**
- **`.mon` monitor files are not used by CI** — `scripts/vice_monitor.py` drives
  the remote monitor. The Makefile comment claiming otherwise was stale.
- **`tests/test_suite.asm` verifies embedded *copies* of dispatch logic**, not the
  production routines. A green suite therefore does not prove production agrees
  with it. See Work Remaining §4.

## Constraints / policy applied

- Anything that changes detection semantics and cannot be validated here was not
  shipped until it could be. P0-5 was carried as a documented WONTFIX-for-now
  through two reverts before the timing-preserving version shipped.
- Every asm change was gated on the full 30-case golden sweep. Comment-only
  changes were proven by md5-identical binaries.
- Goldens were regenerated **once**, only after the behaviour they capture was
  correct, and the diff was reviewed line by line. **Do not run
  `variant_smoke.py --update` (or `make update-variant-goldens`) casually** — the
  previous maintainer's regeneration over a regression is what made the sweep
  permanently red (P0-2).

## Memory-space notes

Segment map at HEAD (`0962f4d`). Main segment has **730 bytes of headroom**
before `$5B00` — it was 373 before P3-4, then 474 after it, and P3-5 freed
another 256.

```
$0801-$080a  BASIC stub          $5b00-$5cb4  tlr_sweep / dedupe
$0a00-$0bea  TLR sid-detect2     $6000-$9120  tables + screen + strings
$1800-$2387  Triangle Intro      $9200-$9f9e  tracker view
$2400-$5826  main program        $a000-$b399  Delirious 9
$c020-$c25a  tune sel + ufs + sid_prov        $c300-$c821  Quality page
```

**Do not hand-maintain this map.** Every extent above is now generated into
`docs/MEMORYMAP.md`'s header by `python scripts/check_memorymap.py --fix`, which
reads the `<Block>` START/END pairs out of `siddetector.dbg` (KickAssembler's own
memory map, rewritten on every build). `--strict` fails on header drift, and
`release.sh` regenerates it after the bump. Read the figures from there rather
than trusting this copy.

Useful symbols (shift with code size — **resolve from `siddetector.vs`, field 2**,
these are HEAD values and P3-5 moved most of them):
`s_s_arm_chk $442B`, `s_s_arm_mir_test $4490`, `fll_refine $47D1`,
`emu_class_tab $541B`, `emu_class_match $545D`, `a2spl_add $4C30`,
`a2spl_add_full $4C4A`, `ecm_pri $57F2`, `osc_base $57F4`,
`plot_x_save $57F5`, `u64_fingerprint_scan $C136`, `ufs_chk_u64 $C220`,
`sid_prov $C252`.
</critical_context>

---

<current_state>

## Deliverables

| Item | Status |
|---|---|
| `CODE-REVIEW.md` | **Complete** — findings, per-item status table, measurements, handoff notes |
| P0-1 ULTISID mislabel | **Fixed** (option 2), emulator-verified. ⚠ wants U64 `hw_test` |
| P0-2 goldens | **Fixed** — regenerated once, diff reviewed |
| P0-3 variant case addresses | **Fixed** |
| P0-4 retry-star flake | **Fixed** + 8 tests |
| P0-5 D5xx ARMSID naming | **Fixed, shipped in V1.5.08** — sweep 30/30. ⚠ wants FPGASID rig to confirm SID2 stays at `$D420` |
| P1-1..P1-8 | **All fixed** |
| P2-1..P2-11 | **All fixed** |
| P3-1, P3-2, P3-3, P3-6 | **Fixed** |
| P3-4 `sid_list_append` | **Partly done** — `a2spl_add` covers the 7 identical ARM2SID appends (101 bytes); 5 structurally-different sites stay inline with a documented reason. ⚠ wants ARM2SID/U64 rig |
| P3-5 table-drive `checktypeandprint`/`get_emu_page` | **Done** (`69426eb`, shipped in V1.5.09) — one `emu_class_tab`, 256 bytes, exhaustive host test |
| `release.sh` whitelist | **Fixed** across 4 commits, and **exercised end to end** by the V1.5.09 release |
| `release.sh` MEMORYMAP + co-author | **Fixed** (`f7a11a1`, `0962f4d`) |
| MEMORYMAP header + guard blind spot | **Fixed** (`eb33279`) — header is now generated from `siddetector.dbg` |
| V1.5.09 release | **Done** — tag `v1.5.09`, GitHub release published, asset matches master |
| `make hw_test` (all 3 items) | **Not run** — hardware unavailable |

Every P0/P1/P2/P3 item in `CODE-REVIEW.md` is now closed.

## Repo state

- `HEAD = 0962f4d`, `origin/master = 0962f4d`, in sync, working tree clean.
- Latest tag `v1.5.09` = `d9bc9b4`, 3 commits behind HEAD — all tooling and docs.
- `siddetector.prg` at HEAD **is the same blob as the one attached to the
  v1.5.09 GitHub release**, and is the build of `siddetector.asm` at HEAD.
- One known tag-vs-master difference: the `v1.5.09` tag's
  `docs/MEMORYMAP.md` still carries the 3 drifted rows and the old header that
  `eb33279` corrected afterwards. Documentation only; not worth re-tagging.
- No temporary changes, workarounds or stashes left behind by this work.

## Open questions for the user

1. **Are the three hardware confirmations worth the days of rig setup now**, or
   do they wait for the next time those rigs are up? They gate confidence, not
   the code — but all three now sit in a published build no rig has run.
2. **Is the `docs/` prefix in the release whitelist the right trade-off?** It
   fixed a real problem but means anything under `docs/` is now staged into a
   release commit silently, so scratch files there would ship.
3. **Is the `tests/test_suite.asm` embedded-copy rework worth starting?** It is
   the highest-leverage testing improvement left and the root cause of P2-6, but
   it is a project, not a session task.

## Sweep expectation for the next session

`make ci-full` (or `python -u scripts/variant_smoke.py`) should report **30/30**
as of V1.5.09. Anything failing is new and should be investigated *before* making
changes. Two cases have been flaky under host load historically: `sidfx` (the
retry star — now normalised away by `strip_retry_star()`) and
`stereo-DE00-swinu` (fixed by raising `MIN_WAIT` to 22 s). A `D460 8580 FOUND`
row in any single-SID case is the specific regression to watch for when touching
either stereo mirror test — see `CODE-REVIEW.md` § P0-5.
</current_state>

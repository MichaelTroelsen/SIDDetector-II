# Documentation Audit — siddetector2 (SIDDetector-II)

**Audited:** 2026-07-18 · **Commit:** `9530211` · **Branch:** `master`
**Working tree:** clean — findings are reproducible from `9530211`.
**Repo:** https://github.com/MichaelTroelsen/SIDDetector-II (PUBLIC)
**Findings:** 1 P2 · 1 P3 — both HIGH confidence
**Verdict:** the documentation is in good condition. This is a short report because there was
little to find, not because the audit was shallow. Coverage is listed under *Verified clean*.

> Context worth stating up front: the most recent commit is
> `9530211 docs: full audit pass — reconcile all docs to V1.5.05` (2026-05-28). A manual
> reconciliation pass had already been done. This audit largely confirms it held, and found one
> number it missed.

---

## Scope

17 markdown files, 347 KB. **All 17 read in full — no tiering.** The file count is below the
~20-file threshold; the byte total is above the ~150 KB guideline, so reading was verified to have
reached the end of each file rather than assumed.

Also inspected as ground truth: `siddetector.asm` (the 8,000-line main source), `Makefile`,
`tests/*.asm` (31 files), `scripts/` (28 files), `patches/`.

**Not audited:** `org/` (frozen V1.1 originals, deliberately preserved for the
`docs/V1.1_VS_CURRENT.md` comparison), and the contents of `bin/*.prg` (binaries).

---

## Ground truth

Established by execution and source inspection **before** reading prose.

| Fact | Actual | Source |
|---|---|---|
| Version | **1.5.05** | `siddetector.asm:2` |
| Main binary | **49,184 bytes** | `ls -l siddetector.prg` |
| Unit tests in `test_suite.asm` | **43** | `rg -c 'inc pass_count'` |
| Tests in `test_arith.asm` | 4 | same |
| Tests in `test_dispatch.asm` | 8 | same |
| `sid_code_to_slot` table | **17 bytes** | `siddetector.asm:8334`, counted |
| Probe programs | 28 | `ls tests/probe_*.asm` |
| Doc-drift guard | **0 drift** | `python scripts/check_memorymap.py` → exit 0 |
| Secrets | none | `rg` + positive control |
| LICENSE / CONTRIBUTING | absent | `ls` |

---

## Findings

### P2-1 · `TODO.md` says the unit suite has 35 tests; it has 43

**Location:** `TODO.md:120`

```
### Covered by test suite (tests/test_suite.asm — 35 tests)
```

**Actual:** 43.

**Verification:**
```bash
rg -c 'inc pass_count' tests/test_suite.asm     # 43
```

**Adjudicated — three other locations are correct:**

| Location | Says | Correct? |
|---|---|---|
| `README.md:468` | "Unit suite grown to 43 tests (T36–T43 …)" | yes |
| `docs/MAKE.md:58` | "43 tests across all detection stages … expect `$07E8 == $2B`" | yes — `$2B` = 43 |
| `docs/MAKE.md:61` | "Gate for CI: all 43 tests must pass" | yes |
| `TODO.md:120` | "35 tests" | **no** |

The CI gate encodes 43 in hex (`$2B`), so the build would fail if the real count were 35. `TODO.md`
is the one copy that was not updated when T36–T43 were added — and `README.md:468` records exactly
why they were added: they guard the `sid_type_index` resolver against the Q-page/debug-page mapping
drift that caused the V1.5.04 `$01`/`$02` swap.

**Consequence:** low. Nothing executes this number; a reader comparing `TODO.md`'s coverage list
against the suite would find eight more tests than expected. It is reported because it is a
*measurable* claim with a machine-readable source, and because the eight missing tests are precisely
the anti-drift guards.

**Fix:** update to 43, or drop the count and let the heading name the file.

**Confidence:** HIGH.

---

### P3-1 · Absolute machine path for the patched VICE in two entry-point docs

**Locations:** `README.md:364`, `CLAUDE.md:22`

```
**Patched WinVICE 3.9** at `C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe`
```

`docs/MAKE.md:13` similarly documents `U64IP` defaulting to `192.168.1.64`, an internal address.

**Why this stays P3 rather than escalating:** the drift catalog escalates machine-specific paths to
P1 when a repo is published, has a LICENSE, or invites contributors. This repo is public, but it has
**no LICENSE, no CONTRIBUTING, and no pull-request invitation** — it reads as a personal tool
released as a binary on CSDb, and the class-9 personal-project caveat applies.

More importantly, **the docs already handle it properly.** Both lines point at a build recipe
(`docs/VICE_PROXY_BUILD.md`) and the patch itself, and the patch is really there:

```bash
ls -l patches/vice-sidvariant-v1.patch     # 80,465 bytes
```

So a reader is told what the binary is, why stock VICE will not do (`-sidvariant` is a local patch),
and how to build their own. The absolute path is "where mine lives", not an unstated dependency.

**Fix (optional):** accept an env var (`VICE_SIDVARIANT`) with the current path as the documented
default, matching how `U64IP` is already handled in the Makefile. Nothing is broken today.

**Confidence:** HIGH on the fact; the severity judgement is a reading of project intent.

---

## Verified clean

Reported so coverage can be judged. Each entry names the method, and each check was confirmed to
have produced output rather than silently matching nothing.

- **Version is consistent everywhere.** `siddetector.asm:2` (1.5.05), `README.md:1`,
  `docs/teststatus.md:5` all agree. `docs/debug.md:10-13`'s V1.5.01–V1.5.04 are version-history
  entries describing past states — correct by definition, not drift.
- **The project's own doc-drift guard passes.** `python scripts/check_memorymap.py` →
  `65/106 matched, 0 drift, 41 unresolved`, exit 0. This is `make ci`'s guard against
  `docs/MEMORYMAP.md` going stale, and it is green. Deferring to it rather than re-adjudicating the
  memory map with weaker tools.
- **No exposed secrets.** `rg -n '(token|api[_-]?key|secret|password|bearer)\s*[=:]\s*["\x27][A-Za-z0-9_\-]{16,}'`
  across the repo → 0 matches. **Positive control passed:** the identical pattern matched a
  synthetic `api_key = "abcdefghij0123456789"` in a scratch file, so the pattern is capable of
  matching and the clean result is real.
- **All documented file paths resolve.** 44 backticked path tokens extracted from
  `README.md`, `CLAUDE.md`, `TODO.md` and `docs/*.md`, each tested with `[ -e ]` plus a repo-wide
  `find` fallback. Zero genuinely missing — see *Not findings* for the three that failed a naive
  root-relative test.
- **Binary size claim is exact.** `README.md:468` states 49,184 bytes; `ls -l siddetector.prg` →
  **49184**. Not approximately — exactly.
- **`sid_code_to_slot` is exactly 17 bytes** as `README.md:468` claims. Counted from the definition
  at `siddetector.asm:8334`: `0,1,2,3,4,5,6,7,3,8,9,10,11,12,13,0,14`.
- **The CI test gate is self-consistent.** `docs/MAKE.md:58` documents `$07E8 == $2B`; `$2B` = 43 =
  the real `inc pass_count` total. The documented expectation and the code agree.
- **Scripts named in `docs/MAKE.md` exist.** `scripts/ci_test.sh` and `scripts/check_memorymap.py`
  both present and, in the latter case, executed.
- **No boilerplate placeholders.** `rg` for `YOUR_[A-Z_]+`, `<… here>`, `TODO: (add|fill|describe)`,
  `Lorem ipsum` across all `*.md` → 0 matches.
- **No missing-LICENSE finding.** Unlike some sibling projects, `README.md` makes **no licence
  promise**, so there is no unbacked claim. The absence is a choice, not a defect.

---

## Not findings

Examined and deliberately not reported, because reporting them would punish good practice.

- **`TODO.md` is 84 closed items to 1 open.** That ratio is far past the structural-bloat threshold,
  but the rule exists to catch stale checklists. This is not one: each closed entry carries a real
  post-mortem — version numbers, register values, why an alternative was rejected, hardware
  verification notes. `TODO.md:19` alone documents the SFX/FM-YAM detection across six versions
  including the false-positive that forced `(status & $E0) == 0` on two reads. **This is a decision
  log.** The one open item (`EMUSID (new)`) is genuinely open.
- **Three paths that failed a root-relative test are all fine.**
  `scripts/build_vice.sh` appears at `docs/ARMSID_PROXY_PLAN.md:259` as *"Wire up a
  `scripts/build_vice.sh`…"* — a planned task, not a claim it exists.
  `vice-emu-code-r46118-testprogs-SID/sidcheck/sidcheck.asm` at `TODO.md:34` is a **provenance
  citation** for code lifted from VICE's test programs, not an in-repo path.
  `tests/test_arith.prg` / `test_dispatch.prg` are Makefile build outputs.
- **"Not implemented" statements are hardware facts, not stale gap tables.**
  `docs/SIDregisters.md:195` ("$D41D–$D41F are not implemented on real SID chips") and
  `docs/CHIPS.md:646` ("POTX/POTY … paddles not implemented") describe the *chip*, not the project.
  The inverse check does not apply.
- **`docs/V1.1_VS_CURRENT.md`'s TODO quotes are the point of the document.** It quotes V1.1's
  original TODO comments and annotates each with how the current version resolved it ("implemented
  via UCI", "implemented via…"). A comparison document quoting stale text is doing its job.
- **`docs/UCI.md:130` and `:370`** mark U64 protocol commands as defined-but-unimplemented, with the
  reason stated (JSON parsing is prohibitive in 6502). Honest scope limits.

---

## Unverifiable

Listed rather than dropped, and not counted as findings.

| Claim | Location | Why |
|---|---|---|
| Every chip-detection result (ARMSID/ARM2SID firmware probing, SwinSID, SIDKick-pico, FPGASID, BackSID, ULTISID filter curves…) | `README.md`, `docs/CHIPS.md`, `docs/teststatus.md` | Requires real C64 hardware with each chip physically installed, or the patched VICE. `docs/teststatus.md` is a hardware test log — the correct place for these, and it is version-stamped V1.5.05. Not re-derivable in this session. |
| `docs/teststatus.md` row-level pass/fail states | `docs/teststatus.md` | Same: a record of hardware runs. Auditing it means re-running on hardware. |
| The 43 unit tests actually pass | `docs/MAKE.md:61` | Running them needs KickAssembler + the patched VICE and writes `tests/ci_result.bin` — a side effect this audit does not perform. The **count** is verified; the **pass state** is not. |
| `check_memorymap.py`'s 41 "unresolved" entries | guard output | The guard reports 0 drift among 65 matched, but 41 entries it could not resolve. Whether those represent real gaps is a question for the guard's own maintainer. |

---

## Blind spots

Text search cannot see inside these. The clean secrets scan is a claim about text files only.

- `bin/*.prg` — 12 C64 binaries, plus `siddetector.prg` (49 KB) and `org/*.prg`.
- `patches/vice-sidvariant-v1.patch` — 80 KB of diff text; scanned by the secrets pattern, not read.
- `scripts/__pycache__/` — compiled Python.
- No archives (`.zip`/`.rar`) or PDFs exist in this repo, so the usual archive blind spot does not
  apply here.

---

## Structural observation

**This project already does what the other audited repos needed.** `scripts/check_memorymap.py` is a
doc-drift guard wired into `make ci` — a machine check that `docs/MEMORYMAP.md` still matches the
source. It is the single reason the memory map, the most drift-prone document in an assembly
project, came through clean.

The one finding above is a count in the **one** document not covered by such a guard. That is a
fairly precise demonstration of the argument: the guarded document held, the unguarded number
drifted.

Worth extending the same idea to the test count — `check_memorymap.py` already establishes the
pattern, and `$07E8 == $2B` is already the machine-readable source.

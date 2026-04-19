# SwinSID Nano False Positive on Empty SID Socket — Investigation & Fix

*SID Detector V1.2.32 / Triangle / Funfun*

---

## The Problem

On a C64 with an Ultimate II+ (U2+) cartridge and an **empty SID socket** (no chip installed),
SID Detector V1.2.27 and earlier non-deterministically reported either:

- **SWINSID NANO** (~50% of runs), or
- **USID64** (~20% of runs)

instead of the correct **NOSID** result. Every fresh machine reset could produce a different answer.

---

## How SwinSID Nano Was Previously Detected

The `checkswinsidnano` routine tested whether OSC3 ($D41B) was oscillating:

1. Reset all SID registers.
2. Set voice 3: noise waveform, gate=1, frequency=$FFFF.
3. Wait ~12 ms.
4. Read $D41B eight times in rapid succession; count how many consecutive pairs differ.
5. If count ≥ 3 → SwinSID Nano found.

This works on real SwinSID Nano hardware because its AVR-based oscillator produces a
continuously changing LFSR output that is readable via OSC3.

---

## Why It Produced False Positives

On a C64 with an **empty SID socket**, the SID data lines float. The U2+ cartridge drives
the expansion bus but leaves the SID socket area alone when its virtual SID is disabled.
The floating data bus retains charge from previous bus activity (capacitive "ghost" values).

After the previous test in the detection chain (`checkpalntsc` + `check128`, ~30 ms of
activity), the bus carried a residual value — often around $F0. This value was
**not constant**: stray noise and EMI cause it to flicker, producing 2–5 changes in 8
reads often enough to trigger the SwinSID Nano threshold.

**Key finding via diagnostic probes** (`probe_swinsid7.asm`, `probe_csn_diag.asm`):

| Hardware | cnt_12ms | cnt_62ms |
|---|---|---|
| SwinSID Nano | 2–3 | 4–7 |
| NOSID fresh (post-reset) | 2–3 | 0–1 |
| NOSID warmed (>1 min) | 4–7 | 4–7 |

The critical discriminant is the **temporal profile**: SwinSID Nano's oscillator
*accelerates* as it warms up — changes **increase** from 12 ms to 62 ms. The floating
bus *settles* — changes **decrease** over time.

---

## The Fix — Two-Stage Test with Real-SID Pre-Check (V1.2.32)

The earlier V1.2.28 fix used a Stage 1 "count ≥ 3 → fast-exit" rule. This turned out
to be wrong in two ways:

1. **SwinSID Nano false negative (~40%):** The SwinSID Nano AVR updates at ~44 kHz —
   at `$FFFF` frequency (max LFSR clock rate), roughly 40% of 8-read windows yield all
   7 pairs changed (cnt = 7), because the AVR update period is close to the 7-read window.
   V1.2.28's Stage 1 would fast-exit on cnt ≥ 3, but this allowed cnt = 7 to also pass
   through — which is fine. However the threshold was later tightened incorrectly.

2. **6581 false positive (introduced in V1.2.32 retry logic):** A real 6581 LFSR advances
   every CPU clock at `$FFFF` frequency, giving cnt = 7 almost always. But empirically
   cnt = 6 occurs in ~40% of 8-read windows at ~19-cycle read intervals. With a 3-retry
   loop that only rejects on *all* attempts giving cnt = 7, a real 6581 could pass Stage 1
   ~78% of the time and then pass Stage 2 → false "SwinSID Nano" result.

### Current algorithm (V1.2.32)

**Step 0.25 — Real SID pre-check (before `checkswinsidnano`):**
Run `checkrealsid` early (it only writes to D412/D40F — never D41F). If a real 6581 or
8580 is confirmed, skip `checkswinsidnano` entirely. This cleanly eliminates the 6581
false positive without touching the SwinSID Nano logic.

**Stage 1 — Change-count gate with 3-retry (freq=$FFFF, noise waveform):**
Read D41B 8 times back-to-back; count pairs that differ. Retry up to 3 times.
- All 3 attempts give cnt = 7 → guaranteed real-SID LFSR speed → **reject**
- Any attempt gives cnt < 7 → ambiguous → proceed to Stage 2
- P(all 3 fail for SwinSID Nano) ≈ (0.4)³ ≈ 6% (acceptable false-negative rate)

**Stage 2 — Activity confirmation at 62 ms:**
After +50 ms wait, count changes in 8 more D41B reads. Require cnt ≥ 3.
- Filters out a fully-dead NOSID bus that slipped through Stage 1.
- SwinSID Nano oscillator remains active → passes.
- Fresh NOSID after reset → settles to near-zero noise → fails.

**Known limitation:** A C64 with Ultimate II+ (virtual SID disabled) generates FPGA-
sourced bus noise at ~44 kHz, indistinguishable from the SwinSID Nano oscillator. Such
a setup is reported as SwinSID Nano. This is an accepted limitation — exhaustive testing
of 10+ discriminants (D41B, D41C, D419/D41A, D41F, freq variation, waveform, interrupt
context, monotone counting, write-to-read-register) all produced overlapping results for
NOSID+U2+ and SwinSID Nano.

---

## uSID64 False Positive Fix

The uSID64 detector was also susceptible. It read $D41F once after writing a 5-byte
config sequence ending with $FF. A floating bus decaying from $FF would produce a
value in the expected $E0–$FE range on the first read.

**Fix (V1.2.27):** Read $D41F **twice** with a ~3 ms gap between reads:
- A real uSID64 holds the register value stable (|read2 − read1| ≤ $02).
- A decaying floating bus drifts by more than $02 between reads.

---

## Investigation: Can U2+ or U64 Be Detected?

As a side investigation, we probed whether the Ultimate II+ cartridge or Ultimate 64
could be identified from C64 code — useful for skipping FPGA-unfriendly tests, or
testing their SID emulation capabilities specifically.

### Ultimate II+ (cartridge)

The U2+ maps its I/O area at $DE00–$DFFF (I/O1/I/O2) when active features are enabled.
The Universal Command Interface (UCI) registers live at $DF1C–$DF1F.

**Finding:** With virtual SID disabled and UCI disabled in the U2+ menu, the entire
$DE00–$DFFF area is **open bus** — completely floating. Multiple DMA reads of the same
addresses returned different random values each time. There is no stable fingerprint
byte that a C64 program can reliably probe.

**Practical conclusion:**
- U2+ with virtual SID **enabled** → detected as **FPGASID** (already works).
- U2+ with virtual SID **disabled** → invisible; siddetector correctly reports **NOSID**.

No new detection code is needed or possible.

### Ultimate 64 (not tested — no hardware available)

The U64 board exposes a debug register at $D7FF (on standard C64 this address mirrors
a SID register or returns open bus). The `c64u` tool exposes `machine debug-reg` for
U64; attempting this command on U2+ returns HTTP 404. Testing would require access to
U64 hardware.

---

## Lessons Learned

**Open bus is not constant.** A floating SID socket does not produce a fixed value —
it produces a value that *decays* from recent bus activity, with noise on top. Tests
that rely on a single read threshold are inherently fragile on empty sockets.

**Temporal profiling is robust.** Rather than asking "is this value changing?", ask
"is the change *rate* increasing or decreasing over time?" Different hardware types
have characteristic temporal signatures that are hard to accidentally replicate.

**The 6510 I/O port ($0001) is not a scratch register.** During debugging, accidentally
using `sty $01` as a temporary store wrote a value that cleared the CHAREN bit,
remapping $D000–$DFFF from I/O to character ROM. All subsequent SID reads silently
returned ROM data. Always use $A0/$A1 or above for zero-page scratch in C64 code.

---

*Tested on: PAL C64C, Ultimate II+L cartridge (virtual SID disabled), SwinSID Nano,
uSID64. SID Detector source: https://github.com/[your-repo]*

---

# SIDFX D420 (LFT) Secondary Slot — Detection Limits

*SID Detector V1.3.83–V1.3.84*

---

## Background

SIDFX is a cartridge that adds a second SID socket to the C64. The SW1 switch selects the
secondary address: CTR=D500, LFT=D420, RGT=DE00. The cartridge exposes SIDFX-reported chip
type via D41E, but the actual chip model must be probed separately for replacement chips.

At D500–D7FF, the secondary probes (DIS echo, SIDKick Pico config-mode, BackSID unlock,
KungFuSID echo) work normally. At D4xx (LFT=D420), the secondary SID sits in the same
address decode range as the primary SID — both are visible on the $D4xx bus simultaneously.

---

## Finding 1: SIDFX Write-Buffer Artifact at D43D–D43F (V1.3.83 — False Fix)

**Probe:** `tests/probe_d41d_holdover.asm`

SIDFX caches writes to unmapped SID registers ($1D–$1F, i.e. addresses D41D/D43D). When
the secondary chip is at D420, writes to D43D ($53 = 'S') are buffered by SIDFX. A
subsequent read of D43D returns $53 regardless of what chip is in the LFT slot.

**Measurement:**
- Write $B5 to D43D → write $00 to D438 (mapped reg, not cached) → read D43D → returns $B5
- Confirmed: SIDFX holds the unmapped reg value; the mapped-reg write does not flush it

**Consequence:** V1.3.83 attempted to detect SIDKick Pico at D420 by writing 'S'/$53 to
D41D and reading it back. This was detecting SIDFX's own write-buffer, not the chip.
The probe was removed in V1.3.84. **WONTFIX** — no chip-specific discriminant available
via this mechanism.

---

## Finding 2: Primary ARMSID Bus Contamination of D43B (V1.3.84)

**Probes:** `tests/probe_armsid_d420.asm`, `tests/probe_dis_d420_discrim.asm`

**Setup:** ARMSID@D400 (primary, CS1), real 6581@D420 (secondary, CS2 via MixSID/SIDFX).

ARMSID monitors the address bus CS-agnostically — it sees ALL writes to D4xx regardless
of CS pin state. Writing the DIS sequence ('D'/$44→D43F, 'I'/$49→D43E, 'S'/$53→D43D)
to CS2 addresses is also detected by the primary ARMSID.

After a valid DIS trigger, ARMSID drives $4E ('N') onto the data bus for all D4xx read
cycles — not only D41B. Because D43B is also in the $D4xx address space on the same
shared data bus, reads of D43B return $4E (contaminated) even though the secondary chip
(6581) returns its own OSC3 value.

**Key measurements:**
- Full CS2 DIS (D43F/D43E/D43D) → D43B = $4E (ARMSID contamination)
- Partial DIS ('S' only to D43D, no D/I) → D43B = $00 (full sequence required, no trigger)
- Full CS1 DIS (D41F/D41E/D41D) → D43B = $4E (also contaminates via CS1-triggered echo)
- D41B after CS1 DIS → $4E (confirmed primary ARMSID response)

Adding `lda $D41B` before reading D43B does NOT stop ARMSID's bus drive. Only cleanup
writes ($00 to $1D/$1E/$1F) stop the drive. The D41B read was therefore ineffective.

**Fix (V1.3.84):** Guard `sfx_probe_dis_echo` for D420 when primary is ARMSID:
check `sid_list_t,x` (x=1, primary type) for $05; if ARMSID, skip DIS probe and use
SIDFX-reported type. **Note:** `data4=$30` (SIDFX flag) inside `sidfx_populate_sid_list`
— primary type is NOT in `data4`; it is in `sid_list_t,x`.

**Status:** SIDFX+ARMSID@D420 (C44) shows SIDFX-reported type (8580/6581). **WONTFIX.**

---

## Finding 3: ARMSID Firmware Ignores CS2 DIS Sequences (V1.3.84)

**Probe:** `tests/probe_armsid_d420e.asm`

**Setup:** Real 8580@D400 (CS1), ARMSID@D420 (CS2 via MixSID).

When ARMSID is installed in the CS2 (D420) slot, its firmware does NOT respond to DIS
sequences. CS2 DIS writes (D43F/D43E/D43D) produce no echo at D43B or D41B.
CS1 DIS writes (D41F/D41E/D41D) also produce no echo via CS2 — the 8580 primary does
not echo them, and ARMSID at CS2 does not snoop them.

**Measurements (all results $06 = open bus / no drive):**
- D43B after CS2 DIS → $06 (no ARMSID response)
- D41B after CS2 DIS → $06 (no CS1 echoed either)
- D43B after CS1 DIS → $06 (ARMSID@CS2 does not snoop CS1)
- D41B after CS1 DIS → $06 (8580 primary does not echo DIS)

**Conclusion:** ARMSID firmware hardcodes DIS detection to CS1 only. There is no
mechanism to detect ARMSID when it occupies the D420 (CS2) slot via SIDFX. **WONTFIX.**

---

## Summary Table

| Config (D400+D420) | DIS probe at D43B | Result | Fix |
|---|---|---|---|
| 6581 + SwinSID U | $4E = 'N' contaminated | Shows 8580 | WONTFIX — 6581 drives D43B (osc3) |
| ARMSID + 6581 | $4E contaminated by primary ARMSID | Shows 8580 | WONTFIX — ARMSID bus drive guard added |
| ARMSID + ARMSID | skipped (ARMSID primary guard) | Shows SIDFX type | WONTFIX — guard prevents false positive |
| 8580 + ARMSID | D43B=$06 (ARMSID@CS2 silent) | Shows SIDFX type | WONTFIX — CS2 ARMSID undetectable |
| 6581/8580 + real SID | D43B=OSC3 (real) | DIS probe safe | Works — SID1 OSC3 ≠ 'S'/'N' |

*Tested on: PAL C64C, SIDFX cartridge, MixSID adapter, ARMSID V2.17, 6581 R4, 8580.*

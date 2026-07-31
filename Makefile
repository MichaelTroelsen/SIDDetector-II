# Tool locations live in ONE place, shared with scripts/ci_test.sh and every
# Python harness via scripts/toolpaths.py.  They were previously copy-pasted
# here, into ci_test.sh and into 15 separate scripts, and they drifted — see
# commit 63659cd, "fix: correct stale Python path in ci_test.sh".
include toolpaths.env

KICKASS   = java -jar $(KICKASS_JAR)
# Patched VICE 3.9 with the -sidvariant personality layer; stock VICE does not
# understand -sidvariant (see docs/ARMSID_PROXY_PLAN.md).
VICE      = $(VICE_X64SC)
U64REMOTE = .\bin\u64remote.exe
U64C64    = .\bin\c64u
U64IP     = 192.168.1.64

SRC       = siddetector.asm
PRG       = siddetector.prg

TEST_SRC       = tests/test_arith.asm
TEST_PRG       = tests/test_arith.prg

TEST_DISP_SRC   = tests/test_dispatch.asm
TEST_DISP_PRG   = tests/test_dispatch.prg

TEST_SUITE_SRC  = tests/test_suite.asm
TEST_SUITE_PRG  = tests/test_suite.prg

.PHONY: all run remote readresult screendump debug test test_dispatch test_suite ci ci-full python_tests hw_test release clean \
	sfx run-none stereo-off \
	run-armsid run-arm2sid run-swinu run-swinnano \
	run-fpgasid8580 run-fpgasid6581 run-pdsid run-kungfusid \
	run-backsid run-usid64 run-sidfx run-skpico8580 run-skpico6581 \
	stereo-armsid stereo-arm2sid stereo-swinu stereo-sidfx stereo-fpgasid \
	run-midi-sequential run-midi-passport run-midi-datel run-midi-namesoft run-midi-maplin \
	test-variants update-variant-goldens

all: $(PRG)

$(PRG): $(SRC)
	$(KICKASS) $(SRC) -o $(PRG)

# =========================================================================
# Run targets — launch siddetector under the patched WinVICE 3.9 with a
# specific SID-chip personality loaded.  See docs/ARMSID_PROXY_PLAN.md.
# Every chip personality is exercised at the primary slot (D400); stereo-*
# targets put a second personality at D420 for MixSID-style scenarios.
# =========================================================================

run: $(PRG)
	$(VICE) -autostart $(PRG)

sfx: $(PRG)
	$(VICE) -autostart $(PRG) -sfxse -sfxsetype 3812

# Plain vanilla 8580 at D400, no stereo, no SFX.  Useful as a regression
# baseline after changes to the patched VICE.
run-none stereo-off: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant none -sidextra 0

# --- single-chip personality at D400 ---
run-armsid: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant armsid    -sidextra 0
run-arm2sid: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant arm2sid   -sidextra 0
run-swinu: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant swinu     -sidextra 0
run-swinnano: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant swinnano  -sidextra 0
run-fpgasid8580: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant fpgasid8580 -sidextra 0
run-fpgasid6581: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant fpgasid6581 -sidextra 0
run-pdsid: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant pdsid     -sidextra 0
run-kungfusid: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant kungfusid-new -sidextra 0
run-backsid: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant backsid   -sidextra 0
run-usid64: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant usid64    -sidextra 0
run-sidfx: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant sidfx     -sidextra 0
run-skpico8580: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant skpico-8580 -sidextra 0
run-skpico6581: $(PRG)
	$(VICE) -autostart $(PRG) -sidvariant skpico-6581 -sidextra 0

# --- MixSID / stereo: 8580 at D400 + personality at D420 ---
# SidStereo=1 + Sid2AddressStart=54304 ($D420), secondary wears the variant.
stereo-armsid: $(PRG)
	$(VICE) -autostart $(PRG) -sidextra 1 -sidvariant2 armsid
stereo-arm2sid: $(PRG)
	$(VICE) -autostart $(PRG) -sidextra 1 -sidvariant2 arm2sid
stereo-swinu: $(PRG)
	$(VICE) -autostart $(PRG) -sidextra 1 -sidvariant2 swinu
stereo-fpgasid: $(PRG)
	$(VICE) -autostart $(PRG) -sidextra 1 -sidvariant2 fpgasid8580
stereo-sidfx: $(PRG)
	$(VICE) -autostart $(PRG) -sidextra 1 -sidvariant2 sidfx

# --- MIDI cartridges (codebase.c64.org/doku.php?id=base:c64_midi_interfaces) ---
# Default 8580 at $D400 + a single MIDI cart (per reference, max 1 attached).
# Detection result lands on row 11 col 25 (the NOSID line).
# Requires VICE built with --enable-midi (see docs/VICE_PROXY_BUILD.md).
run-midi-sequential: $(PRG)
	$(VICE) -autostart $(PRG) -midi -miditype 0
run-midi-passport: $(PRG)
	$(VICE) -autostart $(PRG) -midi -miditype 1
run-midi-datel: $(PRG)
	$(VICE) -autostart $(PRG) -midi -miditype 2
run-midi-namesoft: $(PRG)
	$(VICE) -autostart $(PRG) -midi -miditype 3
run-midi-maplin: $(PRG)
	$(VICE) -autostart $(PRG) -midi -miditype 4

# Run the full variant matrix headless and print pass/fail per variant.
test-variants: $(PRG)
	python scripts/variant_smoke.py

remote: $(PRG)
	$(U64REMOTE) $(U64IP) run $(PRG)

# Read detection result from real hardware after `make remote`.
#
# Every non-zero-page address is resolved from siddetector.vs at run time.
# They shift whenever code size changes, so nothing here may be hard-coded —
# the old $2900 / $2918 / $244D literals had been stale for many releases.
#
# .vs line format is:   al C:59ea .backsid_d41f
# so the address lives in field 2 (field 1 is the "al" record type). Reading
# field 1 — as this target used to — yields the literal string "al".
vssym = $$(grep ' \.$(1)$$' siddetector.vs | awk '{print $$2}' | sed 's/C://')

readresult:
	@echo '=== data1 (chip code, $$A4) ==='
	$(U64C64) machine read-mem 00a4
	@echo '=== data2 ($$A5) ==='
	$(U64C64) machine read-mem 00a5
	@echo '=== sidnum_zp (SID count, $$F7) ==='
	$(U64C64) machine read-mem 00f7
	@a=$(call vssym,backsid_d41f); echo "=== backsid_d41f ($$a) ==="; \
	  $(U64C64) machine read-mem $$a
	@a=$(call vssym,sid_list_h);   echo "=== sid_list_h ($$a), 9 slots ==="; \
	  $(U64C64) machine read-mem $$a --length 9
	@a=$(call vssym,sid_list_l);   echo "=== sid_list_l ($$a), 9 slots ==="; \
	  $(U64C64) machine read-mem $$a --length 9
	@a=$(call vssym,sid_list_t);   echo "=== sid_list_t ($$a), 9 slots ==="; \
	  $(U64C64) machine read-mem $$a --length 9

# Dump screen RAM ($0400-$07E7, 1000 bytes) from real hardware, decode C64 screen codes,
# print to terminal and save to screen_dump.txt.
screendump:
	./bin/c64u machine read-mem 0400 --length 1000 | python scripts/screendump.py | tee screen_dump.txt
	@echo "Saved screen_dump.txt"

# Run with VICE monitor open and breakpoints at key detection checkpoints.
# When VICE pauses, type 'r' to see registers, 'g' to continue, 'x' to exit monitor.
debug: $(PRG)
	$(VICE) -autostart $(PRG) -moncommands tests/debug.mon

# Build and run unit tests in VICE.
# Screen shows PASS/FAIL for each test case.
# In the VICE monitor (Alt+M): type  mem $0600  to read pass count (04 = all pass).
test: $(TEST_PRG)
	$(VICE) -autostart $(TEST_PRG) -moncommands tests/test.mon

$(TEST_PRG): $(TEST_SRC)
	$(KICKASS) $(TEST_SRC) -o $(TEST_PRG)

# Build and run dispatch logic tests in VICE.
# Tests ARMSID/ARM2SID/FPGASID branch conditions (data1/data2/data3 → chip id).
# In the VICE monitor (Alt+M): type  mem $0600  to read pass count (08 = all pass).
test_dispatch: $(TEST_DISP_PRG)
	$(VICE) -autostart $(TEST_DISP_PRG) -moncommands tests/test_dispatch.mon

$(TEST_DISP_PRG): $(TEST_DISP_SRC)
	$(KICKASS) $(TEST_DISP_SRC) -o $(TEST_DISP_PRG)

# Build and run the full test suite in VICE (43 tests across all detection
# stages, Q-page band lookup and the sid_type_index code->slot resolver).
# In the VICE monitor (Alt+M): type  mem $07E8  to read pass count ($2B=43=all pass).
test_suite: $(TEST_SUITE_PRG)
	$(VICE) -autostart $(TEST_SUITE_PRG) -moncommands tests/test_suite.mon

$(TEST_SUITE_PRG): $(TEST_SUITE_SRC)
	$(KICKASS) $(TEST_SUITE_SRC) -o $(TEST_SUITE_PRG)

# Run tests headlessly in VICE and gate on pass count (all 43 must pass).
# VICE opens briefly with -remotemonitor on a dynamically chosen free port;
# scripts/vice_monitor.py connects, breakpoints td_spin, saves $07E8
# (pass_count) to tests/ci_result.bin, then quits.  No -moncommands file is
# involved; the old tests/ci*.mon recipes are retired in tests/attic/.
ci: python_tests
	bash scripts/ci_test.sh
	@echo ""
	@echo "=== MEMORYMAP.md address-drift check ==="
	@python scripts/check_memorymap.py --strict

# Host-side Python unit tests (no emulator needed, <1 s).
python_tests:
	@echo "=== Python host tests ==="
	@python tests/test_hw_snapshot.py
	@python tests/test_variant_render.py
	@python tests/test_c64screen.py
	@python tests/test_emu_classifier.py

# Full regression: unit tests + variant golden diff.  Use this as the pre-PR
# / pre-release gate.  scripts/variant_smoke.py runs 30 cases; budget ~10-16
# min depending on how many need a retry (plus ~40 s for ci).
ci-full: ci
	@echo ""
	@echo "=== SidVariant golden-diff sweep ==="
	@python scripts/variant_smoke.py

# Re-capture variant goldens after an intentional UI / detection change.
# Commit the updated tests/variant_goldens/*.txt alongside the code change.
update-variant-goldens: $(PRG)
	python scripts/variant_smoke.py --update

# Apply bin/tt8-ultimate.cfg to the live U64, boot siddetector, assert that
# detection finds 8 SIDs and is_u64 is set. Runtime-only (no save-to-flash).
# Override C64U_HOST=ip.ip.ip.ip if not 192.168.1.64.
test-tuneful-eight: $(PRG)
	python scripts/u64_tuneful_eight_test.py

# Run automated hardware smoke test on real C64 via U64.
# Deploys siddetector.prg, presses SPACE x3 (verifies detection stable),
# then enters every screen (I/D/R/T/P/Q) and returns. The Q (Quality
# Fingerprint) step captures the per-slot sidcheck score + $D418 decay
# off real hardware into the run report.
# Without SCENARIO: verifies detection is stable (result matches cold-boot baseline).
# With SCENARIO:    also checks chip types and addresses match the scenario file.
#
# Usage:
#   make hw_test                                          # smoke only
#   make hw_test SCENARIO=fpgasid_stereo                 # named scenario
#   make hw_test SCENARIO=tests/hw/scenarios/custom.cfg  # explicit path
hw_test: $(PRG)
	python scripts/hw_test.py --ip $(U64IP) \
	  $(if $(SCENARIO), --scenario $(if $(findstring /,$(SCENARIO)),$(SCENARIO),tests/hw/scenarios/$(SCENARIO).cfg))

# Full release pipeline: clean → build → ci → bump version → rebuild → git tag + push.
# Usage: make release MSG="Description of changes"
release:
	bash scripts/release.sh "$(MSG)"

clean:
	rm -f $(PRG) $(TEST_PRG) $(TEST_DISP_PRG) $(TEST_SUITE_PRG)

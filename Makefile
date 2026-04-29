KICKASS   = java -jar C:/debugger/kickasm/KickAss.jar
# Patched VICE 3.9 with -sidvariant personality layer (see docs/ARMSID_PROXY_PLAN.md).
# Fall back to the upstream 3.7 install at C:/winvice/bin/x64sc.exe if the
# patched build is not present.
VICE      = C:/Users/mit/claude/c64server/vice-sidvariant/GTK3VICE-3.9-win64/bin/x64sc.exe
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

.PHONY: all run remote readresult screendump debug test test_dispatch test_suite ci ci-full hw_test release clean \
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

# Read detection result from real hardware after make remote.
# data1=$A4 (chip code), backsid_d41f=$244D (echo byte), num_sids=$2900, sid_list_t=$2918
# backsid_d41f address auto-detected from siddetector.vs (changes with code size)
readresult:
	@echo "=== data1 (chip code, $A4) ==="
	$(U64C64) machine read-mem 00a4
	@echo "=== data2 ($A5) ==="
	$(U64C64) machine read-mem 00a5
	@addr=$$(grep ' \.backsid_d41f' siddetector.vs | awk '{print $$1}' | sed 's/C://'); \
	echo "=== backsid_d41f ($$addr) ==="; \
	$(U64C64) machine read-mem $$addr
	@echo "=== num_sids ($2900) + sid_list_t ($2918) ==="
	$(U64C64) machine read-mem 2900
	$(U64C64) machine read-mem 2918

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

# Build and run the full test suite in VICE (23 tests across all detection stages).
# In the VICE monitor (Alt+M): type  mem $0600  to read pass count ($17=23=all pass).
test_suite: $(TEST_SUITE_PRG)
	$(VICE) -autostart $(TEST_SUITE_PRG) -moncommands tests/test_suite.mon

$(TEST_SUITE_PRG): $(TEST_SUITE_SRC)
	$(KICKASS) $(TEST_SUITE_SRC) -o $(TEST_SUITE_PRG)

# Run tests headlessly in VICE and gate on pass count (all 23 must pass).
# VICE opens briefly, runs tests/test_suite.prg with tests/ci.mon, saves
# tests/ci_result.bin (1-byte PRG containing pass_count), then quits.
ci:
	bash scripts/ci_test.sh
	@echo ""
	@echo "=== MEMORYMAP.md address-drift check ==="
	@python scripts/check_memorymap.py

# Full regression: unit tests + variant golden diff.  Use this as the pre-PR
# / pre-release gate.  ~4 min total (30 s unit tests + 14 variant launches).
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
# then enters every screen (I/D/R/T/P) and returns.
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

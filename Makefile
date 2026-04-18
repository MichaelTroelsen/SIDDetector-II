KICKASS   = java -jar C:/debugger/kickasm/KickAss.jar
VICE      = C:/winvice/bin/x64sc.exe
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

.PHONY: all run remote readresult screendump debug test test_dispatch test_suite ci hw_test release clean

all: $(PRG)

$(PRG): $(SRC)
	$(KICKASS) $(SRC) -o $(PRG)

run: $(PRG)
	$(VICE) -autostart $(PRG) -sfxse -sfxsetype 3812

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

# Make Targets

Build, test, and deployment commands for SID Detector.

## Toolchain Paths (defined at top of Makefile)

| Variable    | Value                                 | Purpose                      |
|-------------|---------------------------------------|------------------------------|
| `KICKASS`   | `java -jar C:/debugger/kickasm/KickAss.jar` | KickAssembler (needs Java) |
| `VICE`      | `C:/winvice/bin/x64sc.exe`            | WinVICE C64 emulator         |
| `U64REMOTE` | `.\bin\u64remote.exe`                 | Upload/run PRG over network  |
| `U64C64`    | `.\bin\c64u`                          | Ultimate64 REST-API CLI      |
| `U64IP`     | `192.168.1.64`                        | Ultimate64 IP address        |

## Build

### `make` / `make all`
Assemble `siddetector.asm` → `siddetector.prg` using KickAssembler. Also produces `.sym` and `.vs` (VICE) symbol files.

### `make clean`
Remove all generated PRGs (`siddetector.prg` and the `tests/test_*.prg` files).

## Run

### `make run`
Build, then launch WinVICE with the PRG auto-started. Adds `-sfxse -sfxsetype 3812` so VICE emulates a CBM SFX Sound Expander (YM3812) — exercises the OPL detection path.

### `make remote`
Build, then upload `siddetector.prg` to the Ultimate64 at `$U64IP` via `u64remote run`. The U64 executes it immediately.

### `make debug`
Launch WinVICE with the monitor pre-loaded with breakpoints from `tests/debug.mon`. Use `r` (registers), `g` (go), `x` (exit monitor) inside the VICE monitor.

## Real-Hardware Inspection

### `make readresult`
After `make remote`, dump detection results from real hardware via the U64 REST API:
- `$00A4` — `data1` (primary chip code)
- `$00A5` — `data2`
- `backsid_d41f` — echo byte (address auto-derived from `siddetector.vs`)
- `$2900` — `num_sids` (count of detected SIDs)
- `$2918` — `sid_list_t` (chip-type table)

### `make screendump`
Read 1000 bytes of screen RAM (`$0400-$07E7`) from the U64, decode C64 screen codes to ASCII via `scripts/screendump.py`, print to terminal, and save to `screen_dump.txt`.

## Automated Tests (VICE)

All three VICE-based tests write a pass-count byte at `$0600`. Open the monitor with `Alt+M` and type `mem $0600` to read it.

### `make test`
Build & run `tests/test_arith.prg`. 4 arithmetic tests — expect `$0600 == $04`.

### `make test_dispatch`
Build & run `tests/test_dispatch.prg`. 8 dispatch-logic tests covering ARMSID/ARM2SID/FPGASID branch conditions — expect `$0600 == $08`.

### `make test_suite`
Build & run `tests/test_suite.prg`. 23 tests across all detection stages — expect `$0600 == $17`.

### `make ci`
Run `test_suite` headlessly via `scripts/ci_test.sh`. VICE opens briefly, runs the suite with `tests/ci.mon`, saves the pass count to `tests/ci_result.bin` (1-byte PRG), then quits. Gate for CI: all 23 tests must pass.

## Real-Hardware Smoke Test

### `make hw_test`
Run `scripts/hw_test.py` against the U64. Deploys `siddetector.prg`, then:
- Presses `SPACE` 3× to verify detection remains stable across restarts.
- Enters every screen (`I`, `D`, `R`, `T`, `P`) and returns.
- Verifies the detection result matches the cold-boot baseline.

### `make hw_test SCENARIO=<name>`
Also check that chip types/addresses match a named scenario file:
```
make hw_test SCENARIO=fpgasid_stereo                  # resolves to tests/hw/scenarios/fpgasid_stereo.cfg
make hw_test SCENARIO=tests/hw/scenarios/custom.cfg   # explicit path
```

## Release

### `make release MSG="Description of changes"`
Full release pipeline via `scripts/release.sh`: clean → build → CI → bump version → rebuild → git tag + push.

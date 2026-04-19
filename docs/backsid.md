# BackSID Detection Protocol

Reverse-engineered from `bin/backsid.prg` (BackBit's official BackSID firmware/detection tool).

## Key Registers

BackSID responds to four SID registers in sequence:

| Register | Value  | Purpose               |
|----------|--------|-----------------------|
| `$D41B`  | `$02`  | Slot identifier       |
| `$D41C`  | test   | Echo test value       |
| `$D41D`  | `$B5`  | Unlock key 1          |
| `$D41E`  | `$1D`  | Unlock key 2          |

After the sequence, BackSID echoes the value written to `$D41C` back in `$D41F`.

**`$D41B` is always hardcoded to `$D41B` (D400 slot), regardless of which SID address slot is being scanned.** backsid.prg always writes D41B at D400's address.

## Detection Protocol

1. Write `$D41B = $02` **FIRST** (must precede D41C write)
2. Write `$D41C = test_value` (any non-zero value; backsid.prg uses adaptive values 0/1/2)
3. Write `$D41D = $B5` (unlock key 1)
4. Write `$D41E = $1D` (unlock key 2)
5. **Polling loop**: re-write `$D41B = $02`, wait ~40ms (2 jiffies at 50Hz), read `$D41F`
6. If `$D41F == test_value`: BackSID confirmed
7. Loop for up to ~2.4 seconds (121 jiffies in backsid.prg)

### Why Polling (Not Fixed Delay)

BackSID's ARM processor needs time to process the unlock sequence and set up the echo. This time varies — possibly from a few milliseconds to over a second depending on boot state. backsid.prg polls repeatedly (re-writing D41B=2 on each poll) rather than waiting a fixed time.

**Re-writing D41B on every poll is mandatory** — each D41B write re-arms the echo request for that poll cycle.

### Test Value

backsid.prg uses an adaptive test value: `(D41F_baseline + 1) mod 3`, cycling through 0, 1, 2. This ensures the written value differs from whatever D41F returns at rest. Our implementation uses `$01` (a valid choice if D41F baseline is not `$01`).

## Timing from backsid.prg ($0B17 subroutine)

```
$0B17: STX $D41B          ; write X (=$02) to D41B slot identifier
$0B1A: STA $D41C          ; write A (=test value) to D41C
$0B1D: STA $FF            ; save test value to ZP for comparison
$0B1F: LDA #$B5; STA $D41D
$0B24: LDA #$1D; STA $D41E
$0B28: LDA $A2; ADC #$79  ; target = jiffy + 121 (~2.4s at 50Hz PAL)
; poll loop:
$0B2D: CMP $A2            ; has jiffy timer passed target?
$0B2F: BMI $0B40          ; yes: timeout, BackSID not found
$0B31: JSR $0B07          ; poll: STX $D41B + wait 2 jiffies + LDA $D41F
$0B34: CMP $FF            ; does D41F echo the test value?
$0B36: BNE $0B2D          ; no: loop back
$0B38: JSR $0B07          ; double-confirm: read again
$0B3B: CMP $FF
$0B3D: BNE $0B2D          ; failed confirm: loop back
$0B3F: RTS               ; success: BackSID confirmed
$0B40: PLA; PLA; JMP $0823 ; timeout: BackSID not found (unwinds stack)
```

Subroutine `$0B07` (the poll step):
```
$0B07: STX $D41B          ; re-arm echo (X=$02)
$0B0A: LDA $A2; ADC #$02  ; wait 2 jiffies (~40ms)
$0B0F: CMP $A2; BNE $0B0F ; jiffy wait loop
$0B13: LDA $D41F          ; read echo
$0B16: RTS
```

## Implementation Notes for siddetector2

- **`checkbacksid` is in the second segment** (`* = $2900`) to avoid first-segment overflow from the polling loop code.
- **D41C–D41F are self-modified** at runtime to scan any SID slot address (D400, D500, D600, etc.).
- **D41B is hardcoded to `sta $D41B`** (not self-modified) — matches backsid.prg behavior.
- **15 polls at ~42ms each = ~630ms max wait.** This is shorter than backsid.prg's 2.4s but sufficient since the C64 program takes ~200ms to reach the detection step, giving ~830ms total from boot — well past BackSID's ~360ms initialization time.
- **`backsid_d41f`** stores the last `$D41F` value read (debug variable). Its address changes with code size; check with `grep backsid_d41f siddetector.vs`.
- **Stereo scan**: BackSID is scanned first (before ARMSID, FPGA, etc.) to preserve SID register state. The stereo scan re-uses `checkbacksid` with different `sptr_zp` addresses; D41B stays at $D41B regardless.
- **`backsid_post_fixup`**: called instead of `sidstereo_print` after the stereo scan. If BackSID was found in the stereo scan (not the main chain), it prints "BACKSID FOUND" on row 8 and clears row 11's "NOSID FOUND".

## References

- `bin/backsid.prg` — original BackBit firmware/detection tool (PETSCII title: "IT'S TIME TO GO BACK...")
- `siddetector.asm` — `checkbacksid:` label (second segment), `backsid_post_fixup:` label (second segment)

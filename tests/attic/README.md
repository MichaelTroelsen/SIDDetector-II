# tests/attic — retired VICE monitor scripts

Hand-written `-moncommands` recipes that nothing references any more. They are
kept rather than deleted because each one encodes a working monitor sequence
that took some effort to get right, and they are useful starting points when a
new investigation needs one.

Nothing in the build, CI or docs reads these files. The live ones stayed in
`tests/`:

| Still used | Read by |
|---|---|
| `test.mon` | `make test` |
| `test_dispatch.mon` | `make test_dispatch` |
| `test_suite.mon` | `make test_suite` |
| `debug.mon` | `make debug` |

Why these were retired:

- `ci.mon`, `ci_run.mon`, `ci_debug.mon`, `ci_debug2.mon` — from when `make ci`
  drove VICE with a `-moncommands` file. CI now uses the remote monitor via
  `scripts/vice_monitor.py`, which can set a breakpoint, verify the PC and save
  a byte range under program control. The Makefile comment claiming CI used
  `tests/ci.mon` was stale for a long time.
- `diag.mon`, `screenshot.mon` — one-off diagnostics superseded by the scripts
  in `scripts/` (`vice_diag_space.py`, `take_screenshot.py`).

If you revive one, move it back to `tests/` so it is obvious it is live.

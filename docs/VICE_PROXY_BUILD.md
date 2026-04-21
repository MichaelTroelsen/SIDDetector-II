# Building the patched WinVICE 3.9 with SidVariant proxy

This is the reproducible build recipe for the VICE fork that adds the
`-sidvariant` personality layer used by siddetector's headless detection
tests (see `docs/ARMSID_PROXY_PLAN.md`).

## Prerequisites

- **Windows 10/11 x64**.
- **MSYS2** (https://www.msys2.org) — the upstream-supported Windows build
  environment for VICE.  Visual Studio **cannot** build VICE 3.9 — the
  codebase uses autotools + POSIX conventions.  VS 2022 still works as your
  editor / IDE; MSYS2 is invoked only to run the `make` step.
- **Git Bash** (optional, for the `diff`/`patch` invocations below).

Disk: ~2 GB for MSYS2 + VICE build tree.
Time: ~20 min for a clean build from source.

## 1. Install MSYS2 + build packages

```
winget install --id MSYS2.MSYS2 --silent --accept-package-agreements
```

Then from an MSYS2 shell (e.g. `C:\msys64\mingw64.exe`):

```
pacman -Syu --noconfirm                 # update (may ask to close the shell; re-run once)
pacman -S --noconfirm --needed base-devel pactoys
pacman -S --noconfirm --needed \
    mingw-w64-x86_64-autotools \
    mingw-w64-x86_64-pkgconf \
    mingw-w64-x86_64-gcc \
    mingw-w64-x86_64-ntldd \
    mingw-w64-x86_64-gtk3 \
    mingw-w64-x86_64-glew \
    mingw-w64-x86_64-icoutils \
    mingw-w64-x86_64-xa65 \
    mingw-w64-x86_64-curl \
    mingw-w64-x86_64-iconv \
    mingw-w64-x86_64-docbook-xml \
    mingw-w64-x86_64-docbook-xsl \
    unzip zip p7zip subversion libtool xmlto
```

## 2. Unpack pristine VICE 3.9

```
curl -LO https://sourceforge.net/projects/vice-emu/files/releases/vice-3.9.tar.gz
tar xf vice-3.9.tar.gz
```

## 3. Apply the SidVariant patch

```
cd vice-3.9/
patch -p1 < /path/to/siddetector2/patches/vice-sidvariant-v1.patch
```

The patch touches only `src/sid/` (new files + wiring) and a handful of
lines in `src/arch/gtk3/ui.c` / `actions-joystick.c` (window-title cosmetic).

## 4. Configure + build

```
export MSYSTEM=MINGW64                 # if not launched from the MinGW64 shell
./autogen.sh
./configure --enable-native-gtk3ui \
            --disable-html-docs --disable-pdf-docs \
            --without-pulse --disable-desktop-files
make -j$(nproc)
```

After `make` succeeds the emulator binary is at `src/x64sc.exe` (~21 MB).

## 5. Build a standalone Windows distribution

```
make bindist
```

Produces `GTK3VICE-3.9-win64/` — a self-contained directory with `x64sc.exe`
plus every DLL + data file VICE needs at runtime.  Copy the whole directory
wherever you want; the binary is relocatable within it.

## 6. Point siddetector's Makefile at the patched binary

Edit `siddetector2/Makefile`:

```
VICE = /path/to/GTK3VICE-3.9-win64/bin/x64sc.exe
```

Then `make ci-full` should produce:

```
=== CI: pass count = 32 / 32 ===
PASS: all 32 tests passed.

=== SidVariant golden-diff sweep ===
  PASS  none            r06: ... 8580 FOUND
  PASS  armsid-d420     r17: ... D420 ARMSID FOUND
  ... (14/14 PASS)
```

## Troubleshooting

| Symptom | Remedy |
|---|---|
| `configure: error: iconv is missing` | install `mingw-w64-x86_64-iconv` |
| `autoconf: not found` | verify `/c/msys64/usr/bin` is in PATH (base-devel provides autoconf) |
| `cannot stat 'bin/libxml2-2.dll'` in `make bindist` | harmless — only needed for doc rendering which we disabled |
| `x64sc.exe` starts but no font | the bindist directory must be used as-is (DLLs next to exe) |
| `-sidvariant` rejected | confirm you're running the patched binary (`bindist/bin/x64sc.exe`, not the stock VICE install) |

## What the patch adds in source terms

| File | Lines | Purpose |
|---|---|---|
| `src/sid/sid-variant.h` | ~70 | Public API + enum of variant kinds |
| `src/sid/sid-variant.c` | ~280 | Dispatcher, resource/CLI registration |
| `src/sid/sid-variant-armsid.c` | ~220 | ARMSID / ARM2SID state machine |
| `src/sid/sid-variant-swinsid.c` | ~140 | SwinSID U + SwinSID Nano |
| `src/sid/sid-variant-fpgasid.c` | ~90 | FPGASID 6581 / 8580 |
| `src/sid/sid-variant-pdsid.c` | ~60 | PDsid 'P'/'D'→'S' cookie |
| `src/sid/sid-variant-kungfu.c` | ~90 | KungFuSID old + new firmware |
| `src/sid/sid-variant-backsid.c` | ~110 | BackSID unlock + poll |
| `src/sid/sid-variant-skpico.c` | ~140 | SIDKick-pico config + auto-detect |
| `src/sid/sid-variant-sidfx.c` | ~210 | SIDFX SCI bit-serial + PNP handshake |
| `src/sid/sid-variant-usid64.c` | ~70 | uSID64 5-byte unlock |
| `src/sid/sid.c` | +15 | 2 hook calls in sid_read_chip / sid_store_chip |
| `src/sid/sid-resources.c` | +5 | Register SidVariant string resources |
| `src/sid/sid-cmdline-options.c` | +5 | Register -sidvariant CLI flags |
| `src/sid/Makefile.am` | +10 | Build the new sources |
| `src/arch/gtk3/ui.c` | +15 | Include SidVariant in window title |
| `src/arch/gtk3/actions-joystick.c` | +15 | Same for mouse-grab re-title |

**Total: ~1500 LOC added; ~2000-line patch including context.**
No new external dependencies, no changes outside `src/sid/` and the two Gtk3
title-setter sites.  License: GPLv2+ (inherited from VICE).

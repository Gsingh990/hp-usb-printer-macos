#!/bin/bash
# Build HP's hpcups CUPS raster filter, and HP's PPDs, for macOS.
#
# hpcups is part of HPLIP (HP's Linux driver suite).  It is a self-contained
# CUPS raster filter, so it builds and runs on macOS even though the rest of
# HPLIP does not.  Two parts of the tree are Linux-only and are excluded:
#   dbuscomm.cpp  -- HP's D-Bus/hpmud status channel
# Everything else compiles against the macOS SDK plus one JPEG library.
set -euo pipefail

HPLIP_VERSION="${HPLIP_VERSION:-3.23.12}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build"
SRC="${HPLIP_SRC:-}"

mkdir -p "$OUT"

# --- locate a JPEG library (Homebrew jpeg-turbo or jpeg) --------------------
JPEG=""
for c in jpeg-turbo jpeg; do
  if p="$(brew --prefix "$c" 2>/dev/null)" && [ -f "$p/include/jpeglib.h" ]; then
    JPEG="$p"; break
  fi
done
if [ -z "$JPEG" ]; then
  echo "ERROR: no JPEG library found.  Install one with:  brew install jpeg-turbo" >&2
  exit 1
fi
echo "==> JPEG: $JPEG"

# --- obtain HPLIP source ---------------------------------------------------
if [ -z "$SRC" ]; then
  SRC="$OUT/hplip-$HPLIP_VERSION"
  if [ ! -d "$SRC" ]; then
    TARBALL="$OUT/hplip-$HPLIP_VERSION.tar.gz"
    if [ ! -f "$TARBALL" ]; then
      echo "==> Downloading HPLIP $HPLIP_VERSION source"
      curl -fL --progress-bar \
        "https://downloads.sourceforge.net/project/hplip/hplip/$HPLIP_VERSION/hplip-$HPLIP_VERSION.tar.gz" \
        -o "$TARBALL"
    fi
    echo "==> Extracting"
    tar -xzf "$TARBALL" -C "$OUT"
  fi
fi
[ -d "$SRC/prnt/hpcups" ] || { echo "ERROR: not an HPLIP source tree: $SRC" >&2; exit 1; }
echo "==> HPLIP source: $SRC"

# --- apply local patches --------------------------------------------------
# Small, opt-in changes to hpcups (see patches/*.patch for what and why).
# Each is skipped if it is already applied, so re-running build.sh is safe.
for p in "$HERE"/patches/*.patch; do
  [ -f "$p" ] || continue
  # -f stops patch(1) guessing about reversed hunks, so the dry runs are decisive.
  if patch -d "$SRC" -p1 -N -f --dry-run -s < "$p" >/dev/null 2>&1; then
    echo "==> Applying patch: $(basename "$p")"
    patch -d "$SRC" -p1 -N -f -s < "$p"
  elif patch -d "$SRC" -p1 -R -f --dry-run -s < "$p" >/dev/null 2>&1; then
    echo "==> Patch already applied: $(basename "$p")"
  else
    echo "ERROR: $(basename "$p") does not apply to $SRC" >&2; exit 1
  fi
done

# --- build hpcups ----------------------------------------------------------
SDK="$(xcrun --show-sdk-path)"
SHIM="$HERE/shim"
OBJ="$OUT/obj"
rm -rf "$OBJ"; mkdir -p "$OBJ"

INCS="-I$SRC -I$SRC/prnt/hpcups -I$SHIM -I$JPEG/include -I$SRC/prnt/hpijs"
# HPLIP's configure always passes -DAPDK_LITTLE_ENDIAN on x86/ARM.  Without it
# CommonDefinitions.h, ErnieFilter.h and Mode9.cpp fall back to big-endian
# pixel macros (red is read from the always-zero top byte of a 24-bit pixel),
# and every inkjet page comes out solid black.
DEFS="-DCONFDIR=\"/etc/hp\" -DAPDK_LITTLE_ENDIAN"

echo "==> Compiling hpcups (C sources)"
# jccolor.c and jdatadbf.c are C, not C++.  Compiling them with clang++
# fails: C permits assigning a void* to a function pointer, C++ does not.
for f in "$SRC"/prnt/hpcups/*.c "$SRC/common/utils.c"; do
  cc -O2 -w -isysroot "$SDK" $INCS $DEFS \
     -c "$f" -o "$OBJ/$(basename "${f%.c}").o"
done

echo "==> Compiling hpcups (C++ sources)"
# Several hpcups sources do `#include "utils.h"`, meaning common/utils.h.
# On macOS's case-insensitive filesystem that resolves to prnt/hpcups/Utils.h
# (a different header) first, so getHPLogLevel, IsChromeOs, CUPS_TMP_DIR and
# MAX_FILE_PATH_LEN are never declared.  Force-include the intended header.
for f in "$SRC"/prnt/hpcups/*.cpp "$SHIM/imageprocessor_stub.cpp"; do
  c++ -O2 -w -isysroot "$SDK" $INCS $DEFS \
      -include "$SRC/common/utils.h" \
      -c "$f" -o "$OBJ/$(basename "${f%.cpp}").oxx"
done

echo "==> Linking"
c++ -isysroot "$SDK" -o "$OUT/hpcups" "$OBJ"/*.o "$OBJ"/*.oxx \
    -L"$JPEG/lib" -ljpeg -lcups -lcupsimage -lz

# --- bundle the JPEG library beside the filter -----------------------------
# CUPS runs filters in a sandbox that does not expose /opt/homebrew, so a
# filter linked against a Homebrew dylib fails at run time.  Copy the library
# next to the binary and rewrite the load path to @loader_path.
JPEG_DYLIB="$(otool -L "$OUT/hpcups" | awk '/libjpeg/ {print $1; exit}')"
if [ -n "$JPEG_DYLIB" ] && [ -f "$JPEG_DYLIB" ]; then
  BASE="$(basename "$JPEG_DYLIB")"
  cp -f "$JPEG_DYLIB" "$OUT/$BASE"
  chmod 644 "$OUT/$BASE"
  install_name_tool -change "$JPEG_DYLIB" "@loader_path/$BASE" "$OUT/hpcups"
  echo "==> Bundled $BASE"
fi

# --- generate HP's PPDs ----------------------------------------------------
# macOS ships the CUPS PPD compiler, so no HP tooling is needed.
echo "==> Generating PPDs from hpcups.drv"
# The release tarball only ships hpcups.drv.in; HPLIP's configure normally
# fills in @VERSION@ to produce hpcups.drv.  Do that substitution here so a
# plain, unconfigured tarball works.
DRV="$SRC/prnt/drv/hpcups.drv"
if [ ! -f "$DRV" ]; then
  sed "s/@VERSION@/$HPLIP_VERSION/g" "$SRC/prnt/drv/hpcups.drv.in" > "$OUT/hpcups.drv"
  DRV="$OUT/hpcups.drv"
fi
rm -rf "$OUT/ppd"; mkdir -p "$OUT/ppd"
ppdc -d "$OUT/ppd" "$DRV" 2>/dev/null || true
COUNT=$(find "$OUT/ppd" -name '*.ppd*' | wc -l | tr -d ' ')
[ "$COUNT" -gt 0 ] || { echo "ERROR: ppdc generated no PPDs from $DRV" >&2; exit 1; }

echo
echo "Built: $OUT/hpcups"
otool -L "$OUT/hpcups" | grep -E "jpeg|cups" | sed 's/^/    /'
echo "PPDs generated: $COUNT"

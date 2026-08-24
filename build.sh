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

# --- build hpcups ----------------------------------------------------------
SDK="$(xcrun --show-sdk-path)"
SHIM="$HERE/shim"
OBJ="$OUT/obj"
rm -rf "$OBJ"; mkdir -p "$OBJ"

INCS="-I$SRC -I$SRC/prnt/hpcups -I$SHIM -I$JPEG/include -I$SRC/prnt/hpijs"

echo "==> Compiling hpcups (C sources)"
# jccolor.c and jdatadbf.c are C, not C++.  Compiling them with clang++
# fails: C permits assigning a void* to a function pointer, C++ does not.
for f in "$SRC"/prnt/hpcups/*.c "$SRC/common/utils.c"; do
  cc -O2 -w -isysroot "$SDK" $INCS -DCONFDIR='"/etc/hp"' \
     -c "$f" -o "$OBJ/$(basename "${f%.c}").o"
done

echo "==> Compiling hpcups (C++ sources)"
for f in "$SRC"/prnt/hpcups/*.cpp "$SHIM/imageprocessor_stub.cpp"; do
  c++ -O2 -w -isysroot "$SDK" $INCS -DCONFDIR='"/etc/hp"' \
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
rm -rf "$OUT/ppd"; mkdir -p "$OUT/ppd"
ppdc -d "$OUT/ppd" "$SRC/prnt/drv/hpcups.drv" 2>/dev/null || true
COUNT=$(find "$OUT/ppd" -name '*.ppd*' | wc -l | tr -d ' ')

echo
echo "Built: $OUT/hpcups"
otool -L "$OUT/hpcups" | grep -E "jpeg|cups" | sed 's/^/    /'
echo "PPDs generated: $COUNT"

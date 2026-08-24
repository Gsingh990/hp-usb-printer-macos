#!/bin/bash
# Install HP's hpcups driver as a macOS print queue for a USB-attached HP printer.
#
#   sudo ./install.sh              # auto-detect a single USB HP printer
#   sudo ./install.sh --list       # show detected printers and matching PPDs
#   sudo ./install.sh --device <uri> --ppd <file> [--name <queue>]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build"
FILTER_DIR=/Library/Printers/HP/hpcups
PPD_DIR=/Library/Printers/PPDs/Contents/Resources

DEVICE=""; PPD=""; QUEUE=""; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)   LIST=1; shift ;;
    --device) DEVICE="$2"; shift 2 ;;
    --ppd)    PPD="$2"; shift 2 ;;
    --name)   QUEUE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -x "$OUT/hpcups" ] || { echo "ERROR: $OUT/hpcups not built.  Run ./build.sh first." >&2; exit 1; }
[ -d "$OUT/ppd" ]    || { echo "ERROR: $OUT/ppd missing.  Run ./build.sh first." >&2; exit 1; }

# --- percent-decode a device URI into a readable model name ----------------
model_from_uri() {
  printf '%b' "$(printf '%s' "${1#usb://}" | sed 's/?.*//; s|^[^/]*/||; s/+/ /g; s/%/\\x/g')"
}

# --- map a model name onto one of the generated PPDs -----------------------
ppd_for_model() {
  local norm
  norm="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_-')"
  # exact, then progressively shorter prefixes
  local candidate="$OUT/ppd/hp-$norm.ppd"
  [ -f "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  local try="$norm"
  while [ -n "$try" ]; do
    candidate="$(find "$OUT/ppd" -maxdepth 1 -iname "hp-${try}*.ppd" | sort | head -1)"
    [ -n "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    case "$try" in *_*) try="${try%_*}" ;; *) break ;; esac
  done
  return 1
}

# --- discover USB HP printers ----------------------------------------------
URIS="$(lpinfo -v 2>/dev/null | awk '/^direct usb:/ {print $2}' || true)"
if [ -z "$URIS" ]; then
  echo "ERROR: no USB printer detected.  Is it plugged in and powered on?" >&2
  exit 1
fi

if [ "$LIST" = "1" ]; then
  echo "Detected USB printers:"
  while IFS= read -r u; do
    [ -z "$u" ] && continue
    m="$(model_from_uri "$u")"
    p="$(ppd_for_model "$m" || true)"
    echo "  device : $u"
    echo "  model  : $m"
    echo "  ppd    : ${p:-<no match - pass --ppd explicitly>}"
    echo
  done <<< "$URIS"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0 $*" >&2
  exit 1
fi

if [ -z "$DEVICE" ]; then
  COUNT="$(printf '%s\n' "$URIS" | grep -c . || true)"
  if [ "$COUNT" -ne 1 ]; then
    echo "ERROR: $COUNT USB printers found.  Choose one with --device (see --list)." >&2
    exit 1
  fi
  DEVICE="$URIS"
fi

MODEL="$(model_from_uri "$DEVICE")"
[ -n "$PPD" ] || PPD="$(ppd_for_model "$MODEL" || true)"
if [ -z "$PPD" ] || [ ! -f "$PPD" ]; then
  echo "ERROR: no PPD matched model '$MODEL'." >&2
  echo "       Look in $OUT/ppd and pass one with --ppd." >&2
  exit 1
fi
[ -n "$QUEUE" ] || QUEUE="$(printf '%s' "$MODEL" | tr -cd '[:alnum:]_ -' | tr ' ' '_')"

echo "==> Device : $DEVICE"
echo "==> Model  : $MODEL"
echo "==> PPD    : $(basename "$PPD")"
echo "==> Queue  : $QUEUE"

echo "==> Installing filter to $FILTER_DIR"
install -d -o root -g wheel -m 755 "$FILTER_DIR"
install -o root -g wheel -m 755 "$OUT/hpcups" "$FILTER_DIR/hpcups"
for lib in "$OUT"/*.dylib; do
  [ -f "$lib" ] && install -o root -g wheel -m 644 "$lib" "$FILTER_DIR/$(basename "$lib")"
done

# Point the PPD at the installed filter.  CUPS accepts an absolute path in
# cupsFilter, which is required on macOS because SIP makes the normal
# ServerBin directory (/usr/libexec/cups/filter) read-only.
DEST="$PPD_DIR/$(basename "$PPD")"
echo "==> Installing PPD to $DEST"
install -d -o root -g wheel -m 755 "$PPD_DIR"
sed "s|^\*cupsFilter:.*|*cupsFilter: \"application/vnd.cups-raster 0 $FILTER_DIR/hpcups\"|" \
    "$PPD" > "$DEST"
chown root:wheel "$DEST"; chmod 644 "$DEST"

echo "==> Creating queue"
lpadmin -p "$QUEUE" -v "$DEVICE" -P "$DEST" -o printer-is-shared=false -E
cupsenable "$QUEUE"
cupsaccept "$QUEUE"

echo
echo "Installed.  Queue: $QUEUE"
echo "Make it the default with:  sudo lpadmin -d $QUEUE"

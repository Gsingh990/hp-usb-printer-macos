#!/bin/bash
# Remove a queue created by install.sh, and optionally the shared filter.
set -euo pipefail
QUEUE="${1:-}"
FILTER_DIR=/Library/Printers/HP/hpcups

if [ -z "$QUEUE" ]; then
  echo "Usage: sudo $0 <queue-name> [--purge]"
  echo
  echo "Current queues:"
  lpstat -p 2>/dev/null | awk '/^printer/ {print "  " $2}'
  exit 2
fi
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo $0 $*" >&2; exit 1; }

echo "==> Removing queue $QUEUE"
lpadmin -x "$QUEUE" 2>/dev/null || echo "   (queue not present)"

if [ "${2:-}" = "--purge" ]; then
  echo "==> Removing $FILTER_DIR"
  rm -rf "$FILTER_DIR"
  echo "   PPDs in /Library/Printers/PPDs/Contents/Resources were left in place."
fi
echo "Done."

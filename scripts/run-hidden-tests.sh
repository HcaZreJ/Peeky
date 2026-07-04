#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

UNIT="${1:-}"
if [[ -z "$UNIT" ]]; then
  echo "usage: $(basename "$0") <unit>" >&2
  exit 1
fi

if ! swift build --product PeekyTests >/dev/null 2>/tmp/peeky-hidden-build.log; then
  echo "BUILD ERROR"
  exit 1
fi

OUTPUT="$(.build/debug/PeekyTests --filter "Hidden_${UNIT}" 2>&1 | sed -E $'s/\x1b\\[[0-9;]*m//g')"

TOTAL="$(echo "$OUTPUT" | grep -Eo 'Test run with [0-9]+ tests?' | grep -Eo '[0-9]+' | tail -1)"
PASSED="$(echo "$OUTPUT" | grep -Ec '^✔ Test ".*" passed after')"

if [[ -z "$TOTAL" ]]; then
  echo "PASSED: 0/0"
  exit 1
fi

echo "PASSED: ${PASSED}/${TOTAL}"

if [[ "$PASSED" -eq "$TOTAL" ]]; then
  exit 0
else
  exit 1
fi

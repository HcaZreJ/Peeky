#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

UNIT="${1:-}"
if [[ -z "$UNIT" ]]; then
  echo "usage: $(basename "$0") <unit>" >&2
  exit 1
fi

# swiftbuild 偶发漏传 Testing 的宏插件（见 DEVFLOW「常用命令」下的说明），重跑即过；
# 闸门自己重试，免得把环境抖动读成测试失败。
BUILT=0
for _ in 1 2 3; do
  if swift build --product PeekyTests >/dev/null 2>/tmp/peeky-hidden-build.log; then
    BUILT=1
    break
  fi
done

if [[ "$BUILT" -eq 0 ]]; then
  echo "BUILD ERROR"
  exit 1
fi

# swiftbuild（Swift 6.2 起的默认构建系统）产物落在 .build/out/Products/Debug，
# --build-system native 落在 .build/debug；取两者中实际存在且最新的那个。
BIN=""
for candidate in .build/out/Products/Debug/PeekyTests .build/debug/PeekyTests; do
  if [[ -x "$candidate" ]] && { [[ -z "$BIN" ]] || [[ "$candidate" -nt "$BIN" ]]; }; then
    BIN="$candidate"
  fi
done

if [[ -z "$BIN" ]]; then
  echo "BUILD ERROR"
  exit 1
fi

OUTPUT="$("$BIN" --filter "Hidden_${UNIT}" 2>&1 | sed -E $'s/\x1b\\[[0-9;]*m//g')"

TOTAL="$(echo "$OUTPUT" | grep -Eo 'Test run with [0-9]+ tests?' | grep -Eo '[0-9]+' | tail -1)"
PASSED="$(echo "$OUTPUT" | grep -Ec '^✔ Test ".*" (with [0-9]+ test cases )?passed after')"

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

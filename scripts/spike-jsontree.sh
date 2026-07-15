#!/usr/bin/env bash
# R1 spike: JSONTreeIndex.build 性能/内存验收（.claude/plans/2026-07-03-peek-native.md R1 acceptance）。
# 生成 ~80MB JSON 样本（数组套对象，含字符串/数字/嵌套），编译一个只调用
# JSONTreeIndex.build 并打印耗时的小程序，用 /usr/bin/time -l 采样内存峰值。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SAMPLE_PATH="/tmp/peeky-spike-sample.json"
BIN_PATH="/tmp/peeky-spike"

echo "== 生成 ~80MB JSON 样本 =="
python3 - "$SAMPLE_PATH" << 'PYEOF'
import json
import random
import sys

path = sys.argv[1]
target_bytes = 80 * 1024 * 1024
random.seed(42)

def make_record(i):
    return {
        "id": i,
        "name": f"item-{i}-{'x' * (i % 37)}",
        "score": round(random.uniform(-1000, 1000), 4),
        "active": (i % 3 == 0),
        "tags": [f"tag{j}" for j in range(i % 5)],
        "meta": {
            "nested": {
                "depth3": {
                    "value": i * 7,
                    "note": "some descriptive text " * (1 + i % 4)
                }
            },
            "created": f"2026-01-{1 + (i % 28):02d}T00:00:00Z"
        }
    }

with open(path, "w") as f:
    f.write("[\n")
    written = 2
    i = 0
    first = True
    while written < target_bytes:
        record = make_record(i)
        chunk = json.dumps(record)
        if not first:
            f.write(",\n")
            written += 2
        f.write(chunk)
        written += len(chunk)
        first = False
        i += 1
    f.write("\n]\n")

print(f"generated {i} records")
PYEOF

ls -lh "$SAMPLE_PATH"

echo "== 编译 spike 二进制 (swiftc -O) =="
swiftc -O \
  scripts/spike-jsontree-main.swift \
  Sources/PeekyKit/JSONTreeIndex.swift \
  Sources/PeekyKit/FileKind.swift \
  -o "$BIN_PATH"

echo "== 运行 (/usr/bin/time -l) =="
/usr/bin/time -l "$BIN_PATH" "$SAMPLE_PATH"

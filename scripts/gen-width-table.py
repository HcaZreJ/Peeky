"""从 Unicode 的 EastAsianWidth.txt 生成 Sources/PeekTUI/Screen/EastAsianWidthTable.swift。

表里只收 W（Wide）与 F（Fullwidth）两类区间，合并相邻区间后按起点排序，
终端版据此把这些字符算成 2 列宽。幂等：同一份输入生成同一份输出。

用法：
    curl -o /tmp/EastAsianWidth.txt https://www.unicode.org/Public/16.0.0/ucd/EastAsianWidth.txt
    uv run --no-project python scripts/gen-width-table.py /tmp/EastAsianWidth.txt
"""
import pathlib
import re
import sys

LINE = re.compile(r"^([0-9A-F]{4,6})(?:\.\.([0-9A-F]{4,6}))?\s*;\s*(\w+)")


def wide_ranges(source: str) -> list[tuple[int, int]]:
    ranges = []
    for line in source.splitlines():
        match = LINE.match(line)
        if not match or match.group(3) not in ("W", "F"):
            continue
        start = int(match.group(1), 16)
        end = int(match.group(2) or match.group(1), 16)
        ranges.append((start, end))
    ranges.sort()
    merged: list[tuple[int, int]] = []
    for start, end in ranges:
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def render(version: str, ranges: list[tuple[int, int]]) -> str:
    rows = "\n".join(f"        (0x{start:X}, 0x{end:X})," for start, end in ranges)
    return (
        "// 由 scripts/gen-width-table.py 生成，请勿手改。\n"
        f"// 数据来源：Unicode {version} EastAsianWidth.txt 中 W 与 F 两类，相邻区间已合并。\n\n"
        "enum EastAsianWidthTable {\n"
        "    /// 显示宽度为 2 的码位闭区间，按起点升序。\n"
        "    static let wideRanges: [(start: UInt32, end: UInt32)] = [\n"
        f"{rows}\n"
        "    ]\n"
        "}\n"
    )


def main() -> None:
    source_path = pathlib.Path(sys.argv[1])
    source = source_path.read_text(encoding="utf-8")
    version_match = re.search(r"EastAsianWidth-([\d.]+)\.txt", source)
    version = version_match.group(1) if version_match else "unknown"
    output = pathlib.Path(__file__).resolve().parent.parent / "Sources/PeekTUI/Screen/EastAsianWidthTable.swift"
    ranges = wide_ranges(source)
    output.write_text(render(version, ranges), encoding="utf-8")
    print(f"{len(ranges)} ranges → {output}")


if __name__ == "__main__":
    main()

"""Miniature pretty-printer, purely to showcase syntax highlighting in Peeky."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class Token:
    kind: str
    value: str


class Formatter:
    INDENT = "  "

    def __init__(self, tokens: Iterable[Token], *, colored: bool = True) -> None:
        self._tokens = list(tokens)
        self._colored = colored

    def render(self) -> str:
        depth = 0
        lines: list[str] = []
        for tok in self._tokens:
            if tok.kind == "open":
                lines.append(f"{self.INDENT * depth}{tok.value}")
                depth += 1
            elif tok.kind == "close":
                depth = max(0, depth - 1)
                lines.append(f"{self.INDENT * depth}{tok.value}")
            else:
                lines.append(f"{self.INDENT * depth}{tok.value}")
        return "\n".join(lines)


def demo() -> None:
    tokens = [
        Token("open", "{"),
        Token("value", '"name": "peeky",'),
        Token("value", '"limits": ['),
        Token("value", "  80, 8, 1.5"),
        Token("value", "],"),
        Token("close", "}"),
    ]
    print(Formatter(tokens).render())


if __name__ == "__main__":
    demo()

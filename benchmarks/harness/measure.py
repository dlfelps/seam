"""Extract token usage from a Claude Code JSON session output.

Claude Code, when invoked with `--output-format json`, prints a single JSON object on
stdout. The exact shape has shifted across versions, so this parser is intentionally
forgiving: it walks the structure looking for any `usage` dict and sums the standard
token keys it finds. If multiple usage records appear (e.g., per-turn), they are summed.

Usage:
    python harness/measure.py <path-to-session-json>
    # prints one line: input_tokens output_tokens cache_read cache_creation total
"""
from __future__ import annotations

import json
import sys
from typing import Iterable

TOKEN_KEYS = (
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)


def _iter_usage(node) -> Iterable[dict]:
    if isinstance(node, dict):
        if "usage" in node and isinstance(node["usage"], dict):
            yield node["usage"]
        for v in node.values():
            yield from _iter_usage(v)
    elif isinstance(node, list):
        for item in node:
            yield from _iter_usage(item)


def summarize(payload) -> dict:
    totals = {k: 0 for k in TOKEN_KEYS}
    for usage in _iter_usage(payload):
        for k in TOKEN_KEYS:
            v = usage.get(k)
            if isinstance(v, int):
                totals[k] += v
    totals["total"] = sum(totals.values())
    return totals


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: measure.py <session.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        payload = json.load(f)
    t = summarize(payload)
    print(
        t["input_tokens"],
        t["output_tokens"],
        t["cache_read_input_tokens"],
        t["cache_creation_input_tokens"],
        t["total"],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

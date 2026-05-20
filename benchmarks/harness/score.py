"""Aggregate the benchmark cache into a comparison table.

Usage:
    python harness/score.py .cache/baseline .cache/seam

For each cache directory the script:
  - sums token totals per ordering (and overall) using measure.py
  - reads each step's `status` file to compute step and sequence success rates
  - prints a Markdown summary

Expects the layout produced by harness/run.sh:
    <root>/<NN>-<perm>/<NN>-<feature>/claude.json
    <root>/<NN>-<perm>/<NN>-<feature>/status
Plus, one level up, .cache/base/<mode>.json and .cache/base/<mode>.status for the base build.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from measure import summarize


def load_tokens(json_path: Path) -> int:
    if not json_path.exists():
        return 0
    with open(json_path) as f:
        payload = json.load(f)
    return summarize(payload)["total"]


def load_status(status_path: Path) -> str:
    if not status_path.exists():
        return "missing"
    return status_path.read_text().strip()


def aggregate(mode_dir: Path) -> dict:
    mode = mode_dir.name  # 'baseline' or 'seam'
    base_dir = mode_dir.parent / "base"
    base_tokens = load_tokens(base_dir / f"{mode}.json")
    base_status = load_status(base_dir / f"{mode}.status")

    orderings = []
    for perm_dir in sorted(p for p in mode_dir.iterdir() if p.is_dir()):
        if not perm_dir.name[:2].isdigit():
            continue
        per_step = []
        for step_dir in sorted(s for s in perm_dir.iterdir() if s.is_dir()):
            tokens = load_tokens(step_dir / "claude.json")
            status = load_status(step_dir / "status")
            per_step.append({
                "feature": step_dir.name,
                "tokens": tokens,
                "status": status,
            })
        seq_total_tokens = sum(s["tokens"] for s in per_step)
        seq_pass = (
            len(per_step) == 3
            and all(s["status"] == "pass" for s in per_step)
        )
        orderings.append({
            "name": perm_dir.name,
            "steps": per_step,
            "total_tokens": seq_total_tokens,
            "all_pass": seq_pass,
        })

    step_total = sum(len(o["steps"]) for o in orderings)
    step_pass = sum(1 for o in orderings for s in o["steps"] if s["status"] == "pass")
    seq_total = len(orderings)
    seq_pass = sum(1 for o in orderings if o["all_pass"])

    return {
        "dir": mode_dir.name,
        "base_tokens": base_tokens,
        "base_status": base_status,
        "orderings": orderings,
        "step_success_rate": step_pass / step_total if step_total else 0.0,
        "sequence_success_rate": seq_pass / seq_total if seq_total else 0.0,
        "mean_sequence_tokens": (
            sum(o["total_tokens"] for o in orderings) / seq_total if seq_total else 0
        ),
    }


def render(agg: dict) -> str:
    lines = []
    lines.append(f"### {agg['dir']}")
    lines.append("")
    lines.append(f"- base build: {agg['base_tokens']:,} tokens ({agg['base_status']})")
    lines.append(f"- step success rate: {agg['step_success_rate']:.0%}")
    lines.append(f"- sequence success rate: {agg['sequence_success_rate']:.0%}")
    lines.append(f"- mean tokens per sequence (3 features): {agg['mean_sequence_tokens']:,.0f}")
    lines.append("")
    lines.append("| ordering | tokens | all pass |")
    lines.append("|---|---:|:---:|")
    for o in agg["orderings"]:
        lines.append(f"| {o['name']} | {o['total_tokens']:,} | {'yes' if o['all_pass'] else 'no'} |")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: score.py <mode-cache-dir> [<mode-cache-dir> ...]", file=sys.stderr)
        return 2
    aggs = [aggregate(Path(p)) for p in argv[1:]]
    for a in aggs:
        print(render(a))
    if len(aggs) == 2:
        a, b = aggs
        overhead = b["mean_sequence_tokens"] - a["mean_sequence_tokens"]
        delta_pass = b["sequence_success_rate"] - a["sequence_success_rate"]
        print("### comparison")
        print()
        print(f"- mean token overhead: {overhead:+,.0f} tokens per sequence")
        print(f"- sequence success rate delta: {delta_pass:+.0%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

#!/usr/bin/env python3
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "bench_compare.py"
# ============================================================================
"""Compares two bench_results.json files and reports regressions.

Hosted CI machines are noisy, so by default this only reports. Pass --fail-pct
to turn a regression above that percentage into a non-zero exit code.

Usage:
  python3 scripts/bench_compare.py --baseline benches/baseline.json \
      --current bench_results.json [--warn-pct 25] [--fail-pct 0]
"""
import argparse
import json
import os
import sys
from pathlib import Path


def load(path: Path) -> dict:
    return json.loads(path.read_text())["results"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--current", required=True)
    ap.add_argument("--warn-pct", type=float, default=25.0)
    ap.add_argument("--fail-pct", type=float, default=0.0, help="0 means never fail")
    args = ap.parse_args()

    if not Path(args.baseline).is_file():
        print(f"no baseline at {args.baseline}; nothing to compare against")
        return 0
    base, cur = load(Path(args.baseline)), load(Path(args.current))

    rows, worst = [], 0.0
    for name in sorted(cur):
        if name not in base:
            rows.append((name, None, cur[name]["median_ns"], None, "new"))
            continue
        b, c = base[name]["median_ns"], cur[name]["median_ns"]
        pct = (c - b) / b * 100.0 if b else 0.0
        worst = max(worst, pct)
        flag = "SLOWER" if pct > args.warn_pct else ("faster" if pct < -args.warn_pct else "")
        rows.append((name, b, c, pct, flag))
    for name in sorted(set(base) - set(cur)):
        rows.append((name, base[name]["median_ns"], None, None, "missing"))

    def cell(v):
        return "-" if v is None else f"{v:,.0f} ns"

    lines = ["| benchmark | baseline | current | change | |", "|---|---:|---:|---:|---|"]
    for name, b, c, pct, flag in rows:
        ch = "-" if pct is None else f"{pct:+.1f}%"
        lines.append(f"| `{name}` | {cell(b)} | {cell(c)} | {ch} | {flag} |")
    table = "\n".join(lines)
    print(table)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(f"## Comparison against baseline (warn above {args.warn_pct:.0f}%)\n\n{table}\n")

    if args.fail_pct > 0 and worst > args.fail_pct:
        print(f"\nworst regression {worst:.1f}% is above the {args.fail_pct:.0f}% limit", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

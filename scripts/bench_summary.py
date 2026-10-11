#!/usr/bin/env python3
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "bench_summary.py"
# ============================================================================
"""Collects benchmark results into one JSON file and a markdown table.

Reads criterion output (benches/target/criterion/**/new/) and, optionally, a
text file from the Odin benchmark with lines of the form `BENCH <name> <ns_per_op>`.

Usage:
  python3 scripts/bench_summary.py [--criterion DIR] [--odin FILE] [--out FILE]

The markdown table goes to stdout, and to $GITHUB_STEP_SUMMARY when that is set.
"""
import argparse
import json
import os
import sys
from pathlib import Path


def read_criterion(root: Path) -> dict:
    out = {}
    for est in sorted(root.glob("**/new/estimates.json")):
        meta = est.with_name("benchmark.json")
        if not meta.is_file():
            continue
        name = json.loads(meta.read_text())["full_id"]
        data = json.loads(est.read_text())
        out[f"rust/{name}"] = {
            "median_ns": data["median"]["point_estimate"],
            "mean_ns": data["mean"]["point_estimate"],
        }
    return out


def read_odin(path: Path) -> dict:
    out = {}
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "BENCH":
            out[f"odin/{parts[1]}"] = {"median_ns": float(parts[2]), "mean_ns": float(parts[2])}
    return out


def fmt_ns(ns: float) -> str:
    if ns >= 1e6:
        return f"{ns / 1e6:.2f} ms"
    if ns >= 1e3:
        return f"{ns / 1e3:.2f} us"
    return f"{ns:.1f} ns"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--criterion", default="benches/target/criterion")
    ap.add_argument("--odin", default="")
    ap.add_argument("--out", default="bench_results.json")
    args = ap.parse_args()

    results = {}
    croot = Path(args.criterion)
    if croot.is_dir():
        results.update(read_criterion(croot))
    if args.odin and Path(args.odin).is_file():
        results.update(read_odin(Path(args.odin)))
    if not results:
        print("no benchmark results found", file=sys.stderr)
        return 1

    Path(args.out).write_text(json.dumps({"schema": 1, "results": results}, indent=2, sort_keys=True) + "\n")

    lines = ["| benchmark | median | mean |", "|---|---:|---:|"]
    for name, r in sorted(results.items()):
        lines.append(f"| `{name}` | {fmt_ns(r['median_ns'])} | {fmt_ns(r['mean_ns'])} |")
    table = "\n".join(lines)
    print(table)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("## Benchmarks\n\n" + table + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

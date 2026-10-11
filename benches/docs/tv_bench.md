# tv_bench

## Overview

Criterion benchmarks for `tv_proto` and `tv_sim`. This is a separate Cargo workspace on purpose. Criterion pulls in crates that need a newer toolchain than the Rust 1.75 floor the game crates keep, so isolating it lets `cargo test --workspace` at the repository root keep working on 1.75 with no external dependencies.

The Odin soft-body benchmark lives with the client, see `client/docs/client.md`. `scripts/bench_summary.py` merges both into one result file.

## Modules

### `Cargo.toml`
**What it does:** Standalone workspace root and package. Criterion is declared once under `[workspace.dependencies]`, following the workspace guidelines.

**Decisions:**
- `[lib] bench = false`. The library is empty, and without this flag `cargo bench -- <criterion flags>` also runs libtest on it and fails on the unknown options.
- No `rust-version`. Building here needs a recent stable toolchain. The lockfile is format version 4, which Cargo 1.75 refuses to read, and that was checked directly.

### `lib.rs`
**What it does:** Empty library target so the benches have a package to hang off.

### `proto_bench.rs`
**What it does:** Snapshot encode and decode with 48 balloons, throw command encode and decode, event batch encode and decode, and art encode and decode for blank and noisy canvases.

### `sim_bench.rs`
**What it does:** 60 ticks with 0, 16, and 48 balloons in the air (setup excluded from timing), a full 3600-tick scripted match, 1000 chemistry lookups against tables of 16, 256, and 1024 compounds, and the combined outcome of a four-chamber balloon.

**Decisions:**
- Group names are stable ids. `scripts/bench_compare.py` matches results by id, so renaming a bench breaks comparison against an old baseline.

## CI and Workflows

- `.github/workflows/bench.yml` runs `cargo bench` here, runs the Odin benchmark, and calls `scripts/bench_summary.py` and `scripts/bench_compare.py`. See `docs/BENCHMARKS.md` for how baselines work.

## Fixes and Problems

### `Cargo.toml`
- `cargo bench -- --warm-up-time ...` failed with "Unrecognized option" because libtest ran on the empty library. Fixed with `bench = false` on the `[lib]` target.

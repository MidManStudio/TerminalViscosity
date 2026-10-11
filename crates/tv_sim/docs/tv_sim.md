# tv_sim

## Overview

Deterministic fixed-step simulation core. Commands go in, snapshots and events come out. The crate does no I/O, so the same code can run in a dedicated server, a listen server, or a local session.

Determinism here means: the same seed and the same command stream give the same state on every tick, on the same build. That is what an authoritative server needs. Bit-identical results across different CPUs are not claimed, because the sim uses `f32` arithmetic.

## Modules

### `Cargo.toml`
**What it does:** Package manifest. One dependency, `tv_proto`, by path.

### `lib.rs`
**What it does:** Module list and re-exports of the main types.

### `rng.rs`
**What it does:** `SplitMix64`, a small seedable generator whose state can be read for hashing.

**Decisions:**
- Written in-crate to stay dependency free and to make the state hashable.
- Reserved for chemistry backends. Both `chemistry_core` and `nuclear_core` take seeds, so a backend can draw from `World::rng_mut` and stay inside the determinism check.

**Tests:** unit tests in the file compare the first outputs for two seeds against an independent Python implementation of the published algorithm.

### `chem.rs`
**What it does:** The `ChemBackend` trait, `Outcome`, `NullChem`, and `TableChem`.

**Decisions:**
- The trait is the seam to whatever decides what two compounds do. Adapters over `nuclear_core` and `chemistry_core` will implement it. Those crates are not wired in yet, see `docs/OPEN_DECISIONS.md`.
- `TableChem` is a sorted vector with binary search, not a hash map, so nothing depends on hash iteration order.
- When a pair is listed twice, the later entry wins.

**Benchmarks:** see `benches/benches/sim_bench.rs` (group `chem_lookup_1000_pairs`).

### `balloon.rs`
**What it does:** Recipe validation, dominant compound, and the combined outcome when a balloon bursts.

**Decisions:**
- `MAX_TOTAL_VOLUME_ML = 1000` and the combining rule (largest pair volatility, summed heat) are scaffold placeholders. They exist so the pipeline can be tested end to end, and they are expected to change with the reaction design.
- The dominant compound breaks ties by lowest id, so the answer does not depend on chamber order.

**Benchmarks:** `sim_bench.rs`, bench `impact_outcome_4_chambers`.

### `world.rs`
**What it does:** `World`, the fixed tick, balloon flight, detonation events, snapshots, and `state_hash`.

**Decisions:**
- 60 ticks per second. Semi-implicit Euler integration under constant gravity, and a balloon bursts when it reaches the ground.
- Placeholders until players exist in the sim: spawn position, launch speed per unit of power, the blast radius formula.
- At most 48 balloons in flight, so one snapshot always fits one datagram. Extra throws are counted in `rejected()`.
- `state_hash` is FNV-1a over tick, RNG state, ids, recipes, positions, and velocities. It is the tool for spotting nondeterminism.
- Balloons are kept in creation order and removed with `retain_mut`, so event order is stable.

**Benchmarks:** `sim_bench.rs`, groups `step_60_ticks` and `scripted_match_3600_ticks`.

### `testkit.rs`
**What it does:** Reproducible command scripts and synthetic chemistry for tests, benchmarks, and the server self-test.

**Decisions:** The synthetic table carries no chemical meaning. It exists to exercise lookup cost and the determinism check.

### `world_tests.rs`
**What it does:** Same seed gives the same hash on every tick of a 1200-tick scripted match, different seeds differ, a lobbed balloon lands and bursts exactly once, bad commands are counted, the balloon cap matches the snapshot capacity, and wire units are right.

## CI and Workflows

- `.github/workflows/ci.yml` job `rust` runs these tests on Rust 1.75 and stable. Job `determinism` runs `tv_server selftest` twice in separate processes and compares the output.
- `.github/workflows/bench.yml` runs `benches/benches/sim_bench.rs`.

## Fixes and Problems

### `rng.rs`
- Clippy flagged an unparenthesized multiply-then-shift in `below`. The expression was already correct under Rust precedence rules, and it now has explicit parentheses.

### `world.rs`
- None recorded yet.

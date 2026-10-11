# tv_server

## Overview

Headless server binary. Only a deterministic self-test exists so far. Networking is not implemented, and `tv_server serve` says so and exits with code 2.

## Modules

### `Cargo.toml`
**What it does:** Binary package depending on `tv_proto` and `tv_sim`.

### `main.rs`
**What it does:** `tv_server selftest [--seed N] [--ticks N]` runs a scripted match and prints one line with the final state hash, the detonation count, the rejected-command count, and the balloons still in flight.

**Decisions:**
- The output line is stable on purpose. CI runs the command twice in separate processes and requires identical output, which catches nondeterminism that a single-process test cannot, such as anything that depends on hash seeds or addresses.
- Defaults are seed 1 and 3600 ticks, one simulated minute.

## CI and Workflows

- `.github/workflows/ci.yml` job `determinism` builds this binary in release mode and compares two runs, and also checks that two different seeds give different hashes.

## Fixes and Problems

### `main.rs`
- None recorded yet.

# Benchmarks

## What is measured

| Where | What |
|---|---|
| `benches/benches/proto_bench.rs` | Snapshot, command, event, and art encode and decode |
| `benches/benches/sim_bench.rs` | World stepping with 0, 16, and 40 balloons, a full scripted match, chemistry lookups at three table sizes, combined burst outcome |
| `client/bench/softbody_bench.odin` | Soft-body ring step at 16, 24, 48, and 64 nodes |

Run them locally with `cd benches && cargo bench` and `odin run client/bench -o:speed`.

## Two kinds of limits

Timing on hosted CI machines is noisy, so timing results are reported and compared, not enforced by default.

Sizes are exact, so they are enforced as ordinary tests:
- A full snapshot of 8 players and 40 balloons is 1095 bytes and must stay at or under 1200 (`wire_tests.rs`).
- A batch of 40 events must fit the same budget.
- An encoded art canvas must never exceed 32817 bytes, and a blank one must stay under 200 (`art_tests.rs`).

## Baselines

1. Run the `Benchmarks` workflow on `main`.
2. Download the `bench-results` artifact and take `bench_results.json` out of it.
3. Add it to the repository as `benches/baseline.json`.

From then on every run prints a comparison table. Set the `fail_pct` input, for example to 50, to make a regression above that fail the run. Renaming a benchmark breaks its comparison, because results are matched by id.

## First CI run

The first run of the Benchmarks workflow on a GitHub-hosted runner (commit `479e462`, October 2026). Treat it as a reference point, not a baseline. The art rows from that run measured the old 64 by 64 canvas, so they are left out here, and the group is now `art_256x256`.

Protocol version 2 changed the snapshot to 8 players and 40 balloons, so the first three rows measured the old layout of 48 balloons and no players. Their groups are now `snapshot_full` and `step_60_ticks` at 40, and they need a fresh run before they mean anything again.

| Benchmark | Median |
|---|---:|
| snapshot_48_balloons encode (protocol 1) | 407.6 ns |
| snapshot_48_balloons decode (protocol 1) | 391.9 ns |
| step_60_ticks with 48 balloons (protocol 1) | 10.57 us |
| scripted_match_3600_ticks | 530.28 us |
| chem_lookup_1000_pairs, 1024 compounds | 112.18 us |
| impact_outcome_4_chambers | 146.7 ns |
| softbody_step_24 (Odin) | 4.81 us |

## Fixes and Problems

- None recorded yet.

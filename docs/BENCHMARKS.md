# Benchmarks

## What is measured

| Where | What |
|---|---|
| `benches/benches/proto_bench.rs` | Snapshot, command, event, and art encode and decode |
| `benches/benches/sim_bench.rs` | World stepping with 0, 16, and 48 balloons, a full scripted match, chemistry lookups at three table sizes, combined burst outcome |
| `client/bench/softbody_bench.odin` | Soft-body ring step at 16, 24, 48, and 64 nodes |

Run them locally with `cd benches && cargo bench` and `odin run client/bench -o:speed`.

## Two kinds of limits

Timing on hosted CI machines is noisy, so timing results are reported and compared, not enforced by default.

Sizes are exact, so they are enforced as ordinary tests:
- A full snapshot of 48 balloons is 1158 bytes and must stay at or under 1200 (`wire_tests.rs`).
- A batch of 48 events must fit the same budget.
- An encoded art canvas must never exceed 2097 bytes, and a blank one must stay under 200 (`art_tests.rs`).

## Baselines

1. Run the `Benchmarks` workflow on `main`.
2. Download the `bench-results` artifact and take `bench_results.json` out of it.
3. Add it to the repository as `benches/baseline.json`.

From then on every run prints a comparison table. Set the `fail_pct` input, for example to 50, to make a regression above that fail the run. Renaming a benchmark breaks its comparison, because results are matched by id.

## First smoke run

One short run (`--warm-up-time 0.2 --measurement-time 0.5 --sample-size 10`) on a shared development machine on 2026-10-10. These numbers show orders of magnitude only. They are not a baseline.

| Benchmark | Result |
|---|---:|
| snapshot_48_balloons encode | 0.86 us |
| snapshot_48_balloons decode | 0.7 us |
| step_60_ticks with 48 balloons | 43 us |
| scripted_match_3600_ticks | 1.2 ms |
| chem_lookup_1000_pairs, 1024 compounds | 140 us |
| art_64x64 encode, noisy canvas | 10.5 us |
| softbody_step_24 (Odin) | about 4.1 to 4.6 us |

## Fixes and Problems

- None recorded yet.

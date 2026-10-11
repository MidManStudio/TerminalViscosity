// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_bench.md, section "sim_bench.rs"
// ============================================================================

use criterion::{black_box, criterion_group, criterion_main, BatchSize, BenchmarkId, Criterion};
use tv_proto::{Chamber, Command, Recipe};
use tv_sim::balloon::impact_outcome;
use tv_sim::testkit::{scripted_commands, synthetic_chem};
use tv_sim::{ChemBackend, NullChem, SplitMix64, World};

fn high_lob() -> Command {
    Command::Throw {
        recipe: Recipe { chambers: vec![Chamber { compound: 1, volume_ml: 100 }] },
        dir: [0, 1000, 0],
        power: 255,
    }
}

/// Cost of 60 ticks (one simulated second) with N balloons in the air.
/// Setup runs outside the timed region.
fn step_one_second(c: &mut Criterion) {
    let mut g = c.benchmark_group("step_60_ticks");
    for n in [0usize, 16, 48] {
        g.bench_with_input(BenchmarkId::from_parameter(n), &n, |b, &n| {
            b.iter_batched(
                || {
                    let mut w = World::new(1, NullChem);
                    let cmds: Vec<_> = (0..n).map(|_| (0u8, high_lob())).collect();
                    w.step(&cmds);
                    w
                },
                |mut w| {
                    for _ in 0..60 {
                        w.step(&[]);
                    }
                    w
                },
                BatchSize::SmallInput,
            )
        });
    }
    g.finish();
}

/// The same scripted match the server self-test runs, start to finish.
fn scripted_match(c: &mut Criterion) {
    let chem = synthetic_chem(16, 7);
    c.bench_function("scripted_match_3600_ticks", |b| {
        b.iter(|| {
            let mut w = World::new(1, chem.clone());
            let mut script = SplitMix64::new(1 ^ 0xA5A5);
            for t in 0..3600u32 {
                let cmds = scripted_commands(&mut script, t, 4, 16);
                w.step(&cmds);
                black_box(w.drain_events());
            }
            w.state_hash()
        })
    });
}

fn chem_lookup(c: &mut Criterion) {
    let mut g = c.benchmark_group("chem_lookup_1000_pairs");
    for compounds in [16u16, 256, 1024] {
        let table = synthetic_chem(compounds, 3);
        let mut rng = SplitMix64::new(11);
        let pairs: Vec<(u16, u16)> = (0..1000)
            .map(|_| (rng.below(compounds as u32) as u16, rng.below(compounds as u32) as u16))
            .collect();
        g.bench_with_input(BenchmarkId::from_parameter(compounds), &pairs, |b, pairs| {
            b.iter(|| {
                let mut acc = 0.0f32;
                for &(x, y) in pairs {
                    acc += table.react(x, y).volatility;
                }
                black_box(acc)
            })
        });
    }
    g.finish();
}

fn impact(c: &mut Criterion) {
    let table = synthetic_chem(16, 3);
    let recipe = Recipe {
        chambers: (0..4).map(|i| Chamber { compound: i, volume_ml: 100 }).collect(),
    };
    c.bench_function("impact_outcome_4_chambers", |b| {
        b.iter(|| impact_outcome(black_box(&recipe), &table))
    });
}

criterion_group!(benches, step_one_second, scripted_match, chem_lookup, impact);
criterion_main!(benches);

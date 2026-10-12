// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_bench.md, section "proto_bench.rs"
// ============================================================================

use criterion::{black_box, criterion_group, criterion_main, Criterion, Throughput};
use tv_proto::art::{ArtCanvas, ART_H, ART_W};
use tv_proto::wire::{decode_events, encode_events, BalloonState, Command, Event, Snapshot};
use tv_proto::{Chamber, Recipe, MAX_BALLOONS_PER_SNAPSHOT};

fn full_snapshot() -> Snapshot {
    Snapshot {
        tick: 1,
        balloons: (0..MAX_BALLOONS_PER_SNAPSHOT as u16)
            .map(|i| BalloonState {
                id: i,
                owner: (i % 8) as u8,
                compound: i,
                pos_mm: [i as i32 * 1000, 1500, -2000],
                vel_cms: [100, 900, -50],
                flags: 0,
            })
            .collect(),
    }
}

fn noisy_canvas() -> ArtCanvas {
    let mut c = ArtCanvas::blank(0);
    let mut s: u32 = 1;
    for y in 0..ART_H {
        for x in 0..ART_W {
            s = s.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            c.set(x, y, (s >> 24) as u8);
        }
    }
    c
}

fn snapshot(c: &mut Criterion) {
    let snap = full_snapshot();
    let bytes = snap.encode().unwrap();
    let mut g = c.benchmark_group("snapshot_48_balloons");
    g.throughput(Throughput::Bytes(bytes.len() as u64));
    g.bench_function("encode", |b| b.iter(|| black_box(&snap).encode().unwrap()));
    g.bench_function("decode", |b| b.iter(|| Snapshot::decode(black_box(&bytes)).unwrap()));
    g.finish();
}

fn command(c: &mut Criterion) {
    let cmd = Command::Throw {
        recipe: Recipe {
            chambers: vec![Chamber { compound: 3, volume_ml: 120 }; 4],
        },
        dir: [100, 500, -300],
        power: 180,
    };
    let bytes = cmd.encode();
    let mut g = c.benchmark_group("throw_command");
    g.bench_function("encode", |b| b.iter(|| black_box(&cmd).encode()));
    g.bench_function("decode", |b| b.iter(|| Command::decode(black_box(&bytes)).unwrap()));
    g.finish();
}

fn events(c: &mut Criterion) {
    let e = Event::Detonate { balloon: 1, compound: 2, volatility_q: 200, pos_mm: [1, 0, 2], radius_mm: 900 };
    let list = vec![e; MAX_BALLOONS_PER_SNAPSHOT];
    let bytes = encode_events(&list).unwrap();
    let mut g = c.benchmark_group("events_48");
    g.throughput(Throughput::Bytes(bytes.len() as u64));
    g.bench_function("encode", |b| b.iter(|| encode_events(black_box(&list)).unwrap()));
    g.bench_function("decode", |b| b.iter(|| decode_events(black_box(&bytes)).unwrap()));
    g.finish();
}

fn art(c: &mut Criterion) {
    let blank = ArtCanvas::blank(2);
    let noisy = noisy_canvas();
    let blank_bytes = blank.encode();
    let noisy_bytes = noisy.encode();
    let mut g = c.benchmark_group("art_256x256");
    g.bench_function("encode_blank", |b| b.iter(|| black_box(&blank).encode()));
    g.bench_function("encode_noisy", |b| b.iter(|| black_box(&noisy).encode()));
    g.bench_function("decode_blank", |b| b.iter(|| ArtCanvas::decode(black_box(&blank_bytes)).unwrap()));
    g.bench_function("decode_noisy", |b| b.iter(|| ArtCanvas::decode(black_box(&noisy_bytes)).unwrap()));
    g.finish();
}

criterion_group!(benches, snapshot, command, events, art);
criterion_main!(benches);

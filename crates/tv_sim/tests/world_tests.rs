// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "world_tests.rs"
// ============================================================================

use tv_proto::{
    Chamber, Command, Event, Recipe, Snapshot, MAX_BALLOONS_PER_SNAPSHOT, MAX_PAYLOAD_BYTES,
};
use tv_sim::testkit::{scripted_commands, synthetic_chem};
use tv_sim::{NullChem, SplitMix64, World, TICK_HZ};

fn simple_recipe() -> Recipe {
    Recipe {
        chambers: vec![Chamber {
            compound: 1,
            volume_ml: 100,
        }],
    }
}

fn lob(power: u8) -> Command {
    Command::Throw {
        recipe: simple_recipe(),
        dir: [0, 1000, 0],
        power,
    }
}

fn run_script(seed: u64, ticks: u32) -> (Vec<u64>, usize) {
    let mut world = World::new(seed, synthetic_chem(16, 7));
    let mut script_rng = SplitMix64::new(seed ^ 0xA5A5);
    let mut hashes = Vec::new();
    let mut detonations = 0;
    for t in 0..ticks {
        let cmds = scripted_commands(&mut script_rng, t, 4, 16);
        world.step(&cmds);
        detonations += world.drain_events().len();
        hashes.push(world.state_hash());
    }
    (hashes, detonations)
}

#[test]
fn same_seed_gives_identical_state_every_tick() {
    let (a, da) = run_script(42, 1200);
    let (b, db) = run_script(42, 1200);
    assert_eq!(a, b);
    assert_eq!(da, db);
    assert!(
        da > 0,
        "script never detonated anything, test proves nothing"
    );
}

#[test]
fn different_seed_gives_different_state() {
    let (a, _) = run_script(1, 300);
    let (b, _) = run_script(2, 300);
    assert_ne!(a.last(), b.last());
}

#[test]
fn lobbed_balloon_lands_and_detonates_once() {
    let mut w = World::new(0, NullChem);
    w.step(&[(0, lob(100))]);
    assert_eq!(w.balloon_count(), 1);
    let mut events = Vec::new();
    for _ in 0..(TICK_HZ * 4) {
        w.step(&[]);
        events.extend(w.drain_events());
    }
    assert_eq!(events.len(), 1);
    assert_eq!(w.balloon_count(), 0);
    match events[0] {
        Event::Detonate {
            pos_mm, balloon, ..
        } => {
            assert_eq!(pos_mm[1], 0);
            assert_eq!(balloon, 0);
        }
    }
}

#[test]
fn bad_commands_are_counted_and_ignored() {
    let mut w = World::new(0, NullChem);
    let empty = Command::Throw {
        recipe: Recipe { chambers: vec![] },
        dir: [0, 1, 0],
        power: 10,
    };
    let no_aim = Command::Throw {
        recipe: simple_recipe(),
        dir: [0, 0, 0],
        power: 10,
    };
    w.step(&[(0, empty), (0, no_aim)]);
    assert_eq!(w.rejected(), 2);
    assert_eq!(w.balloon_count(), 0);
}

#[test]
fn balloon_cap_matches_snapshot_capacity() {
    let mut w = World::new(0, NullChem);
    let cmds: Vec<_> = (0..MAX_BALLOONS_PER_SNAPSHOT + 5)
        .map(|_| (0u8, lob(10)))
        .collect();
    w.step(&cmds);
    assert_eq!(w.balloon_count(), MAX_BALLOONS_PER_SNAPSHOT);
    assert_eq!(w.rejected(), 5);
    let bytes = w.snapshot().encode().unwrap();
    assert!(bytes.len() <= MAX_PAYLOAD_BYTES);
    assert_eq!(Snapshot::decode(&bytes).unwrap(), w.snapshot());
}

#[test]
fn snapshot_reports_motion_in_wire_units() {
    let mut w = World::new(0, NullChem);
    w.step(&[(1, lob(100))]);
    let snap = w.snapshot();
    let b = snap.balloons[0];
    // 10 m/s straight up, minus one tick of gravity, in cm/s
    assert!(
        b.vel_cms[1] > 980 && b.vel_cms[1] < 1000,
        "vy = {}",
        b.vel_cms[1]
    );
    assert_eq!(b.owner, 1);
    assert!(b.pos_mm[1] > 1500);
}

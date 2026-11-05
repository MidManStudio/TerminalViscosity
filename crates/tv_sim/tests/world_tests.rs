// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "world_tests.rs"
// ============================================================================

//! World tests: determinism, players walking, balloon flight, rejected commands, and the
//! snapshot budget.
use tv_proto::{
    Chamber, Command, Event, Recipe, Snapshot, BUTTON_JUMP, MAX_BALLOONS_PER_SNAPSHOT,
    MAX_PAYLOAD_BYTES, MAX_PLAYERS,
};
use tv_sim::testkit::{scripted_commands, synthetic_chem};
use tv_sim::{
    ChemBackend, NullChem, SplitMix64, World, ARENA_RADIUS_M, INPUT_TIMEOUT_TICKS, JUMP_SPEED_MS,
    PLAYER_RADIUS_M, TICK_HZ, WALK_SPEED_MS,
};

fn simple_recipe() -> Recipe {
    Recipe {
        chambers: vec![Chamber {
            compound: 1,
            volume_ml: 100,
        }],
    }
}

fn throw(slot: u8, dir: [i16; 3], power: u8) -> Command {
    Command::Throw {
        slot,
        recipe: simple_recipe(),
        dir,
        power,
    }
}

fn lob(power: u8) -> Command {
    throw(0, [0, 1000, 0], power)
}

fn walk(forward: i8, strafe: i8, yaw_q: u16) -> Command {
    Command::Input {
        forward,
        strafe,
        yaw_q,
        buttons: 0,
    }
}

/// A player standing still with the jump button held.
fn jump() -> Command {
    Command::Input {
        forward: 0,
        strafe: 0,
        yaw_q: 0,
        buttons: BUTTON_JUMP,
    }
}

/// Where the feet of player `id` are above the floor, in millimetres.
fn height<C: ChemBackend>(w: &World<C>, id: u8) -> i32 {
    w.snapshot()
        .players
        .into_iter()
        .find(|p| p.id == id)
        .expect("player has not joined")
        .pos_mm[1]
}

/// Where player `id` is, in millimetres on the floor (x, z).
fn at<C: ChemBackend>(w: &World<C>, id: u8) -> [i32; 2] {
    let p = w
        .snapshot()
        .players
        .into_iter()
        .find(|p| p.id == id)
        .expect("player has not joined");
    [p.pos_mm[0], p.pos_mm[2]]
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
fn scripted_match_moves_players_and_keeps_them_in_the_arena() {
    let mut world = World::new(5, synthetic_chem(16, 7));
    let mut script_rng = SplitMix64::new(5 ^ 0xA5A5);
    for t in 0..2400 {
        world.step(&scripted_commands(&mut script_rng, t, 4, 16));
        for p in world.snapshot().players {
            let [x, z] = [p.pos_mm[0] as f32 / 1000.0, p.pos_mm[2] as f32 / 1000.0];
            assert!(
                (x * x + z * z).sqrt() <= ARENA_RADIUS_M - PLAYER_RADIUS_M + 0.002,
                "player {} left the arena at tick {t}",
                p.id
            );
        }
    }
    assert_eq!(world.player_count(), 4);
    let moved = (0..4u8)
        .filter(|&i| at(&world, i) != at(&fresh_spawn(i), i))
        .count();
    assert!(moved >= 3, "the script barely moved anyone");
}

/// A world where only `id` has joined, so its spawn point can be read back. It joins by
/// throwing, because an input command would replace the heading it spawned with.
fn fresh_spawn(id: u8) -> World<NullChem> {
    let mut w = World::new(0, NullChem);
    w.step(&[(id, lob(10))]);
    w
}

#[test]
fn player_joins_on_the_first_command_at_its_spawn_point() {
    let mut w = World::new(0, NullChem);
    assert_eq!(w.player_count(), 0);
    w.step(&[(3, lob(10))]);
    assert_eq!(w.player_count(), 1);
    let p = w.snapshot().players[0];
    assert_eq!(p.id, 3);
    assert_eq!(p.pos_mm, [9900, 0, -9900]);
    // Facing the middle of the arena, which for this spawn is a heading of 135 degrees.
    assert_eq!(p.yaw_q, 40_960);
    // An input command carries its own heading, which replaces the spawn heading.
    w.step(&[(3, walk(0, 0, 777))]);
    assert_eq!(w.snapshot().players[0].yaw_q, 777);
}

#[test]
fn joining_puts_a_player_on_the_spawn_point_without_any_command() {
    let mut w = World::new(0, NullChem);
    assert!(w.join(6));
    assert_eq!(w.player_count(), 1);
    let p = w.snapshot().players[0];
    assert_eq!((p.id, p.pos_mm, p.yaw_q), (6, [-14_000, 0, 0], 16_384));
    // Joining again changes nothing, and a walking player is not put back.
    for _ in 0..30 {
        w.step(&[(6, walk(127, 0, 16_384))]);
    }
    let moved = w.snapshot().players[0].pos_mm;
    assert!(w.join(6));
    assert_eq!(w.snapshot().players[0].pos_mm, moved);
    // There is no room beyond the player limit.
    assert!(!w.join(MAX_PLAYERS as u8));
    assert_eq!(w.player_count(), 1);
}

#[test]
fn every_spawn_point_is_on_the_ring_facing_the_middle() {
    for id in 0..MAX_PLAYERS as u8 {
        let w = fresh_spawn(id);
        let p = w.snapshot().players[0];
        let (x, z) = (p.pos_mm[0] as f32 / 1000.0, p.pos_mm[2] as f32 / 1000.0);
        assert!(
            ((x * x + z * z).sqrt() - 14.0).abs() < 0.01,
            "spawn {id} is off the ring"
        );
        // The direction the heading looks in, from the sim's own convention.
        let yaw = tv_proto::q_to_yaw(p.yaw_q);
        let (fx, fz) = (yaw.sin(), -yaw.cos());
        let toward_middle = -(x * fx + z * fz) / (x * x + z * z).sqrt();
        assert!(toward_middle > 0.999, "spawn {id} does not face the middle");
    }
}

#[test]
fn walking_forward_goes_at_walking_speed() {
    let mut w = World::new(0, NullChem);
    for _ in 0..TICK_HZ {
        w.step(&[(0, walk(127, 0, 0))]);
    }
    // Player 0 starts at z = 14 m facing -z, so one second forward is 3.2 m toward the middle.
    let [x, z] = at(&w, 0);
    assert_eq!(x, 0);
    let walked = 14_000 - z;
    let want = (WALK_SPEED_MS * 1000.0) as i32;
    assert!(
        (walked - want).abs() < 20,
        "walked {walked} mm, wanted about {want}"
    );
}

#[test]
fn strafing_and_diagonals_are_not_faster() {
    let mut a = World::new(0, NullChem);
    let mut b = World::new(0, NullChem);
    for _ in 0..TICK_HZ {
        // Heading 0 looks along -z, so a strafe to the right is toward +x.
        a.step(&[(0, walk(0, 127, 0))]);
        b.step(&[(0, walk(127, 127, 0))]);
    }
    let [ax, az] = at(&a, 0);
    assert!(
        ax > 3100 && ax < 3300 && az == 14_000,
        "strafe went to ({ax}, {az})"
    );
    let [bx, bz] = at(&b, 0);
    let dist = (((bx * bx) + (bz - 14_000) * (bz - 14_000)) as f32).sqrt();
    assert!(
        (dist - 3200.0).abs() < 30.0,
        "a diagonal covered {dist} mm in a second"
    );
}

#[test]
fn walking_follows_the_heading() {
    let mut w = World::new(0, NullChem);
    // A quarter turn faces +x.
    for _ in 0..TICK_HZ {
        w.step(&[(0, walk(127, 0, 16_384))]);
    }
    let [x, z] = at(&w, 0);
    assert!((x - 3200).abs() < 30, "x = {x}");
    assert!((z - 14_000).abs() < 30, "z = {z}");
}

#[test]
fn a_quiet_client_stops_walking() {
    let mut w = World::new(0, NullChem);
    w.step(&[(0, walk(127, 0, 0))]);
    for _ in 0..(INPUT_TIMEOUT_TICKS as u32 * 3) {
        w.step(&[]);
    }
    let [_, z] = at(&w, 0);
    let walked = (14_000 - z) as f32;
    let most = WALK_SPEED_MS * 1000.0 * INPUT_TIMEOUT_TICKS as f32 / TICK_HZ as f32;
    assert!(walked <= most + 5.0, "kept walking: {walked} mm");
    assert!(walked >= most * 0.9, "stopped too early: {walked} mm");
    let before = at(&w, 0);
    w.step(&[]);
    assert_eq!(at(&w, 0), before);
}

#[test]
fn the_wall_stops_players() {
    let mut w = World::new(0, NullChem);
    // Backwards from z = 14 m, away from the middle, for ten seconds.
    for _ in 0..(TICK_HZ * 10) {
        w.step(&[(0, walk(-127, 0, 0))]);
    }
    let [x, z] = at(&w, 0);
    let limit = ((ARENA_RADIUS_M - PLAYER_RADIUS_M) * 1000.0) as i32;
    assert_eq!(x, 0);
    assert!((z - limit).abs() <= 1, "z = {z}, wall at {limit}");
}

#[test]
fn sliding_along_the_wall_keeps_the_player_on_the_floor() {
    let mut w = World::new(0, NullChem);
    // Press into the wall at an angle for a long time.
    for _ in 0..(TICK_HZ * 30) {
        w.step(&[(0, walk(-127, 127, 0))]);
        let [x, z] = at(&w, 0);
        let dist = (((x as i64 * x as i64) + (z as i64 * z as i64)) as f64).sqrt();
        assert!(
            dist <= 19_700.0 + 1.5,
            "player at {dist} mm from the middle"
        );
    }
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
            // Straight up from a player standing at (0, 14), so it comes back near there.
            assert!(pos_mm[0].abs() < 50 && (pos_mm[2] - 14_000).abs() < 50);
        }
    }
}

#[test]
fn a_throw_leaves_from_the_thrower() {
    let mut w = World::new(0, NullChem);
    // Player 2 stands at x = 14 m. Throw level, toward +z, at 10 m/s.
    w.step(&[(2, throw(1, [0, 0, 1000], 100))]);
    let b = w.snapshot().balloons[0];
    let tick = 10.0 / 60.0;
    assert!((b.pos_mm[0] - 14_000).abs() <= 1, "x = {}", b.pos_mm[0]);
    assert!(
        (b.pos_mm[2] as f32 - (500.0 + tick * 1000.0)).abs() < 3.0,
        "z = {}",
        b.pos_mm[2]
    );
    assert!(
        b.pos_mm[1] < 1500 && b.pos_mm[1] > 1480,
        "y = {}",
        b.pos_mm[1]
    );
    assert_eq!(b.owner, 2);

    // Thrown straight up it leaves half a metre higher, and has risen 10/60 m by the first tick.
    let mut w = World::new(0, NullChem);
    w.step(&[(2, throw(0, [0, 1000, 0], 100))]);
    let b = w.snapshot().balloons[0];
    let want = 1500.0 + 500.0 + tick * 1000.0;
    assert!(
        (b.pos_mm[1] as f32 - want).abs() < 5.0,
        "y = {}",
        b.pos_mm[1]
    );
    assert!((b.pos_mm[0] - 14_000).abs() <= 1 && b.pos_mm[2].abs() <= 1);
}

#[test]
fn the_state_hash_sees_where_players_are() {
    let mut a = World::new(3, NullChem);
    let mut b = World::new(3, NullChem);
    a.step(&[(0, walk(0, 0, 0))]);
    b.step(&[(0, walk(0, 0, 0))]);
    assert_eq!(a.state_hash(), b.state_hash());
    for _ in 0..10 {
        a.step(&[(0, walk(127, 0, 0))]);
        b.step(&[(0, walk(0, 0, 0))]);
    }
    assert_ne!(
        a.state_hash(),
        b.state_hash(),
        "walking left no mark on the hash"
    );
    // Same last input, different places: only the positions can tell them apart.
    for dir in [(127, 0), (0, 127)] {
        let mut here = World::new(3, NullChem);
        let mut there = World::new(3, NullChem);
        for _ in 0..10 {
            here.step(&[(0, walk(dir.0, dir.1, 0))]);
            there.step(&[(0, walk(0, 0, 0))]);
        }
        here.step(&[(0, walk(0, 0, 0))]);
        there.step(&[(0, walk(0, 0, 0))]);
        assert_ne!(
            here.state_hash(),
            there.state_hash(),
            "positions are not in the hash ({dir:?})"
        );
    }
    // A different heading with the same position is a different state too.
    let mut c = World::new(3, NullChem);
    let mut d = World::new(3, NullChem);
    c.step(&[(0, walk(0, 0, 100))]);
    d.step(&[(0, walk(0, 0, 200))]);
    assert_ne!(c.state_hash(), d.state_hash());
}

#[test]
fn the_slot_of_a_throw_comes_back_in_the_balloon_flags() {
    let mut w = World::new(0, NullChem);
    w.step(&[
        (0, throw(0, [0, 1000, 0], 50)),
        (0, throw(1, [0, 1000, 0], 50)),
        (1, throw(2, [0, 1000, 0], 50)),
    ]);
    let flags: Vec<u8> = w.snapshot().balloons.iter().map(|b| b.flags).collect();
    assert_eq!(flags, vec![0, 1, 2]);
}

#[test]
fn a_balloon_bursts_on_the_wall_at_the_height_it_hit() {
    let mut w = World::new(0, NullChem);
    // From (0, 14) level toward +z, away from the middle, at 20 m/s: the wall is 5.5 m on.
    w.step(&[(0, throw(0, [0, 0, 1000], 200))]);
    let mut events = Vec::new();
    for _ in 0..TICK_HZ {
        w.step(&[]);
        events.extend(w.drain_events());
    }
    assert_eq!(events.len(), 1, "it should have burst once");
    assert_eq!(w.balloon_count(), 0);
    let Event::Detonate { pos_mm, .. } = events[0];
    let dist = (((pos_mm[0] as i64).pow(2) + (pos_mm[2] as i64).pow(2)) as f64).sqrt();
    assert!(
        (dist - 20_000.0).abs() < 2.0,
        "burst {dist} mm from the middle"
    );
    assert!(
        pos_mm[1] > 900 && pos_mm[1] < 1400,
        "burst at height {}",
        pos_mm[1]
    );
}

#[test]
fn bad_commands_are_counted_and_ignored() {
    let mut w = World::new(0, NullChem);
    let empty = Command::Throw {
        slot: 0,
        recipe: Recipe { chambers: vec![] },
        dir: [0, 1, 0],
        power: 10,
    };
    let no_aim = throw(0, [0, 0, 0], 10);
    w.step(&[(0, empty), (0, no_aim)]);
    assert_eq!(w.rejected(), 2);
    assert_eq!(w.balloon_count(), 0);
}

#[test]
fn players_beyond_the_limit_are_refused() {
    let mut w = World::new(0, NullChem);
    w.step(&[
        (MAX_PLAYERS as u8, walk(1, 1, 1)),
        (200, lob(10)),
        (7, walk(0, 0, 0)),
    ]);
    assert_eq!(w.rejected(), 2);
    assert_eq!(w.player_count(), 1);
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
fn a_full_match_fits_one_datagram() {
    let mut w = World::new(0, NullChem);
    let mut cmds: Vec<_> = (0..MAX_PLAYERS as u8)
        .map(|id| (id, walk(0, 0, 0)))
        .collect();
    cmds.extend((0..MAX_BALLOONS_PER_SNAPSHOT).map(|i| ((i % MAX_PLAYERS) as u8, lob(10))));
    w.step(&cmds);
    let snap = w.snapshot();
    assert_eq!(snap.players.len(), MAX_PLAYERS);
    assert_eq!(snap.balloons.len(), MAX_BALLOONS_PER_SNAPSHOT);
    let bytes = snap.encode().unwrap();
    assert!(
        bytes.len() <= MAX_PAYLOAD_BYTES,
        "snapshot is {} bytes",
        bytes.len()
    );
    assert_eq!(Snapshot::decode(&bytes).unwrap(), snap);
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

#[test]
fn players_stand_on_the_floor_until_they_jump() {
    let mut w = World::new(0, NullChem);
    w.step(&[(0, walk(127, 0, 0))]);
    for _ in 0..120 {
        w.step(&[(0, walk(127, 127, 3000))]);
        assert_eq!(height(&w, 0), 0);
    }
}

#[test]
fn a_jump_goes_up_comes_down_and_lands_where_it_left() {
    let mut w = World::new(0, NullChem);
    w.step(&[(0, jump())]);
    let start = at(&w, 0);
    let mut peak = 0;
    let mut airborne_ticks = 0;
    for _ in 0..60 {
        w.step(&[]);
        peak = peak.max(height(&w, 0));
        if height(&w, 0) > 0 {
            airborne_ticks += 1;
        }
    }
    // v squared over twice gravity, from 3 m/s: 0.458 m, a little less for the tick it is counted in.
    let want = (JUMP_SPEED_MS * JUMP_SPEED_MS / (2.0 * 9.81) * 1000.0) as i32;
    assert!(
        (peak - want).abs() < 25,
        "peaked at {peak} mm, wanted about {want}"
    );
    assert_eq!(height(&w, 0), 0, "back on the floor");
    assert_eq!(at(&w, 0), start, "and where it left");
    // Up and down take 2 v over g seconds, about 37 ticks.
    assert!(
        (34..=40).contains(&airborne_ticks),
        "was in the air for {airborne_ticks} ticks"
    );
}

#[test]
fn there_is_no_jumping_in_the_air() {
    // Holding the button in the air does not lift the player higher than one jump does.
    let mut w = World::new(0, NullChem);
    w.step(&[(0, jump())]);
    let mut peak = 0;
    for _ in 0..30 {
        w.step(&[(0, jump())]);
        peak = peak.max(height(&w, 0));
    }
    assert!(
        peak < 480,
        "peaked at {peak} mm: a second jump started in the air"
    );
}

#[test]
fn holding_jump_jumps_again_on_landing() {
    let mut w = World::new(0, NullChem);
    let mut peaks = 0;
    let mut rising = false;
    let mut last = 0;
    for _ in 0..200 {
        w.step(&[(0, jump())]);
        let h = height(&w, 0);
        if h > last {
            rising = true;
        } else if h < last && rising {
            peaks += 1;
            rising = false;
        }
        last = h;
    }
    assert!(
        peaks >= 4,
        "only {peaks} jumps in 200 ticks of holding the button"
    );
}

#[test]
fn a_jump_without_the_button_held_goes_no_further_than_the_input_lasts() {
    // One input with the button, then nothing: the quiet timeout lets go of the button, so the
    // player does not hop for ever, and lands once.
    let mut w = World::new(0, NullChem);
    w.step(&[(0, jump())]);
    let mut landings = 0;
    let mut last = 0;
    for _ in 0..200 {
        w.step(&[]);
        let h = height(&w, 0);
        if h == 0 && last > 0 {
            landings += 1;
        }
        last = h;
    }
    assert_eq!(landings, 1);
}

#[test]
fn a_jump_does_not_stop_the_walk() {
    let mut w = World::new(0, NullChem);
    let cmd = Command::Input {
        forward: 127,
        strafe: 0,
        yaw_q: 0,
        buttons: BUTTON_JUMP,
    };
    for _ in 0..TICK_HZ {
        w.step(&[(0, cmd.clone())]);
    }
    let [_, z] = at(&w, 0);
    let walked = 14_000 - z;
    assert!(
        (walked - 3200).abs() < 25,
        "walked {walked} mm in a second of jumping"
    );
}

#[test]
fn a_throw_from_the_air_leaves_from_where_the_hand_is() {
    let mut w = World::new(0, NullChem);
    w.step(&[(0, jump())]);
    for _ in 0..18 {
        w.step(&[]);
    }
    let up = height(&w, 0);
    assert!(up > 350, "should be near the top, is at {up} mm");
    w.step(&[(0, throw(0, [0, 0, 1000], 100))]);
    let b = w.snapshot().balloons[0];
    let feet = height(&w, 0);
    // Level throw: the hand is 1.5 m above the feet, less a tick of gravity.
    assert!(
        (b.pos_mm[1] - (feet + 1500)).abs() < 30,
        "the balloon is at {} and the feet at {feet}",
        b.pos_mm[1]
    );
}

#[test]
fn the_state_hash_sees_the_height_and_the_buttons() {
    let mut a = World::new(3, NullChem);
    let mut b = World::new(3, NullChem);
    a.step(&[(0, jump())]);
    b.step(&[(0, walk(0, 0, 0))]);
    // The same input from here on, so only the height of one of them tells them apart.
    for _ in 0..5 {
        a.step(&[(0, walk(0, 0, 0))]);
        b.step(&[(0, walk(0, 0, 0))]);
    }
    assert!(height(&a, 0) > 0 && height(&b, 0) == 0);
    assert_ne!(
        a.state_hash(),
        b.state_hash(),
        "a jump in the air left no mark on the hash"
    );
    // A held button is a different state even when it changes nothing yet: two players in the air
    // at the same height, one holding the jump button, which cannot do anything up there.
    let mut c = World::new(3, NullChem);
    let mut d = World::new(3, NullChem);
    c.step(&[(0, jump())]);
    d.step(&[(0, jump())]);
    for _ in 0..5 {
        c.step(&[(0, walk(0, 0, 0))]);
        d.step(&[(0, walk(0, 0, 0))]);
    }
    c.step(&[(0, walk(0, 0, 0))]);
    d.step(&[(0, jump())]);
    assert_eq!(
        height(&c, 0),
        height(&d, 0),
        "the button changed nothing in the air"
    );
    assert_ne!(
        c.state_hash(),
        d.state_hash(),
        "a held button left no mark on the hash"
    );
}

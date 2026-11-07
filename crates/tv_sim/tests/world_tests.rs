// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "world_tests.rs"
// ============================================================================

//! World tests: determinism, players walking, balloon flight, rejected commands, and the
//! snapshot budget.
use tv_proto::{
    Chamber, Command, Event, Recipe, Snapshot, BUTTON_JUMP, MAX_BALLOONS_PER_SNAPSHOT, MAX_HEALTH,
    MAX_PAYLOAD_BYTES, MAX_PLAYERS,
};
use tv_sim::testkit::{scripted_commands, synthetic_chem};
use tv_sim::{
    ChemBackend, NullChem, Outcome, SplitMix64, TableChem, World, ARENA_RADIUS_M, DAMAGE_BASE_HP,
    INPUT_TIMEOUT_TICKS, JUMP_SPEED_MS, PLAYER_RADIUS_M, RESPAWN_TICKS, TICK_HZ, WALK_SPEED_MS,
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

// ---------------------------------------------------------------------------------------------
// Hit points: balloons that hit, splashes, knock-outs and coming back.
// ---------------------------------------------------------------------------------------------

/// The hit points player `id` has left.
fn hp<C: ChemBackend>(w: &World<C>, id: u8) -> u8 {
    w.snapshot()
        .players
        .into_iter()
        .find(|p| p.id == id)
        .expect("player has not joined")
        .hp
}

/// A command that holds a player still, facing `yaw_q`.
fn stand(yaw_q: u16) -> Command {
    walk(0, 0, yaw_q)
}

/// Players 0 and 4 start 28 m apart on the same line, facing each other. Player 0 walks at
/// the middle for `ticks0` ticks and player 4 for `ticks4`, and both stand still after.
/// 240 ticks is 12.8 m: player 0 then stands at z = 1.2 m and player 4 at z = -1.2 m.
fn walked(ticks0: u32, ticks4: u32) -> World<NullChem> {
    let mut w = World::new(1, NullChem);
    for t in 0..ticks0.max(ticks4) {
        let c0 = if t < ticks0 {
            walk(127, 0, 0)
        } else {
            stand(0)
        };
        let c4 = if t < ticks4 {
            walk(127, 0, 32_768)
        } else {
            stand(32_768)
        };
        w.step(&[(0, c0), (4, c4)]);
    }
    w
}

fn face_off() -> World<NullChem> {
    walked(240, 240)
}

/// A level throw by player 0 at player 4 in a `face_off`, at the weakest power.
fn level_throw() -> Command {
    throw(0, [0, 0, -1000], 60)
}

/// Steps the world `ticks` times with both players standing still, and returns the bursts.
fn settle<C: ChemBackend>(w: &mut World<C>, ticks: u32) -> Vec<Event> {
    let mut out = Vec::new();
    for _ in 0..ticks {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
        out.extend(w.drain_events());
    }
    out
}

fn bursts_of(events: &[Event]) -> Vec<(i32, [i32; 3])> {
    events
        .iter()
        .map(|e| match e {
            Event::Detonate {
                radius_mm, pos_mm, ..
            } => (*radius_mm as i32, *pos_mm),
        })
        .collect()
}

#[test]
fn players_start_with_full_hit_points() {
    let mut w = World::new(1, NullChem);
    assert!(w.join(2));
    assert_eq!(hp(&w, 2), MAX_HEALTH);
    assert_eq!(MAX_HEALTH, 100);
}

#[test]
fn a_direct_hit_takes_the_base_damage_off_and_the_balloon_bursts_on_the_body() {
    let mut w = face_off();
    w.step(&[(0, level_throw())]);
    let events = settle(&mut w, 60);
    assert_eq!(hp(&w, 4), MAX_HEALTH - DAMAGE_BASE_HP as u8);
    let bursts = bursts_of(&events);
    assert_eq!(bursts.len(), 1);
    // It burst where it met the body, a little short of the middle of it, and at the height it
    // was flying, not on the floor.
    let (_, pos) = bursts[0];
    assert!(
        (-900..=-790).contains(&pos[2]),
        "burst at z = {} mm",
        pos[2]
    );
    assert!(
        (1000..=1400).contains(&pos[1]),
        "burst at y = {} mm",
        pos[1]
    );
    assert_eq!(w.balloon_count(), 0);
}

#[test]
fn the_thrower_is_never_hurt_by_their_own_balloon() {
    let mut w = face_off();
    // Straight up, so that it comes back down on the thrower.
    w.step(&[(0, throw(0, [0, 1000, 0], 60))]);
    let events = settle(&mut w, 120);
    assert_eq!(hp(&w, 0), MAX_HEALTH);
    let bursts = bursts_of(&events);
    assert_eq!(bursts.len(), 1);
    // It went through the body of the one who threw it and burst on the floor.
    assert_eq!(bursts[0].1[1], 0);
}

#[test]
fn a_balloon_over_a_head_goes_on() {
    let mut w = face_off();
    w.step(&[(0, throw(0, [0, 400, -1000], 100))]);
    let events = settle(&mut w, 120);
    assert_eq!(hp(&w, 4), MAX_HEALTH);
    let bursts = bursts_of(&events);
    assert_eq!(bursts.len(), 1);
    assert_eq!(bursts[0].1[1], 0, "it burst on the floor, far past them");
}

/// A thousand millilitres of nothing in particular, so that a burst reaches 1.5 m.
fn big_lob() -> Command {
    Command::Throw {
        slot: 0,
        recipe: Recipe {
            chambers: vec![Chamber {
                compound: 1,
                volume_ml: 1000,
            }],
        },
        dir: [0, 1000, 0],
        power: 60,
    }
}

/// How many hit points player 4 loses when player 0, standing `ticks0` ticks of walking from
/// where they began, lobs a big balloon straight up and it comes down on them.
fn splash_taken(ticks0: u32) -> (u8, Vec<Event>) {
    let mut w = walked(ticks0, 240);
    w.step(&[(0, big_lob())]);
    let events = settle(&mut w, 150);
    (MAX_HEALTH - hp(&w, 4), events)
}

#[test]
fn a_splash_takes_less_off_the_farther_it_bursts() {
    // Player 4 stands at z = -1.2 m. Player 0 stands 0.8 m, 1.6 m and 2.4 m from them, which
    // is 0.4 m, 1.2 m and 2.0 m from the edge of the body. The burst reaches 1.5 m.
    let (near, events) = splash_taken(270);
    assert_eq!(bursts_of(&events)[0].0, 1500);
    assert_eq!(near, 15, "20 * (1 - 0.4 / 1.5)");
    assert_eq!(splash_taken(255).0, 4, "20 * (1 - 1.2 / 1.5)");
    assert_eq!(splash_taken(240).0, 0, "out of reach");
}

fn volatile_chem(volatility: f32) -> TableChem {
    TableChem::from_entries([(
        1,
        2,
        Outcome {
            volatility,
            heat: 0.0,
        },
    )])
}

#[test]
fn volatility_adds_to_the_damage_of_a_direct_hit() {
    for (volatility, dealt) in [(0.5_f32, 60_u8), (1.0, 100)] {
        let mut w = World::new(1, volatile_chem(volatility));
        for _ in 0..240 {
            w.step(&[(0, walk(127, 0, 0)), (4, walk(127, 0, 32_768))]);
        }
        let balloon = Command::Throw {
            slot: 0,
            recipe: Recipe {
                chambers: vec![
                    Chamber {
                        compound: 1,
                        volume_ml: 10,
                    },
                    Chamber {
                        compound: 2,
                        volume_ml: 10,
                    },
                ],
            },
            dir: [0, 0, -1000],
            power: 60,
        };
        w.step(&[(0, balloon)]);
        settle(&mut w, 60);
        assert_eq!(MAX_HEALTH - hp(&w, 4), dealt, "volatility {volatility}");
    }
}

/// Player 0 hits player 4 with `n` balloons, one every half second.
fn hit_times<C: ChemBackend>(w: &mut World<C>, n: u32) {
    for _ in 0..n {
        w.step(&[(0, level_throw())]);
        settle(w, 30);
    }
}

#[test]
fn five_plain_hits_knock_a_player_out() {
    let mut w = face_off();
    hit_times(&mut w, 4);
    assert_eq!(hp(&w, 4), 20);
    hit_times(&mut w, 1);
    assert_eq!(hp(&w, 4), 0);
}

#[test]
fn a_knocked_out_player_cannot_walk_jump_or_throw_and_balloons_pass_through() {
    let mut w = face_off();
    hit_times(&mut w, 5);
    let rejected = w.rejected();
    let before = at(&w, 4);
    // Walking, jumping and throwing all do nothing.
    w.step(&[(4, walk(127, 0, 0)), (4, throw(0, [0, 1000, 0], 60))]);
    assert_eq!(w.rejected(), rejected + 1, "the throw is refused");
    assert_eq!(w.balloon_count(), 0);
    let jumping = Command::Input {
        forward: 127,
        strafe: 0,
        yaw_q: 0,
        buttons: BUTTON_JUMP,
    };
    for _ in 0..30 {
        w.step(&[(0, stand(0)), (4, jumping.clone())]);
        assert_eq!(height(&w, 4), 0);
    }
    assert_eq!(at(&w, 4), before, "and does not move");
    // A balloon thrown right through where they lie goes on to the floor, and does no harm.
    w.step(&[(0, level_throw())]);
    let events = settle(&mut w, 60);
    let bursts = bursts_of(&events);
    assert_eq!(bursts.len(), 1);
    assert_eq!(bursts[0].1[1], 0);
    assert_eq!(hp(&w, 4), 0);
}

#[test]
fn a_knocked_out_player_comes_back_at_their_spawn_point_after_the_wait() {
    let mut w = face_off();
    hit_times(&mut w, 4);
    // The last hit, and the tick it lands on is the first with no hit points.
    w.step(&[(0, level_throw())]);
    let mut ticks = 0;
    while hp(&w, 4) != 0 {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
        ticks += 1;
        assert!(ticks < 100, "the balloon never landed");
    }
    // Down for RESPAWN_TICKS snapshots counting that one, and back on the next step.
    for _ in 1..RESPAWN_TICKS {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
        assert_eq!(hp(&w, 4), 0);
    }
    w.step(&[(0, stand(0)), (4, stand(32_768))]);
    assert_eq!(hp(&w, 4), MAX_HEALTH);
    assert_eq!(at(&w, 4), [0, -14_000]);
    assert_eq!(height(&w, 4), 0);
    // And it can be hit, and can throw, again.
    w.step(&[(4, throw(0, [0, 1000, 0], 60))]);
    assert_eq!(w.balloon_count(), 1);
}

#[test]
fn a_splash_on_a_knocked_out_player_does_not_keep_them_down_longer() {
    // Player 0 stands 0.8 m from player 4, so that a big balloon lobbed up reaches them.
    let mut w = walked(270, 240);
    hit_times(&mut w, 4);
    w.step(&[(0, level_throw())]);
    let mut ticks = 0;
    while hp(&w, 4) != 0 {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
        ticks += 1;
        assert!(ticks < 100, "the balloon never landed");
    }
    // Down for RESPAWN_TICKS snapshots, with a big splash landing beside them part of the way.
    let mut down_for = 1;
    for t in 0..400 {
        let c0 = if t == 40 { big_lob() } else { stand(0) };
        w.step(&[(0, c0), (4, stand(32_768))]);
        if hp(&w, 4) != 0 {
            break;
        }
        down_for += 1;
    }
    assert_eq!(down_for, RESPAWN_TICKS as u32);
}

#[test]
fn a_player_knocked_out_in_the_air_comes_down() {
    let mut w = World::new(1, volatile_chem(1.0));
    for t in 0..240 {
        // Player 4 starts a jump on the last tick of the walk, as the balloon is thrown.
        let c4 = if t == 239 {
            Command::Input {
                forward: 0,
                strafe: 0,
                yaw_q: 32_768,
                buttons: BUTTON_JUMP,
            }
        } else {
            walk(127, 0, 32_768)
        };
        w.step(&[(0, walk(127, 0, 0)), (4, c4)]);
    }
    let killer = Command::Throw {
        slot: 0,
        recipe: Recipe {
            chambers: vec![
                Chamber {
                    compound: 1,
                    volume_ml: 10,
                },
                Chamber {
                    compound: 2,
                    volume_ml: 10,
                },
            ],
        },
        dir: [0, 0, -1000],
        power: 60,
    };
    w.step(&[(0, killer)]);
    let mut ticks = 0;
    while hp(&w, 4) != 0 {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
        ticks += 1;
        assert!(ticks < 60, "the balloon never hit");
    }
    assert!(height(&w, 4) > 0, "knocked out while still in the air");
    for _ in 0..60 {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
    }
    assert_eq!(hp(&w, 4), 0);
    assert_eq!(height(&w, 4), 0, "it fell to the floor while down");
}

#[test]
fn the_state_hash_sees_hit_points_and_the_wait() {
    let mut a = face_off();
    let b = face_off();
    assert_eq!(a.state_hash(), b.state_hash());
    a.step(&[(0, level_throw())]);
    let mut b = face_off();
    b.step(&[(0, level_throw())]);
    settle(&mut a, 60);
    settle(&mut b, 60);
    assert_eq!(a.state_hash(), b.state_hash());
    // One more hit leaves the two worlds differing only in hit points.
    a.step(&[(0, level_throw())]);
    settle(&mut a, 60);
    assert_ne!(a.state_hash(), b.state_hash());
    // Knocked out, the hash goes on changing as the wait runs down.
    let mut c = face_off();
    hit_times(&mut c, 5);
    let h0 = c.state_hash();
    c.step(&[(0, stand(0)), (4, stand(32_768))]);
    assert_ne!(c.state_hash(), h0);
}

#[test]
fn a_knocked_out_player_waits_three_seconds() {
    assert_eq!(RESPAWN_TICKS as u32, 3 * TICK_HZ);
}

#[test]
fn the_state_hash_sees_hit_points_and_nothing_else_when_they_are_all_that_differs() {
    // One balloon goes level at player 4 in one world and over their head in the other. When both
    // have burst, the worlds differ only in hit points.
    let mut hit = face_off();
    hit.step(&[(0, throw(0, [0, 0, -1000], 100))]);
    let mut miss = face_off();
    miss.step(&[(0, throw(0, [0, 400, -1000], 100))]);
    settle(&mut hit, 150);
    settle(&mut miss, 150);
    assert_ne!(hp(&hit, 4), hp(&miss, 4));
    assert_ne!(hit.state_hash(), miss.state_hash());
}

#[test]
fn the_state_hash_sees_how_long_a_knocked_out_player_has_still_to_wait() {
    // Player 4 is knocked out in both worlds, one tick apart. A while after both, they differ in
    // nothing but the time left.
    fn knocked_out_after(delay: u32) -> World<NullChem> {
        let mut w = face_off();
        hit_times(&mut w, 4);
        for t in 0..60 {
            let last = if t == delay { level_throw() } else { stand(0) };
            w.step(&[(0, stand(0)), (0, last), (4, stand(32_768))]);
        }
        w
    }
    let (early, late) = (knocked_out_after(0), knocked_out_after(1));
    assert_eq!(hp(&early, 4), 0);
    assert_eq!(hp(&late, 4), 0);
    assert_ne!(early.state_hash(), late.state_hash());
}

#[test]
fn a_player_in_the_air_takes_less_of_a_splash_from_the_floor() {
    // The tick a big balloon lobbed up beside player 4 bursts on the floor.
    let mut w = walked(270, 240);
    w.step(&[(0, big_lob())]);
    let mut burst_at = 0;
    for t in 1..300 {
        w.step(&[(0, stand(0)), (4, stand(32_768))]);
        if !w.drain_events().is_empty() {
            burst_at = t;
            break;
        }
    }
    assert!(burst_at > 20, "it burst on tick {burst_at}");
    // Again, with player 4 jumping so that they are near the top of the jump when it bursts.
    let jump = Command::Input {
        forward: 0,
        strafe: 0,
        yaw_q: 32_768,
        buttons: BUTTON_JUMP,
    };
    let mut w = walked(270, 240);
    w.step(&[(0, big_lob())]);
    for t in 1..=burst_at {
        let c4 = if t == burst_at - 18 {
            jump.clone()
        } else {
            stand(32_768)
        };
        w.step(&[(0, stand(0)), (4, c4)]);
    }
    let taken = MAX_HEALTH - hp(&w, 4);
    assert!(
        (8..=14).contains(&taken),
        "took {taken}, not the 15 of standing there"
    );
}

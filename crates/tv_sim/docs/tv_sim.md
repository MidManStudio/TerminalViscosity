# tv_sim

## Overview

Deterministic fixed-step simulation core. Commands go in, snapshots and events come out. The crate does no I/O, so the same code can run in a dedicated server, a listen server, or a local session.

Determinism here means: the same seed and the same command stream give the same state on every tick, on the same build. That is what an authoritative server needs. Bit-identical results across different CPUs are not claimed, because the sim uses `f32` arithmetic.

## Modules

### `Cargo.toml`
**What it does:** Package manifest. One dependency, `tv_proto`, by path.

### `lib.rs`
**What it does:** Module list and re-exports of the main types and of the constants of the walking and damage rules.

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
**What it does:** `World`, the fixed tick, players walking a round arena, balloon flight, detonation events, snapshots, and `state_hash`. A player joins on the first command it sends, or by `join`, and starts on one of eight spawn points on a ring of 14 m, facing the middle. An input command sets the stick and the heading, and every tick moves each player by the stick last sent, at 3.2 m a second, with the diagonals no faster than straight ahead, and keeps them inside the arena wall. A player that sends nothing for half a second stops. A throw leaves from the thrower, at a height of 1.5 m above the feet and half a metre along the aim. A player jumps when the jump button is held on the floor, at 3 m a second upward, the lab's, which is about 46 cm and 0.6 s in the air, and falls at 9.81 m a second squared. A jump cannot be started in the air, so holding the button hops, and the walk goes on in the air as on the floor. The height comes out in the snapshot as the second coordinate of the position.

**Decisions:**
- 60 ticks per second. Semi-implicit Euler integration under constant gravity, and a balloon bursts when it reaches the ground.
- Placeholders: the launch speed per unit of power, the blast radius formula, the walking speed, the throw height, the spawn ring, and every number of the damage rules below. The owner has not specified the combat rules in detail. The rules below are the assumptions made so that a player can be hurt, and are listed in `docs/OPEN_DECISIONS.md`.
- Jumping is a button held in the input, and the quiet timeout lets go of it with the stick, so a client that goes quiet in the air lands once and stays on the floor. The jump speed is the lab's, so the arena feels like the lab.
- The arena is a circle of 20 m radius. A player stops 0.3 m short of the wall and slides along it. A balloon that crosses the wall bursts on it at the height it had, and one that reaches the ground bursts there. The client draws its wall from the same number, and its self-test checks that the two agree.
- Spawn points are constants and not computed from sine and cosine, so a spawn cannot differ between machines. Walking does use `sin_cos` on the heading, so the determinism claim above still stands for the same build and no further.
- A command from a player id beyond `MAX_PLAYERS` is refused and counted. Any command joins its sender, so a throw from a player who never sent an input still has somewhere to leave from.
- At most 40 balloons in flight, so one snapshot with a full player list always fits one datagram. Extra throws are counted in `rejected()`.
- `state_hash` is FNV-1a over tick, RNG state, players (with their buttons, height, hit points and the wait left of one who is knocked out), ids, slots, recipes, positions, and velocities. The vertical speed of a player is not hashed, because in a jump it follows from the height. It is the tool for spotting nondeterminism.
- Balloons are kept in creation order and removed with `retain_mut`, so event order is stable.

**Benchmarks:** `sim_bench.rs`, groups `step_60_ticks` and `scripted_match_3600_ticks`.

**Hit points.** Every player starts with `MAX_HEALTH` (100). A balloon that reaches the body of a player, a cylinder of 0.4 m radius standing 1.9 m high on their feet, bursts on them, at the height it had. A balloon that bursts anywhere, on a body, on the ground or on the wall, takes hit points off every other player standing within its radius: the most at the burst, `DAMAGE_BASE_HP` (20) plus `DAMAGE_VOLATILE_HP` (80) times the volatility, and less the farther the burst is from the nearest point of the body, down to nothing at the radius. The distance is measured to the cylinder, so a burst on the floor under a player who has jumped is farther than one beside them on the floor. A player at 0 is knocked out for `RESPAWN_TICKS` (180, three seconds): they cannot walk, jump or throw, balloons pass through them and do no harm to them, and they fall if they were in the air. When the wait is over they come back at their own spawn point with full hit points.

**Decisions:**
- The thrower is never hit by their own balloon and never hurt by its burst. That was not specified. It keeps a balloon thrown straight up from hurting the one who threw it, and the same rule serves a balloon thrown at the feet. Whether a blast that hurts the thrower is wanted is a decision for later.
- A balloon bursts on the first body it meets, so it cannot go through one player to hurt another. A tick moves a balloon at most 0.3 m at the fastest throw, and the body is 0.8 m across, so none passes through a player between two ticks.
- The radius that hurts is the radius of the burst the event carries, so what a client draws and what the simulation does agree, and they change together when the radius formula is replaced.
- Volatility adds to the damage, and is zero until the compound database is shared, so for now every balloon is the same. The damage of the worst balloon, 100, is a full set of hit points.
- Hit points are whole numbers, rounded to the nearest, so a splash at the very edge of the radius hurts by nothing.

### `testkit.rs`
**What it does:** Reproducible command scripts and synthetic chemistry for tests, benchmarks, and the server self-test. The script now has players walk in random directions every third tick as well as throw every fifth, so the determinism check covers movement.

**Decisions:** The synthetic table carries no chemical meaning. It exists to exercise lookup cost and the determinism check.

### `world_tests.rs`
**What it does:** Same seed gives the same hash on every tick of a 1200-tick scripted match, different seeds differ, and the hash sees where players are and which way they face. Players join at their spawn point facing the middle, walk at walking speed along their heading, are no faster sideways or on a diagonal, stop when their client goes quiet, and cannot leave the arena or climb the wall by pressing into it at an angle. A throw leaves from the thrower and carries its slot, a lobbed balloon lands and bursts exactly once, and one that hits the wall bursts on it at its height. A jump goes up about 46 cm, comes down in 34 to 40 ticks where it left, cannot be repeated in the air, repeats on landing while the button is held, stops with the input, keeps the walk, and lifts the hand a throw leaves from. Bad commands and players beyond the limit are counted, the balloon cap matches the snapshot capacity, and a full match of 8 players and 40 balloons fits one datagram.

Hit points: players start with 100, a direct hit takes 20 and the balloon bursts on the body at the height it had, the thrower is never hurt by their own balloon, a balloon over a head goes on, a splash takes 15, 4 and 0 off at distances of 0.4 m, 1.2 m and beyond the radius of 1.5 m, volatility adds to a direct hit, five hits knock a player out, a player who is knocked out cannot walk, jump or throw, balloons pass through them, a splash on them does not lengthen the wait, they come back after exactly 180 ticks at their spawn point with full hit points, one who is knocked out in the air comes down, a player in the air takes less of a splash from the floor, and the state hash sees hit points and the wait left when they are all that differs.

## CI and Workflows

- `.github/workflows/ci.yml` job `rust` runs these tests on Rust 1.75 and stable. Job `determinism` runs `tv_server selftest` twice in separate processes and compares the output.
- `.github/workflows/bench.yml` runs `benches/benches/sim_bench.rs`.

## Fixes and Problems

### `rng.rs`
- Clippy flagged an unparenthesized multiply-then-shift in `below`. The expression was already correct under Rust precedence rules, and it now has explicit parentheses.

### `world.rs`
- A check with deliberate changes found two things redundant in the jump: the test that the vertical speed is zero when a jump starts, which a player on the floor always satisfies, and the vertical speed in the state hash, which follows from the height. Both were removed. Before that, no test could tell the height from the speed in the hash, because they only differ together.
- The tests joined a player with an input command, and then read the spawn heading back. The input carries its own heading, so it replaced the one the player spawned with and the test saw zero. The sim was right and the test was wrong. The tests now join with a throw, or with `join`, which exists so a client can learn where it starts without sending anything.
- A first check of the tests with deliberate bugs found that the hash test could not tell positions apart: a player walking and a player standing differed in their stick and quiet counter as well. It now compares two worlds that end on the same input and differ only in where the player is.

- A check with deliberate changes found the lines that put a returning player back on the floor redundant, because a player who is knocked out falls while they wait. They were removed.
- The same check found four weak tests. Two hash tests differed in more than hit points, because one world had thrown more balloons, so they would have passed with hit points left out of the hash. They now compare two worlds that differ in nothing else. A test of the wait used the constant in its own check, so it could not notice the constant changing, and a literal of three seconds was added. And no test had a player in the air under a burst on the floor, so the distance to the body, including height, was not covered until one was written.
- Nothing about the damage rules has been tried against a person.


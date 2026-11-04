// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "world.rs"
// ============================================================================

//! The authoritative world: players walking a round arena, balloons in flight, a
//! fixed tick, and the events each tick produces.

use crate::balloon::{dominant_compound, impact_outcome, total_volume_ml, validate_recipe};
use crate::chem::ChemBackend;
use crate::rng::SplitMix64;
use tv_proto::wire::{q_to_yaw, BalloonState, Command, Event, PlayerId, PlayerState, Snapshot};
use tv_proto::{BalloonId, Recipe, MAX_BALLOONS_PER_SNAPSHOT, MAX_PLAYERS};

/// Simulation ticks per second.
pub const TICK_HZ: u32 = 60;
/// Seconds per tick.
pub const DT: f32 = 1.0 / 60.0;
/// Downward acceleration in metres per second squared.
pub const GRAVITY: f32 = 9.81;

/// Radius of the round arena floor in metres. The client draws its walls here, and a
/// self-test in the client checks that both sides agree on the number.
pub const ARENA_RADIUS_M: f32 = 20.0;
/// Walking speed at full stick, in metres per second. Placeholder, same as the lab.
pub const WALK_SPEED_MS: f32 = 3.2;
/// How far from the arena wall the centre of a player has to stay, in metres.
pub const PLAYER_RADIUS_M: f32 = 0.3;
/// Ticks without an input command after which a walking player stops, so a client that
/// goes quiet does not leave its player running.
pub const INPUT_TIMEOUT_TICKS: u8 = 30;

// Placeholder launch rules: where a balloon leaves the hand, and how fast it goes.
const THROW_HEIGHT_M: f32 = 1.5;
const THROW_REACH_M: f32 = 0.5;
const SPEED_PER_POWER: f32 = 0.1;

// Where each player slot starts: eight points on a ring of 14 m, facing the middle.
// Constants instead of sine and cosine, so spawning cannot differ between machines.
const SPAWN_POINTS: [([f32; 2], u16); MAX_PLAYERS] = [
    ([0.0, 14.0], 0),
    ([9.8995, 9.8995], 57_344),
    ([14.0, 0.0], 49_152),
    ([9.8995, -9.8995], 40_960),
    ([0.0, -14.0], 32_768),
    ([-9.8995, -9.8995], 24_576),
    ([-14.0, 0.0], 16_384),
    ([-9.8995, 9.8995], 8_192),
];

#[derive(Debug, Clone)]
struct Balloon {
    id: BalloonId,
    owner: PlayerId,
    slot: u8,
    recipe: Recipe,
    pos: [f32; 3],
    vel: [f32; 3],
}

#[derive(Debug, Clone, Copy)]
struct Player {
    /// Position on the floor: x, then z.
    pos: [f32; 2],
    yaw_q: u16,
    forward: i8,
    strafe: i8,
    /// Ticks since the last input command, saturating.
    quiet: u8,
}

/// Authoritative simulation state, generic over the chemistry backend.
#[derive(Debug)]
pub struct World<C: ChemBackend> {
    tick: u32,
    rng: SplitMix64,
    next_id: BalloonId,
    players: [Option<Player>; MAX_PLAYERS],
    balloons: Vec<Balloon>,
    events: Vec<Event>,
    rejected: u32,
    chem: C,
}

fn mm(metres: f32) -> i32 {
    (metres * 1000.0).round() as i32
}

fn cms(metres_per_s: f32) -> i16 {
    ((metres_per_s * 100.0).round() as i32).clamp(i16::MIN as i32, i16::MAX as i32) as i16
}

impl<C: ChemBackend> World<C> {
    /// Creates an empty world. The seed feeds the RNG that chemistry backends may draw from.
    pub fn new(seed: u64, chem: C) -> Self {
        Self {
            tick: 0,
            rng: SplitMix64::new(seed),
            next_id: 0,
            players: [None; MAX_PLAYERS],
            balloons: Vec::new(),
            events: Vec::new(),
            rejected: 0,
            chem,
        }
    }

    /// Ticks completed so far.
    pub fn tick(&self) -> u32 {
        self.tick
    }

    /// Balloons currently in flight.
    pub fn balloon_count(&self) -> usize {
        self.balloons.len()
    }

    /// Players that have joined, which happens on the first command a player sends.
    pub fn player_count(&self) -> usize {
        self.players.iter().flatten().count()
    }

    /// Commands refused so far (bad recipe, zero aim, too many balloons, or a player id
    /// beyond [`MAX_PLAYERS`]).
    pub fn rejected(&self) -> u32 {
        self.rejected
    }

    /// Mutable access to the RNG, for chemistry backends that need randomness.
    pub fn rng_mut(&mut self) -> &mut SplitMix64 {
        &mut self.rng
    }

    /// Applies `commands` in order, then advances the world by one tick.
    pub fn step(&mut self, commands: &[(PlayerId, Command)]) {
        for (player, cmd) in commands {
            if !self.join(*player) {
                self.rejected += 1;
                continue;
            }
            match cmd {
                Command::Throw {
                    slot,
                    recipe,
                    dir,
                    power,
                } => self.throw(*player, *slot, recipe, *dir, *power),
                Command::Input {
                    forward,
                    strafe,
                    yaw_q,
                } => {
                    if let Some(p) = self.players[*player as usize].as_mut() {
                        p.forward = *forward;
                        p.strafe = *strafe;
                        p.yaw_q = *yaw_q;
                        p.quiet = 0;
                    }
                }
            }
        }
        self.walk();
        self.integrate();
        self.tick = self.tick.wrapping_add(1);
    }

    /// Makes sure `id` is in the match, putting a new player on the spawn point of that
    /// slot, facing the middle of the arena. Every command joins its sender this way, so
    /// calling it first is only needed to learn where the player starts. Returns false for
    /// an id the match has no room for.
    pub fn join(&mut self, id: PlayerId) -> bool {
        let Some(slot) = self.players.get_mut(id as usize) else {
            return false;
        };
        if slot.is_none() {
            let (pos, yaw_q) = SPAWN_POINTS[id as usize];
            *slot = Some(Player {
                pos,
                yaw_q,
                forward: 0,
                strafe: 0,
                quiet: INPUT_TIMEOUT_TICKS,
            });
        }
        true
    }

    /// Moves every player by the stick they last sent, and keeps them inside the arena.
    fn walk(&mut self) {
        for p in self.players.iter_mut().flatten() {
            p.quiet = p.quiet.saturating_add(1);
            if p.quiet >= INPUT_TIMEOUT_TICKS {
                p.forward = 0;
                p.strafe = 0;
            }
            if p.forward == 0 && p.strafe == 0 {
                continue;
            }
            let (sin, cos) = q_to_yaw(p.yaw_q).sin_cos();
            // Yaw 0 looks toward -z and a quarter turn looks toward +x.
            let ahead = [sin, -cos];
            let right = [cos, sin];
            let f = p.forward as f32 / 127.0;
            let s = p.strafe as f32 / 127.0;
            let wish = [right[0] * s + ahead[0] * f, right[1] * s + ahead[1] * f];
            let len = (wish[0] * wish[0] + wish[1] * wish[1]).sqrt();
            let scale = if len > 1.0 { 1.0 / len } else { 1.0 };
            p.pos[0] += wish[0] * scale * WALK_SPEED_MS * DT;
            p.pos[1] += wish[1] * scale * WALK_SPEED_MS * DT;
            let limit = ARENA_RADIUS_M - PLAYER_RADIUS_M;
            let dist = (p.pos[0] * p.pos[0] + p.pos[1] * p.pos[1]).sqrt();
            if dist > limit {
                p.pos[0] *= limit / dist;
                p.pos[1] *= limit / dist;
            }
        }
    }

    fn throw(&mut self, owner: PlayerId, slot: u8, recipe: &Recipe, dir: [i16; 3], power: u8) {
        let len = {
            let [x, y, z] = dir.map(|d| d as f32);
            (x * x + y * y + z * z).sqrt()
        };
        if validate_recipe(recipe).is_err()
            || len == 0.0
            || self.balloons.len() >= MAX_BALLOONS_PER_SNAPSHOT
        {
            self.rejected += 1;
            return;
        }
        let Some(thrower) = self.players[owner as usize] else {
            self.rejected += 1;
            return;
        };
        let aim = dir.map(|d| d as f32 / len);
        let speed = power as f32 * SPEED_PER_POWER;
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1);
        self.balloons.push(Balloon {
            id,
            owner,
            slot,
            recipe: recipe.clone(),
            pos: [
                thrower.pos[0] + aim[0] * THROW_REACH_M,
                THROW_HEIGHT_M + aim[1] * THROW_REACH_M,
                thrower.pos[1] + aim[2] * THROW_REACH_M,
            ],
            vel: aim.map(|a| a * speed),
        });
    }

    fn integrate(&mut self) {
        let Self {
            balloons,
            events,
            chem,
            ..
        } = self;
        balloons.retain_mut(|b| {
            // Semi-implicit Euler: update velocity first, then position.
            b.vel[1] -= GRAVITY * DT;
            for axis in 0..3 {
                b.pos[axis] += b.vel[axis] * DT;
            }
            // A balloon that reaches the wall bursts on it, at the height it hit.
            let dist = (b.pos[0] * b.pos[0] + b.pos[2] * b.pos[2]).sqrt();
            let hit_wall = dist > ARENA_RADIUS_M;
            if !hit_wall && b.pos[1] > 0.0 {
                return true;
            }
            if hit_wall {
                b.pos[0] *= ARENA_RADIUS_M / dist;
                b.pos[2] *= ARENA_RADIUS_M / dist;
            }
            let outcome = impact_outcome(&b.recipe, chem);
            let volatility = outcome.volatility.clamp(0.0, 1.0);
            // Placeholder area-of-effect rule: base radius plus volume scaled by volatility.
            let radius = 500.0 + total_volume_ml(&b.recipe) as f32 * (1.0 + 4.0 * volatility);
            let height = if hit_wall { b.pos[1].max(0.0) } else { 0.0 };
            events.push(Event::Detonate {
                balloon: b.id,
                compound: dominant_compound(&b.recipe),
                volatility_q: (volatility * 255.0).round() as u8,
                pos_mm: [mm(b.pos[0]), mm(height), mm(b.pos[2])],
                radius_mm: radius as u32,
            });
            false
        });
    }

    /// Takes the events produced since the last call.
    pub fn drain_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
    }

    /// Current state in wire form.
    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            tick: self.tick,
            players: self
                .players
                .iter()
                .enumerate()
                .filter_map(|(id, p)| {
                    p.map(|p| PlayerState {
                        id: id as PlayerId,
                        pos_mm: [mm(p.pos[0]), 0, mm(p.pos[1])],
                        yaw_q: p.yaw_q,
                        flags: 0,
                    })
                })
                .collect(),
            balloons: self
                .balloons
                .iter()
                .map(|b| BalloonState {
                    id: b.id,
                    owner: b.owner,
                    compound: dominant_compound(&b.recipe),
                    pos_mm: b.pos.map(mm),
                    vel_cms: b.vel.map(cms),
                    flags: b.slot,
                })
                .collect(),
        }
    }

    /// FNV-1a hash of everything that defines the simulation state. Two runs
    /// with the same seed and commands must produce the same value.
    pub fn state_hash(&self) -> u64 {
        let mut h = Fnv::new();
        h.u64(self.tick as u64);
        h.u64(self.rng.state());
        h.u64(self.next_id as u64);
        h.u64(self.rejected as u64);
        for (id, p) in self.players.iter().enumerate() {
            if let Some(p) = p {
                h.u64(id as u64);
                h.u64(p.yaw_q as u64);
                h.u64(p.forward as u8 as u64);
                h.u64(p.strafe as u8 as u64);
                h.u64(p.quiet as u64);
                h.u64(p.pos[0].to_bits() as u64);
                h.u64(p.pos[1].to_bits() as u64);
            }
        }
        for b in &self.balloons {
            h.u64(b.id as u64);
            h.u64(b.owner as u64);
            h.u64(b.slot as u64);
            for c in &b.recipe.chambers {
                h.u64(c.compound as u64);
                h.u64(c.volume_ml as u64);
            }
            for v in b.pos.iter().chain(b.vel.iter()) {
                h.u64(v.to_bits() as u64);
            }
        }
        h.finish()
    }
}

struct Fnv(u64);

impl Fnv {
    fn new() -> Self {
        Fnv(0xcbf2_9ce4_8422_2325)
    }

    fn u64(&mut self, v: u64) {
        for byte in v.to_le_bytes() {
            self.0 ^= byte as u64;
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01B3);
        }
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

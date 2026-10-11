// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "world.rs"
// ============================================================================

//! The authoritative world: balloons in flight, a fixed tick, and the events
//! each tick produces.

use crate::balloon::{dominant_compound, impact_outcome, total_volume_ml, validate_recipe};
use crate::chem::ChemBackend;
use crate::rng::SplitMix64;
use tv_proto::wire::{BalloonState, Command, Event, PlayerId, Snapshot};
use tv_proto::{BalloonId, Recipe, MAX_BALLOONS_PER_SNAPSHOT};

/// Simulation ticks per second.
pub const TICK_HZ: u32 = 60;
/// Seconds per tick.
pub const DT: f32 = 1.0 / 60.0;
/// Downward acceleration in metres per second squared.
pub const GRAVITY: f32 = 9.81;

// Placeholder launch rules until players exist in the sim.
const SPAWN_HEIGHT_M: f32 = 1.5;
const SPAWN_SPACING_M: f32 = 2.0;
const SPEED_PER_POWER: f32 = 0.1;

#[derive(Debug, Clone)]
struct Balloon {
    id: BalloonId,
    owner: PlayerId,
    recipe: Recipe,
    pos: [f32; 3],
    vel: [f32; 3],
}

/// Authoritative simulation state, generic over the chemistry backend.
#[derive(Debug)]
pub struct World<C: ChemBackend> {
    tick: u32,
    rng: SplitMix64,
    next_id: BalloonId,
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

    /// Commands refused so far (bad recipe, zero aim, or too many balloons).
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
            match cmd {
                Command::Throw { recipe, dir, power } => self.throw(*player, recipe, *dir, *power),
            }
        }
        self.integrate();
        self.tick = self.tick.wrapping_add(1);
    }

    fn throw(&mut self, owner: PlayerId, recipe: &Recipe, dir: [i16; 3], power: u8) {
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
        let speed = power as f32 * SPEED_PER_POWER;
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1);
        self.balloons.push(Balloon {
            id,
            owner,
            recipe: recipe.clone(),
            pos: [owner as f32 * SPAWN_SPACING_M, SPAWN_HEIGHT_M, 0.0],
            vel: dir.map(|d| d as f32 / len * speed),
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
            if b.pos[1] > 0.0 {
                return true;
            }
            let outcome = impact_outcome(&b.recipe, chem);
            let volatility = outcome.volatility.clamp(0.0, 1.0);
            // Placeholder area-of-effect rule: base radius plus volume scaled by volatility.
            let radius = 500.0 + total_volume_ml(&b.recipe) as f32 * (1.0 + 4.0 * volatility);
            events.push(Event::Detonate {
                balloon: b.id,
                compound: dominant_compound(&b.recipe),
                volatility_q: (volatility * 255.0).round() as u8,
                pos_mm: [mm(b.pos[0]), 0, mm(b.pos[2])],
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
            balloons: self
                .balloons
                .iter()
                .map(|b| BalloonState {
                    id: b.id,
                    owner: b.owner,
                    compound: dominant_compound(&b.recipe),
                    pos_mm: b.pos.map(mm),
                    vel_cms: b.vel.map(cms),
                    flags: 0,
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
        for b in &self.balloons {
            h.u64(b.id as u64);
            h.u64(b.owner as u64);
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

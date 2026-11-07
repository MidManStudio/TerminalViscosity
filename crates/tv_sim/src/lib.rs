// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "lib.rs"
// ============================================================================

//! Deterministic fixed-step simulation core for Terminal Viscosity.
//!
//! Commands go in, snapshots and events come out. Nothing here touches the
//! network or the renderer, so the same code runs inside a dedicated server, a
//! listen server, or a local single-player session.

pub mod balloon;
pub mod chem;
pub mod rng;
pub mod testkit;
pub mod world;

pub use chem::{ChemBackend, NullChem, Outcome, TableChem};
pub use rng::SplitMix64;
pub use world::{
    World, ARENA_RADIUS_M, DAMAGE_BASE_HP, DAMAGE_VOLATILE_HP, DT, INPUT_TIMEOUT_TICKS,
    JUMP_SPEED_MS, PLAYER_BODY_HEIGHT_M, PLAYER_BODY_RADIUS_M, PLAYER_RADIUS_M, RESPAWN_TICKS,
    TICK_HZ, WALK_SPEED_MS,
};

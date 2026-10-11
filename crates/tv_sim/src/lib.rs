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
pub use world::{World, DT, TICK_HZ};

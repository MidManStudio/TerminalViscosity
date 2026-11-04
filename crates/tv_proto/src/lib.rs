// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_proto.md, section "lib.rs"
// ============================================================================

//! Wire protocol and balloon art codec for Terminal Viscosity.
//!
//! No dependencies. Every decoder returns an error on bad input and never
//! panics, so it is safe to point at untrusted network bytes.

pub mod art;
pub mod codec;
pub mod wire;

pub use codec::DecodeError;
pub use wire::{
    q_to_yaw, yaw_to_q, BalloonId, BalloonState, Chamber, Command, CompoundId, Event, PlayerId,
    PlayerState, Recipe, Snapshot,
};

/// Bumped whenever an encoded layout changes.
pub const PROTOCOL_VERSION: u16 = 2;

/// Largest datagram payload the snapshot encoder is allowed to produce.
/// 1200 bytes stays under the usual path MTU once IP and UDP/QUIC headers are added.
pub const MAX_PAYLOAD_BYTES: usize = 1200;

/// Most balloons that fit in one snapshot datagram next to a full player list:
/// 7 header bytes + 8 players * 16 + 40 balloons * 24 = 1095 bytes.
pub const MAX_BALLOONS_PER_SNAPSHOT: usize = 40;

/// Most players one match holds, and so the most in one snapshot.
pub const MAX_PLAYERS: usize = 8;

/// Most chambers one balloon recipe may carry.
pub const MAX_CHAMBERS: usize = 4;

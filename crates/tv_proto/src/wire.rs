// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_proto.md, section "wire.rs"
// ============================================================================

//! Commands, events, and snapshots as they travel between client and server.
//!
//! Positions are fixed-point millimetres and velocities are centimetres per
//! second, so a balloon costs a fixed 24 bytes in a snapshot.

use crate::codec::{DecodeError, EncodeError, Reader, Writer};
use crate::{MAX_BALLOONS_PER_SNAPSHOT, MAX_CHAMBERS};

/// Index of a connected player.
pub type PlayerId = u8;
/// Server-assigned balloon identifier.
pub type BalloonId = u16;
/// Index into the compound table.
pub type CompoundId = u16;

const TAG_SNAPSHOT: u8 = 0x01;
const TAG_CMD_THROW: u8 = 0x10;
const TAG_EVT_DETONATE: u8 = 0x20;
const TAG_EVENT_LIST: u8 = 0x21;

/// Bytes one balloon occupies inside a snapshot.
pub const BALLOON_STATE_BYTES: usize = 24;
/// Bytes of snapshot header (tag, tick, count).
pub const SNAPSHOT_HEADER_BYTES: usize = 6;

/// One sealed compartment of a balloon.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Chamber {
    /// What the compartment holds.
    pub compound: CompoundId,
    /// Fill volume in millilitres.
    pub volume_ml: u16,
}

/// The crafted contents of one balloon. Membranes sit between neighbouring chambers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Recipe {
    /// One to [`MAX_CHAMBERS`] chambers.
    pub chambers: Vec<Chamber>,
}

impl Recipe {
    fn write(&self, w: &mut Writer) {
        w.u8(self.chambers.len() as u8);
        for c in &self.chambers {
            w.u16(c.compound);
            w.u16(c.volume_ml);
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        let n = r.u8()? as usize;
        if n == 0 {
            return Err(DecodeError::BadValue("chamber count"));
        }
        if n > MAX_CHAMBERS {
            return Err(DecodeError::TooMany {
                got: n,
                max: MAX_CHAMBERS,
            });
        }
        let mut chambers = Vec::with_capacity(n);
        for _ in 0..n {
            chambers.push(Chamber {
                compound: r.u16()?,
                volume_ml: r.u16()?,
            });
        }
        Ok(Self { chambers })
    }
}

/// Client to server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    /// Throw a balloon. The recipe travels with the throw until an inventory design exists.
    Throw {
        /// Contents of the balloon.
        recipe: Recipe,
        /// Aim direction, not required to be normalized.
        dir: [i16; 3],
        /// 0 to 255, mapped to launch speed by the simulation.
        power: u8,
    },
}

impl Command {
    /// Encodes the command to wire bytes.
    pub fn encode(&self) -> Vec<u8> {
        let mut w = Writer::with_capacity(32);
        match self {
            Command::Throw { recipe, dir, power } => {
                w.u8(TAG_CMD_THROW);
                recipe.write(&mut w);
                for d in dir {
                    w.i16(*d);
                }
                w.u8(*power);
            }
        }
        w.finish()
    }

    /// Decodes one command, rejecting truncated, malformed, or trailing bytes.
    pub fn decode(bytes: &[u8]) -> Result<Self, DecodeError> {
        let mut r = Reader::new(bytes);
        let out = match r.u8()? {
            TAG_CMD_THROW => {
                let recipe = Recipe::read(&mut r)?;
                let dir = [r.i16()?, r.i16()?, r.i16()?];
                let power = r.u8()?;
                Command::Throw { recipe, dir, power }
            }
            t => return Err(DecodeError::BadTag(t)),
        };
        r.finish()?;
        Ok(out)
    }
}

/// Server to client, once per occurrence.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    /// A balloon burst.
    Detonate {
        /// Which balloon.
        balloon: BalloonId,
        /// Dominant compound, used to pick effect colors.
        compound: CompoundId,
        /// 0 to 255, where 255 is fully volatile.
        volatility_q: u8,
        /// Impact point in millimetres.
        pos_mm: [i32; 3],
        /// Area-of-effect radius in millimetres.
        radius_mm: u32,
    },
}

impl Event {
    fn write(&self, w: &mut Writer) {
        match self {
            Event::Detonate {
                balloon,
                compound,
                volatility_q,
                pos_mm,
                radius_mm,
            } => {
                w.u8(TAG_EVT_DETONATE);
                w.u16(*balloon);
                w.u16(*compound);
                w.u8(*volatility_q);
                for p in pos_mm {
                    w.i32(*p);
                }
                w.u32(*radius_mm);
            }
        }
    }

    fn read(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        match r.u8()? {
            TAG_EVT_DETONATE => Ok(Event::Detonate {
                balloon: r.u16()?,
                compound: r.u16()?,
                volatility_q: r.u8()?,
                pos_mm: [r.i32()?, r.i32()?, r.i32()?],
                radius_mm: r.u32()?,
            }),
            t => Err(DecodeError::BadTag(t)),
        }
    }
}

/// Encodes a batch of events into one datagram payload.
pub fn encode_events(events: &[Event]) -> Result<Vec<u8>, EncodeError> {
    if events.len() > u8::MAX as usize {
        return Err(EncodeError::TooMany {
            got: events.len(),
            max: u8::MAX as usize,
        });
    }
    let mut w = Writer::with_capacity(2 + events.len() * 22);
    w.u8(TAG_EVENT_LIST);
    w.u8(events.len() as u8);
    for e in events {
        e.write(&mut w);
    }
    Ok(w.finish())
}

/// Decodes a batch produced by [`encode_events`].
pub fn decode_events(bytes: &[u8]) -> Result<Vec<Event>, DecodeError> {
    let mut r = Reader::new(bytes);
    match r.u8()? {
        TAG_EVENT_LIST => {}
        t => return Err(DecodeError::BadTag(t)),
    }
    let n = r.u8()? as usize;
    // Each event needs at least one byte, so a count beyond the remainder is hostile.
    if n > r.remaining() {
        return Err(DecodeError::UnexpectedEnd);
    }
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        out.push(Event::read(&mut r)?);
    }
    r.finish()?;
    Ok(out)
}

/// High-level state of one balloon in flight. Soft-body nodes are never sent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BalloonState {
    /// Balloon identifier.
    pub id: BalloonId,
    /// Who threw it.
    pub owner: PlayerId,
    /// Dominant compound, for rendering.
    pub compound: CompoundId,
    /// Position in millimetres.
    pub pos_mm: [i32; 3],
    /// Velocity in centimetres per second.
    pub vel_cms: [i16; 3],
    /// Reserved, zero for now.
    pub flags: u8,
}

/// Authoritative world state sent at the snapshot rate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    /// Simulation tick this snapshot describes.
    pub tick: u32,
    /// Balloons in flight, in creation order.
    pub balloons: Vec<BalloonState>,
}

impl Snapshot {
    /// Encodes the snapshot. Fails if it would not fit one datagram.
    pub fn encode(&self) -> Result<Vec<u8>, EncodeError> {
        if self.balloons.len() > MAX_BALLOONS_PER_SNAPSHOT {
            return Err(EncodeError::TooMany {
                got: self.balloons.len(),
                max: MAX_BALLOONS_PER_SNAPSHOT,
            });
        }
        let mut w = Writer::with_capacity(
            SNAPSHOT_HEADER_BYTES + self.balloons.len() * BALLOON_STATE_BYTES,
        );
        w.u8(TAG_SNAPSHOT);
        w.u32(self.tick);
        w.u8(self.balloons.len() as u8);
        for b in &self.balloons {
            w.u16(b.id);
            w.u8(b.owner);
            w.u16(b.compound);
            for p in b.pos_mm {
                w.i32(p);
            }
            for v in b.vel_cms {
                w.i16(v);
            }
            w.u8(b.flags);
        }
        Ok(w.finish())
    }

    /// Decodes a snapshot, rejecting truncated, oversized, or trailing input.
    pub fn decode(bytes: &[u8]) -> Result<Self, DecodeError> {
        let mut r = Reader::new(bytes);
        match r.u8()? {
            TAG_SNAPSHOT => {}
            t => return Err(DecodeError::BadTag(t)),
        }
        let tick = r.u32()?;
        let n = r.u8()? as usize;
        if n > MAX_BALLOONS_PER_SNAPSHOT {
            return Err(DecodeError::TooMany {
                got: n,
                max: MAX_BALLOONS_PER_SNAPSHOT,
            });
        }
        let mut balloons = Vec::with_capacity(n);
        for _ in 0..n {
            balloons.push(BalloonState {
                id: r.u16()?,
                owner: r.u8()?,
                compound: r.u16()?,
                pos_mm: [r.i32()?, r.i32()?, r.i32()?],
                vel_cms: [r.i16()?, r.i16()?, r.i16()?],
                flags: r.u8()?,
            });
        }
        r.finish()?;
        Ok(Self { tick, balloons })
    }
}

// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_ffi.md, section "lib.rs"
// ============================================================================

//! C ABI over the simulation. The matching header is `include/tv.h`.
//!
//! Rules every function follows: pointers are checked for null, buffer sizes
//! are checked before copying, and a Rust panic is turned into `TV_ERR_PANIC`
//! instead of unwinding into the caller.

// This crate is the one place raw pointers are allowed. Every unsafe block carries a SAFETY note.
#![allow(unsafe_code)]

use std::panic::{catch_unwind, AssertUnwindSafe};
use tv_proto::wire::{decode_events, encode_events, Command, Event, Snapshot};
use tv_proto::{Chamber, Recipe, MAX_CHAMBERS};
use tv_sim::{NullChem, World};

/// Bumped whenever any signature or struct layout in `tv.h` changes.
pub const TV_ABI_VERSION: u32 = 1;
/// Success.
pub const TV_OK: i32 = 0;
/// A required pointer was null.
pub const TV_ERR_NULL: i32 = -1;
/// Input bytes did not decode.
pub const TV_ERR_DECODE: i32 = -2;
/// The output buffer was too small.
pub const TV_ERR_CAPACITY: i32 = -3;
/// An argument was out of range.
pub const TV_ERR_ARG: i32 = -4;
/// A Rust panic was caught at the boundary.
pub const TV_ERR_PANIC: i32 = -99;

/// Opaque handle owned by the caller between `tv_world_new` and `tv_world_free`.
pub struct TvWorld {
    world: World<NullChem>,
    pending: Vec<(u8, Command)>,
    events: Vec<Event>,
}

/// One chamber of a recipe, as passed to `tv_encode_throw`.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct TvChamber {
    /// Compound id.
    pub compound: u16,
    /// Fill in millilitres.
    pub volume_ml: u16,
}

/// A balloon in a decoded snapshot.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct TvBalloonView {
    /// Balloon id.
    pub id: u16,
    /// Owning player.
    pub owner: u8,
    /// Reserved flags.
    pub flags: u8,
    /// Dominant compound.
    pub compound: u16,
    /// Padding, always zero.
    pub reserved: u16,
    /// Position in millimetres.
    pub pos_mm: [i32; 3],
    /// Velocity in centimetres per second.
    pub vel_cms: [i16; 3],
    /// Padding, always zero.
    pub reserved2: i16,
}

/// A detonation in a decoded event batch.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct TvDetonateView {
    /// Balloon id.
    pub balloon: u16,
    /// Dominant compound.
    pub compound: u16,
    /// 0 to 255.
    pub volatility_q: u8,
    /// Padding, always zero.
    pub reserved: [u8; 3],
    /// Impact point in millimetres.
    pub pos_mm: [i32; 3],
    /// Area-of-effect radius in millimetres.
    pub radius_mm: u32,
}

fn guard(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(TV_ERR_PANIC)
}

/// # Safety
/// `ptr` must be null or valid for reads of `len` bytes for the whole call.
unsafe fn bytes_in<'a>(ptr: *const u8, len: u32) -> Option<&'a [u8]> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: the caller guarantees `len` readable bytes and null was ruled out above.
    Some(unsafe { std::slice::from_raw_parts(ptr, len as usize) })
}

/// # Safety
/// `ptr` must be null or valid for writes of `cap` bytes for the whole call.
unsafe fn bytes_out<'a>(ptr: *mut u8, cap: u32) -> Option<&'a mut [u8]> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: the caller guarantees `cap` writable bytes and null was ruled out above.
    Some(unsafe { std::slice::from_raw_parts_mut(ptr, cap as usize) })
}

fn copy_out(src: &[u8], out: &mut [u8]) -> i32 {
    if src.len() > out.len() {
        return TV_ERR_CAPACITY;
    }
    out[..src.len()].copy_from_slice(src);
    src.len() as i32
}

/// ABI version this library was built with.
#[no_mangle]
pub extern "C" fn tv_abi_version() -> u32 {
    TV_ABI_VERSION
}

/// `sizeof(TvChamber)`.
#[no_mangle]
pub extern "C" fn tv_sizeof_chamber() -> u32 {
    std::mem::size_of::<TvChamber>() as u32
}

/// `sizeof(TvBalloonView)`.
#[no_mangle]
pub extern "C" fn tv_sizeof_balloon_view() -> u32 {
    std::mem::size_of::<TvBalloonView>() as u32
}

/// `sizeof(TvDetonateView)`.
#[no_mangle]
pub extern "C" fn tv_sizeof_detonate_view() -> u32 {
    std::mem::size_of::<TvDetonateView>() as u32
}

/// Creates a world. Returns null if creation failed. Free it with `tv_world_free`.
#[no_mangle]
pub extern "C" fn tv_world_new(seed: u64) -> *mut TvWorld {
    catch_unwind(|| {
        Box::into_raw(Box::new(TvWorld {
            world: World::new(seed, NullChem),
            pending: Vec::new(),
            events: Vec::new(),
        }))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Frees a world. Null is allowed and ignored.
///
/// # Safety
/// `w` must be null or a pointer from `tv_world_new` that has not been freed yet.
#[no_mangle]
pub unsafe extern "C" fn tv_world_free(w: *mut TvWorld) {
    if !w.is_null() {
        // SAFETY: non-null, and the caller promises it came from `tv_world_new` and is freed once.
        drop(unsafe { Box::from_raw(w) });
    }
}

/// Encodes a throw command into `out`. Returns bytes written or a negative error.
///
/// # Safety
/// `chambers` must be valid for `n` reads and `out` for `cap` writes.
#[no_mangle]
pub unsafe extern "C" fn tv_encode_throw(
    chambers: *const TvChamber,
    n: u32,
    dx: i16,
    dy: i16,
    dz: i16,
    power: u8,
    out: *mut u8,
    cap: u32,
) -> i32 {
    guard(|| {
        if chambers.is_null() {
            return TV_ERR_NULL;
        }
        if n == 0 || n as usize > MAX_CHAMBERS {
            return TV_ERR_ARG;
        }
        // SAFETY: non-null, and the caller promises `n` readable elements.
        let list = unsafe { std::slice::from_raw_parts(chambers, n as usize) };
        let recipe = Recipe {
            chambers: list
                .iter()
                .map(|c| Chamber {
                    compound: c.compound,
                    volume_ml: c.volume_ml,
                })
                .collect(),
        };
        let bytes = Command::Throw {
            recipe,
            dir: [dx, dy, dz],
            power,
        }
        .encode();
        // SAFETY: the caller promises `cap` writable bytes at `out`.
        match unsafe { bytes_out(out, cap) } {
            Some(buf) => copy_out(&bytes, buf),
            None => TV_ERR_NULL,
        }
    })
}

/// Queues one wire-encoded command from `player` for the next step.
///
/// # Safety
/// `w` must be a live world and `bytes` valid for `len` reads.
#[no_mangle]
pub unsafe extern "C" fn tv_world_submit(
    w: *mut TvWorld,
    player: u8,
    bytes: *const u8,
    len: u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller promises `w` is null or a live world.
        let Some(w) = (unsafe { w.as_mut() }) else {
            return TV_ERR_NULL;
        };
        // SAFETY: the caller promises `len` readable bytes at `bytes`.
        let Some(data) = (unsafe { bytes_in(bytes, len) }) else {
            return TV_ERR_NULL;
        };
        match Command::decode(data) {
            Ok(cmd) => {
                w.pending.push((player, cmd));
                TV_OK
            }
            Err(_) => TV_ERR_DECODE,
        }
    })
}

/// Applies queued commands and advances one tick. Returns the number of new events.
///
/// # Safety
/// `w` must be a live world.
#[no_mangle]
pub unsafe extern "C" fn tv_world_step(w: *mut TvWorld) -> i32 {
    guard(|| {
        // SAFETY: the caller promises `w` is null or a live world.
        let Some(w) = (unsafe { w.as_mut() }) else {
            return TV_ERR_NULL;
        };
        let cmds = std::mem::take(&mut w.pending);
        w.world.step(&cmds);
        let fresh = w.world.drain_events();
        let n = fresh.len() as i32;
        w.events.extend(fresh);
        n
    })
}

/// Writes the current snapshot into `out`. Returns bytes written or a negative error.
///
/// # Safety
/// `w` must be a live world and `out` valid for `cap` writes.
#[no_mangle]
pub unsafe extern "C" fn tv_world_snapshot(w: *const TvWorld, out: *mut u8, cap: u32) -> i32 {
    guard(|| {
        // SAFETY: the caller promises `w` is null or a live world.
        let Some(w) = (unsafe { w.as_ref() }) else {
            return TV_ERR_NULL;
        };
        // SAFETY: the caller promises `cap` writable bytes at `out`.
        let Some(buf) = (unsafe { bytes_out(out, cap) }) else {
            return TV_ERR_NULL;
        };
        match w.world.snapshot().encode() {
            Ok(bytes) => copy_out(&bytes, buf),
            Err(_) => TV_ERR_CAPACITY,
        }
    })
}

/// Writes all pending events into `out` and clears them. On error the events are kept.
///
/// # Safety
/// `w` must be a live world and `out` valid for `cap` writes.
#[no_mangle]
pub unsafe extern "C" fn tv_world_take_events(w: *mut TvWorld, out: *mut u8, cap: u32) -> i32 {
    guard(|| {
        // SAFETY: the caller promises `w` is null or a live world.
        let Some(w) = (unsafe { w.as_mut() }) else {
            return TV_ERR_NULL;
        };
        // SAFETY: the caller promises `cap` writable bytes at `out`.
        let Some(buf) = (unsafe { bytes_out(out, cap) }) else {
            return TV_ERR_NULL;
        };
        let Ok(bytes) = encode_events(&w.events) else {
            return TV_ERR_CAPACITY;
        };
        let written = copy_out(&bytes, buf);
        if written >= 0 {
            w.events.clear();
        }
        written
    })
}

/// Hash of the full simulation state, or 0 if `w` is null.
///
/// # Safety
/// `w` must be null or a live world.
#[no_mangle]
pub unsafe extern "C" fn tv_world_state_hash(w: *const TvWorld) -> u64 {
    // SAFETY: the caller promises `w` is null or a live world.
    match unsafe { w.as_ref() } {
        Some(w) => catch_unwind(AssertUnwindSafe(|| w.world.state_hash())).unwrap_or(0),
        None => 0,
    }
}

/// Decodes a snapshot into `out`. Returns the balloon count, and stores the tick in `out_tick`.
/// If `out_cap` is smaller than the count, returns `TV_ERR_CAPACITY`.
///
/// # Safety
/// `buf` valid for `len` reads, `out` valid for `out_cap` elements, `out_tick` valid for one write.
#[no_mangle]
pub unsafe extern "C" fn tv_snapshot_decode(
    buf: *const u8,
    len: u32,
    out: *mut TvBalloonView,
    out_cap: u32,
    out_tick: *mut u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller promises `len` readable bytes at `buf`.
        let Some(data) = (unsafe { bytes_in(buf, len) }) else {
            return TV_ERR_NULL;
        };
        if out.is_null() || out_tick.is_null() {
            return TV_ERR_NULL;
        }
        let Ok(snap) = Snapshot::decode(data) else {
            return TV_ERR_DECODE;
        };
        if snap.balloons.len() > out_cap as usize {
            return TV_ERR_CAPACITY;
        }
        // SAFETY: non-null, and the caller promises room for `out_cap` elements.
        let views = unsafe { std::slice::from_raw_parts_mut(out, out_cap as usize) };
        for (view, b) in views.iter_mut().zip(&snap.balloons) {
            *view = TvBalloonView {
                id: b.id,
                owner: b.owner,
                flags: b.flags,
                compound: b.compound,
                reserved: 0,
                pos_mm: b.pos_mm,
                vel_cms: b.vel_cms,
                reserved2: 0,
            };
        }
        // SAFETY: non-null, and the caller promises one writable u32.
        unsafe { *out_tick = snap.tick };
        snap.balloons.len() as i32
    })
}

/// Decodes an event batch into `out`. Returns the event count.
///
/// # Safety
/// `buf` valid for `len` reads and `out` valid for `out_cap` elements.
#[no_mangle]
pub unsafe extern "C" fn tv_events_decode(
    buf: *const u8,
    len: u32,
    out: *mut TvDetonateView,
    out_cap: u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller promises `len` readable bytes at `buf`.
        let Some(data) = (unsafe { bytes_in(buf, len) }) else {
            return TV_ERR_NULL;
        };
        if out.is_null() {
            return TV_ERR_NULL;
        }
        let Ok(events) = decode_events(data) else {
            return TV_ERR_DECODE;
        };
        if events.len() > out_cap as usize {
            return TV_ERR_CAPACITY;
        }
        // SAFETY: non-null, and the caller promises room for `out_cap` elements.
        let views = unsafe { std::slice::from_raw_parts_mut(out, out_cap as usize) };
        for (view, e) in views.iter_mut().zip(&events) {
            let Event::Detonate {
                balloon,
                compound,
                volatility_q,
                pos_mm,
                radius_mm,
            } = *e;
            *view = TvDetonateView {
                balloon,
                compound,
                volatility_q,
                reserved: [0; 3],
                pos_mm,
                radius_mm,
            };
        }
        events.len() as i32
    })
}

// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "tv_ffi.odin"
// ============================================================================

package main

// Bindings for crates/tv_ffi/include/tv.h. Keep the two in step, and bump
// TV_ABI_VERSION on both sides together.

TV_ABI_VERSION :: 1

TV_OK :: 0
TV_ERR_NULL :: -1
TV_ERR_DECODE :: -2
TV_ERR_CAPACITY :: -3
TV_ERR_ARG :: -4
TV_ERR_PANIC :: -99

// Path to the Rust static library, relative to this file. Override with
// -define:TV_LIB=... for other targets such as the browser build.
TV_LIB :: #config(TV_LIB, "../../target/release/libtv_ffi.a")

// libs a Rust staticlib needs on Linux, from `rustc --print native-static-libs`.
// The Android build links through scripts/build_android.sh instead, so these are
// not used there.
when ODIN_OS == .Linux {
	foreign import tv {
		TV_LIB,
		"system:gcc_s",
		"system:util",
		"system:rt",
		"system:pthread",
		"system:m",
		"system:dl",
		"system:c",
	}
}

TvWorld :: struct {} // opaque, only ever used behind a pointer

TvChamber :: struct {
	compound:  u16,
	volume_ml: u16,
}

TvBalloonView :: struct {
	id:       u16,
	owner:    u8,
	flags:    u8,
	compound: u16,
	reserved: u16,
	pos_mm:   [3]i32,
	vel_cms:  [3]i16,
	reserved2: i16,
}

TvDetonateView :: struct {
	balloon:      u16,
	compound:     u16,
	volatility_q: u8,
	reserved:     [3]u8,
	pos_mm:       [3]i32,
	radius_mm:    u32,
}

#assert(size_of(TvChamber) == 4)
#assert(size_of(TvBalloonView) == 28)
#assert(size_of(TvDetonateView) == 24)

@(default_calling_convention = "c")
foreign tv {
	tv_abi_version :: proc() -> u32 ---
	tv_sizeof_chamber :: proc() -> u32 ---
	tv_sizeof_balloon_view :: proc() -> u32 ---
	tv_sizeof_detonate_view :: proc() -> u32 ---

	tv_world_new :: proc(seed: u64) -> ^TvWorld ---
	tv_world_free :: proc(w: ^TvWorld) ---

	tv_encode_throw :: proc(chambers: [^]TvChamber, n: u32, dx, dy, dz: i16, power: u8, out: [^]u8, cap: u32) -> i32 ---
	tv_world_submit :: proc(w: ^TvWorld, player: u8, bytes: [^]u8, len: u32) -> i32 ---
	tv_world_step :: proc(w: ^TvWorld) -> i32 ---
	tv_world_snapshot :: proc(w: ^TvWorld, out: [^]u8, cap: u32) -> i32 ---
	tv_world_take_events :: proc(w: ^TvWorld, out: [^]u8, cap: u32) -> i32 ---
	tv_world_state_hash :: proc(w: ^TvWorld) -> u64 ---

	tv_snapshot_decode :: proc(buf: [^]u8, len: u32, out: [^]TvBalloonView, out_cap: u32, out_tick: ^u32) -> i32 ---
	tv_events_decode :: proc(buf: [^]u8, len: u32, out: [^]TvDetonateView, out_cap: u32) -> i32 ---
}

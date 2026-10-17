// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "selftest.odin"
// ============================================================================

package main

import "core:fmt"
import "balloon"
import "softbody"

// Runs without a window: checks the ABI against the Rust library, plays one
// balloon through the simulation, steps the soft-body ring, and drops and
// hangs the 3D balloon. Returns a process exit code.
selftest :: proc() -> int {
	failures := 0
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}

	check(&failures, tv_abi_version() == TV_ABI_VERSION, "abi version matches")
	check(&failures, tv_sizeof_chamber() == size_of(TvChamber), "TvChamber size matches")
	check(&failures, tv_sizeof_balloon_view() == size_of(TvBalloonView), "TvBalloonView size matches")
	check(&failures, tv_sizeof_detonate_view() == size_of(TvDetonateView), "TvDetonateView size matches")
	if failures > 0 do return 1

	w := tv_world_new(5)
	defer tv_world_free(w)
	check(&failures, w != nil, "world created")
	if w == nil do return 1

	chambers := [2]TvChamber{{compound = 1, volume_ml = 100}, {compound = 2, volume_ml = 50}}
	cmd: [64]u8
	n := tv_encode_throw(raw_data(chambers[:]), 2, 0, 1000, 0, 100, raw_data(cmd[:]), len(cmd))
	check(&failures, n > 0, "throw command encoded")
	check(&failures, tv_world_submit(w, 1, raw_data(cmd[:]), u32(n)) == TV_OK, "command accepted")

	events: i32 = 0
	for _ in 0 ..< 400 {
		events += tv_world_step(w)
	}
	check(&failures, events == 1, "exactly one detonation after 400 ticks")

	snap: [1200]u8
	sn := tv_world_snapshot(w, raw_data(snap[:]), len(snap))
	views: [48]TvBalloonView
	tick: u32
	count := tv_snapshot_decode(raw_data(snap[:]), u32(sn), raw_data(views[:]), len(views), &tick)
	check(&failures, count == 0 && tick == 400, "snapshot decodes, balloon has landed")

	ev: [1200]u8
	en := tv_world_take_events(w, raw_data(ev[:]), len(ev))
	dets: [8]TvDetonateView
	dcount := tv_events_decode(raw_data(ev[:]), u32(en), raw_data(dets[:]), len(dets))
	check(&failures, dcount == 1 && dets[0].pos_mm[1] == 0, "detonation decodes at ground level")

	r: softbody.Ring
	softbody.ring_init(&r, {400, 200}, 80)
	r.floor_y = 600
	for _ in 0 ..< 300 do softbody.ring_step(&r, 1.0 / 60.0)
	area := softbody.ring_area(&r) / r.rest_area
	check(&failures, area > 0.85 && area < 1.15, "soft-body ring settles near rest area")

	selftest_balloon(&failures)

	fmt.printf("state_hash=%#016x\n", tv_world_state_hash(w))
	if failures == 0 {
		fmt.println("selftest passed")
		return 0
	}
	fmt.printf("selftest FAILED (%d)\n", failures)
	return 1
}

// Drops the 3D balloon on the floor, then lifts it by the tip, and checks the
// shapes it takes: flattened at rest, a teardrop when hanging, volume kept.
selftest_balloon :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}

	b := new(balloon.Balloon)
	defer free(b)
	balloon.init(b, balloon.default_config())
	balloon.reset(b, {0, 2.5, 0})
	for _ in 0 ..< 240 {
		balloon.step(b, 1.0 / 60.0)
	}
	lo, hi := balloon.bounds(b)
	ratio := balloon.volume(b) / b.target_volume
	check(failures, balloon.is_finite(b), "3D balloon stays finite after a drop")
	check(failures, ratio > 0.97 && ratio < 1.03, "3D balloon keeps its volume after landing")
	check(failures, lo.y > -0.001 && lo.y < 0.02 && balloon.max_speed(b) < 0.3, "3D balloon rests on the floor")

	for _ in 0 ..< 300 {
		balloon.pin(b, balloon.TIP, {0, 4.6, 0})
		balloon.step(b, 1.0 / 60.0)
	}
	lo, hi = balloon.bounds(b)
	width := max(hi.x - lo.x, hi.z - lo.z)
	ratio = balloon.volume(b) / b.target_volume
	check(failures, ratio > 0.97 && ratio < 1.03, "3D balloon keeps its volume while held by the tip")
	check(failures, (hi.y - lo.y) / width > 1.4, "3D balloon held by the tip is a tall teardrop")
	check(failures, b.pos[balloon.TIP].y == hi.y, "the tip is the highest point")
}

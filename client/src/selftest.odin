// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "selftest.odin"
// ============================================================================

package main

import "arena"
import "core:fmt"
import "balloon"
import "softbody"

// Runs without a window: checks the ABI against the Rust library, plays one
// balloon through the simulation, steps the soft-body ring, drops and hangs the 3D
// balloon, and plays a short match through the local host. Returns a process exit code.
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
	check(&failures, tv_sizeof_player_view() == size_of(TvPlayerView), "TvPlayerView size matches")
	check(&failures, tv_arena_radius_mm() == u32(arena.ARENA_RADIUS * 1000), "arena radius matches the simulation")
	if failures > 0 do return 1

	w := tv_world_new(5)
	defer tv_world_free(w)
	check(&failures, w != nil, "world created")
	if w == nil do return 1

	chambers := [2]TvChamber{{compound = 1, volume_ml = 100}, {compound = 2, volume_ml = 50}}
	cmd: [64]u8
	n := tv_encode_throw(raw_data(chambers[:]), 2, 1, 0, 1000, 0, 100, raw_data(cmd[:]), len(cmd))
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
	people: [8]TvPlayerView
	pcount := tv_snapshot_decode_players(raw_data(snap[:]), u32(sn), raw_data(people[:]), len(people))
	check(&failures, pcount == 1 && people[0].id == 1, "the thrower joined the match and the snapshot lists them")

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
	selftest_arena(&failures)

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

// Plays a short match through the local host, the way the arena scene does: walk, throw, and
// watch the balloon fly and burst, with everything coming back through the wire format.
selftest_arena :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}

	h := local_host_new(3, arena.LOCAL_PLAYER)
	check(failures, h != nil, "local host starts a match")
	if h == nil {
		return
	}
	defer local_host_free(h)
	host := local_host_table(h)
	view := arena.host_view(&host)
	p, found := arena.view_player(view, arena.LOCAL_PLAYER)
	at_spawn := abs(p.pos.x) < 0.001 && abs(p.pos.y) < 0.001 && abs(p.pos.z - 14) < 0.001
	check(failures, found && at_spawn && p.yaw == 0, "the player starts on its spawn point, facing the middle")

	// One second of walking forward, which is toward -z from the spawn point.
	for _ in 0 ..< 60 {
		arena.host_input(&host, {forward = 1, yaw = 0})
		arena.host_step(&host, TICK_DT)
	}
	p, _ = arena.view_player(view, arena.LOCAL_PLAYER)
	check(failures, abs(p.pos.z - (14 - 3.2)) < 0.08 && abs(p.pos.x) < 0.01, "the player walks at walking speed")

	// The heading the client sends is the heading the match keeps.
	// The view is a tick behind the world, since it is drawn between the last two, so it takes two.
	arena.host_input(&host, {yaw = 1})
	arena.host_step(&host, TICK_DT)
	arena.host_step(&host, TICK_DT)
	p, _ = arena.view_player(view, arena.LOCAL_PLAYER)
	check(failures, abs(p.yaw - 1) < 0.002, "the heading the client sends is the one the match keeps")

	// Lets a balloon fly until it bursts: how many bursts there were, the last one, and the
	// last place the balloon was seen in the air.
	fly :: proc(host: ^arena.Host, view: ^arena.Match_View) -> (bursts: int, burst: arena.Burst, last: arena.Vec3) {
		for _ in 0 ..< 240 {
			arena.host_step(host, TICK_DT)
			if view.balloon_count == 1 {
				last = view.balloons[0].pos
			}
			for i in 0 ..< view.burst_count {
				bursts += 1
				burst = view.bursts[i]
			}
		}
		return
	}

	// A throw from slot 2, level and a little upward, at a medium power: 12 m/s along the
	// look direction, less two ticks of gravity.
	arena.host_input(&host, {})
	dir := arena.look_dir({yaw = 0, pitch = 0.3})
	check(failures, arena.host_throw(&host, {slot = 2, compound = 4, ml = 300, dir = dir, power = 120}), "a throw is accepted")
	arena.host_step(&host, TICK_DT)
	arena.host_step(&host, TICK_DT)
	check(failures, view.balloon_count == 1, "the balloon is in the air")
	flown_id: u16
	if view.balloon_count == 1 {
		b := view.balloons[0]
		flown_id = b.id
		check(failures, b.slot == 2 && b.compound == 4 && b.owner == arena.LOCAL_PLAYER, "it carries its slot, compound, and owner")
		check(failures, abs(b.pos.x - p.pos.x) < 1 && abs(b.pos.z - p.pos.z) < 1 && b.pos.y > 1.4, "it left from the thrower")
		check(failures, abs(b.vel.z + 11.46) < 0.05 && abs(b.vel.y - 3.22) < 0.05 && abs(b.vel.x) < 0.01, "it flies at the speed the power gives, the way the thrower looked")
	}
	bursts, burst, last := fly(&host, view)
	check(failures, bursts == 1 && view.balloon_count == 0, "it burst once and is gone")
	check(failures, burst.pos.y == 0 && burst.compound == 4 && burst.pos.z < p.pos.z, "it burst on the sand, ahead of the thrower")
	check(failures, abs(burst.pos.x - last.x) < 0.5 && abs(burst.pos.z - last.z) < 0.5, "where it was last seen is where it burst")
	check(failures, burst.balloon == flown_id && abs(burst.radius - 0.8) < 0.001, "the burst names its balloon and reaches 0.8 m, as 300 ml of a plain liquid does")
	check(failures, abs(burst.pos.x * burst.pos.x + burst.pos.z * burst.pos.z) < arena.ARENA_RADIUS * arena.ARENA_RADIUS, "inside the arena")

	// A second balloon is a different balloon.
	check(failures, arena.host_throw(&host, {slot = 0, compound = 7, ml = 100, dir = dir, power = 90}), "a second throw is accepted")
	bursts, burst, _ = fly(&host, view)
	check(failures, bursts == 1 && burst.compound == 7 && burst.balloon == flown_id + 1, "the second balloon has the next id")

	// Frames that are not whole ticks show the player between ticks: after one and a half
	// ticks of walking, one tick has run and the view is half a tick past the one before.
	before, _ := arena.view_player(view, arena.LOCAL_PLAYER)
	arena.host_input(&host, {forward = 1, yaw = 0})
	arena.host_step(&host, TICK_DT * 0.5)
	still, _ := arena.view_player(view, arena.LOCAL_PLAYER)
	arena.host_step(&host, TICK_DT * 0.5)
	arena.host_step(&host, TICK_DT * 0.5)
	after, _ := arena.view_player(view, arena.LOCAL_PLAYER)
	one_tick := 3.2 * TICK_DT
	moved := before.pos.z - after.pos.z
	check(failures, still.pos.z == before.pos.z, "no tick has run yet, so the view has not moved")
	check(failures, moved > one_tick * 0.2 && moved < one_tick * 0.9, "half-tick frames still move the player smoothly")

	// A client that is another player: it starts at that player's spawn point facing the middle,
	// and its balloons are marked as its own.
	other := local_host_new(5, 3)
	check(failures, other != nil, "a match can be started as another player")
	if other == nil {
		return
	}
	defer local_host_free(other)
	other_host := local_host_table(other)
	other_view := arena.host_view(&other_host)
	q, q_found := arena.view_player(other_view, 3)
	at_other_spawn := abs(q.pos.x - 9.9) < 0.01 && abs(q.pos.z + 9.9) < 0.01
	check(failures, q_found && at_other_spawn && abs(q.yaw - 3.92699) < 0.001, "player 3 starts on its own spawn point, facing the middle")
	_, mine := arena.view_player(other_view, arena.LOCAL_PLAYER)
	check(failures, !mine && other_view.player_count == 1, "nobody else is in that match")
	arena.host_throw(&other_host, {slot = 1, compound = 2, ml = 200, dir = {0, 1, 0}, power = 100})
	arena.host_step(&other_host, TICK_DT)
	arena.host_step(&other_host, TICK_DT)
	check(failures, other_view.balloon_count == 1 && other_view.balloons[0].owner == 3 && other_view.balloons[0].slot == 1, "its balloon is marked as player 3's")
}

// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "selftest.odin"
// ============================================================================

package main

import "arena"
import "carry"
import "chemistry"
import "dragdrop"
import "inventory"
import "lab"
import "core:math"
import "core:math/linalg"
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
	check(&failures, tv_max_health() == u32(arena.MAX_HEALTH), "starting hit points match the simulation")
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
	selftest_arena_bots(&failures)
	selftest_arena_layout(&failures)
	selftest_lab_equipment(&failures)
	selftest_paint_screen(&failures)
	selftest_book(&failures)
	selftest_stock(&failures)

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

	// A jump: the button is held for a few frames, as a thumb on the screen is, and the player
	// goes up by about 46 cm and comes down where they were, with the walk going on in the air.
	arena.host_input(&host, {})
	for _ in 0 ..< 4 {
		arena.host_step(&host, TICK_DT)
	}
	before_jump, _ := arena.view_player(view, arena.LOCAL_PLAYER)
	check(failures, arena.on_floor(before_jump), "the player is on the floor before the jump")
	peak: f32
	air_frames := 0
	for frame in 0 ..< 90 {
		arena.host_input(&host, {forward = 1, jump = frame < 6})
		arena.host_step(&host, TICK_DT)
		now, _ := arena.view_player(view, arena.LOCAL_PLAYER)
		peak = max(peak, now.pos.y)
		if !arena.on_floor(now) {
			air_frames += 1
		}
	}
	arena.host_input(&host, {})
	for _ in 0 ..< 4 {
		arena.host_step(&host, TICK_DT)
	}
	after_jump, _ := arena.view_player(view, arena.LOCAL_PLAYER)
	check(failures, peak > 0.40 && peak < 0.48, "the jump goes up about 46 cm")
	check(failures, air_frames > 28 && air_frames < 42, "and is over in about 0.6 s")
	check(failures, after_jump.pos.y == 0 && arena.on_floor(after_jump), "the player is back on the floor")
	check(failures, before_jump.pos.z - after_jump.pos.z > 3, "and walked on while they jumped, 90 frames at 3.2 m/s less the ones after the sticks let go")
	check(failures, after_jump.pos.z > -arena.ARENA_RADIUS, "inside the arena")

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


	// A balloon from the player that meets a second player who stands still takes hit points off them,
	// all the way through the world, the C ABI and the decoders: aimed by the bot's own solver, a
	// plain balloon at 10.7 m is a direct hit and takes 20 off. The thrower loses nothing.
	target := local_host_new(11, arena.LOCAL_PLAYER)
	check(failures, target != nil, "a match for the hit test starts")
	if target == nil {
		return
	}
	defer local_host_free(target)
	check(failures, tv_world_join(target.world, 1) == TV_OK, "a second player joins")
	target_host := local_host_table(target)
	target_view := arena.host_view(&target_host)
	arena.host_step(&target_host, TICK_DT)
	shooter, _ := arena.view_player(target_view, arena.LOCAL_PLAYER)
	victim, victim_found := arena.view_player(target_view, 1)
	check(failures, victim_found && victim.hp == arena.MAX_HEALTH, "players start with full hit points")
	yaw, pitch, speed, reachable := arena.bot_aim(shooter.pos, victim.pos, {}, 0)
	check(failures, reachable, "the other player is in reach")
	check(failures, arena.host_throw(&target_host, {slot = 0, compound = u16(chemistry.Id.Water), ml = arena.PRACTICE_ML, dir = arena.look_dir({yaw = yaw, pitch = pitch}), power = u8(math.round(speed * 10))}), "the throw is accepted")
	for _ in 0 ..< 90 {
		arena.host_step(&target_host, TICK_DT)
	}
	victim, _ = arena.view_player(target_view, 1)
	shooter, _ = arena.view_player(target_view, arena.LOCAL_PLAYER)
	check(failures, victim.hp == arena.MAX_HEALTH - 20, "a direct hit takes 20 hit points off")
	check(failures, shooter.hp == arena.MAX_HEALTH, "and the thrower loses none")

	// A match with the stand-in bot, against a player who stands still for forty seconds: the bot
	// is a second player on its own spawn point, it turns to face the player, walks, jumps, throws
	// again and again, every balloon it throws bursts, and some of them hurt. It stays on the sand.
	with_bot := local_host_new(7, arena.LOCAL_PLAYER, 1)
	check(failures, with_bot != nil, "a match with a bot starts")
	if with_bot == nil {
		return
	}
	defer local_host_free(with_bot)
	bot_host := local_host_table(with_bot)
	bot_view := arena.host_view(&bot_host)
	bot_start, bot_found := arena.view_player(bot_view, 1)
	check(failures, bot_view.player_count == 2 && bot_found, "the bot is a second player")
	check(failures, abs(bot_start.pos.x - 9.9) < 0.01 && abs(bot_start.pos.z - 9.9) < 0.01 && abs(bot_start.yaw - 5.4978) < 0.001, "on its own spawn point, facing the middle")
	// Each match seed gives the bot its own luck: the same seed starts it the same way, another does not.
	same_seed := local_host_new(7, arena.LOCAL_PLAYER, 1)
	other_seed := local_host_new(8, arena.LOCAL_PLAYER, 1)
	if same_seed != nil && other_seed != nil {
		check(failures, same_seed.bots[0].bot.rng == with_bot.bots[0].bot.rng, "the same match seed starts the bot the same way")
		check(failures, other_seed.bots[0].bot.rng != with_bot.bots[0].bot.rng, "and another one does not")
	}
	if same_seed != nil {
		local_host_free(same_seed)
	}
	if other_seed != nil {
		local_host_free(other_seed)
	}
	// A second and a half in, it has turned to face the player, who is at 0, 14.
	for _ in 0 ..< 90 {
		arena.host_step(&bot_host, TICK_DT)
	}
	bot_early, _ := arena.view_player(bot_view, 1)
	face := math.atan2(-bot_early.pos.x, bot_early.pos.z - 14) // the heading that faces (0, 14) from where the bot is
	check(failures, abs(arena.angle_diff(bot_early.yaw, face)) < 0.35, "the bot faces the player")
	bot_balloons, bot_bursts := 0, 0
	fastest := f32(0)
	seen_bot_balloon := false
	bot_far: f32
	bot_jumped := false
	lowest := arena.MAX_HEALTH
	for _ in 0 ..< 60 * 40 {
		arena.host_step(&bot_host, TICK_DT)
		for i in 0 ..< bot_view.balloon_count {
			if bot_view.balloons[i].owner == 1 && bot_view.balloons[i].slot == 0 {
				seen_bot_balloon = true
				bot_balloons += 1
				v := bot_view.balloons[i].vel
				fastest = max(fastest, math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z))
			}
		}
		bot_bursts += bot_view.burst_count
		if bp, ok := arena.view_player(bot_view, 1); ok {
			bot_far = max(bot_far, math.sqrt(bp.pos.x * bp.pos.x + bp.pos.z * bp.pos.z))
			if !arena.on_floor(bp) {
				bot_jumped = true
			}
		}
		if lp, ok := arena.view_player(bot_view, arena.LOCAL_PLAYER); ok {
			lowest = min(lowest, lp.hp)
		}
	}
	bot_end, _ := arena.view_player(bot_view, 1)
	bot_moved := math.sqrt((bot_end.pos.x - bot_start.pos.x) * (bot_end.pos.x - bot_start.pos.x) + (bot_end.pos.z - bot_start.pos.z) * (bot_end.pos.z - bot_start.pos.z))
	check(failures, bot_moved > 1 || bot_far > 0, "the bot walks")
	check(failures, bot_jumped, "and jumps")
	check(failures, seen_bot_balloon && bot_balloons > 20, "its balloons are in the air, marked as its own")
	check(failures, bot_bursts >= with_bot.bots[0].bot.thrown - 1 && bot_bursts <= with_bot.bots[0].bot.thrown, "every balloon it threw has burst, bar one that may still be in the air")
	check(failures, with_bot.bots[0].bot.thrown >= 8, "it threw at least eight in forty seconds")
	check(failures, fastest > 9 && fastest <= 18.01, "it throws with the power it chose, well above the weakest throw")
	check(failures, bot_far < arena.ARENA_RADIUS, "all inside the arena")
	check(failures, lowest < arena.MAX_HEALTH, "and its balloons hurt the player who stood and took them")
	me, me_found := arena.view_player(bot_view, arena.LOCAL_PLAYER)
	check(failures, me_found && abs(me.pos.z - 14) < 0.001 && abs(me.pos.x) < 0.001, "the player who sent nothing is where they started, knocked out or not")
}

// A match with three bots, as the arena scene starts one: four players on four spawn points well
// apart, every bot plays on its own for thirty seconds and throws, their balloons are marked as
// theirs, balloons burst, somebody is hurt, and everybody stays inside the arena.
selftest_arena_bots :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}

	check(failures, ARENA_BOTS == 3, "the arena scene starts three bots")
	h := local_host_new(21, arena.LOCAL_PLAYER, ARENA_BOTS)
	check(failures, h != nil, "a match with three bots starts")
	if h == nil {
		return
	}
	defer local_host_free(h)
	check(failures, h.bot_count == 3, "the host keeps three bots")
	table := local_host_table(h)
	view := arena.host_view(&table)
	check(failures, view.player_count == 4, "four players with the local one")
	apart := f32(1e9)
	for i in 0 ..< view.player_count {
		for j in i + 1 ..< view.player_count {
			d := view.players[i].pos - view.players[j].pos
			apart = min(apart, math.sqrt(d.x * d.x + d.z * d.z))
		}
	}
	check(failures, apart > 8, "on four spawn points well apart")
	ids_differ := h.bots[0].id != h.bots[1].id && h.bots[1].id != h.bots[2].id && h.bots[0].id != h.bots[2].id
	check(failures, ids_differ && h.bots[0].bot.rng != h.bots[1].bot.rng && h.bots[1].bot.rng != h.bots[2].bot.rng, "each bot has its own id and its own luck")

	owners: [arena.MAX_PLAYERS]bool
	bursts := 0
	far := f32(0)
	lowest := arena.MAX_HEALTH
	for _ in 0 ..< 60 * 30 {
		arena.host_step(&table, TICK_DT)
		for i in 0 ..< view.balloon_count {
			owners[int(view.balloons[i].owner) % arena.MAX_PLAYERS] = true
		}
		bursts += view.burst_count
		for i in 0 ..< view.player_count {
			p := view.players[i]
			far = max(far, math.sqrt(p.pos.x * p.pos.x + p.pos.z * p.pos.z))
			lowest = min(lowest, p.hp)
		}
	}
	all_threw, all_marked := true, true
	for i in 0 ..< h.bot_count {
		all_threw &&= h.bots[i].bot.thrown >= 3
		all_marked &&= owners[int(h.bots[i].id) % arena.MAX_PLAYERS]
	}
	check(failures, all_threw, "every bot threw at least three balloons in thirty seconds")
	check(failures, all_marked, "and its balloons were in the air, marked as its own")
	check(failures, !owners[arena.LOCAL_PLAYER], "while the player who threw nothing has none")
	check(failures, bursts >= 6, "balloons burst")
	check(failures, lowest < arena.MAX_HEALTH, "and somebody was hurt")
	check(failures, far < arena.ARENA_RADIUS, "everybody stayed inside the arena")
}

// Checks the lab as the room builds it, with all its equipment: the boxes fit the list and the
// props fit theirs, every vial starts in a hole of a rack, a vessel set on the scale is weighed,
// and the cabinet heals.
selftest_lab_equipment :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}
	l := new(lab.Layout)
	defer free(l)
	lab.build(l)
	lab.add_dispensers(l, carry.station_colors())
	lab.add_apparatus(l)
	shelf := carry.shelf_colors()
	lab.add_shelves(l, shelf[:])
	check(failures, l.box_count < lab.MAX_BOXES - 50, "the lab with all its equipment fits the box list with room to spare")
	props := new(carry.Props)
	defer free(props)
	carry.props_init(props)
	carry.props_place_defaults(props, l)
	vials, in_holes := 0, 0
	for i in 0 ..< props.count {
		pr := props.items[i]
		if pr.kind == .Vial {
			vials += 1
			if _, found := carry.vial_slot_at(pr.pos.x, pr.pos.z); found {
				in_holes += 1
			}
		}
	}
	check(failures, props.count == 47 && props.count < carry.MAX_PROPS, "the starting vessels fit the list")
	check(failures, vials == 24 && in_holes == vials, "every vial starts in a hole of a rack")
	// A beaker of water on the scale: 60 g of glass and 100 ml.
	scale: carry.Scale
	carry.props_add(props, l, .Beaker, 0, -7.6, u16(chemistry.Id.Water), 100)
	grams, loaded := carry.scale_reading(&scale, props)
	check(failures, loaded && abs(grams - 160) < 0.01, "a beaker with 100 ml of water on the scale reads 160 g")
	scale.aimed = true
	check(failures, carry.scale_zero(&scale, props), "and it can be zeroed")
	grams, _ = carry.scale_reading(&scale, props)
	check(failures, abs(grams) < 0.01, "after which it reads nothing")
	// The cabinet.
	health: carry.Health
	carry.health_init(&health)
	carry.health_hurt(&health, 70)
	aid := carry.First_Aid {
		aimed = true,
	}
	props.held = -1
	check(failures, carry.first_aid_use(&aid, &health) && health.hp == carry.HEALTH_MAX, "the first aid cabinet puts a hurt player back at full health")
}

// Whether two boxes (x, y, width, height) overlap.
boxes_overlap :: proc(a, b: [4]f32) -> bool {
	return a.x < b.x + b.z && b.x < a.x + a.z && a.y < b.y + b.w && b.y < a.y + a.w
}

// Whether a box lies inside a screen.
box_on_screen :: proc(b: [4]f32, w, h: f32) -> bool {
	return b.x >= 0 && b.y >= 0 && b.x + b.z <= w && b.y + b.w <= h
}

// Checks the arena's buttons on several screen shapes: the fire stick, the jump button, the three
// slot buttons, the lab button and the hit point bar are all on the screen and none lies on another,
// so a thumb that lands on one cannot press two. The fire stick is round and its box is square.
selftest_arena_layout :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}
	screens := [?][2]f32{{1600, 720}, {1280, 720}, {1024, 600}, {800, 480}, {2400, 1080}, {1000, 1000}}
	all_on, none_over, round_ok := true, true, true
	for s in screens {
		w, h := s.x, s.y
		boxes := [?][4]f32{switch_button(w, h), throw_button(w, h), arena_jump_button(w, h), slot_button(w, h, 0), slot_button(w, h, 1), slot_button(w, h, 2), health_bar(w, h)}
		for b, i in boxes {
			if !box_on_screen(b, w, h) {
				all_on = false
			}
			for c, j in boxes {
				if i < j && boxes_overlap(b, c) {
					none_over = false
					fmt.printf("      %vx%v: box %d overlaps box %d\n", w, h, i, j)
				}
			}
		}
		stick := throw_button(w, h)
		centre, radius := fire_stick(w, h)
		if stick.z != stick.w || radius * 2 != stick.z || centre.x != stick.x + radius || centre.y != stick.y + radius {
			round_ok = false
		}
	}
	check(failures, all_on, "every arena button is on the screen, on every screen shape")
	check(failures, none_over, "and no arena button lies on another")
	check(failures, round_ok, "the fire stick is a circle in a square box")
}

// Checks that the drawing screen puts the balloon where its layout leaves room for it: the
// middle of the balloon, projected through the paint camera by plain matrix arithmetic, falls
// inside the balloon area on the left of the screen, and the whole balloon, 6.2 cm each side of
// its axis, fits in the area. It is done on several screen shapes.
selftest_paint_screen :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}

	screens := [?][2]f32{{1280, 720}, {1600, 720}, {2400, 1080}, {960, 540}, {800, 600}}
	all_inside, all_left, all_fit, all_tall := true, true, true, true
	for sc in screens {
		w, h := sc.x, sc.y
		cam := paint_camera(w, h)
		l := carry.paint_layout(w, h)
		view := linalg.matrix4_look_at_f32(cam.position, cam.target, cam.up)
		proj := linalg.matrix4_perspective_f32(cam.fovy * math.RAD_PER_DEG, w / h, 0.08, 70)
		across :: proc(m: matrix[4, 4]f32, p: [3]f32, w: f32) -> f32 {
			clip := m * [4]f32{p.x, p.y, p.z, 1}
			return (clip.x / clip.w * 0.5 + 0.5) * w
		}
		both := proj * view
		mid := lab.PAINT_CLAMP - {0, lab.PAINT_DROP * 0.5, 0}
		x := across(both, mid, w)
		// Down the screen: the tip of the balloon at the clamp and its bottom, `PAINT_DROP` lower, are
		// both on the screen, with a little to spare. Screen y runs down.
		down :: proc(m: matrix[4, 4]f32, p: [3]f32, h: f32) -> f32 {
			clip := m * [4]f32{p.x, p.y, p.z, 1}
			return (1 - (clip.y / clip.w * 0.5 + 0.5)) * h
		}
		tip_y := down(both, lab.PAINT_CLAMP, h)
		bottom_y := down(both, lab.PAINT_CLAMP - {0, lab.PAINT_DROP, 0}, h)
		if !(tip_y > h * 0.02 && bottom_y < h * 0.98 && tip_y < bottom_y) {
			all_tall = false
			fmt.printf("      screen %vx%v: the balloon spans %.0f to %.0f of %v from the top\n", w, h, tip_y, bottom_y, h)
		}
		// The camera looks along -x with the north on the right of the picture, so a point
		// further south, z larger, is on the left of the screen.
		x_left := across(both, mid + {0, 0, 0.062}, w)
		x_right := across(both, mid - {0, 0, 0.062}, w)
		area_left, area_right := l.balloon[0], l.balloon[0] + l.balloon[2]
		if !(x > area_left && x < area_right) {
			all_inside = false
		}
		if !(x < w * 0.5) {
			all_left = false
		}
		if !(x_left > area_left && x_right < area_right && x_left < x_right) {
			all_fit = false
			fmt.printf("      screen %vx%v: the balloon spans %.0f to %.0f and the area %.0f to %.0f\n", w, h, x_left, x_right, area_left, area_right)
		}
	}
	check(failures, all_inside, "the middle of the balloon is inside the balloon area on every screen shape")
	check(failures, all_left, "and on the left half of the screen")
	check(failures, all_fit, "and the whole balloon fits in the area")
	check(failures, all_tall, "and from its tip to its bottom it is on the screen, down the screen")
}

// Checks the book of reactions on several screen shapes: its buttons and the tiles of the contents page are on
// the screen, inside the panel, and none lies on another, so a thumb that lands on one cannot press two. Then the
// pages: every compound has a first page that the contents page reaches, the back and next buttons stop at the
// ends, and a press that is on nothing turns nothing.
selftest_book :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}
	screens := [?][2]f32{{1600, 720}, {1280, 720}, {1024, 600}, {800, 480}, {2400, 1080}, {1000, 1000}}
	all_on, all_in, none_over := true, true, true
	for s in screens {
		w, h := s.x, s.y
		panel := book_panel(w, h)
		boxes: [chemistry.COMPOUND_COUNT + 4][4]f32
		for k in 0 ..< chemistry.COMPOUND_COUNT {
			boxes[k] = book_tile(w, h, k)
		}
		boxes[chemistry.COMPOUND_COUNT] = book_close_button(w, h)
		boxes[chemistry.COMPOUND_COUNT + 1] = book_prev_button(w, h)
		boxes[chemistry.COMPOUND_COUNT + 2] = book_contents_button(w, h)
		boxes[chemistry.COMPOUND_COUNT + 3] = book_next_button(w, h)
		for b, i in boxes {
			if !box_on_screen(b, w, h) {
				all_on = false
			}
			if b.x < panel.x || b.y < panel.y || b.x + b.z > panel.x + panel.z || b.y + b.w > panel.y + panel.w {
				all_in = false
			}
			for c, j in boxes {
				if i < j && boxes_overlap(b, c) {
					none_over = false
					fmt.printf("      %vx%v: box %d overlaps box %d\n", w, h, i, j)
				}
			}
		}
	}
	check(failures, all_on, "every book button and tile is on the screen, on every screen shape")
	check(failures, all_in, "and inside the panel of the book")
	check(failures, none_over, "and none lies on another")

	last := book_last_page()
	check(failures, last == 19, "the book has the contents and 19 more pages, as the pages are")
	id, part := book_at(0)
	check(failures, id == .None && part == 0, "page 0 is the contents, of no compound")
	id, part = book_at(1)
	check(failures, id == .Water && part == 0, "page 1 is the first spread of water")
	id, part = book_at(2)
	check(failures, id == .Water && part == 1, "page 2 is the second spread of water, which has 13 lines")
	id, part = book_at(3)
	check(failures, id == .Acetic_Acid && part == 0, "page 3 is acetic acid")
	id, part = book_at(last)
	check(failures, id == .Persulfate && part == 0, "the last page is the last compound")
	id, part = book_at(last + 40)
	check(failures, id == .Persulfate && part == 0, "a page past the end is the last page")
	id, part = book_at(-3)
	check(failures, id == .None && part == 0, "and a page before the start is the contents")
	check(failures, book_first_page(.Water) == 1 && book_first_page(.Acetic_Acid) == 3 && book_first_page(.Sulfuric_Acid) == 5 && book_first_page(.Dilute_Sulfuric_Acid) == 7, "the first pages follow the spreads of the compounds before")
	roundtrip := true
	for page in 1 ..= last {
		who, which := book_at(page)
		if book_first_page(who) + which != page || which >= book_parts(who) {
			roundtrip = false
		}
	}
	check(failures, roundtrip, "every page is the first page of its compound plus its spread")
	check(failures, book_prev_page(0) == 0 && book_prev_page(1) == 0 && book_prev_page(7) == 6, "back stops at the contents")
	check(failures, book_next_page(last) == last && book_next_page(last - 1) == last && book_next_page(0) == 1, "and next stops at the last page")

	w, h := f32(1600), f32(720)
	centre :: proc(b: [4]f32) -> [2]f32 {
		return {b.x + b.z * 0.5, b.y + b.w * 0.5}
	}
	reached := true
	for k in 0 ..< chemistry.COMPOUND_COUNT {
		if book_press(0, centre(book_tile(w, h, k)), w, h) != book_first_page(chemistry.Id(k + 1)) {
			reached = false
		}
	}
	check(failures, reached, "a tile on the contents page opens the first page of its compound")
	check(failures, book_press(5, centre(book_prev_button(w, h)), w, h) == 4 && book_press(5, centre(book_next_button(w, h)), w, h) == 6, "the back and next buttons turn one page")
	check(failures, book_press(5, centre(book_contents_button(w, h)), w, h) == 0, "the contents button goes to the contents")
	check(failures, book_press(0, centre(book_prev_button(w, h)), w, h) == 0 && book_press(last, centre(book_next_button(w, h)), w, h) == last, "back on the contents and next on the last page stay where they are")
	check(failures, book_press(5, centre(book_tile(w, h, 9)), w, h) == 5, "a tile's place does nothing on a compound's page")
	check(failures, book_press(5, {2, 2}, w, h) == 5 && book_press(0, {2, 2}, w, h) == 0, "a press on nothing turns nothing")
}

// Checks the screen of the bag, the bottle wall and the bar: on six screen shapes its close button and all 28 slots are on
// the screen, inside the panel, none lies on another, and each slot is big enough to press with a thumb. Then the
// drags, without a window: a stack is picked up, carried over a slot and dropped, and what may not move does not.
selftest_stock :: proc(failures: ^int) {
	check :: proc(failures: ^int, ok: bool, what: string) {
		if ok {
			fmt.printf("ok    %s\n", what)
		} else {
			fmt.printf("FAIL  %s\n", what)
			failures^ += 1
		}
	}
	screens := [?][2]f32{{1600, 720}, {1280, 720}, {1024, 600}, {800, 480}, {2400, 1080}, {1000, 1000}}
	all_on, all_in, none_over, big_enough := true, true, true, true
	for s in screens {
		w, h := s.x, s.y
		panel := book_panel(w, h)
		boxes: [22 + 6 + 3][4]f32
		n := 0
		for c in 0 ..< STOCK_CONTAINERS {
			for slot in 0 ..< stock_slot_count(c) {
				boxes[n] = stock_slot_box(w, h, c, slot)
				n += 1
			}
		}
		boxes[n] = book_close_button(w, h)
		boxes[n + 1] = bag_button(w, h)
		boxes[n + 2] = pickup_button(w, h)
		for b, i in boxes {
			if i < n && b.z < 44 {
				big_enough = false
			}
			if !box_on_screen(b, w, h) {
				all_on = false
			}
			if i <= n && (b.x < panel.x || b.y < panel.y || b.x + b.z > panel.x + panel.z || b.y + b.w > panel.y + panel.w) {
				all_in = false
			}
			for c, j in boxes {
				if i < j && j <= n && boxes_overlap(b, c) {
					none_over = false
					fmt.printf("      %vx%v: box %d overlaps box %d\n", w, h, i, j)
				}
			}
		}
		// The bag button sits beside the book button and on none of the others of the lab.
		bag := bag_button(w, h)
		pick := pickup_button(w, h)
		others := [7][4]f32{switch_button(w, h), grab_button(w, h), jump_button(w, h), bench_button(w, h), pour_button(w, h), book_button(w, h), speed_button(w, h)}
		for o in others {
			if boxes_overlap(bag, o) {
				none_over = false
				fmt.printf("      %vx%v: the bag button overlaps another button\n", w, h)
			}
			if boxes_overlap(pick, o) {
				none_over = false
				fmt.printf("      %vx%v: the pick up button overlaps another button\n", w, h)
			}
		}
		if boxes_overlap(bag, arena_button(w, h)) || boxes_overlap(pick, arena_button(w, h)) || boxes_overlap(pick, bag) || !box_on_screen(pick, w, h) {
			none_over = false
		}
		// The bar along the bottom of the lab is on the screen, at least 44 pixels across, and lies on none of the buttons.
		lab_buttons := [10][4]f32{switch_button(w, h), grab_button(w, h), jump_button(w, h), bench_button(w, h), pour_button(w, h), book_button(w, h), speed_button(w, h), arena_button(w, h), bag, pick}
		for slot_box, k in hotbar_buttons(w, h) {
			if slot_box.z < 44 {
				big_enough = false
				fmt.printf("      %vx%v: slot %d of the bar is %v pixels across\n", w, h, k, slot_box.z)
			}
			if !box_on_screen(slot_box, w, h) {
				all_on = false
			}
			for o, j in lab_buttons {
				if boxes_overlap(slot_box, o) {
					none_over = false
					fmt.printf("      %vx%v: slot %d of the bar overlaps button %d of the lab\n", w, h, k, j)
				}
			}
		}
	}
	counts := true
	probe: carry.Stock
	carry.stock_init(&probe)
	for c in 0 ..< STOCK_CONTAINERS {
		counts &&= stock_slot_count(c) == stock_container(&probe, c).size
	}
	check(failures, counts, "the screen has a slot for every slot of the bag, the wall and the bar")
	check(failures, hotbar_slot_size(640, 360) >= 44 && hotbar_slot_size(1600, 720) == 72, "a slot of the bar is a tenth of the height, and at least 44 pixels across even on a screen that is only 360 high")
	check(failures, all_on, "every slot of the bag, the wall and the bar, and the close button, is on the screen, on every screen shape")
	check(failures, all_in, "and inside the panel")
	check(failures, none_over, "and none lies on another, nor do the bag and pick up buttons lie on another button, nor the slots of the bar on any button of the lab")
	check(failures, big_enough, "and every slot is at least 44 pixels across")

	w, h := f32(1600), f32(720)
	centre :: proc(w, h: f32, container, slot: int) -> [2]f32 {
		b := stock_slot_box(w, h, container, slot)
		return {b.x + b.z * 0.5, b.y + b.w * 0.5}
	}
	st: carry.Stock
	carry.stock_init(&st)
	ui: Stock_Ui
	stock_ui_init(&ui)
	ethanol := inventory.Item{.Dispenser, u16(chemistry.Id.Ethanol)}
	acid := inventory.Item{.Dispenser, u16(chemistry.Id.Sulfuric_Acid)}

	changed := stock_update(&ui, &st, centre(w, h, STOCK_WALL, 1), true, false, w, h)
	check(failures, !changed && dragdrop.is_dragging(&ui.drag), "a press on a dispenser starts a drag and changes nothing")
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 0), false, false, w, h)
	check(failures, !changed && ui.drag.hover == STOCK_BAG * inventory.MAX_SLOTS && ui.drag.hover_ok, "carried over an empty slot of the bag, the drag is over it and it takes the dispenser")
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 0), false, true, w, h)
	check(failures, changed && !dragdrop.is_dragging(&ui.drag) && st.wall.slots[1].count == 0 && st.bag.slots[0] == (inventory.Slot{ethanol, 1}), "letting go over it moves the dispenser from the wall to the bag")

	changed = stock_update(&ui, &st, centre(w, h, STOCK_WALL, 5), true, false, w, h)
	check(failures, !changed && !dragdrop.is_dragging(&ui.drag), "a press on an empty slot starts no drag")
	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 5), false, true, w, h)

	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 0), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_WALL, 6), false, true, w, h)
	check(failures, changed && st.bag.slots[0].count == 0 && st.wall.slots[6] == (inventory.Slot{ethanol, 1}), "from the bag to another mount of the wall")

	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 0), true, false, w, h)
	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 2), false, false, w, h)
	check(failures, ui.drag.hover == STOCK_WALL * inventory.MAX_SLOTS + 2 && !ui.drag.hover_ok, "over a slot that holds another dispenser, the drag is over it and it does not take it")
	acetic := st.wall.slots[0]
	changed = stock_update(&ui, &st, centre(w, h, STOCK_WALL, 2), false, true, w, h)
	check(failures, !changed && st.wall.slots[0] == acetic && st.wall.slots[2].item == acid && !dragdrop.is_dragging(&ui.drag), "and letting go there changes nothing and swaps nothing")

	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 0), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_WALL, 0), false, true, w, h)
	check(failures, !changed && st.wall.slots[0] == acetic, "letting go on the slot it came from changes nothing")

	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 0), true, false, w, h)
	changed = stock_update(&ui, &st, {2, 2}, false, true, w, h)
	check(failures, !changed && st.wall.slots[0] == acetic && !dragdrop.is_dragging(&ui.drag), "letting go away from every slot cancels the drag")

	st.bag.locked = true
	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 0), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 3), false, true, w, h)
	check(failures, !changed && st.wall.slots[0] == acetic, "a locked bag takes nothing")
	st.bag.locked = false
	st.wall.locked = true
	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 0), true, false, w, h)
	check(failures, !dragdrop.is_dragging(&ui.drag), "and nothing can be taken from a locked wall")
	st.wall.locked = false

	station: carry.Station
	carry.station_init(&station)
	carry.station_sync(&station, &st.wall)
	check(failures, station.items[1].compound == 0 && station.items[6].compound == u16(chemistry.Id.Ethanol) && station.items[0].compound == u16(chemistry.Id.Acetic_Acid), "the taps follow the wall: the ethanol tap is now at mount 7")

	// A station in the bag: dragged it moves like a dispenser, tapped it is to be carried, and it cannot go on the wall.
	scale := inventory.Item{.Scale, 0}
	inventory.put(&st.bag, 6, scale, 1)
	ui.hands_free = true
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 6), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 6), false, true, w, h)
	check(failures, !changed && ui.carry_slot == 6 && st.bag.slots[6] == (inventory.Slot{scale, 1}), "a tap on a station of the bag asks for it to be carried and moves nothing")
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 6), true, false, w, h)
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 7), false, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 7), false, true, w, h)
	check(failures, changed && ui.carry_slot == -1 && st.bag.slots[7] == (inventory.Slot{scale, 1}) && st.bag.slots[6].count == 0, "dragged to another slot it moves there and is not carried")
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 7), true, false, w, h)
	stock_update(&ui, &st, centre(w, h, STOCK_WALL, 8), false, false, w, h)
	check(failures, ui.drag.hover == STOCK_WALL * inventory.MAX_SLOTS + 8 && !ui.drag.hover_ok, "a station over a mount of the wall is not taken")
	changed = stock_update(&ui, &st, centre(w, h, STOCK_WALL, 8), false, true, w, h)
	check(failures, !changed && ui.carry_slot == -1 && st.bag.slots[7].item == scale && st.wall.slots[8].count == 0, "and letting go there leaves it in the bag")
	ui.hands_free = false
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 7), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 7), false, true, w, h)
	check(failures, !changed && ui.carry_slot == -1, "a tap with the hands full carries nothing")
	ui.hands_free = true
	inventory.put(&st.bag, 8, inventory.Item{.Dispenser, u16(chemistry.Id.Ethanol)}, 1)
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 8), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 8), false, true, w, h)
	check(failures, !changed && ui.carry_slot == -1, "a tap on a dispenser carries nothing")
	// A tap on a dispenser of the wall carries nothing, even where the bag has a station under the same number.
	mount := 0
	for mount < lab.DISPENSER_COUNT && st.wall.slots[mount].count == 0 {
		mount += 1
	}
	inventory.take(&st.bag, mount, 1)
	inventory.put(&st.bag, mount, scale, 1)
	stock_update(&ui, &st, centre(w, h, STOCK_WALL, mount), true, false, w, h)
	changed = stock_update(&ui, &st, centre(w, h, STOCK_WALL, mount), false, true, w, h)
	check(failures, !changed && ui.carry_slot == -1, "nor does a tap on a dispenser of the wall, whatever the bag holds at that number")
	// A drag that began on a station and is let go over no slot is not a tap, whichever slot it began on.
	inventory.take(&st.bag, 0, 1)
	inventory.put(&st.bag, 0, scale, 1)
	stock_update(&ui, &st, centre(w, h, STOCK_BAG, 0), true, false, w, h)
	changed = stock_update(&ui, &st, {2, 2}, false, true, w, h)
	check(failures, !changed && ui.carry_slot == -1 && st.bag.slots[0] == (inventory.Slot{scale, 1}), "letting go over no slot is no tap and moves nothing")
	// With no drag going on a release is nothing.
	changed = stock_update(&ui, &st, centre(w, h, STOCK_BAG, 0), false, true, w, h)
	check(failures, !changed && ui.carry_slot == -1, "a release with no drag is not a tap")

	// The bar: a station is dragged into it from the bag and out of it, a dispenser is not taken, and a tap on a station in it
	// asks for the station to be carried.
	bar: carry.Stock
	carry.stock_init(&bar)
	bui: Stock_Ui
	stock_ui_init(&bui)
	inventory.put(&bar.bag, 4, scale, 1)
	inventory.put(&bar.bag, 5, ethanol, 1)
	stock_update(&bui, &bar, centre(w, h, STOCK_BAG, 4), true, false, w, h)
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), false, false, w, h)
	check(failures, bui.drag.hover == STOCK_HOTBAR * inventory.MAX_SLOTS + 2 && bui.drag.hover_ok, "a station over a slot of the bar is taken")
	changed = stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), false, true, w, h)
	check(failures, changed && bar.hotbar.slots[2] == (inventory.Slot{scale, 1}) && bar.bag.slots[4].count == 0, "and letting go there puts it in the bar")
	stock_update(&bui, &bar, centre(w, h, STOCK_BAG, 5), true, false, w, h)
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 3), false, false, w, h)
	check(failures, bui.drag.hover == STOCK_HOTBAR * inventory.MAX_SLOTS + 3 && !bui.drag.hover_ok, "a dispenser over a slot of the bar is not taken")
	changed = stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 3), false, true, w, h)
	check(failures, !changed && bar.hotbar.slots[3].count == 0 && bar.bag.slots[5].count == 1, "and letting go there leaves it in the bag")
	bui.hands_free = true
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), true, false, w, h)
	changed = stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), false, true, w, h)
	check(failures, !changed && bui.carry_slot == 2 && bui.carry_container == STOCK_HOTBAR, "a tap on a station of the bar asks for it to be carried")
	bui.hands_free = false
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), true, false, w, h)
	changed = stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), false, true, w, h)
	check(failures, !changed && bui.carry_slot == -1, "a tap on it with the hands full carries nothing")
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 2), true, false, w, h)
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 4), false, false, w, h)
	changed = stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 4), false, true, w, h)
	check(failures, changed && bar.hotbar.slots[4] == (inventory.Slot{scale, 1}) && bar.hotbar.slots[2].count == 0, "dragged along the bar it moves, and that alone is a change")
	stock_update(&bui, &bar, centre(w, h, STOCK_HOTBAR, 4), true, false, w, h)
	stock_update(&bui, &bar, centre(w, h, STOCK_BAG, 8), false, false, w, h)
	changed = stock_update(&bui, &bar, centre(w, h, STOCK_BAG, 8), false, true, w, h)
	check(failures, changed && bar.bag.slots[8] == (inventory.Slot{scale, 1}) && bar.hotbar.slots[4].count == 0 && bui.carry_slot == -1, "dragged back out of the bar into the bag it moves and is not carried")

	// A point of the screen is on the slot it is in the middle of, and the gap between two slots is on none.
	each_slot := true
	for k in 0 ..< carry.HOTBAR_SIZE {
		at := centre(w, h, STOCK_HOTBAR, k)
		if i, ok := hotbar_slot_at(w, h, at); !ok || i != k {
			each_slot = false
		}
		if hotbar_buttons(w, h)[k] != hotbar_slot_rect(w, h, k) {
			each_slot = false
		}
	}
	first := hotbar_slot_rect(w, h, 0)
	_, in_gap := hotbar_slot_at(w, h, {first.x + first.z + 1, first.y + first.w * 0.5})
	_, above := hotbar_slot_at(w, h, {first.x + first.z * 0.5, first.y - 2})
	check(failures, each_slot && !in_gap && !above, "each slot of the bar is found by its middle, and the gap and the space over the bar are no slot")
}

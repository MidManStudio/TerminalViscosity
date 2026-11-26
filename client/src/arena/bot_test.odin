// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "bot_test.odin"
// ============================================================================

package arena

import "core:math"
import "core:math/linalg"
import "core:testing"

STEP :: f32(1.0 / 60)

alive :: proc(id: u8, x, z: f32) -> Player_View {
	return {id = id, pos = {x, 0, z}, hp = MAX_HEALTH}
}

view_of :: proc(players: ..Player_View) -> (v: Match_View) {
	for p in players {
		v.players[v.player_count] = p
		v.player_count += 1
	}
	return
}

// Which way on the floor, as an x and a z, a player with this input walks at full speed: the
// simulation's own walking rule, with yaw 0 facing -z and a quarter turn facing +x.
world_move :: proc(input: Input) -> [2]f32 {
	s, c := math.sin(input.yaw), math.cos(input.yaw)
	return {input.forward * s + input.strafe * c, -input.forward * c + input.strafe * s}
}

// Flies a balloon the way tv_sim does (it leaves the hand half a metre along the aim, 1.5 m up,
// and falls at 9.81, in 60 steps a second) and says whether it meets the body of a player
// standing at `at` and walking at `vel`: a cylinder 0.4 m across the middle and 1.9 m high.
flies_into_body :: proc(from: Vec3, act: Bot_Act, at: Vec3, vel: Vec3 = {}) -> bool {
	pos := from + {0, 1.5, 0} + act.dir * 0.5
	v := act.dir * (f32(act.power) * 0.1)
	target := at
	for _ in 0 ..< 900 {
		v.y -= GRAVITY * STEP
		pos += v * STEP
		target += vel * STEP
		if pos.y <= 0 {
			return false
		}
		dx, dz := pos.x - target.x, pos.z - target.z
		if dx * dx + dz * dz <= 0.4 * 0.4 && pos.y <= target.y + 1.9 && pos.y >= target.y {
			return true
		}
	}
	return false
}

// How near, in metres, a balloon thrown this way comes to the middle of the chest (1.1 m up) of a
// player who stands at `at` and walks at `vel`. It is flown in ten small steps for every tick, so
// that the answer is not spoiled by the length of a tick.
closest_approach :: proc(from: Vec3, act: Bot_Act, at: Vec3, vel: Vec3 = {}) -> f32 {
	pos := from + {0, 1.5, 0} + act.dir * 0.5
	v := act.dir * (f32(act.power) * 0.1)
	target := at
	best := f32(1e9)
	for _ in 0 ..< 9000 {
		v.y -= GRAVITY * STEP / 10
		pos += v * STEP / 10
		target += vel * STEP / 10
		best = min(best, linalg.length(pos - (target + Vec3{0, 1.1, 0})))
		if pos.y <= 0 {
			break
		}
	}
	return best
}

// A bot with no aim error and nothing to wait for, at the origin and facing a player `d` metres
// away to the north, and the match it sees.
duel :: proc(d: f32) -> (b: Bot, v: Match_View) {
	b = bot_new(12345)
	b.sloppy = 0
	b.throw_in = 0
	v = view_of(alive(0, 0, 0), alive(1, 0, -d))
	return
}

Run :: struct {
	count:   int,
	step_of: [64]int, // the step each throw came on
	acts:    [64]Bot_Act,
	last:    Bot_Act,
}

// Runs `seconds` of steps against one fixed view, as the player `me`.
run_bot :: proc(b: ^Bot, v: ^Match_View, me: u8, seconds: f32) -> (r: Run) {
	for i in 0 ..< int(seconds * 60) {
		r.last = bot_step(b, v, me, STEP)
		if r.last.throw && r.count < len(r.acts) {
			r.step_of[r.count] = i
			r.acts[r.count] = r.last
			r.count += 1
		}
	}
	return
}

@(test)
the_flat_arc_matches_the_textbook :: proc(t: ^testing.T) {
	// At level ground, sin(2a) = g x / v^2: 10 m at 10 m/s is the flat one of 39.4 and 50.6 degrees.
	pitch, ok := ballistic_pitch(10, 10, 0)
	testing.expect(t, ok, "it can be reached")
	testing.expect(t, near(pitch, 0.6876, 0.002), "the flat arc, not the lob")
	// A point that is too far for the speed cannot be reached.
	_, ok = ballistic_pitch(5, 10, 0)
	testing.expect(t, !ok, "10 m is out of reach at 5 m/s")
	_, ok = ballistic_pitch(10, 0, 0)
	testing.expect(t, !ok, "no distance, no arc")
	_, ok = ballistic_pitch(0, 5, 0)
	testing.expect(t, !ok, "no speed, no arc")
}

@(test)
the_arc_passes_through_the_point_asked_for :: proc(t: ^testing.T) {
	for c in ([?][3]f32{{12, 8, 0}, {12, 8, 1.5}, {12, 8, -0.4}, {18, 14, -0.4}, {9, 3, 2}, {20, 25, -1}}) {
		speed, x, y := c[0], c[1], c[2]
		pitch, ok := ballistic_pitch(speed, x, y)
		testing.expectf(t, ok, "%v m/s reaches %v m out and %v up", speed, x, y)
		c2 := math.cos(pitch)
		height := x * math.tan(pitch) - GRAVITY * x * x / (2 * speed * speed * c2 * c2)
		testing.expectf(t, near(height, y, 0.002), "it arrives %v m up, not %v", height, y)
		testing.expectf(t, pitch < math.PI / 4 + (y > 0 ? 0.2 : 0), "%v is the flat arc", pitch)
	}
}

@(test)
launches_are_whole_tenths_in_the_power_range :: proc(t: ^testing.T) {
	for x := f32(1); x <= 24; x += 0.5 {
		speed, _, ok := bot_launch(x, -0.4)
		testing.expectf(t, ok, "it can reach %v m", x)
		testing.expectf(t, speed >= BOT_SPEED_MIN && speed <= BOT_SPEED_MAX, "%v m/s is out of range", speed)
		testing.expectf(t, near(speed * 10, math.round(speed * 10), 0.001), "%v m/s is not a whole number of tenths", speed)
	}
	slow, _, _ := bot_launch(1, -0.4)
	testing.expect_value(t, slow, BOT_SPEED_MIN)
	// Far enough, the flat speed falls short and it throws as hard as it can.
	fast, _, ok := bot_launch(26, -0.4)
	testing.expect(t, ok, "it can still reach")
	testing.expect_value(t, fast, BOT_SPEED_MAX)
	// A target a good deal higher than the hand is out of reach of the flat speed and not of the full one.
	high, _, high_ok := bot_launch(10, 5)
	testing.expect(t, high_ok, "10 m out and 5 m up can be reached")
	testing.expect_value(t, high, BOT_SPEED_MAX)
}

@(test)
aim_reaches_a_standing_player_at_every_range :: proc(t: ^testing.T) {
	from := Vec3{3, 0, 4}
	for d in ([?]f32{3.5, 5, 8, 11, 14, 17.5}) {
		for a in ([?]f32{0, 1, 2.5, 4, 5.5}) {
			at := from + {d * math.sin(a), 0, -d * math.cos(a)}
			yaw, pitch, speed, ok := bot_aim(from, at, {}, 1)
			testing.expectf(t, ok, "%v m away is in reach", d)
			act := Bot_Act {
				dir   = look_dir({yaw = yaw, pitch = pitch}),
				power = u8(math.round(speed * 10)),
			}
			testing.expectf(t, flies_into_body(from, act, at), "a throw %v m away at heading %v misses", d, a)
			testing.expectf(t, closest_approach(from, act, at) < 0.03, "a throw %v m away at heading %v passes %v m from the chest", d, a, closest_approach(from, act, at))
		}
	}
	_, _, _, ok := bot_aim({0, 0, 0}, {0, 0, -40}, {}, 1)
	testing.expect(t, !ok, "40 m is out of reach")
}

@(test)
aim_leads_a_walking_player :: proc(t: ^testing.T) {
	from := Vec3{0, 0, 0}
	at := Vec3{-4, 0, -10}
	vel := Vec3{3.2, 0, 0}
	hit :: proc(from, at, vel: Vec3, lead: f32) -> bool {
		yaw, pitch, speed, ok := bot_aim(from, at, vel, lead)
		act := Bot_Act {
			dir   = look_dir({yaw = yaw, pitch = pitch}),
			power = u8(math.round(speed * 10)),
		}
		return ok && flies_into_body(from, act, at, vel)
	}
	testing.expect(t, hit(from, at, vel, 1), "leading all the way hits")
	testing.expect(t, hit(from, at, vel, BOT_LEAD), "and so does the bot's lead")
	testing.expect(t, !hit(from, at, vel, 0), "aiming where they are does not")
	_, _, _, ok := bot_aim(from, at, vel, 1)
	testing.expect(t, ok, "it can be reached")
}

@(test)
aim_meets_a_walking_player_across_toward_and_away :: proc(t: ^testing.T) {
	scratch :: proc(t: ^testing.T, from, at, vel: Vec3, lead: f32) -> f32 {
		yaw, pitch, speed, ok := bot_aim(from, at, vel, lead)
		testing.expect(t, ok, "in reach")
		act := Bot_Act {
			dir   = look_dir({yaw = yaw, pitch = pitch}),
			power = u8(math.round(speed * 10)),
		}
		return closest_approach(from, act, at, vel)
	}
	from := Vec3{0, 0, 0}
	// Leading all the way, it passes within a few centimetres of the chest of somebody walking
	// across its aim, away from it, and toward it, near and far.
	cases := [?][2]Vec3{
		{{-4, 0, -10}, {3.2, 0, 0}},
		{{0, 0, -12}, {0, 0, -3.2}},
		{{0, 0, -16}, {0, 0, 3.2}},
		{{-8, 0, -14}, {0, 0, -3.2}},
	}
	for c, i in cases {
		full := scratch(t, from, c[0], c[1], 1)
		testing.expectf(t, full < 0.05, "case %d: leading all the way passes %v m from the chest", i, full)
		// The bot leads nine tenths of the way, and so passes a little wide, well inside the body.
		part := scratch(t, from, c[0], c[1], BOT_LEAD)
		testing.expectf(t, part > 0.05 && part < 0.3, "case %d: the bot's lead passes %v m from the chest", i, part)
	}
}

@(test)
a_bot_that_watched_a_player_walk_leads_them :: proc(t: ^testing.T) {
	b, v := duel(10)
	b.throw_in = 1 // time for it to work out how fast they go
	walking := Vec3{3.2, 0, 0}
	pos := Vec3{-5, 0, -10}
	v.players[1].pos = pos
	threw := false
	for _ in 0 ..< 600 {
		pos += walking * STEP
		v.players[1].pos = pos
		act := bot_step(&b, &v, 0, STEP)
		if act.throw {
			testing.expect(t, near(b.target_vel.x, 3.2, 0.15), "it has seen how fast they go")
			testing.expect(t, near(b.target_vel.z, 0, 0.01), "and that it is not up or down")
			testing.expect(t, flies_into_body({0, 0, 0}, act, pos, walking), "and its balloon meets them")
			threw = true
			break
		}
	}
	testing.expect(t, threw, "it threw")
}

@(test)
a_bot_turns_no_faster_than_it_can :: proc(t: ^testing.T) {
	b, v := duel(10)
	v.players[1].pos = {10, 0, 0} // a quarter turn to the right
	bot_step(&b, &v, 0, STEP)
	testing.expect(t, near(b.heading, BOT_TURN_RATE * STEP, 0.0005), "one step turns one step's worth")
	for _ in 0 ..< 19 {
		bot_step(&b, &v, 0, STEP)
	}
	testing.expect(t, near(b.heading, BOT_TURN_RATE * 20 * STEP, 0.001), "and a steady rate after that")
	for _ in 0 ..< 40 {
		bot_step(&b, &v, 0, STEP)
	}
	testing.expect(t, near(b.heading, math.PI * 0.5, 0.001), "it stops on the target and does not overshoot")
}

@(test)
a_bot_turns_the_short_way_round :: proc(t: ^testing.T) {
	b, v := duel(10)
	b.heading = 6.1
	v.players[1].pos = {10 * math.sin(f32(0.3)), 0, -10 * math.cos(f32(0.3))}
	bot_step(&b, &v, 0, STEP)
	testing.expect(t, b.heading > 6.1, "from just before a full turn to just after goes forward, through zero")
	for _ in 0 ..< 30 {
		bot_step(&b, &v, 0, STEP)
	}
	testing.expect(t, near(b.heading, 0.3, 0.002), "and arrives")
}

@(test)
a_bot_goes_for_the_nearest_player_standing :: proc(t: ^testing.T) {
	b, _ := duel(10)
	v := view_of(alive(0, 0, 0), alive(1, 0, -12), alive(2, 9, 0))
	for _ in 0 ..< 90 {
		bot_step(&b, &v, 0, STEP)
	}
	testing.expect_value(t, b.target, 2)
	testing.expect(t, near(b.heading, math.PI * 0.5, 0.01), "it faces the nearer one, to the east")
	// Knocked out, they are no longer a target, and it turns to the other.
	v.players[2].hp = 0
	for _ in 0 ..< 120 {
		bot_step(&b, &v, 0, STEP)
	}
	testing.expect_value(t, b.target, 1)
	testing.expect(t, near(angle_diff(b.heading, 0), 0, 0.01), "it faces the one to the north")
}

@(test)
a_bot_with_nobody_to_fight_goes_to_the_middle_and_waits :: proc(t: ^testing.T) {
	b := bot_new(7)
	v := view_of(alive(0, 10, 0))
	r := run_bot(&b, &v, 0, 2)
	testing.expect_value(t, r.count, 0)
	testing.expect(t, r.last.input.forward > 0.4, "it sets off for the middle")
	testing.expect(t, near(angle_diff(b.heading, -math.PI * 0.5), 0, 0.02), "facing west, where the middle is")
	// Close enough to the middle, it stands.
	b = bot_new(7)
	v = view_of(alive(0, 2, 0))
	r = run_bot(&b, &v, 0, 2)
	testing.expect_value(t, r.last.input.forward, 0)
	testing.expect_value(t, r.last.input.strafe, 0)
	// Not in the match, or knocked out, it does nothing at all.
	b = bot_new(7)
	v = view_of(alive(1, 0, -8))
	r = run_bot(&b, &v, 0, 5)
	testing.expect_value(t, r.count, 0)
	testing.expect_value(t, r.last.input, Input{})
}

@(test)
a_knocked_out_bot_does_nothing :: proc(t: ^testing.T) {
	b, v := duel(8)
	v.players[0].hp = 0
	r := run_bot(&b, &v, 0, 10)
	testing.expect_value(t, r.count, 0)
	testing.expect_value(t, r.last.input, Input{})
	// Back on its feet, it goes at them again.
	v.players[0].hp = MAX_HEALTH
	r = run_bot(&b, &v, 0, 10)
	testing.expect(t, r.count > 0, "it throws again")
}

@(test)
a_bot_keeps_its_range :: proc(t: ^testing.T) {
	push :: proc(d: f32, hp: u8) -> Input {
		b, v := duel(d)
		v.players[0].hp = hp
		return bot_step(&b, &v, 0, STEP).input
	}
	// Facing the player to the north, so forward is toward them.
	far := push(16, 100)
	testing.expect(t, near(far.forward, BOT_STICK, 0.001), "too far: closes in at full push")
	testing.expect(t, near(far.strafe, 0, 0.001), "and does not circle")
	close := push(3, 100)
	testing.expect(t, near(close.forward, -BOT_STICK, 0.001), "too close: backs away at full push")
	good := push(8.5, 100)
	testing.expect(t, near(good.forward, 0, 0.001), "a good range: neither")
	testing.expect(t, near(abs(good.strafe), BOT_CIRCLE * BOT_STICK, 0.001), "it circles instead")
	// Half way between good and too far, it half closes in.
	half := push(BOT_RANGE_FAR + BOT_RANGE_EASE * 0.5, 100)
	testing.expect(t, near(half.forward, BOT_STICK * 0.5, 0.01), "the push grows over the ease distance")
	// Wounded, it wants more room.
	testing.expect(t, push(8, BOT_WOUNDED).forward < -0.8, "wounded, 8 m is too close")
	testing.expect(t, push(8, BOT_WOUNDED + 1).forward > -0.001, "a little healthier, it is fine")
	testing.expect(t, near(push(16, BOT_WOUNDED).forward, BOT_STICK * 0.5, 0.01), "wounded, 16 m is only just too far")
}

@(test)
a_bot_circles_and_changes_its_mind_now_and_then :: proc(t: ^testing.T) {
	b, v := duel(8.5)
	last_sign := f32(0)
	flips := 0
	dwell := 0
	shortest := 100000
	for _ in 0 ..< 60 * 40 {
		s := bot_step(&b, &v, 0, STEP).input.strafe
		sign := s > 0 ? f32(1) : f32(-1)
		if sign != last_sign && last_sign != 0 {
			flips += 1
			shortest = min(shortest, dwell)
			dwell = 0
		}
		last_sign = sign
		dwell += 1
	}
	testing.expectf(t, flips >= 4, "it changed direction %v times in 40 s", flips)
	testing.expectf(t, flips <= 30, "and not every step: %v times", flips)
	testing.expectf(t, shortest >= int(BOT_STRAFE_MIN * 60) - 2, "never within %v steps", shortest)
}

@(test)
a_bot_waits_to_notice_a_player_before_it_throws :: proc(t: ^testing.T) {
	b, v := duel(8.5)
	r := run_bot(&b, &v, 0, 1)
	testing.expect(t, r.count >= 1, "it throws")
	first := f32(r.step_of[0]) * STEP
	testing.expectf(t, first >= BOT_NOTICE - 0.03 && first <= BOT_NOTICE + 0.05, "the first throw came at %v s", first)
}

@(test)
a_bot_lets_go_only_when_it_faces_its_aim :: proc(t: ^testing.T) {
	b, v := duel(8.5)
	b.heading = 1 // a radian off
	b.target = 1
	b.seen = 5
	r := run_bot(&b, &v, 0, 1)
	testing.expect(t, r.count >= 1, "it throws once it has turned")
	// It needs to turn from 1 radian to within the tolerance of 0 at BOT_TURN_RATE.
	steps := (1 - BOT_AIM_TOLERANCE) / BOT_TURN_RATE * 60
	testing.expectf(t, f32(r.step_of[0]) >= steps - 2, "it threw on step %v, before it faced the aim", r.step_of[0])
	testing.expectf(t, f32(r.step_of[0]) <= steps + 3, "and not long after, on step %v", r.step_of[0])
}

@(test)
a_bot_spaces_its_throws :: proc(t: ^testing.T) {
	b, v := duel(8.5)
	r := run_bot(&b, &v, 0, 60)
	testing.expectf(t, r.count >= 14 && r.count <= 28, "%v throws in a minute", r.count)
	for i in 1 ..< r.count {
		gap := f32(r.step_of[i] - r.step_of[i - 1]) * STEP
		testing.expectf(t, gap >= 2.17 && gap <= 4.1, "a gap of %v s, the bot waits 2.2 to 4 s", gap)
	}
	testing.expect_value(t, b.thrown, r.count)
}

@(test)
a_bot_throws_only_within_reach :: proc(t: ^testing.T) {
	for d in ([?]f32{1.5, BOT_THROW_MIN - 0.3, BOT_THROW_MAX + 0.3, 25}) {
		b, v := duel(d)
		testing.expect_value(t, run_bot(&b, &v, 0, 8).count == 0, true)
	}
	for d in ([?]f32{BOT_THROW_MIN + 0.2, BOT_THROW_MAX - 0.2}) {
		b, v := duel(d)
		testing.expectf(t, run_bot(&b, &v, 0, 8).count > 0, "it throws at %v m", d)
	}
}

@(test)
what_it_throws_is_a_unit_vector_with_a_power_in_range :: proc(t: ^testing.T) {
	b, v := duel(9)
	b.sloppy = 1
	r := run_bot(&b, &v, 0, 30)
	testing.expect(t, r.count > 5, "it threw a few")
	for i in 0 ..< r.count {
		d := r.acts[i].dir
		testing.expect(t, near(d.x * d.x + d.y * d.y + d.z * d.z, 1, 0.001), "a unit vector")
		testing.expect(t, d.z < -0.8, "toward the player to the north")
		testing.expect(t, d.y > 0, "and a little up")
		testing.expect(t, r.acts[i].power >= POWER_MIN && r.acts[i].power <= POWER_MAX, "a power a player could throw with")
	}
}

@(test)
its_throws_hit_a_standing_player_often_but_not_always :: proc(t: ^testing.T) {
	rate :: proc(d: f32) -> f32 {
		hits := 0
		for seed in 1 ..= u32(100) {
			b, v := duel(d)
			b.rng = seed * 7919 | 1
			b.sloppy = 1
			r := run_bot(&b, &v, 0, 5)
			if r.count > 0 && flies_into_body({0, 0, 0}, r.acts[0], {0, 0, -d}) {
				hits += 1
			}
		}
		return f32(hits) / 100
	}
	close, middle, far := rate(6), rate(10), rate(16)
	testing.expectf(t, close >= 0.95, "at 6 m it hit %v of the time", close)
	testing.expectf(t, middle >= 0.45 && middle <= 0.85, "at 10 m it hit %v of the time", middle)
	testing.expectf(t, far >= 0.15 && far <= 0.55, "at 16 m it hit %v of the time", far)
}

@(test)
its_aim_error_grows_with_the_distance_as_documented :: proc(t: ^testing.T) {
	// The error is up to 0.012 rad and 0.005 rad for each metre, either way, so the worst of many
	// throws at a target dead ahead is just under that, in heading.
	worst :: proc(d: f32) -> f32 {
		most := f32(0)
		for seed in 1 ..= u32(300) {
			b, v := duel(d)
			b.rng = seed * 104729 | 1
			b.sloppy = 1
			r := run_bot(&b, &v, 0, 5)
			if r.count > 0 {
				dir := r.acts[0].dir
				most = max(most, abs(math.atan2(dir.x, -dir.z)))
			}
		}
		return most
	}
	near_worst, far_worst := worst(3.5), worst(15)
	testing.expectf(t, near_worst > 0.027 && near_worst <= 0.0296, "at 3.5 m the worst heading error is %v, 0.0295 at most", near_worst)
	testing.expectf(t, far_worst > 0.08 && far_worst <= 0.0875, "at 15 m the worst heading error is %v, 0.087 at most", far_worst)
}

@(test)
a_bot_sidesteps_a_balloon_coming_at_it :: proc(t: ^testing.T) {
	move :: proc(balloon: Flight, strafe_dir: f32) -> [2]f32 {
		b, v := duel(8.5)
		b.strafe_dir = strafe_dir
		b.strafe_left = 100 // no change of mind in this step
		b.dodge_chance, b.react_min, b.react_max = 1, 0, 0 // sees every balloon and moves at once
		v.balloons[0] = balloon
		v.balloon_count = 1
		return world_move(bot_step(&b, &v, 0, STEP).input)
	}
	// From the north, heading south at 10 m/s, 4 m from the bot and 0.3 m east of its path.
	coming := Flight {
		owner = 1,
		pos   = {0.3, 1.5, -4},
		vel   = {0, 0, 10},
	}
	m := move(coming, 1)
	testing.expect(t, near(m.x, -BOT_STICK, 0.02) && near(m.y, 0, 0.02), "the bot is west of its path, so it goes west, at full push")
	coming.pos.x = -0.3
	m = move(coming, 1)
	testing.expect(t, near(m.x, BOT_STICK, 0.02), "and east of it, east")
	// Right in its path, it goes the way it was already circling.
	coming.pos.x = 0
	testing.expect(t, near(move(coming, -1).x, BOT_STICK, 0.02), "circling east, east")
	testing.expect(t, near(move(coming, 1).x, -BOT_STICK, 0.02), "circling west, west")
	// What it does not sidestep: its own, one that has gone past, one far off, one passing wide.
	ignored := [?]Flight {
		{owner = 0, pos = {0.3, 1.5, -4}, vel = {0, 0, 10}},
		{owner = 1, pos = {0.3, 1.5, 3}, vel = {0, 0, 10}},
		{owner = 1, pos = {0.3, 1.5, -(BOT_DODGE_RANGE + 1)}, vel = {0, 0, 10}},
		{owner = 1, pos = {BOT_DODGE_WIDTH + 0.4, 1.5, -4}, vel = {0, 0, 10}},
		{owner = 1, pos = {0.3, 1.5, -4}, vel = {0, 0, 0.2}},
	}
	for f, i in ignored {
		m = move(f, 1)
		testing.expectf(t, near(abs(m.x), BOT_CIRCLE * BOT_STICK, 0.02), "balloon %v is none of its business, it moved %v", i, m)
	}
}

@(test)
a_bot_comes_in_from_the_wall :: proc(t: ^testing.T) {
	b := bot_new(1)
	b.sloppy = 0
	b.strafe_dir = 1
	b.strafe_left = 100
	// 18.5 m out, with a player a good range off along the wall, so that only circling and the wall act.
	v := view_of(alive(0, 0, 18.5), alive(1, 8.4, 18.0))
	m := world_move(bot_step(&b, &v, 0, STEP).input)
	testing.expect(t, m.y < -0.1, "it is pushed toward the middle, which is to the north")
	// Not out far enough for that, circling carries it on.
	b = bot_new(1)
	b.sloppy = 0
	b.strafe_dir = 1
	b.strafe_left = 100
	v = view_of(alive(0, 0, BOT_WALL - 0.5), alive(1, 8.4, BOT_WALL - 1))
	m = world_move(bot_step(&b, &v, 0, STEP).input)
	testing.expect(t, m.y > 0.1, "inside the wall it just circles")
}

@(test)
a_bot_taps_jump_now_and_then :: proc(t: ^testing.T) {
	b, v := duel(8.5)
	presses, held, longest := 0, 0, 0
	for _ in 0 ..< 60 * 60 {
		if bot_step(&b, &v, 0, STEP).input.jump {
			if held == 0 {
				presses += 1
			}
			held += 1
			longest = max(longest, held)
		} else {
			held = 0
		}
	}
	testing.expectf(t, presses >= 9 && presses <= 25, "%v jumps in a minute", presses)
	testing.expectf(t, longest >= 8 && longest <= 10, "each held for %v steps", longest)
}

@(test)
a_bot_gives_the_same_play_for_the_same_seed :: proc(t: ^testing.T) {
	play :: proc(seed: u32) -> (acts: [900]Bot_Act) {
		b := bot_new(seed)
		v := view_of(alive(0, 0, 0), alive(1, 3, -9))
		for i in 0 ..< len(acts) {
			v.players[1].pos.x = 3 + 2 * math.sin(f32(i) * 0.02)
			acts[i] = bot_step(&b, &v, 0, STEP)
		}
		return
	}
	a, b, c := play(5), play(5), play(6)
	same, differ := true, false
	for i in 0 ..< len(a) {
		same &&= a[i] == b[i]
		differ ||= a[i] != c[i]
	}
	testing.expect(t, same, "the same seed plays the same game")
	testing.expect(t, differ, "another seed does not")
}

@(test)
a_bot_starts_afresh_on_a_player_who_has_been_knocked_out_and_comes_back :: proc(t: ^testing.T) {
	b, v := duel(8.5)
	run_bot(&b, &v, 0, 3)
	v.players[1].hp = 0
	run_bot(&b, &v, 0, 0.5)
	// Back on their spawn point, a long way off.
	v.players[1].hp = MAX_HEALTH
	v.players[1].pos = {6, 0, -7}
	bot_step(&b, &v, 0, STEP)
	testing.expect_value(t, b.target_vel, Vec3{})
	testing.expect(t, b.seen < 0.001, "it has not seen them for a moment yet")
	b.throw_in = 0
	r := run_bot(&b, &v, 0, 1)
	testing.expect(t, r.count >= 1, "it throws at them in the end")
	testing.expect(t, f32(r.step_of[0]) * STEP >= BOT_NOTICE - 0.05, "but not before it has noticed them")
}

@(test)
the_stick_walks_where_the_bot_wants_to_go :: proc(t: ^testing.T) {
	for h in ([?]f32{0, 0.7, math.PI * 0.5, 2.5, 4, 5.9}) {
		for w in ([?][2]f32{{1, 0}, {0, 1}, {-1, 0}, {0, -1}, {0.6, -0.3}}) {
			walking := bot_stick(w, h)
			walking.yaw = h
			m := world_move(walking)
			testing.expectf(t, near(m.x, w.x * BOT_STICK, 0.001) && near(m.y, w.y * BOT_STICK, 0.001), "heading %v wish %v walks %v", h, w, m)
		}
	}
	testing.expect_value(t, bot_stick({0, -1}, 0).forward, BOT_STICK)
	testing.expect_value(t, bot_stick({1, 0}, 0).strafe, BOT_STICK)
	testing.expect(t, near(bot_stick({1, 0}, math.PI * 0.5).forward, BOT_STICK, 0.001), "east is ahead for a bot facing east")
}

@(test)
a_push_is_never_longer_than_one :: proc(t: ^testing.T) {
	v := bot_limit({3, 4})
	testing.expect(t, near(v.x, 0.6) && near(v.y, 0.8), "a long push is cut to one")
	testing.expect_value(t, bot_limit({0.3, 0.4}), [2]f32{0.3, 0.4})
}

@(test)
random_numbers_are_in_range_and_different :: proc(t: ^testing.T) {
	b := bot_new(99)
	lo, hi := f32(1), f32(0)
	sum := f32(0)
	for _ in 0 ..< 10000 {
		r := bot_rand(&b)
		lo, hi = min(lo, r), max(hi, r)
		sum += r
	}
	testing.expect(t, lo >= 0 && hi < 1, "from 0 up to but not including 1")
	testing.expect(t, near(sum / 10000, 0.5, 0.02), "spread about evenly")
	testing.expect(t, lo < 0.01 && hi > 0.99, "right across the range")
	// A seed of 0 does not leave it stuck, and the same seed gives the same numbers.
	a, c := bot_new(0), bot_new(0)
	first := bot_rand(&a)
	testing.expect(t, a.rng != 0 && bot_rand(&a) != first, "seed 0 still gives different numbers")
	testing.expect_value(t, bot_rand(&c), first)
}

TEST_WALK_SPEED :: f32(3.2) // tv_sim::WALK_SPEED_MS

// A balloon of somebody else's, in the air 4 m north of a bot at the origin and heading straight
// at it at 10 m/s, a little to its east.
balloon_coming :: proc(id: u16) -> Flight {
	return {id = id, owner = 1, pos = {0.3, 1.5, -4}, vel = {0, 0, 10}}
}

// Whether a step of the bot's walking is a sidestep out of the way of balloon_coming: the bot
// circles at no more than BOT_CIRCLE * BOT_STICK across the line it faces, and a sidestep pushes
// past that.
sidestepping :: proc(b: ^Bot, v: ^Match_View) -> bool {
	m := world_move(bot_step(b, v, 0, STEP).input)
	return abs(m.x) > 0.8
}

// A bot at the origin whose random numbers start from `seed`, with balloon_coming (id 1) in the
// air, and the match it sees. It has nothing to wait for and makes no aim error.
dodger :: proc(seed: u32) -> (b: Bot, v: Match_View) {
	b, v = duel(8.5)
	b.rng = seed * 2654435761 | 1
	v.balloons[0] = balloon_coming(1)
	v.balloon_count = 1
	return
}

// Throws one balloon a second at the bot `b` for `seconds`, each aimed by the bot's own solver at
// where the bot is and where it is going, from `dist` metres away to the south. That is better
// than a player aims. The balloons fly the way tv_sim flies them, and the bot walks the way
// tv_sim lets it. `owner` is 1 for balloons the bot takes for a rival's and 0 for balloons it
// takes for its own, which it lets pass. Gives the hits and the throws.
thrown_at_bot :: proc(b: ^Bot, dist: f32, seconds: int, owner: u8 = 1) -> (hits, throws: int) {
	thrower := Vec3{0, 0, dist}
	pos, vel: Vec3
	v := view_of(alive(0, 0, 0), alive(1, thrower.x, thrower.z))
	flights: [8]Flight
	flying: [8]bool
	next_id := u16(1)
	until_throw := f32(1)
	for _ in 0 ..< seconds * 60 {
		v.players[0].pos = pos
		v.balloon_count = 0
		for f, i in flights {
			if flying[i] {
				v.balloons[v.balloon_count] = f
				v.balloon_count += 1
			}
		}
		walk := world_move(bot_step(b, &v, 0, STEP).input)
		vel = {walk.x * TEST_WALK_SPEED, 0, walk.y * TEST_WALK_SPEED}
		pos += vel * STEP
		until_throw -= STEP
		if until_throw <= 0 {
			until_throw = 1
			yaw, pitch, speed, reaches := bot_aim(thrower, pos, vel, 1)
			dir := look_dir({yaw = yaw, pitch = pitch})
			for i in 0 ..< len(flights) {
				if reaches && !flying[i] {
					flights[i] = {id = next_id, owner = owner, pos = thrower + {0, 1.5, 0} + dir * 0.5, vel = dir * speed}
					flying[i] = true
					next_id += 1
					throws += 1
					break
				}
			}
		}
		for i in 0 ..< len(flights) {
			if !flying[i] {
				continue
			}
			flights[i].vel.y -= GRAVITY * STEP
			flights[i].pos += flights[i].vel * STEP
			at := flights[i].pos
			dx, dz := at.x - pos.x, at.z - pos.z
			if at.y <= 0 {
				flying[i] = false
			} else if dx * dx + dz * dz <= 0.4 * 0.4 && at.y <= 1.9 {
				flying[i] = false
				hits += 1
			}
		}
	}
	return
}

// The share of throws that hit, over twelve bots with different seeds.
hit_share :: proc(dist: f32, chance: f32 = -1, owner: u8 = 1) -> f32 {
	hits, throws := 0, 0
	for seed in 1 ..= 12 {
		b := bot_new(u32(seed) * 7919)
		b.sloppy = 0
		if chance >= 0 {
			b.dodge_chance = chance
			if chance == 1 {
				b.react_min, b.react_max = 0, 0
			}
		}
		h, n := thrown_at_bot(&b, dist, 40, owner)
		hits += h
		throws += n
	}
	return f32(hits) / f32(max(throws, 1))
}

@(test)
a_bot_sees_some_balloons_and_not_others :: proc(t: ^testing.T) {
	seen := 0
	for seed in 1 ..= 400 {
		b, v := dodger(u32(seed))
		b.react_min, b.react_max = 0, 0
		if sidestepping(&b, &v) {
			seen += 1
		}
	}
	testing.expectf(t, seen >= 140 && seen <= 180, "%v of 400 balloons were dodged at once, about 40 percent are seen", seen)
	for seed in 1 ..= 50 {
		b, v := dodger(u32(seed))
		b.react_min, b.react_max = 0, 0
		b.dodge_chance = 0
		testing.expect(t, !sidestepping(&b, &v), "a bot that never sees a balloon never dodges it")
		b, v = dodger(u32(seed))
		b.react_min, b.react_max = 0, 0
		b.dodge_chance = 1
		testing.expect(t, sidestepping(&b, &v), "and one that always does, does")
	}
}

@(test)
a_bot_takes_a_moment_to_move_out_of_the_way :: proc(t: ^testing.T) {
	b, v := dodger(7)
	b.dodge_chance, b.react_min, b.react_max = 1, 0.3, 0.3
	for i in 0 ..< 30 {
		sidestepped := sidestepping(&b, &v)
		elapsed := f32(i + 1) * STEP
		testing.expectf(t, !(elapsed <= 0.25 && sidestepped), "it moved after %v s, before its reaction time", elapsed)
		testing.expectf(t, !(elapsed >= 0.35 && !sidestepped), "it still had not moved after %v s", elapsed)
	}
	// Each balloon has its own reaction time between the least and the most.
	first, last, varied := f32(9), f32(0), 0
	for seed in 1 ..= 40 {
		b, v = dodger(u32(seed))
		b.dodge_chance, b.react_min, b.react_max = 1, 0.2, 0.4
		started := f32(-1)
		for i in 0 ..< 40 {
			if sidestepping(&b, &v) {
				started = f32(i + 1) * STEP
				break
			}
		}
		testing.expectf(t, started >= 0.2 - STEP && started <= 0.4 + STEP, "moved after %v s, between 0.2 and 0.4", started)
		first, last = min(first, started), max(last, started)
		if started > 0.2 + STEP && started < 0.4 - STEP {
			varied += 1
		}
	}
	testing.expectf(t, last - first > 0.1 && varied > 5, "the reaction times differ: %v to %v", first, last)
}

@(test)
it_is_decided_once_whether_a_bot_sees_a_balloon :: proc(t: ^testing.T) {
	saw, missed := 0, 0
	for seed in 1 ..= 60 {
		b, v := dodger(u32(seed))
		b.react_min, b.react_max = 0, 0
		first := sidestepping(&b, &v)
		saw += first ? 1 : 0
		missed += first ? 0 : 1
		for _ in 0 ..< 90 {
			testing.expect(t, sidestepping(&b, &v) == first, "a balloon a bot did not see is not seen a moment later, and one it saw is not lost")
		}
	}
	testing.expect(t, saw > 10 && missed > 10, "both happen")
}

@(test)
a_bot_sees_nothing_new_for_a_while_after_a_sidestep :: proc(t: ^testing.T) {
	b, v := dodger(3)
	b.dodge_chance, b.react_min, b.react_max = 1, 0, 0
	testing.expect(t, sidestepping(&b, &v), "it dodges the first")
	v.balloons[0] = balloon_coming(2)
	testing.expect(t, !sidestepping(&b, &v), "and does not see the next one a step later")
	v.balloon_count = 0
	for _ in 0 ..< 58 {
		bot_step(&b, &v, 0, STEP)
	}
	v.balloons[0] = balloon_coming(4)
	v.balloon_count = 1
	testing.expect(t, !sidestepping(&b, &v), "nor one a second after")
	v.balloon_count = 0
	for _ in 0 ..< 30 {
		bot_step(&b, &v, 0, STEP)
	}
	testing.expect_value(t, b.rest, 0) // it counts down to nothing and stays there
	v.balloons[0] = balloon_coming(5)
	v.balloon_count = 1
	testing.expect(t, sidestepping(&b, &v), "but sees the one after that, 1.5 s on")
	testing.expect_value(t, b.rest, BOT_DODGE_REST)
}

@(test)
the_bot_as_played_has_a_human_reaction :: proc(t: ^testing.T) {
	b := bot_new(1)
	testing.expectf(t, b.dodge_chance >= 0.3 && b.dodge_chance <= 0.5, "it sees %v of the balloons that come at it", b.dodge_chance)
	testing.expectf(t, b.react_min >= 0.2 && b.react_max <= 0.5 && b.react_min < b.react_max, "it reacts in %v to %v s", b.react_min, b.react_max)
	testing.expectf(t, BOT_DODGE_REST >= 1 && BOT_DODGE_REST <= 1.5, "it rests %v s after a sidestep", BOT_DODGE_REST)
	testing.expect_value(t, b.aware_count, 0)
	testing.expect_value(t, b.rest, 0)
}

@(test)
a_bot_forgets_balloons_that_are_gone_and_keeps_its_list_in_order :: proc(t: ^testing.T) {
	b, v := dodger(11)
	b.dodge_chance, b.react_min, b.react_max = 1, 0.3, 0.3
	for i in 0 ..< 3 {
		v.balloons[i] = balloon_coming(u16(i + 1))
		v.balloons[i].pos.z = -3 - f32(i)
	}
	v.balloon_count = 3
	bot_step(&b, &v, 0, STEP)
	testing.expect_value(t, b.aware_count, 3)
	// The first goes. The other two are still there with what the bot worked out for them.
	v.balloons[0], v.balloons[1] = v.balloons[1], v.balloons[2]
	v.balloon_count = 2
	bot_step(&b, &v, 0, STEP)
	testing.expect_value(t, b.aware_count, 2)
	for id in ([?]u16{2, 3}) {
		known := bot_aware_of(&b, id)
		testing.expectf(t, known != nil && known.id == id && near(known.wait, 0.3 - 2 * STEP, 0.0005) && known.sees, "balloon %v kept its own state: %v", id, known)
	}
	testing.expect_value(t, b.aware_count, 2)
	// All gone: nothing is left over in the list.
	v.balloon_count = 0
	bot_step(&b, &v, 0, STEP)
	testing.expect_value(t, b.aware_count, 0)
	// More at once than it can follow: it follows BOT_AWARE of them and does not see the rest.
	for i in 0 ..< 20 {
		v.balloons[i] = balloon_coming(u16(i + 1))
	}
	v.balloon_count = 20
	bot_step(&b, &v, 0, STEP)
	testing.expect_value(t, b.aware_count, BOT_AWARE)
	testing.expect(t, bot_aware_of(&b, 20) == nil, "a ninth balloon is not followed")
	testing.expect_value(t, b.aware_count, BOT_AWARE)
	// Knocked out, it starts afresh, rest included.
	b.rest = 1
	v.players[0].hp = 0
	bot_step(&b, &v, 0, STEP)
	testing.expect_value(t, b.aware_count, 0)
	testing.expect_value(t, b.rest, 0)
}

@(test)
a_player_who_aims_well_hits_the_bot_about_half_the_time :: proc(t: ^testing.T) {
	for d in ([?]f32{5, 8, 11, 14}) {
		share := hit_share(d)
		testing.expectf(t, share >= 0.35 && share <= 0.65, "at %v m a thrower who aims as well as a bot does hit %v of the time, about half", d, share)
	}
	// Dodging is what makes the difference, and seeing every balloon at once makes it still more.
	never, usual, always := hit_share(8, 0), hit_share(8), hit_share(8, 1)
	testing.expectf(t, never - usual > 0.15, "a bot that never sees a balloon is hit %v of the time, one that does %v", never, usual)
	testing.expectf(t, usual - always > 0.08, "one that sees them all is hit %v of the time", always)
	// Balloons it takes for its own are none of its business.
	own := hit_share(8, -1, 0)
	testing.expectf(t, own > 0.65, "balloons of its own side hit it %v of the time", own)
}

@(test)
a_bot_gives_the_same_dodges_for_the_same_seed :: proc(t: ^testing.T) {
	play :: proc(seed: u32) -> (hits, throws: int) {
		b := bot_new(seed)
		b.sloppy = 0
		return thrown_at_bot(&b, 8, 30)
	}
	h1, n1 := play(5)
	h2, n2 := play(5)
	testing.expect(t, h1 == h2 && n1 == n2, "the same seed is hit by the same throws")
	differs := false
	for seed in 6 ..= 12 {
		h3, _ := play(u32(seed))
		differs ||= h3 != h1
	}
	testing.expect(t, differs, "other seeds are not")
}

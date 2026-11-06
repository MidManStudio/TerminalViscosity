// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "bot_test.odin"
// ============================================================================

package arena

import "core:math"
import "core:testing"

// Runs a bot for `seconds` with a very plain model of walking: it moves along its heading at the
// speed of the stick, up to the arena wall. Returns where it was at the end, how far out it ever
// was, and the log of what it did.
Bot_Run :: struct {
	pos:         Vec3,
	farthest:    f32,
	throws:      int,
	jumps:       int, // times the jump button went down
	pauses:      int, // times it went from walking to standing
	first_throw: f32,
	throw_times: [64]f32,
	headings_ok: bool,
}

run_bot :: proc(b: ^Bot, start: Vec3, seconds: f32) -> (r: Bot_Run) {
	r.pos = start
	r.headings_ok = true
	was_jump, was_walking := false, false
	r.first_throw = -1
	steps := int(seconds * 60)
	for _ in 0 ..< steps {
		input, throw := bot_step(b, r.pos, 1.0 / 60)
		walk := input.forward * 3.2 / 60
		r.pos.x += math.sin(input.yaw) * walk
		r.pos.z -= math.cos(input.yaw) * walk
		d := math.sqrt(r.pos.x * r.pos.x + r.pos.z * r.pos.z)
		if d > 19.7 {
			r.pos.x *= 19.7 / d
			r.pos.z *= 19.7 / d
		}
		r.farthest = max(r.farthest, d)
		if throw {
			if r.throws < len(r.throw_times) {
				r.throw_times[r.throws] = b.t
			}
			r.throws += 1
			if r.first_throw < 0 {
				r.first_throw = b.t
			}
		}
		if input.jump && !was_jump {
			r.jumps += 1
		}
		walking := input.forward > 0
		if was_walking && !walking {
			r.pauses += 1
		}
		was_jump, was_walking = input.jump, walking
		if input.yaw < 0 || input.yaw >= 2 * math.PI {
			r.headings_ok = false
		}
	}
	return
}

@(test)
two_bots_with_the_same_start_do_the_same :: proc(t: ^testing.T) {
	a, b: Bot
	ra := run_bot(&a, {9.9, 0, 9.9}, 120)
	rb := run_bot(&b, {9.9, 0, 9.9}, 120)
	testing.expect_value(t, ra.pos, rb.pos)
	testing.expect_value(t, ra.throws, rb.throws)
	testing.expect_value(t, a.heading, b.heading)
}

@(test)
a_bot_starts_standing_then_walks_and_stops_every_seven_and_a_half_seconds :: proc(t: ^testing.T) {
	b: Bot
	input, _ := bot_step(&b, {0, 0, 14}, 0.1)
	testing.expect_value(t, input.forward, f32(0))
	for _ in 0 ..< 120 { // 2 s in
		input, _ = bot_step(&b, {0, 0, 5}, 1.0 / 60)
	}
	testing.expect_value(t, input.forward, BOT_STICK)
	c: Bot
	r := run_bot(&c, {0, 0, 5}, 60)
	// Standing 1.5 s of every 7.5 s: from walking to standing seven times in a minute, the first
	// stop being the one it starts in.
	testing.expect_value(t, r.pauses, 7)
}

@(test)
a_bot_jumps_with_a_tap_every_five_seconds :: proc(t: ^testing.T) {
	b: Bot
	r := run_bot(&b, {0, 0, 5}, 60)
	testing.expect_value(t, r.jumps, 12)
	c: Bot
	held := 0
	for _ in 0 ..< 60 * 5 {
		input, _ := bot_step(&c, {0, 0, 5}, 1.0 / 60)
		if input.jump {
			held += 1
		}
	}
	testing.expect(t, held >= 8 && held <= 10, "the button is held for about 0.15 s, a tap, and not for ever")
}

@(test)
a_bot_throws_every_four_seconds_and_not_before_the_first :: proc(t: ^testing.T) {
	b: Bot
	r := run_bot(&b, {0, 0, 5}, 61) // 15 throws, at 4, 8, and so on to 60 s
	testing.expect_value(t, r.throws, 15)
	testing.expect(t, r.first_throw >= 4 && r.first_throw < 4.05, "the first throw is at 4 s")
	for i in 1 ..< r.throws {
		gap := r.throw_times[i] - r.throw_times[i - 1]
		testing.expectf(t, gap > 3.98 && gap < 4.03, "throw %d came %v s after the one before", i, gap)
	}
}

@(test)
a_bot_never_throws_twice_in_a_step_even_after_a_long_one :: proc(t: ^testing.T) {
	b: Bot
	_, throw := bot_step(&b, {0, 0, 5}, 10)
	testing.expect(t, throw, "a throw is due")
	_, throw = bot_step(&b, {0, 0, 5}, 0.001)
	testing.expect(t, !throw, "and only the one")
}

@(test)
a_bot_wanders_without_going_far_from_the_middle_and_keeps_moving :: proc(t: ^testing.T) {
	b: Bot
	r := run_bot(&b, {9.9, 0, 9.9}, 600)
	testing.expectf(t, r.farthest < BOT_RADIUS + 3, "it went as far as %v m from the middle", r.farthest)
	testing.expect(t, r.headings_ok, "the heading stays inside one turn")
	// It is not stuck: over ten minutes it is somewhere that is neither the start nor the middle.
	d := math.sqrt(r.pos.x * r.pos.x + r.pos.z * r.pos.z)
	testing.expect(t, abs(r.pos.x - 9.9) + abs(r.pos.z - 9.9) > 1, "it has moved from where it started")
	testing.expect(t, d <= BOT_RADIUS + 3, "and is still on the sand")
}

@(test)
a_bot_that_is_too_far_out_turns_back_toward_the_middle :: proc(t: ^testing.T) {
	// Out at 16 m on the +x side, looking straight outward.
	b := Bot{heading = math.PI * 0.5}
	pos := Vec3{16, 0, 0}
	start := pos.x
	for _ in 0 ..< 60 * 8 {
		input, _ := bot_step(&b, pos, 1.0 / 60)
		walk := input.forward * 3.2 / 60
		pos.x += math.sin(input.yaw) * walk
		pos.z -= math.cos(input.yaw) * walk
	}
	testing.expect(t, math.sqrt(pos.x * pos.x + pos.z * pos.z) < start - 2, "eight seconds later it is well inside where it was")
	// And on the other sides too.
	for angle in ([]f32{0, 1.2, 2.5, 3.9, 5.1}) {
		b = Bot{heading = angle}
		pos = {math.sin(angle) * 17, 0, -math.cos(angle) * 17}
		for _ in 0 ..< 60 * 10 {
			input, _ := bot_step(&b, pos, 1.0 / 60)
			walk := input.forward * 3.2 / 60
			pos.x += math.sin(input.yaw) * walk
			pos.z -= math.cos(input.yaw) * walk
		}
		testing.expectf(t, math.sqrt(pos.x * pos.x + pos.z * pos.z) < 16, "from the %v side it is still %v m out", angle, math.sqrt(pos.x * pos.x + pos.z * pos.z))
	}
}

@(test)
the_heading_that_looks_at_the_middle_is_the_one_the_bot_steers_to :: proc(t: ^testing.T) {
	// From (0, 14) the middle is toward -z, which is heading 0. From (14, 0) it is toward -x.
	b := Bot{heading = 3}
	for _ in 0 ..< 60 * 5 {
		bot_step(&b, {0, 0, 14}, 1.0 / 60)
	}
	d := math.mod(b.heading + math.PI, 2 * math.PI) - math.PI // from -pi to pi
	testing.expect(t, abs(d) < 0.8, "heading 0 faces -z, toward the middle from the south")
}

@(test)
a_bot_wanders_its_heading_one_way_and_back_over_seventeen_seconds :: proc(t: ^testing.T) {
	// Held still at the middle, nothing steers it, so the drift is all that turns it. The drift is
	// 0.6 sin(0.37 t) radians a second: a quarter of a period of it, 4.25 s, turns it by 1.62
	// radians, and a whole period, 17 s, brings it back to the heading it began with.
	b := Bot{heading = 1}
	for _ in 0 ..< int(4.25 * 60) {
		bot_step(&b, {0, 0, 0}, 1.0 / 60)
	}
	turned := math.mod(b.heading - 1 + 3 * math.PI, 2 * math.PI) - math.PI
	testing.expect(t, abs(turned - 1.62) < 0.1, "a quarter of a period turns it about 1.62 radians")
	for _ in 0 ..< int(12.75 * 60) {
		bot_step(&b, {0, 0, 0}, 1.0 / 60)
	}
	back := math.mod(b.heading - 1 + 3 * math.PI, 2 * math.PI) - math.PI
	testing.expect(t, abs(back) < 0.15, "a whole one brings it back")
}

@(test)
a_bot_inside_its_radius_is_not_steered_toward_the_middle :: proc(t: ^testing.T) {
	// At (5, 5), 7 m out, pointing away from the middle: for a second only the drift turns it.
	b := Bot{heading = 1}
	for _ in 0 ..< 60 {
		bot_step(&b, {5, 0, 5}, 1.0 / 60)
	}
	testing.expect(t, abs(b.heading - 1) < 0.2, "it keeps its heading, give or take the drift")
	// Past the radius, the same second turns it a long way.
	c := Bot{heading = 1}
	for _ in 0 ..< 60 {
		bot_step(&c, {10, 0, 10}, 1.0 / 60)
	}
	testing.expect(t, abs(c.heading - 1) > 0.5, "at 14 m it is turned for the middle")
}

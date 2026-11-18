// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "jet_test.odin"
// ============================================================================

package carry

import "../lab"
import "core:math"
import "core:testing"

// Puts a drop in the stream, `x` along and `y` metres above 0.6 m, which is over the island in the middle of the
// lab, falling at `speed` metres a second, and made `age` seconds ago. The drops of one stream have to be within
// the box that the first one sets, so they are kept within half a metre.
add_drop :: proc(s: PourScene, x, y, speed, age: f32, ml: f32 = 3.4) -> int {
	i := s.st.sim.count
	ok := stream_spawn_ml(s.st, s.l, {x, y + 0.6, 0}, {0, -speed, 0}, u16(1), ml)
	assert(ok)
	s.st.age[i] = age
	return i
}

@(test)
jet_order_is_the_order_the_drops_were_made_in_even_after_swaps :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	for k in 0 ..< 6 {
		add_drop(s, 0.05 * f32(k), 1.0, 1.5, 0)
	}
	stream_remove(s.st, 1) // the last one moves into its place
	stream_remove(s.st, 3)
	order: [MAX_STREAM]int
	n := jet_order(s.st, order[:])
	testing.expect_value(t, n, 4)
	for k in 1 ..< n {
		testing.expect(t, s.st.seq[order[k - 1]] < s.st.seq[order[k]], "older first")
	}
	// What is left is drops 0, 2, 4 and 5, as made.
	testing.expect_value(t, s.st.seq[order[0]], u32(0))
	testing.expect_value(t, s.st.seq[order[1]], u32(2))
	testing.expect_value(t, s.st.seq[order[2]], u32(4))
	testing.expect_value(t, s.st.seq[order[3]], u32(5))
}

@(test)
jet_order_stops_at_the_room_it_is_given :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	for k in 0 ..< 5 {
		add_drop(s, 0.05 * f32(k), 1.0, 1.5, 0)
	}
	small: [3]int
	testing.expect_value(t, jet_order(s.st, small[:]), 3)
	testing.expect_value(t, jet_order(s.st, small[:0]), 0)
}

@(test)
two_drops_going_the_same_way_close_enough_are_one_jet :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	a := add_drop(s, 0, 1.0, 1.5, 0.04) // the older, a little lower
	b := add_drop(s, 0, 1.0, 1.5, 0)
	s.st.sim.particles[a].x.y -= 0.06
	testing.expect(t, jet_joined(s.st, a, b), "6 cm apart after 0.04 s at 1.5 m/s")
}

@(test)
drops_that_are_slow_resting_misaligned_or_far_apart_are_not_one_jet :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	a := add_drop(s, 0, 1.0, 1.5, 0.04)
	b := add_drop(s, 0, 1.0, 1.5, 0)
	s.st.sim.particles[a].x.y -= 0.06
	testing.expect(t, jet_joined(s.st, a, b), "to start with")

	s.st.sim.particles[b].v = {0, -0.1, 0}
	testing.expect(t, !jet_joined(s.st, a, b), "one of them is slow")
	s.st.sim.particles[b].v = {0, -1.5, 0}

	s.st.rest[b] = 0.3
	testing.expect(t, !jet_joined(s.st, a, b), "one of them is lying still")
	s.st.rest[b] = 0

	s.st.sim.particles[b].v = {1.5, 0, 0} // at right angles
	testing.expect(t, !jet_joined(s.st, a, b), "they go different ways")
	s.st.sim.particles[b].v = {0, -1.5, 0}

	s.st.sim.particles[a].x.y -= 0.3 // 36 cm apart, where 1.6 x 1.5 x 0.04 + 0.04 is 14 cm
	testing.expect(t, !jet_joined(s.st, a, b), "too far apart for the time between them")
}

@(test)
a_jet_that_is_just_inside_the_reach_is_joined_and_just_outside_is_not :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	a := add_drop(s, 0, 1.0, 1.0, 0.1)
	b := add_drop(s, 0, 1.0, 1.0, 0)
	reach := JET_REACH * 1.0 * 0.1 + JET_SLACK
	s.st.sim.particles[a].x.y -= reach - 0.01
	testing.expect(t, jet_joined(s.st, a, b), "just inside")
	s.st.sim.particles[a].x.y -= 0.02
	testing.expect(t, !jet_joined(s.st, a, b), "just outside")
}

@(test)
drops_made_in_the_same_moment_are_joined_only_when_they_are_almost_together :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	a := add_drop(s, 0, 1.0, 1.5, 0)
	b := add_drop(s, 0, 1.0, 1.5, 0)
	s.st.sim.particles[a].x.y -= JET_SLACK * 0.5
	testing.expect(t, jet_joined(s.st, a, b), "within the slack")
	s.st.sim.particles[a].x.y -= JET_SLACK
	testing.expect(t, !jet_joined(s.st, a, b), "outside it")
}

// A falling jet of `count` drops 6 cm apart, the oldest lowest: they were made 0.04 s apart at 1.5 m/s.
falling :: proc(s: PourScene, count: int) {
	for k in 0 ..< count {
		i := add_drop(s, 0, 1.0, 1.5, 0.04 * f32(count - 1 - k))
		s.st.sim.particles[i].x.y -= 0.06 * f32(count - 1 - k)
	}
}

@(test)
a_run_of_joined_drops_is_one_smooth_jet_from_the_oldest_to_the_newest :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	falling(s, 6)
	jet := new(Jet)
	defer free(jet)
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 1)
	testing.expect_value(t, int(jet.strand_len[0]), 5 * (JET_SUBDIV + 1) + 1)
	testing.expect_value(t, jet.count, 5 * (JET_SUBDIV + 1) + 1)
	for i in 0 ..< 6 {
		testing.expect(t, !jet.loose[i], "no drop is on its own")
	}
	// It starts at the oldest drop, which is the lowest, and ends at the newest.
	first, last := jet.points[0], jet.points[jet.count - 1]
	testing.expect(t, math.abs(first.pos.y - (s.st.origin.y + s.st.sim.particles[0].x.y)) < 1e-4, "starts at the oldest")
	testing.expect_value(t, int(first.drop), 0)
	testing.expect(t, math.abs(last.pos.y - (s.st.origin.y + s.st.sim.particles[5].x.y)) < 1e-4, "ends at the newest")
	testing.expect_value(t, int(last.drop), 5)
	// Going up from the oldest, every point is higher than the one before, so it does not double back.
	for i in 1 ..< jet.count {
		testing.expect(t, jet.points[i].pos.y > jet.points[i - 1].pos.y, "up")
	}
	// Both ends are drawn thinner than the middle, since neither is joined to a mouth.
	middle := jet.points[jet.count / 2].radius
	testing.expect(t, first.radius < middle * 0.8 && last.radius < middle * 0.8, "tapered at the ends, by the 0.7 of the tip")
	testing.expect(t, first.radius >= JET_R_MIN * JET_TIP - 1e-6, "but not thinner than that")
}

@(test)
the_points_between_two_drops_lie_between_them :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	falling(s, 3)
	jet := new(Jet)
	defer free(jet)
	jet_build(s.st, jet)
	a, mid, b := jet.points[0], jet.points[1], jet.points[2]
	testing.expect(t, math.abs(mid.pos.y - (a.pos.y + b.pos.y) * 0.5) < 1e-3, "the point between two on a line is halfway")
	// And the same for the last two drops, where the curve has no drop after it to lean on.
	c, mid2, d := jet.points[2], jet.points[3], jet.points[4]
	testing.expect(t, math.abs(mid2.pos.y - (c.pos.y + d.pos.y) * 0.5) < 1e-3, "also at the other end")
	testing.expect_value(t, int(mid.drop), 0) // it has the color of the nearer control, the first
}

@(test)
drops_that_are_not_joined_make_separate_jets_and_a_lone_drop_is_loose :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	falling(s, 3) // drops 0 to 2
	// A second jet well away from the first, made later: drops 3 and 4.
	for k in 0 ..< 2 {
		i := add_drop(s, 0.4, 1.0, 1.5, 0.04 * f32(1 - k))
		s.st.sim.particles[i].x.y -= 0.06 * f32(1 - k)
	}
	add_drop(s, -0.4, 1.0, 1.5, 0) // a lone drop, 5
	jet := new(Jet)
	defer free(jet)
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 2)
	testing.expect(t, jet.loose[5], "the lone drop is loose")
	for i in 0 ..< 5 {
		testing.expect(t, !jet.loose[i], "the others are in jets")
	}
}

@(test)
a_splash_going_every_way_is_not_a_jet :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	dirs := [6]Vec3{{1, 1, 0}, {-1, 1, 0}, {0, 1, 1}, {0, 1, -1}, {1, 0, 1}, {-1, 0, -1}}
	for k in 0 ..< 6 {
		i := add_drop(s, 0.02 * f32(k), 1.0, 1.0, 0.02 * f32(k))
		s.st.sim.particles[i].v = dirs[k] * 1.2
	}
	jet := new(Jet)
	defer free(jet)
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 0)
	for i in 0 ..< 6 {
		testing.expect(t, jet.loose[i], "each is on its own")
	}
}

@(test)
a_jet_is_joined_to_the_mouth_while_liquid_comes_out_and_not_after :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	falling(s, 4)
	newest := stream_position(s.st, 3)
	jet := new(Jet)
	defer free(jet)

	stream_mouth(s.st, newest + {0, 0.07, 0}) // the lip, a little above the newest drop
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 1)
	testing.expect_value(t, jet.count, 4 * (JET_SUBDIV + 1) + 1) // three gaps between four drops, and one to the mouth
	end := jet.points[jet.count - 1]
	testing.expect(t, near(end.pos.y, newest.y + 0.07, 1e-4), "it ends at the mouth")
	testing.expect_value(t, int(end.drop), 3)
	testing.expect(t, jet.to_mouth[0], "so the end is not closed off")
	testing.expect(t, end.radius >= jet.points[jet.count - 1 - (JET_SUBDIV + 1)].radius - 1e-6, "and is not thinned there")

	s.st.mouth_age = JET_MOUTH_HOLD + 0.01 // liquid stopped coming out
	jet_build(s.st, jet)
	testing.expect(t, !jet.to_mouth[0], "the end is closed off again")
	testing.expect_value(t, jet.count, 3 * (JET_SUBDIV + 1) + 1)

	stream_mouth(s.st, newest + {0, 0.5, 0}) // too far from the newest drop
	jet_build(s.st, jet)
	testing.expect_value(t, jet.count, 3 * (JET_SUBDIV + 1) + 1)
}

@(test)
a_lone_newest_drop_next_to_the_mouth_is_a_short_jet_and_far_from_it_is_loose :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	i := add_drop(s, 0, 1.0, 1.0, 0)
	jet := new(Jet)
	defer free(jet)
	stream_mouth(s.st, stream_position(s.st, i) + {0, 0.05, 0})
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 1)
	testing.expect_value(t, jet.count, JET_SUBDIV + 2)
	testing.expect(t, !jet.loose[i], "it is in the jet")
	s.st.mouth_age = JET_NEVER
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 0)
	testing.expect(t, jet.loose[i], "with no mouth it is loose")
}

@(test)
an_empty_stream_has_no_jets :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	jet := new(Jet)
	defer free(jet)
	jet.count = 5 // left over from a frame before
	jet_build(s.st, jet)
	testing.expect_value(t, jet.count, 0)
	testing.expect_value(t, jet.strands, 0)
}

@(test)
a_jet_is_as_wide_as_the_liquid_in_it_between_the_least_and_the_most :: proc(t: ^testing.T) {
	// 3.4 ml spread over 7 cm: the width of the stream that holds it, 1.4 times.
	testing.expect(t, near(jet_radius(3.4, 0.07), f32(1.4 * math.sqrt(3.4e-6 / 0.07 / math.PI)), 1e-5), "the liquid, made thicker")
	testing.expect(t, jet_radius(27, 0.07) > jet_radius(3.4, 0.07), "more liquid is wider")
	testing.expect(t, jet_radius(3.4, 0.03) > jet_radius(3.4, 0.2), "drops closer together are wider")
	testing.expect_value(t, jet_radius(0.01, 0.2), JET_R_MIN)
	testing.expect_value(t, jet_radius(500, 0.01), JET_R_MAX)
	// Drops on top of each other do not make it infinite.
	testing.expect(t, jet_radius(3.4, 0) <= JET_R_MAX, "no division by zero")
}

@(test)
catmull_rom_goes_through_its_two_middle_points_and_is_straight_on_a_line :: proc(t: ^testing.T) {
	a, b, c, d := Vec3{0, 0, 0}, Vec3{1, 0, 0}, Vec3{2, 0, 0}, Vec3{3, 0, 0}
	testing.expect(t, near(catmull_rom(a, b, c, d, 0).x, 1, 1e-6), "starts at the second")
	testing.expect(t, near(catmull_rom(a, b, c, d, 1).x, 2, 1e-6), "ends at the third")
	testing.expect(t, near(catmull_rom(a, b, c, d, 0.5).x, 1.5, 1e-6), "halfway on a line")
	bent := catmull_rom({0, 0, 0}, {1, 0, 0}, {2, 1, 0}, {3, 1, 0}, 0.5)
	testing.expect(t, bent.y > 0 && bent.y < 1, "a bend stays between")
}

@(test)
the_mouth_is_noted_by_a_pour_a_tap_and_the_oven_and_ages :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	testing.expect_value(t, s.st.mouth_age, JET_NEVER)
	stream_mouth(s.st, {1, 2, 3})
	testing.expect_value(t, s.st.mouth, Vec3{1, 2, 3})
	testing.expect_value(t, s.st.mouth_age, f32(0))
	stream_step(s.st, 21)
	testing.expect(t, near(s.st.mouth_age, 21 * STREAM_DT, 1e-6), "it ages with the steps, even with nothing in the air")
}

@(test)
a_pour_notes_the_lip_as_the_mouth_only_while_liquid_leaves :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	pour_setup(s, .Water, .None, 300, 0)
	events: [MAX_EVENTS]Mix_Result
	found: [dynamic]Mix_Result
	defer delete(found)
	for _ in 0 ..< 4 { // only slightly tipped: nothing leaves yet
		pour_frame(s, &events, &found)
	}
	testing.expect_value(t, s.st.sim.count, 0)
	testing.expect(t, s.st.mouth_age > JET_MOUTH_HOLD, "no mouth while nothing leaves")
	noted, near_hands := false, true
	for _ in 0 ..< 240 {
		pour_frame(s, &events, &found)
		if s.st.mouth_age < JET_MOUTH_HOLD {
			noted = true
			near_hands = near_hands && length3(s.st.mouth - s.props.items[s.props.held].pos) < 0.3
		}
	}
	testing.expect(t, noted, "the lip is the mouth while liquid leaves")
	testing.expect(t, near_hands, "and it is by the vessel in the hands")
	for _ in 0 ..< 60 { // the vessel is empty by now, and the mouth is let go
		pour_frame(s, &events, &found)
	}
	testing.expect(t, s.st.mouth_age > JET_MOUTH_HOLD, "and it is let go when nothing leaves")
}

@(test)
a_tap_notes_its_nozzle_as_the_mouth :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	st: Station
	station_init(&st)
	testing.expect(t, station_flow(&st, s.st, s.l, 1, 1.0 / 60), "the tap runs")
	testing.expect_value(t, s.st.mouth, lab.tap_nozzle(1))
	testing.expect_value(t, s.st.mouth_age, f32(0))
	st.items[2].unlocked = false
	s.st.mouth_age = 5
	testing.expect(t, !station_flow(&st, s.st, s.l, 2, 1.0 / 60), "a locked tap does not")
	testing.expect_value(t, s.st.mouth_age, f32(5))
}

length3 :: proc(v: Vec3) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
}

@(test)
the_oven_spout_notes_its_tip_as_the_mouth_while_the_tank_has_liquid :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	below := Vec3{lab.MIXER_SPOUT.x, lab.MIXER_SPOUT.y - 0.5, lab.MIXER_SPOUT.z}
	testing.expect(t, !oven_flow(&o, s.st, s.l, 1.0 / 60, below, 1), "nothing in the tank")
	testing.expect_value(t, s.st.mouth_age, JET_NEVER)
	fill_with(&o.tank, id(.Water), 100)
	testing.expect(t, oven_flow(&o, s.st, s.l, 1.0 / 60, below, 1), "the spout runs")
	testing.expect_value(t, s.st.mouth, lab.MIXER_SPOUT)
	testing.expect_value(t, s.st.mouth_age, f32(0))
}

@(test)
drops_whose_ages_are_the_wrong_way_round_are_joined_only_within_the_slack :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	a := add_drop(s, 0, 1.0, 1.5, 0) // made first, but no older than the next
	b := add_drop(s, 0, 1.0, 1.5, 0.05)
	s.st.sim.particles[a].x.y -= JET_SLACK * 0.5
	testing.expect(t, jet_joined(s.st, a, b), "the gap is nothing, not less than nothing")
	s.st.sim.particles[a].x.y -= JET_SLACK
	testing.expect(t, !jet_joined(s.st, a, b), "and past the slack it is not joined")
}

@(test)
the_reach_of_two_drops_is_set_by_the_faster_of_them :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	a := add_drop(s, 0, 1.0, 1.0, 0.1)
	b := add_drop(s, 0, 1.0, 2.0, 0)
	s.st.sim.particles[a].x.y -= 0.28 // 28 cm: the faster one reaches 1.6 x 2 x 0.1 + 0.04 = 36 cm, the slower 20 cm
	testing.expect(t, jet_joined(s.st, a, b), "the faster speed counts")
	s.st.sim.particles[a].x.y -= 0.22 // 50 cm is past both
	testing.expect(t, !jet_joined(s.st, a, b), "but not without limit")
}

@(test)
only_the_jet_with_the_newest_drop_is_joined_to_the_mouth :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	falling(s, 3) // the older jet, drops 0 to 2
	for k in 0 ..< 3 { // the newer jet, drops 3 to 5, well away from the first
		i := add_drop(s, 0.4, 1.0, 1.5, 0.04 * f32(2 - k))
		s.st.sim.particles[i].x.y -= 0.06 * f32(2 - k)
	}
	stream_mouth(s.st, stream_position(s.st, 5) + {0, 0.06, 0})
	jet := new(Jet)
	defer free(jet)
	jet_build(s.st, jet)
	testing.expect_value(t, jet.strands, 2)
	testing.expect(t, !jet.to_mouth[0], "the older jet is not joined to the mouth")
	testing.expect(t, jet.to_mouth[1], "the newer is")
}

@(test)
a_jet_of_no_liquid_or_no_room_between_drops_is_still_a_number :: proc(t: ^testing.T) {
	testing.expect_value(t, jet_radius(0, 0), JET_R_MIN)
	testing.expect_value(t, jet_radius(0, 0.1), JET_R_MIN)
}

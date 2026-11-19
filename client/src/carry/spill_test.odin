// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "spill_test.odin"
// ============================================================================

package carry

import "../lab"
import "core:math"
import "core:testing"

@(test)
a_puddle_is_as_wide_as_the_circle_that_holds_its_liquid_between_the_least_and_the_most :: proc(t: ^testing.T) {
	// 3.4 ml at 1.2 mm thick is a circle of 3 cm radius.
	testing.expect(t, near(spill_size(3.4), f32(math.sqrt(3.4e-6 / (math.PI * 0.0012))), 1e-5), "the circle that holds it")
	testing.expect(t, spill_size(34) > spill_size(3.4), "more liquid spreads wider")
	testing.expect_value(t, spill_size(0.001), SPILL_R_MIN)
	testing.expect_value(t, spill_size(100000), SPILL_R_MAX)
}

@(test)
a_new_puddle_starts_small_and_waits_for_its_delay :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {1, 0.5, 2}, 3.4, 7, 0.3)
	testing.expect_value(t, sp.count, 1)
	p := sp.puddles[0]
	testing.expect_value(t, p.pos, Vec3{1, 0.5, 2})
	testing.expect_value(t, p.ml, f32(3.4))
	testing.expect_value(t, p.compound, u16(7))
	testing.expect_value(t, p.delay, f32(0.3))
	testing.expect(t, near(p.radius, spill_size(3.4) * SPILL_START, 1e-6), "it starts at a share of its width")
	testing.expect(t, !puddle_landed(p), "it has not landed")
	spill_step(sp, 0.2)
	testing.expect(t, !puddle_landed(sp.puddles[0]), "not yet")
	testing.expect_value(t, sp.puddles[0].radius, p.radius) // it does not spread before it lands
	spill_step(sp, 0.2)
	testing.expect(t, puddle_landed(sp.puddles[0]), "landed")
}

@(test)
a_drop_that_lands_in_a_puddle_of_the_same_liquid_joins_it :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0.5, 0}, 10, 1)
	spill_add(sp, {0.02, 0.5, 0}, 30, 1) // within the reach of the first, which is about 5 cm
	testing.expect_value(t, sp.count, 1)
	testing.expect_value(t, sp.puddles[0].ml, f32(40))
	testing.expect(t, near(sp.puddles[0].pos.x, 0.015, 1e-6), "the middle moves towards the drop, by its share")
	spill_add(sp, {0.5, 0.5, 0}, 5, 1) // far away
	testing.expect_value(t, sp.count, 2)
	spill_add(sp, {0.0, 0.5, 0}, 5, 2) // another liquid
	testing.expect_value(t, sp.count, 3)
	spill_add(sp, {0.0, 0.9, 0}, 5, 1) // another surface, higher
	testing.expect_value(t, sp.count, 4)
}

@(test)
joining_a_puddle_makes_it_fresh_again_and_does_not_make_it_fall_early :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0, 0}, 10, 1)
	spill_step(sp, SPILL_STAY + 0.5) // it has begun to dissolve
	testing.expect(t, puddle_dissolve(sp.puddles[0]) > 0, "dissolving")
	spill_add(sp, {0.01, 0, 0}, 3.4, 1)
	testing.expect_value(t, sp.puddles[0].age, f32(0))
	testing.expect_value(t, puddle_dissolve(sp.puddles[0]), f32(0))
	// A puddle that has not landed does not go back in time beyond when it lands.
	spill_add(sp, {1, 0, 1}, 10, 1, 0.5)
	spill_add(sp, {1.01, 0, 1}, 3.4, 1, 0)
	testing.expect_value(t, sp.count, 2)
	testing.expect_value(t, sp.puddles[1].age, f32(0))
	testing.expect_value(t, sp.puddles[1].delay, f32(0.5))
}

@(test)
when_all_the_puddles_are_in_use_the_one_that_has_lain_longest_is_taken :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	for i in 0 ..< MAX_PUDDLES {
		spill_add(sp, {f32(i) * 2, 0, 0}, 3.4, 1)
		spill_step(sp, 0.01)
	}
	testing.expect_value(t, sp.count, MAX_PUDDLES)
	// The first made is the oldest. A new one far from the rest takes its place.
	spill_add(sp, {-5, 0, 0}, 3.4, 1)
	testing.expect_value(t, sp.count, MAX_PUDDLES)
	testing.expect_value(t, sp.puddles[0].pos.x, f32(-5))
	testing.expect_value(t, sp.puddles[0].age, f32(0))
	for i in 1 ..< MAX_PUDDLES {
		testing.expect(t, sp.puddles[i].pos.x == f32(i) * 2, "the others are as they were")
	}
}

@(test)
a_puddle_spreads_to_its_size_and_dissolves_and_is_then_gone :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0, 0}, 20, 1)
	size := spill_size(20)
	last := sp.puddles[0].radius
	for _ in 0 ..< 60 { // a second
		spill_step(sp, 1.0 / 60)
		testing.expect(t, sp.puddles[0].radius >= last, "it only spreads")
		testing.expect(t, sp.puddles[0].radius <= size + 1e-6, "and not past its size")
		last = sp.puddles[0].radius
	}
	testing.expect(t, last > size * 0.95, "it has nearly spread in a second")
	testing.expect_value(t, puddle_dissolve(sp.puddles[0]), f32(0)) // it lies, still whole
	spill_step(sp, SPILL_STAY - 1.0)
	testing.expect_value(t, puddle_dissolve(sp.puddles[0]), f32(0))
	spill_step(sp, SPILL_FADE * 0.5)
	testing.expect_value(t, sp.count, 1) // still there, half gone
	testing.expect(t, near(puddle_dissolve(sp.puddles[0]), 0.5, 1e-3), "half dissolved half way through")
	spill_step(sp, SPILL_FADE * 0.5 + 0.1)
	testing.expect_value(t, sp.count, 0)
}

@(test)
removing_a_puddle_keeps_the_others :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0, 0}, 3.4, 1)
	spill_step(sp, SPILL_STAY + SPILL_FADE * 0.9)
	spill_add(sp, {2, 0, 0}, 3.4, 1)
	spill_add(sp, {4, 0, 0}, 3.4, 1)
	spill_step(sp, SPILL_FADE * 0.2) // the first is gone, the others are not
	testing.expect_value(t, sp.count, 2)
	testing.expect(t, sp.puddles[0].pos.x != 0 && sp.puddles[1].pos.x != 0, "the first is the one that went")
	testing.expect(t, (sp.puddles[0].pos.x == 2 && sp.puddles[1].pos.x == 4) || (sp.puddles[0].pos.x == 4 && sp.puddles[1].pos.x == 2), "the others are there")
}

@(test)
a_drop_that_lies_on_a_surface_becomes_a_puddle_once :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	top := lab.COUNTER_HEIGHT
	testing.expect(t, stream_spawn_ml(s.st, s.l, {0, top + 0.05, 0}, {0, 0, 0}, 3, 3.4), "a drop over the island")
	for _ in 0 ..< 40 {
		stream_step(s.st, 21)
	}
	testing.expect(t, s.st.puddled[0] || s.st.sim.count == 0, "it has landed")
	testing.expect_value(t, s.st.spill.count, 1)
	p := s.st.spill.puddles[0]
	testing.expect(t, near(p.pos.y, top, 0.02), "on the top of the island")
	testing.expect_value(t, p.compound, u16(3))
	testing.expect_value(t, p.ml, f32(3.4))
	testing.expect_value(t, p.delay, f32(0))
	// It lies there until it is wiped away from the stream, and makes no second puddle.
	for _ in 0 ..< 200 {
		stream_step(s.st, 21)
	}
	testing.expect_value(t, s.st.sim.count, 0)
	testing.expect_value(t, s.st.spill.count, 1)
	testing.expect_value(t, s.st.spill.puddles[0].ml, f32(3.4))
}

@(test)
a_drop_that_falls_off_a_counter_makes_a_puddle_on_the_floor_when_it_gets_there :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	testing.expect(t, stream_spawn_ml(s.st, s.l, {3, 1.5, 2}, {0, 0, 0}, 4, 3.4), "a drop over the floor")
	testing.expect(t, s.st.air_floor, "the box floor is in the air")
	for _ in 0 ..< 400 {
		stream_step(s.st, 21)
		if s.st.sim.count == 0 {
			break
		}
	}
	testing.expect_value(t, s.st.sim.count, 0)
	testing.expect_value(t, s.st.spill.count, 1)
	p := s.st.spill.puddles[0]
	testing.expect_value(t, p.pos.y, f32(0))
	testing.expect(t, near(p.pos.x, 3, 0.1) && near(p.pos.z, 2, 0.1), "where it fell")
	// It was 0.4 m up where it left the box, which is 0.29 s of falling.
	testing.expect(t, p.delay > 0.2 && p.delay < 0.4, "it lands after it has fallen")
	testing.expect_value(t, p.compound, u16(4))
}

@(test)
the_flag_of_a_drop_that_has_landed_goes_with_it_when_another_is_removed :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	for k in 0 ..< 3 {
		testing.expect(t, stream_spawn_ml(s.st, s.l, {0.1 * f32(k), 1.5, 0}, {0, -1, 0}, 1, 3.4), "a drop")
	}
	s.st.puddled[2] = true
	stream_remove(s.st, 0) // the last moves into its place
	testing.expect_value(t, s.st.sim.count, 2)
	testing.expect(t, s.st.puddled[0], "the flag moved with the drop")
	testing.expect(t, !s.st.puddled[1], "and the other has none")
	// A new drop starts with none.
	testing.expect(t, stream_spawn_ml(s.st, s.l, {0.4, 1.5, 0}, {0, -1, 0}, 1, 3.4), "another")
	testing.expect(t, !s.st.puddled[2], "a new drop has not landed")
}

@(test)
one_long_step_does_not_spread_a_puddle_past_its_size :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0, 0}, 20, 1)
	spill_step(sp, 3)
	testing.expect(t, sp.puddles[0].radius <= spill_size(20) + 1e-6, "it stops at its size")
	testing.expect(t, sp.puddles[0].radius > spill_size(20) * 0.9, "having spread to it")
}

@(test)
the_dissolve_of_a_puddle_that_fell_a_way_counts_from_when_it_landed :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0, 0}, 20, 1, 1.0) // lands after a second
	spill_step(sp, 1.0 + SPILL_STAY + SPILL_FADE * 0.5)
	testing.expect_value(t, sp.count, 1)
	testing.expect(t, near(puddle_dissolve(sp.puddles[0]), 0.5, 1e-3), "half dissolved half way through, from when it landed")
	spill_step(sp, SPILL_FADE * 0.6)
	testing.expect_value(t, sp.count, 0)
}

@(test)
a_puddle_with_no_delay_has_landed_at_once :: proc(t: ^testing.T) {
	sp := new(Spill)
	defer free(sp)
	spill_add(sp, {0, 0, 0}, 3.4, 1)
	testing.expect(t, puddle_landed(sp.puddles[0]), "it is there from the start")
	testing.expect_value(t, puddle_dissolve(sp.puddles[0]), f32(0))
}

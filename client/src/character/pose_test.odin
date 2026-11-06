// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "pose_test.odin"
// ============================================================================

package character

import "core:math"
import "core:testing"

// Walks at `speed` for `seconds` at 60 steps a second.
walk_for :: proc(a: ^Anim, speed: f32, seconds: f32, airborne := false) {
	for _ in 0 ..< int(seconds * 60) {
		anim_step(a, speed, airborne, 1.0 / 60)
	}
}

@(test)
a_character_standing_still_is_not_swung_or_lifted :: proc(t: ^testing.T) {
	a := anim_new()
	walk_for(&a, 0, 2)
	p := anim_pose(&a)
	testing.expect_value(t, p, Pose{})
}

@(test)
at_full_speed_the_legs_swing_against_each_other_and_the_arms_against_the_legs :: proc(t: ^testing.T) {
	a := anim_new()
	walk_for(&a, WALK_SPEED, 2)
	biggest := f32(0)
	for _ in 0 ..< 120 {
		anim_step(&a, WALK_SPEED, false, 1.0 / 60)
		p := anim_pose(&a)
		biggest = max(biggest, abs(p.leg_l))
		testing.expect(t, near(p.leg_l, -p.leg_r), "the legs are opposite")
		testing.expect(t, near(p.arm_l * LEG_SWING, -p.leg_l * ARM_SWING, 0.0001), "the arm on the left goes with the leg on the right")
		testing.expect(t, near(p.arm_r * LEG_SWING, p.leg_l * ARM_SWING, 0.0001), "and the arm on the right with the leg on the left")
		testing.expect(t, p.lift >= 0 && p.lift <= BOB + 0.0001, "the body rises at each step and never sinks")
	}
	testing.expect(t, biggest > LEG_SWING * 0.97 && biggest <= LEG_SWING + 0.0001, "the legs reach the full swing and no further")
}

@(test)
slower_walking_swings_less :: proc(t: ^testing.T) {
	full, half := anim_new(), anim_new()
	walk_for(&full, WALK_SPEED, 2)
	walk_for(&half, WALK_SPEED * 0.5, 2)
	most_full, most_half := f32(0), f32(0)
	for _ in 0 ..< 240 {
		anim_step(&full, WALK_SPEED, false, 1.0 / 60)
		anim_step(&half, WALK_SPEED * 0.5, false, 1.0 / 60)
		most_full = max(most_full, abs(anim_pose(&full).leg_l))
		most_half = max(most_half, abs(anim_pose(&half).leg_l))
	}
	testing.expect(t, most_half > most_full * 0.4 && most_half < most_full * 0.6, "half the speed, about half the swing")
	// Running faster than a walk does not swing the legs further.
	fast := anim_new()
	walk_for(&fast, WALK_SPEED * 3, 2)
	most_fast := f32(0)
	for _ in 0 ..< 240 {
		anim_step(&fast, WALK_SPEED * 3, false, 1.0 / 60)
		most_fast = max(most_fast, abs(anim_pose(&fast).leg_l))
	}
	testing.expect(t, most_fast <= LEG_SWING + 0.0001, "the swing stops at the full one")
}

@(test)
the_walk_cycle_goes_round_at_the_speed_of_the_stride :: proc(t: ^testing.T) {
	a := anim_new()
	walk_for(&a, WALK_SPEED, 2) // settled
	before := a.phase
	for _ in 0 ..< 60 {
		anim_step(&a, WALK_SPEED, false, 1.0 / 60)
	}
	gone := math.mod(a.phase - before + 2 * math.PI, 2 * math.PI)
	want := math.mod(WALK_SPEED * STRIDE, 2 * math.PI)
	testing.expect(t, near(gone, want, 0.01), "one second at walking speed")
	for _ in 0 ..< 1000 {
		anim_step(&a, WALK_SPEED, false, 1.0 / 60)
		testing.expect(t, a.phase >= 0 && a.phase < 2 * math.PI, "the phase stays inside one turn")
	}
}

@(test)
stopping_slows_down_and_does_not_snap :: proc(t: ^testing.T) {
	a := anim_new()
	walk_for(&a, WALK_SPEED, 2)
	anim_step(&a, 0, false, 1.0 / 60)
	testing.expect(t, a.speed > WALK_SPEED * 0.7 && a.speed < WALK_SPEED, "a tick after stopping it is still going")
	walk_for(&a, 0, 1.5)
	p := anim_pose(&a)
	testing.expect(t, abs(p.leg_l) < 0.01 && abs(p.arm_r) < 0.01 && p.lift < 0.001, "and a second and a half on it is still")
}

@(test)
a_big_frame_does_not_throw_the_smoothing_past_its_target :: proc(t: ^testing.T) {
	a := anim_new()
	anim_step(&a, 3.2, false, 5)
	testing.expect_value(t, a.speed, f32(3.2))
	anim_step(&a, 0, true, 5)
	testing.expect_value(t, a.air, f32(1))
	testing.expect_value(t, a.speed, f32(0))
}

@(test)
in_the_air_the_legs_are_drawn_up_the_arms_go_out_and_the_walk_stops :: proc(t: ^testing.T) {
	a := anim_new()
	walk_for(&a, WALK_SPEED, 1)
	walk_for(&a, WALK_SPEED, 0.5, true)
	p := anim_pose(&a)
	testing.expect(t, a.air > 0.99, "the pose has eased into the air")
	testing.expect(t, near(p.arm_out, 0.5, 0.01), "the arms are out")
	testing.expect(t, p.leg_l > 0.4 && p.leg_r < -0.1 && abs(p.leg_l) > abs(p.leg_r), "the legs are drawn up, one more than the other")
	testing.expect(t, p.arm_l > 0.55 && p.arm_r > 0.55, "and the arms are forward")
	testing.expect(t, p.lift == 0 || p.lift < 0.001, "and the walk bob has stopped")
	walk_for(&a, WALK_SPEED, 0.5, false)
	testing.expect(t, a.air < 0.01, "landing eases back to the walk")
}

@(test)
the_air_is_eased_into_and_not_a_snap :: proc(t: ^testing.T) {
	a := anim_new()
	anim_step(&a, 0, true, 1.0 / 60)
	testing.expect(t, a.air > 0.05 && a.air < 0.5, "one frame into a jump it is a part of the way")
}

@(test)
a_throw_winds_back_swings_up_and_forward_and_comes_down :: proc(t: ^testing.T) {
	testing.expect_value(t, throw_angle(-1), f32(0))
	testing.expect_value(t, throw_angle(0), f32(0))
	lowest, highest := f32(1e9), f32(-1e9)
	t_low, t_high := f32(0), f32(0)
	for i in 0 ..= 500 {
		x := f32(i) * 0.001
		angle := throw_angle(x)
		if angle < lowest {lowest, t_low = angle, x}
		if angle > highest {highest, t_high = angle, x}
	}
	testing.expect(t, near(lowest, -1.3, 0.01) && t_low < t_high, "it winds back first")
	testing.expect(t, near(highest, 2.4, 0.02), "and goes up and forward over the head")
	testing.expect(t, t_low > 0.15 && t_low < 0.25 && t_high > 0.3 && t_high < 0.4, "at 0.2 s and 0.35 s")
	testing.expect_value(t, throw_angle(THROW_TIME), f32(0))
	testing.expect_value(t, throw_angle(THROW_TIME + 1), f32(0))
}

@(test)
the_throw_is_smooth_with_no_jumps :: proc(t: ^testing.T) {
	last := throw_angle(0)
	for i in 1 ..= 500 {
		angle := throw_angle(f32(i) * 0.001)
		testing.expectf(t, abs(angle - last) < 0.06, "the arm jumps %v in a millisecond at %v s", angle - last, f32(i) * 0.001)
		last = angle
	}
}

@(test)
a_throw_runs_its_course_and_ends :: proc(t: ^testing.T) {
	a := anim_new()
	testing.expect_value(t, a.throw_t, f32(-1))
	anim_throw(&a)
	testing.expect_value(t, a.throw_t, f32(0))
	steps := 0
	for a.throw_t >= 0 && steps < 1000 {
		anim_step(&a, 0, false, 1.0 / 60)
		steps += 1
	}
	testing.expect(t, steps >= 29 && steps <= 31, "half a second at 60 steps")
	testing.expect_value(t, a.throw_t, f32(-1))
	testing.expect_value(t, anim_pose(&a).arm_r, f32(0))
}

@(test)
a_throw_moves_the_right_arm_only_and_wins_over_the_walk :: proc(t: ^testing.T) {
	a := anim_new()
	walk_for(&a, WALK_SPEED, 2)
	walking := anim_pose(&a)
	anim_throw(&a)
	for _ in 0 ..< 21 { // 0.35 s at the top of the throw
		anim_step(&a, 0, false, 1.0 / 60)
	}
	thrown := anim_pose(&a)
	testing.expect(t, thrown.arm_r > 1.5, "the right arm is up and forward")
	testing.expect(t, abs(thrown.arm_l) < abs(walking.arm_l) + 0.5, "the left arm is not thrown with it")
	// Mid throw while still walking, the throw owns the arm.
	b := anim_new()
	walk_for(&b, WALK_SPEED, 2)
	anim_throw(&b)
	anim_step(&b, WALK_SPEED, false, 0.01)
	testing.expect(t, near(anim_pose(&b).arm_r, throw_angle(b.throw_t)), "the arm follows the throw and not the walk")
}

@(test)
the_body_and_head_are_lifted_with_the_walk_and_the_legs_are_not :: proc(t: ^testing.T) {
	root := mat_identity()
	pose := Pose{lift = 0.02}
	body := part_matrix(root, pose, .Body)
	testing.expect(t, near3(mat_point(body, {0, 0, 0}), {0, 0.02, 0}), "the body is lifted")
	head := part_matrix(root, pose, .Head)
	testing.expect(t, near3(mat_point(head, {0, 0, 0}), part_pivot(.Head) + {0, 0.02, 0}), "the head goes with it")
	leg := part_matrix(root, pose, .Leg_L)
	testing.expect(t, near3(mat_point(leg, {0, 0, 0}), part_pivot(.Leg_L)), "the hip stays")
}

@(test)
a_part_swings_about_its_pivot_and_stays_on_it :: proc(t: ^testing.T) {
	root := root_matrix({5, 0, -3}, 0.4)
	pose := Pose{leg_l = 0.5, arm_r = -0.5}
	for p in ([]Part{.Leg_L, .Arm_R}) {
		m := part_matrix(root, pose, p)
		at_rest := mat_point(root, part_pivot(p))
		testing.expectf(t, near3(mat_point(m, {0, 0, 0}), at_rest, 0.0005), "%v moves off its pivot", p)
	}
	// With the character at the origin facing -z, a forward swing takes a foot toward -z.
	m := part_matrix(mat_identity(), Pose{leg_l = 0.5}, .Leg_L)
	foot := mat_point(m, {0, -0.38, 0})
	testing.expect(t, foot.z < -0.15 && foot.y > 0 && foot.y < 0.38, "a positive swing takes the foot forward and up")
	m = part_matrix(mat_identity(), Pose{leg_l = -0.5}, .Leg_L)
	testing.expect(t, mat_point(m, {0, -0.38, 0}).z > 0.15, "a negative one takes it back")
}

@(test)
the_arms_are_held_out_from_the_sides_and_further_in_the_air :: proc(t: ^testing.T) {
	hand :: proc(pose: Pose, p: Part) -> Vec3 {
		return mat_point(part_matrix(mat_identity(), pose, p), {0, -0.64, 0})
	}
	l, r := hand({}, .Arm_L), hand({}, .Arm_R)
	testing.expect(t, l.x < part_pivot(.Arm_L).x - 0.05 && r.x > part_pivot(.Arm_R).x + 0.05, "a little out at rest, away from the body")
	l2, r2 := hand(Pose{arm_out = 0.5}, .Arm_L), hand(Pose{arm_out = 0.5}, .Arm_R)
	testing.expect(t, l2.x < l.x - 0.1 && r2.x > r.x + 0.1, "further in the air")
	testing.expect(t, near(l.x, -r.x) && near(l.y, r.y) && near(l.z, r.z), "the two sides mirror each other")
}

@(test)
placing_a_character_puts_its_parts_at_the_feet_facing_the_heading :: proc(t: ^testing.T) {
	root := root_matrix({10, 0, 5}, math.PI * 0.5) // faces +x
	head := part_matrix(root, Pose{}, .Head)
	top := mat_point(head, {0, 0.5, 0}) // above the neck
	testing.expect(t, near3(top, {10, part_pivot(.Head).y + 0.5, 5}, 0.001), "the head is over the feet")
	right_arm := mat_point(part_matrix(root, Pose{}, .Arm_R), {0, 0, 0})
	// Facing +x, the right hand is toward +z.
	testing.expect(t, right_arm.z > 5 + 0.3 && near(right_arm.x, 10, 0.001), "the right shoulder is to the right of a character facing +x")
}

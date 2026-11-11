// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "touch_test.odin"
// ============================================================================

package touch

import "core:math"
import "core:testing"

// A phone held sideways. The buttons: 0 is a fire pad that also aims, in the bottom right, 1 is
// a jump button above it, 2 is a small button in the top left.
W :: f32(1600)
H :: f32(720)
PAD :: [4]f32{1280, 480, 220, 220}
JUMP :: [4]f32{1280, 300, 220, 120}
CORNER :: [4]f32{20, 20, 100, 60}

near :: proc(a, b: f32, eps := f32(0.01)) -> bool {
	return abs(a - b) <= eps
}

length_of :: proc(v: [2]f32) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

screen_of :: proc(buttons: [][4]f32, aim: u32 = 0, stick := true, w := W, h := H) -> Screen {
	return {w = w, h = h, buttons = buttons, aim_mask = aim, stick_enabled = stick}
}

// The middle of a button, where a thumb lands.
middle :: proc(b: [4]f32) -> [2]f32 {
	return {b.x + b.z * 0.5, b.y + b.w * 0.5}
}

@(test)
stick_appears_under_the_thumb :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	out := update(&s, []Finger{{id = 1, pos = {400, 500}}}, scr)
	testing.expect(t, out.stick_active, "a finger on the left starts the stick")
	testing.expect_value(t, out.anchor, [2]f32{400, 500})
	testing.expect_value(t, out.stick, [2]f32{0, 0})
	testing.expect_value(t, out.knob, [2]f32{400, 500})
	out = update(&s, []Finger{{id = 1, pos = {400 + stick_radius(H), 500}}}, scr)
	testing.expect(t, near(out.stick.x, 1) && near(out.stick.y, 0), "all the way right is 1, 0")
	out = update(&s, []Finger{{id = 1, pos = {400, 500 + stick_radius(H)}}}, scr)
	testing.expect(t, near(out.stick.x, 0) && near(out.stick.y, 1), "all the way down is 0, 1 (y points down)")
}

@(test)
stick_stays_put_while_the_finger_moves :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	update(&s, []Finger{{id = 1, pos = {400, 500}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {450, 540}}}, scr)
	testing.expect_value(t, out.anchor, [2]f32{400, 500})
	out = update(&s, []Finger{{id = 1, pos = {300, 520}}}, scr)
	testing.expect_value(t, out.anchor, [2]f32{400, 500})
}

@(test)
dead_zone_is_rescaled_so_its_edge_reads_zero :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	r := stick_radius(H)
	update(&s, []Finger{{id = 1, pos = {400, 500}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {400 + r * 0.04, 500}}}, scr)
	testing.expect_value(t, out.stick, [2]f32{0, 0})
	out = update(&s, []Finger{{id = 1, pos = {400 + r * 0.079, 500}}}, scr)
	testing.expect_value(t, out.stick, [2]f32{0, 0})
	out = update(&s, []Finger{{id = 1, pos = {400 + r * 0.09, 500}}}, scr)
	testing.expect(t, out.stick.x > 0 && out.stick.x < 0.02, "just past the dead zone is a very small push, not a jump")
	// Half way between the edge of the dead zone and the rim is half a push.
	out = update(&s, []Finger{{id = 1, pos = {400 + r * 0.54, 500}}}, scr)
	testing.expect(t, near(out.stick.x, 0.5, 0.005), "half way past the dead zone is half a push")
	// A diagonal keeps its direction.
	out = update(&s, []Finger{{id = 1, pos = {400 + r * 0.6, 500 + r * 0.6}}}, scr)
	testing.expect(t, near(out.stick.x, out.stick.y, 0.001) && out.stick.x > 0, "a diagonal push is even on both axes")
}

@(test)
stick_is_clamped_to_the_ring :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	r := stick_radius(H)
	update(&s, []Finger{{id = 1, pos = {400, 500}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {400 + r * 3, 500}}}, scr)
	testing.expect(t, near(length_of(out.stick), 1), "far past the ring is a push of 1")
	testing.expect(t, near(length_of(out.knob - out.anchor), r), "and the knob stops at the ring")
	out = update(&s, []Finger{{id = 1, pos = {400 + r * 0.5, 500}}}, scr)
	testing.expect(t, near(length_of(out.knob - out.anchor), r * 0.5), "inside the ring the knob is under the finger")
}

@(test)
stick_ring_stays_on_the_screen_on_every_shape :: proc(t: ^testing.T) {
	shapes := [?][2]f32{{1600, 720}, {1280, 720}, {2400, 1080}, {960, 720}, {2000, 1000}}
	for shape in shapes {
		w, h := shape.x, shape.y
		r := stick_radius(h)
		corners := [?][2]f32{{1, 1}, {w * 0.49, 1}, {1, h - 1}, {w * 0.49, h - 1}}
		for c in corners {
			s: State
			init(&s, nil)
			out := update(&s, []Finger{{id = 1, pos = c}}, screen_of(nil, w = w, h = h))
			a := out.anchor
			testing.expect(t, out.stick_active, "the corner finger is the stick")
			testing.expect(t, a.x - r >= -0.01 && a.y - r >= -0.01, "the ring is not cut off at the left or the top")
			testing.expect(t, a.x + r <= w + 0.01 && a.y + r <= h + 0.01, "nor on the right or the bottom")
		}
	}
}

@(test)
stick_radius_is_a_share_of_the_height :: proc(t: ^testing.T) {
	testing.expect(t, near(stick_radius(450), 85.5, 0.01), "a 450 pixel high screen gets a ring of 85.5, close to Tower-Of-Babylon's 87")
	testing.expect(t, near(stick_radius(720) * 2, stick_radius(1440)), "and it scales with the height")
}

@(test)
look_finger_turns_by_exactly_how_far_it_moves :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	out := update(&s, []Finger{{id = 1, pos = {1000, 300}}}, scr)
	testing.expect(t, out.look_active, "a finger on the right is the look finger")
	testing.expect_value(t, out.look, [2]f32{0, 0})
	out = update(&s, []Finger{{id = 1, pos = {1030, 280}}}, scr)
	testing.expect_value(t, out.look, [2]f32{30, -20})
	out = update(&s, []Finger{{id = 1, pos = {1030, 280}}}, scr)
	testing.expect_value(t, out.look, [2]f32{0, 0})
	testing.expect(t, !out.stick_active, "a look finger is not the stick")
}

@(test)
spare_fingers_do_nothing :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	update(&s, []Finger{{id = 1, pos = {1000, 300}}}, scr)
	update(&s, []Finger{{id = 1, pos = {1000, 300}}, {id = 2, pos = {1100, 300}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {1010, 300}}, {id = 2, pos = {1500, 100}}}, scr)
	testing.expect_value(t, out.look, [2]f32{10, 0})
	// A second finger on the left, with the stick held, is not a look finger either.
	update(&s, []Finger{{id = 1, pos = {1010, 300}}, {id = 2, pos = {1500, 100}}, {id = 3, pos = {300, 500}}}, scr)
	out = update(&s, []Finger{{id = 1, pos = {1010, 300}}, {id = 2, pos = {1500, 100}}, {id = 3, pos = {300, 500}}, {id = 4, pos = {200, 400}}}, scr)
	testing.expect(t, out.stick_active, "the first left finger holds the stick")
	out = update(&s, []Finger{{id = 1, pos = {1010, 300}}, {id = 2, pos = {1500, 100}}, {id = 3, pos = {300, 500}}, {id = 4, pos = {100, 100}}}, scr)
	testing.expect_value(t, out.look, [2]f32{0, 0})
	testing.expect_value(t, out.anchor, [2]f32{300, 500})
}

@(test)
look_finger_sliding_over_a_button_does_not_press_it :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons)
	update(&s, []Finger{{id = 1, pos = {1000, 300}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = middle(JUMP)}}, scr)
	testing.expect_value(t, out.pressed, u32(0))
	testing.expect_value(t, out.held, u32(0))
	testing.expect(t, out.look.x > 0, "and it keeps turning the view")
	out = update(&s, []Finger{{id = 1, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.held, u32(0))
}

@(test)
button_finger_keeps_the_button_when_it_leaves :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons)
	out := update(&s, []Finger{{id = 1, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.pressed, u32(1))
	testing.expect_value(t, out.held, u32(1))
	out = update(&s, []Finger{{id = 1, pos = {900, 200}}}, scr)
	testing.expect_value(t, out.pressed, u32(0))
	testing.expect_value(t, out.held, u32(1))
	out = update(&s, []Finger{{id = 1, pos = {100, 600}}}, scr)
	testing.expect_value(t, out.held, u32(1))
	testing.expect(t, !out.stick_active, "a button finger that wanders left does not become the stick")
	out = update(&s, nil, scr)
	testing.expect_value(t, out.held, u32(0))
}

@(test)
two_buttons_can_be_held_at_once :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons)
	out := update(&s, []Finger{{id = 1, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.held, u32(1))
	out = update(&s, []Finger{{id = 1, pos = middle(PAD)}, {id = 2, pos = middle(JUMP)}}, scr)
	testing.expect_value(t, out.held, u32(3))
	testing.expect_value(t, out.pressed, u32(2))
	out = update(&s, []Finger{{id = 1, pos = middle(PAD)}, {id = 2, pos = middle(JUMP)}}, scr)
	testing.expect_value(t, out.held, u32(3))
	testing.expect_value(t, out.pressed, u32(0))
	out = update(&s, []Finger{{id = 2, pos = middle(JUMP)}}, scr)
	testing.expect_value(t, out.held, u32(2))
}

@(test)
second_finger_on_a_held_button_is_spare :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons)
	update(&s, []Finger{{id = 1, pos = middle(PAD)}}, scr)
	out := update(&s, []Finger{{id = 1, pos = middle(PAD)}, {id = 2, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.pressed, u32(0))
	// The first finger lifts: the spare one does not take the button over.
	out = update(&s, []Finger{{id = 2, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.held, u32(0))
}

@(test)
aim_button_turns_the_view_and_others_do_not :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons, aim = 1)
	update(&s, []Finger{{id = 1, pos = middle(PAD)}, {id = 2, pos = middle(JUMP)}}, scr)
	p := middle(PAD)
	j := middle(JUMP)
	out := update(&s, []Finger{{id = 1, pos = p + {20, -10}}, {id = 2, pos = j + {50, 50}}}, scr)
	testing.expect_value(t, out.look, [2]f32{20, -10})
	testing.expect_value(t, out.held, u32(3))
	// A look finger and the aiming finger add up.
	update(&s, []Finger{{id = 1, pos = p + {20, -10}}, {id = 2, pos = j + {50, 50}}, {id = 3, pos = {1000, 300}}}, scr)
	out = update(&s, []Finger{{id = 1, pos = p + {25, -20}}, {id = 2, pos = j + {50, 50}}, {id = 3, pos = {1004, 303}}}, scr)
	testing.expect_value(t, out.look, [2]f32{9, -7})
}

@(test)
look_is_capped_in_a_frame :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	update(&s, []Finger{{id = 1, pos = {1000, 300}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {1000 + 30, 300 + 40}}}, scr)
	testing.expect_value(t, out.look, [2]f32{30, 40})
	out = update(&s, []Finger{{id = 1, pos = {1030 + 600, 340 + 800}}}, scr)
	testing.expect(t, near(length_of(out.look), look_cap(H)), "a jump is cut to the cap")
	testing.expect(t, near(out.look.y / out.look.x, 800.0 / 600.0, 0.001), "and keeps its direction")
	testing.expect(t, near(look_cap(H), 144), "a fifth of the height")
}

@(test)
fingers_down_at_the_start_are_spare_until_they_lift :: proc(t: ^testing.T) {
	s: State
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons, aim = 1)
	init(&s, []Finger{{id = 7, pos = middle(PAD)}})
	out := update(&s, []Finger{{id = 7, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.pressed, u32(0))
	testing.expect_value(t, out.held, u32(0))
	out = update(&s, []Finger{{id = 7, pos = middle(PAD) + {40, 0}}}, scr)
	testing.expect_value(t, out.look, [2]f32{0, 0})
	out = update(&s, nil, scr)
	out = update(&s, []Finger{{id = 7, pos = middle(PAD)}}, scr)
	testing.expect_value(t, out.pressed, u32(1))
}

@(test)
lifted_stick_finger_gives_the_stick_up :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil)
	update(&s, []Finger{{id = 1, pos = {400, 500}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {500, 500}}}, scr)
	testing.expect(t, out.stick.x > 0.5, "pushed right")
	out = update(&s, nil, scr)
	testing.expect(t, !out.stick_active, "no finger, no stick")
	testing.expect_value(t, out.stick, [2]f32{0, 0})
	out = update(&s, []Finger{{id = 2, pos = {300, 400}}}, scr)
	testing.expect_value(t, out.anchor, [2]f32{300, 400})
}

@(test)
desktop_left_side_looks_too :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil, stick = false)
	update(&s, []Finger{{id = 1, pos = {300, 400}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {330, 410}}}, scr)
	testing.expect(t, !out.stick_active, "no stick without a touch screen")
	testing.expect_value(t, out.look, [2]f32{30, 10})
}

@(test)
buttons_come_before_the_stick :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	out := update(&s, []Finger{{id = 1, pos = middle(CORNER)}}, screen_of(buttons))
	testing.expect_value(t, out.pressed, u32(4))
	testing.expect(t, !out.stick_active, "a button in the left half is a button, not a stick")
}

@(test)
only_eight_fingers_are_followed :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons)
	crowd: [9]Finger
	for i in 0 ..< 8 {
		crowd[i] = {id = i + 1, pos = {1000 + f32(i) * 10, 200}}
	}
	crowd[8] = {id = 9, pos = middle(PAD)}
	out := update(&s, crowd[:], scr)
	testing.expect_value(t, out.held, u32(0))
	// One finger lifts, and the ninth, still down, is given its job.
	out = update(&s, crowd[1:], scr)
	testing.expect_value(t, out.held, u32(1))
}

@(test)
no_finger_means_everything_is_off :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	out := update(&s, nil, screen_of(nil))
	testing.expect_value(t, out, Out{})
}

@(test)
buttons_that_land_in_the_same_frame_are_both_pressed :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	out := update(&s, []Finger{{id = 1, pos = middle(PAD)}, {id = 2, pos = middle(JUMP)}}, screen_of(buttons))
	testing.expect_value(t, out.pressed, u32(3))
	testing.expect_value(t, out.held, u32(3))
}

@(test)
where_buttons_overlap_the_later_one_wins :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{{1000, 300, 200, 200}, {1100, 300, 200, 200}}
	out := update(&s, []Finger{{id = 1, pos = {1150, 400}}}, screen_of(buttons))
	testing.expect_value(t, out.held, u32(2))
}

@(test)
a_screen_with_no_height_makes_no_nonsense :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	scr := screen_of(nil, w = 800, h = 0)
	update(&s, []Finger{{id = 1, pos = {100, 100}}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {150, 120}}}, scr)
	testing.expect_value(t, out.stick, [2]f32{0, 0})
	testing.expect_value(t, out.look, [2]f32{0, 0})
}

@(test)
stick_middle_is_pulled_in_by_numbers :: proc(t: ^testing.T) {
	// 1600 by 720: the ring is 136.8 px, so the middle may go from 155.95 to 705.6 across and from
	// 255.6 to 583.2 down.
	cases := [?][4]f32{{5, 400, 155.95, 400}, {790, 400, 705.6, 400}, {400, 5, 400, 255.6}, {400, 715, 400, 583.2}}
	for c in cases {
		s: State
		init(&s, nil)
		out := update(&s, []Finger{{id = 1, pos = {c.x, c.y}}}, screen_of(nil))
		testing.expect(t, near(out.anchor.x, c.z, 0.1) && near(out.anchor.y, c.w, 0.1), "the ring's middle is pulled in to keep the ring on the screen")
	}
}

@(test)
aiming_finger_adds_to_a_look_finger_that_came_first :: proc(t: ^testing.T) {
	s: State
	init(&s, nil)
	buttons := [][4]f32{PAD, JUMP, CORNER}
	scr := screen_of(buttons, aim = 1)
	update(&s, []Finger{{id = 1, pos = {1000, 300}}}, scr)
	update(&s, []Finger{{id = 1, pos = {1000, 300}}, {id = 2, pos = middle(PAD)}}, scr)
	out := update(&s, []Finger{{id = 1, pos = {1004, 303}}, {id = 2, pos = middle(PAD) + {5, -10}}}, scr)
	testing.expect_value(t, out.look, [2]f32{9, -7})
}

@(test)
more_fingers_at_the_start_than_slots_are_cut_off :: proc(t: ^testing.T) {
	s: State
	crowd: [10]Finger
	for i in 0 ..< 10 {
		crowd[i] = {id = i + 1, pos = {1000, 200}}
	}
	init(&s, crowd[:])
	used := 0
	for sl in s.slots {
		if sl.used {
			used += 1
		}
	}
	testing.expect_value(t, used, MAX_FINGERS)
}

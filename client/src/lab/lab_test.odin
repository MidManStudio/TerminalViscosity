// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "lab_test.odin"
// ============================================================================

package lab

import "core:testing"

new_walker :: proc() -> (l: ^Layout, p: ^Player) {
	l = new(Layout)
	p = new(Player)
	build(l)
	player_init(p, l)
	return
}

@(test)
the_layout_fits_its_arrays_and_every_box_has_a_size :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	testing.expect(t, l.box_count > 30 && l.box_count < MAX_BOXES)
	testing.expect_value(t, l.collider_count, 5)
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		testing.expectf(t, b.size.x > 0 && b.size.y > 0 && b.size.z > 0, "box %v has no size", i)
		testing.expectf(t, b.emissive >= 0 && b.emissive <= 1 && b.gloss >= 0 && b.gloss <= 1, "box %v glow or gloss out of range", i)
	}
}

@(test)
the_player_starts_in_the_open :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	testing.expect(t, !blocked(l, p.x, p.z))
}

@(test)
walking_at_full_stick_covers_the_walking_speed :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	start := p.z
	for _ in 0 ..< 60 {
		player_move(p, l, {0, -1}, 1.0 / 60)
	}
	testing.expectf(t, abs((start - p.z) - WALK_SPEED) < 0.05, "walked %v in a second", start - p.z)
}

@(test)
a_counter_stops_the_player_and_a_slanted_walk_slides_along_it :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	island := l.colliders[3]
	// Straight at the island's near side.
	for _ in 0 ..< 600 {
		player_move(p, l, {0, -1}, 1.0 / 60)
	}
	testing.expectf(t, p.z >= island.max_z + PLAYER_RADIUS - 0.001, "stopped inside the island at z=%v", p.z)
	testing.expectf(t, p.z < island.max_z + PLAYER_RADIUS + 0.2, "stopped %v short of the island", p.z - island.max_z)
	// Pushing forward and right now carries the player along the counter.
	before := p.x
	for _ in 0 ..< 120 {
		player_move(p, l, {0.7, -0.7}, 1.0 / 60)
	}
	testing.expect(t, p.x > before + 1)
	testing.expect(t, !blocked(l, p.x, p.z))
}

@(test)
the_player_cannot_leave_the_room_in_any_direction :: proc(t: ^testing.T) {
	directions := [][2]f32{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {0.7, 0.7}, {-0.7, -0.7}}
	for dir in directions {
		l, p := new_walker()
		defer free(l)
		defer free(p)
		for _ in 0 ..< 1200 {
			player_move(p, l, dir, 1.0 / 60)
		}
		testing.expectf(t, !blocked(l, p.x, p.z), "direction %v ended blocked at %v, %v", dir, p.x, p.z)
		testing.expectf(t, abs(p.x) <= ROOM_W * 0.5 && abs(p.z) <= ROOM_D * 0.5, "direction %v left the room", dir)
	}
}

@(test)
a_long_frame_does_not_carry_the_player_through_a_counter :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	p.z = 1.5
	// One half-second frame at full stick would cross the island's width twice over.
	player_move(p, l, {0, -1}, 0.5)
	player_move(p, l, {0, -1}, 0.5)
	player_move(p, l, {0, -1}, 0.5)
	testing.expectf(t, p.z > l.colliders[3].max_z, "went through the island to z=%v", p.z)
}

@(test)
looking_clamps_the_pitch_and_wraps_nothing :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	player_look(p, 0.5, 5)
	testing.expect_value(t, p.pitch, PITCH_LIMIT)
	player_look(p, 0, -10)
	testing.expect_value(t, p.pitch, -PITCH_LIMIT)
	testing.expect_value(t, p.yaw, f32(0.5))
}

@(test)
walking_follows_the_view_direction :: proc(t: ^testing.T) {
	l, p := new_walker()
	defer free(l)
	defer free(p)
	f := player_flat_forward(p)
	r := player_flat_right(p)
	testing.expect(t, abs(f.x) < 1e-5 && f.y < -0.99) // yaw 0 faces -z
	testing.expect(t, r.x > 0.99 && abs(r.y) < 1e-5) // right is +x
	player_look(p, 1.5707964, 0) // a quarter turn to the right faces +x
	f = player_flat_forward(p)
	testing.expect(t, f.x > 0.99 && abs(f.y) < 1e-4)
}

@(test)
a_jump_rises_about_half_a_metre_and_lands :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	p := new(Player)
	defer free(p)
	build(l)
	player_init(p, l)
	testing.expect(t, player_jump(p))
	peak := f32(0)
	for _ in 0 ..< 90 {
		player_update_air(p, 1.0 / 60)
		peak = max(peak, p.jump)
	}
	testing.expectf(t, peak > 0.40 && peak < 0.50, "the peak was %v m", peak)
	testing.expect_value(t, p.jump, 0)
	testing.expect_value(t, p.vy, 0)
	testing.expect_value(t, player_eye_y(p), EYE_HEIGHT)
}

@(test)
there_is_no_jump_in_the_air :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	p := new(Player)
	defer free(p)
	build(l)
	player_init(p, l)
	testing.expect(t, player_jump(p))
	for _ in 0 ..< 10 {
		player_update_air(p, 1.0 / 60)
	}
	testing.expect(t, p.jump > 0)
	testing.expect(t, !player_jump(p))
	testing.expect(t, player_eye_y(p) > EYE_HEIGHT)
}

@(test)
a_jump_is_too_low_to_clear_a_counter :: proc(t: ^testing.T) {
	testing.expect(t, JUMP_SPEED * JUMP_SPEED / (2 * GRAVITY) < COUNTER_HEIGHT)
}

@(test)
the_bottle_wall_fits_over_its_counter_and_in_the_room :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	before := l.box_count
	colors: [DISPENSER_COUNT][4]u8
	for i in 0 ..< DISPENSER_COUNT {
		colors[i] = {u8(20 * i), 100, 200, 255}
	}
	add_dispensers(l, colors)
	testing.expect_value(t, l.box_count, before + 1 + 4 * DISPENSER_COUNT)
	testing.expect(t, l.box_count < MAX_BOXES)

	counter := Rect{}
	found := false
	for i in 0 ..< l.collider_count {
		c := l.colliders[i]
		if c.min_x > 11 {
			counter, found = c, true
		}
	}
	testing.expect(t, found)
	previous_z := f32(-1e9)
	for i in 0 ..< DISPENSER_COUNT {
		n := dispenser_nozzle(i)
		testing.expectf(t, n.x > counter.min_x && n.x < counter.max_x, "nozzle %v is not over the counter", i)
		testing.expectf(t, n.z > counter.min_z && n.z < counter.max_z, "nozzle %v is past the counter", i)
		testing.expect(t, n.z - previous_z > 0.5)
		previous_z = n.z
		testing.expect(t, n.y > COUNTER_HEIGHT + 0.3 && n.y < 1.8)
	}
}

@(test)
the_east_counter_stops_the_player_but_can_be_walked_round :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	p := new(Player)
	defer free(p)
	build(l)
	player_init(p, l)
	p.x, p.z = 8, 0
	for _ in 0 ..< 240 {
		player_move(p, l, {1, 0}, 1.0 / 60) // walk east
	}
	testing.expectf(t, p.x < 11.28, "the player got to x %v", p.x)
	testing.expect(t, p.x > 10.8)
	p.x, p.z = 8, 5.6 // past the end of the counter
	p.yaw = 0
	for _ in 0 ..< 240 {
		player_move(p, l, {1, 0}, 1.0 / 60)
	}
	testing.expect(t, p.x > 11.3)
}

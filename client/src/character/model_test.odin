// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "model_test.odin"
// ============================================================================

package character

import "core:testing"

built :: proc(id: u8) -> ^Model {
	m := new(Model)
	model_build(m, palette_for(id))
	return m
}

// The lowest and highest point of a part in the space of the character, with the part in its
// rest pose, which is its soup moved to its pivot.
extent :: proc(m: ^Model, p: Part) -> (lo, hi: Vec3) {
	lo, hi = {1e9, 1e9, 1e9}, {-1e9, -1e9, -1e9}
	s := &m.parts[p]
	pivot := part_pivot(p)
	for i in 0 ..< s.count {
		q := s.pos[i] + pivot
		lo = {min(lo.x, q.x), min(lo.y, q.y), min(lo.z, q.z)}
		hi = {max(hi.x, q.x), max(hi.y, q.y), max(hi.z, q.z)}
	}
	return
}

@(test)
every_part_has_a_body_and_the_whole_is_cheap_enough_for_a_phone_to_draw_eight_of :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	total := 0
	for p in Part {
		testing.expectf(t, m.parts[p].count > 0, "%v is empty", p)
		testing.expectf(t, m.parts[p].count < MAX_SOUP, "%v filled its soup and may have lost triangles", p)
		testing.expectf(t, m.parts[p].count % 3 == 0, "%v is not whole triangles", p)
		total += m.parts[p].count / 3
	}
	testing.expectf(t, total < 1000, "%d triangles is a lot for eight players: under 8000 for all of them is what a phone draws without noticing", total)
	testing.expectf(t, total > 250, "%d triangles is too few to be the design", total)
}

@(test)
every_triangle_has_a_unit_normal_and_an_opaque_colour :: proc(t: ^testing.T) {
	m := built(3)
	defer free(m)
	for p in Part {
		s := &m.parts[p]
		for i in 0 ..< s.count {
			n := s.normal[i]
			testing.expectf(t, near(dot(n, n), 1, 0.001), "%v vertex %d has a normal of length %v", p, i, dot(n, n))
			testing.expectf(t, s.color[i].a == 255, "%v vertex %d is not opaque", p, i)
		}
	}
}

@(test)
each_part_is_closed_and_wound_outward :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	for p in Part {
		testing.expectf(t, signed_volume(&m.parts[p]) > 0.001, "%v wraps no volume: its shapes are wound the wrong way", p)
	}
}

@(test)
the_character_stands_on_the_floor_and_is_as_tall_as_it_is_said_to_be :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	lowest, highest := f32(1e9), f32(-1e9)
	for p in Part {
		lo, hi := extent(m, p)
		lowest, highest = min(lowest, lo.y), max(highest, hi.y)
	}
	testing.expect(t, near(lowest, 0, 0.01), "the feet are on the floor")
	testing.expect(t, near(highest, HEIGHT, 0.01), "the top of the quiff is at HEIGHT")
}

@(test)
the_eyes_are_where_the_first_person_camera_is :: proc(t: ^testing.T) {
	// The arena puts the eye 1.6 m above the feet, so another player's goggles have to be about there.
	m := built(0)
	defer free(m)
	lo, hi := extent(m, .Head)
	testing.expect(t, lo.y < 1.6 && hi.y > 1.6, "the head spans the height of the eye")
	pal := palette_for(0)
	goggles_at := f32(0)
	n := 0
	for i in 0 ..< m.parts[.Head].count {
		if m.parts[.Head].color[i] == pal.lens {
			goggles_at += m.parts[.Head].pos[i].y + part_pivot(.Head).y
			n += 1
		}
	}
	testing.expect(t, n > 0, "there are lenses")
	testing.expect(t, near(goggles_at / f32(n), 1.62, 0.02), "and they are at about the height of the eye")
}

@(test)
the_front_is_minus_z_where_the_player_looks :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	pal := palette_for(0)
	head := &m.parts[.Head]
	for i in 0 ..< head.count {
		if head.color[i] == pal.mask || head.color[i] == pal.lens {
			testing.expectf(t, head.pos[i].z < 0, "the mask or a lens is behind the head at vertex %d", i)
		}
	}
	// The vest and the badge are on the front of the body, and the quiff leans forward from the crown.
	body := &m.parts[.Body]
	front, back := 0, 0
	for i in 0 ..< body.count {
		if body.color[i] == pal.shirt {
			if body.pos[i].z < 0 {front += 1} else {back += 1}
		}
	}
	testing.expect(t, front > 0 && back == 0, "the vest and collar are all in front")
}

@(test)
the_left_side_is_minus_x_and_the_two_sides_are_the_same_shape :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	testing.expect(t, part_pivot(.Arm_L).x < 0 && part_pivot(.Arm_R).x > 0, "left arm is -x")
	testing.expect(t, part_pivot(.Leg_L).x < 0 && part_pivot(.Leg_R).x > 0, "left leg is -x")
	testing.expect_value(t, part_pivot(.Arm_L).x, -part_pivot(.Arm_R).x)
	testing.expect_value(t, part_pivot(.Leg_L).x, -part_pivot(.Leg_R).x)
	testing.expect_value(t, m.parts[.Arm_L].count, m.parts[.Arm_R].count)
	testing.expect_value(t, m.parts[.Leg_L].count, m.parts[.Leg_R].count)
	for i in 0 ..< m.parts[.Arm_L].count {
		testing.expectf(t, m.parts[.Arm_L].pos[i] == m.parts[.Arm_R].pos[i], "arm vertex %d differs", i)
	}
}

@(test)
arms_and_legs_hang_from_their_pivots_so_they_swing_about_them :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	for p in ([]Part{.Arm_L, .Arm_R}) {
		s := &m.parts[p]
		top, bottom := f32(-1e9), f32(1e9)
		for i in 0 ..< s.count {
			top, bottom = max(top, s.pos[i].y), min(bottom, s.pos[i].y)
		}
		testing.expectf(t, top < 0.05 && top > -0.05, "%v does not start at its shoulder: top is %v", p, top)
		testing.expectf(t, bottom < -0.7 && bottom > -0.8, "%v reaches %v below the shoulder", p, bottom)
	}
	for p in ([]Part{.Leg_L, .Leg_R}) {
		s := &m.parts[p]
		top, bottom := f32(-1e9), f32(1e9)
		for i in 0 ..< s.count {
			top, bottom = max(top, s.pos[i].y), min(bottom, s.pos[i].y)
		}
		testing.expectf(t, near(top, 0, 0.01), "%v does not start at its hip: top is %v", p, top)
		testing.expectf(t, near(bottom, -0.38, 0.01), "%v reaches %v below the hip", p, bottom)
	}
	// The arms are at the shoulders, which are on the body, and the legs under it.
	lo, hi := extent(m, .Body)
	testing.expect(t, part_pivot(.Arm_L).y < hi.y && part_pivot(.Arm_L).y > lo.y, "the shoulder is on the body")
	testing.expect(t, part_pivot(.Leg_L).y >= lo.y - 0.02 && part_pivot(.Leg_L).y < lo.y + 0.1, "the hip is at the bottom of the body")
}

@(test)
the_head_turns_about_the_neck_and_sits_on_the_body :: proc(t: ^testing.T) {
	m := built(0)
	defer free(m)
	lo, hi := extent(m, .Head)
	_, body_hi := extent(m, .Body)
	testing.expect(t, near(part_pivot(.Head).x, 0) && near(part_pivot(.Head).z, 0), "the neck is on the middle line")
	testing.expect(t, part_pivot(.Head).y <= body_hi.y && part_pivot(.Head).y > lo.y, "the neck is where the head meets the body")
	testing.expect(t, near(lo.x + hi.x, 0, 0.05), "the head is centred")
}

@(test)
palettes_give_eight_different_players_and_wrap :: proc(t: ^testing.T) {
	seen := 0
	for i in 0 ..< 8 {
		for j in 0 ..< i {
			testing.expectf(t, palette_for(u8(i)).trim != palette_for(u8(j)).trim, "players %d and %d have the same trim", i, j)
		}
		seen += 1
	}
	testing.expect_value(t, seen, 8)
	testing.expect_value(t, palette_for(0), palette_for(8))
	testing.expect_value(t, palette_for(3), palette_for(11))
	for i in 0 ..< 8 {
		p := palette_for(u8(i))
		testing.expectf(t, int(p.hair.r) + int(p.hair.g) + int(p.hair.b) < int(p.trim.r) + int(p.trim.g) + int(p.trim.b), "the hair of player %d is not darker than the trim", i)
		testing.expect_value(t, p.coat, palette_for(0).coat)
		testing.expect_value(t, p.skin, palette_for(0).skin)
	}
}

@(test)
a_palette_changes_the_colours_and_not_the_shape :: proc(t: ^testing.T) {
	a, b := built(0), built(5)
	defer free(a)
	defer free(b)
	differing := 0
	for p in Part {
		testing.expect_value(t, a.parts[p].count, b.parts[p].count)
		for i in 0 ..< a.parts[p].count {
			testing.expectf(t, a.parts[p].pos[i] == b.parts[p].pos[i], "%v vertex %d moved with the palette", p, i)
			if a.parts[p].color[i] != b.parts[p].color[i] {
				differing += 1
			}
		}
	}
	testing.expect(t, differing > 100, "the trim and the hair are in the colour of the player")
}

@(test)
building_again_gives_the_same_model_and_starts_from_nothing :: proc(t: ^testing.T) {
	a := built(2)
	defer free(a)
	b := new(Model)
	defer free(b)
	b.parts[.Body].count = 99 // left over from something else
	model_build(b, palette_for(2))
	for p in Part {
		testing.expect_value(t, a.parts[p].count, b.parts[p].count)
		for i in 0 ..< a.parts[p].count {
			testing.expectf(t, a.parts[p].pos[i] == b.parts[p].pos[i], "%v vertex %d differs", p, i)
		}
	}
}

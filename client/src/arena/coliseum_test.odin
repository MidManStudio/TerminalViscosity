// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "coliseum_test.odin"
// ============================================================================

package arena

import "core:math"
import "core:testing"

built :: proc() -> ^Coliseum {
	c := new(Coliseum)
	coliseum_build(c)
	return c
}

@(test)
the_coliseum_fits_its_mesh :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	testing.expect(t, c.count > 600, "a coliseum with stands is hundreds of boxes")
	testing.expect(t, c.count < MAX_PIECES, "and leaves room under the limit: it did not hit the cap")
	testing.expect(t, c.count * 24 <= 65535, "its mesh stays within 16-bit indices")
}

@(test)
every_piece_is_a_real_box :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	for i in 0 ..< c.count {
		p := c.pieces[i]
		testing.expectf(t, p.size.x > 0 && p.size.y > 0 && p.size.z > 0, "piece %d has no volume: %v", i, p.size)
		testing.expectf(t, p.color.a == 255, "piece %d is not opaque", i)
		testing.expectf(t, piece_top(p) >= 0, "piece %d is under the floor", i)
	}
}

@(test)
nothing_tall_stands_on_the_sand :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	tall := 0
	for i in 0 ..< c.count {
		p := c.pieces[i]
		if piece_top(p) <= FLOOR_FLAT {
			continue // markings drawn on the floor
		}
		tall += 1
		d := piece_distance(p)
		testing.expectf(t, d >= ARENA_RADIUS - GATE_PROTRUSION - 0.001, "piece %d reaches in to %.3f m from the middle", i, d)
	}
	testing.expect(t, tall > 500, "the checks ran on the stands and walls")
}

@(test)
the_floor_markings_lie_flat_inside_the_arena :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	flat := 0
	for i in 0 ..< c.count {
		p := c.pieces[i]
		if p.center.y > 0 && piece_top(p) <= FLOOR_FLAT {
			flat += 1
			testing.expect(t, piece_distance(p) < ARENA_RADIUS, "a marking is on the sand")
		}
	}
	testing.expect_value(t, flat, 64 + 48)
}

@(test)
the_distance_to_a_turned_box_is_measured_along_its_own_axes :: proc(t: ^testing.T) {
	// A box 4 long and 2 deep, centred 10 m out along +x, with its long side across the radius
	// (turned so its z side points along x): the nearest point is 1 m nearer than the middle.
	p := Piece{center = {10, 0, 0}, size = {4, 1, 2}, yaw = math.PI * 0.5}
	testing.expect(t, near(piece_distance(p), 9), "z side along the radius, 1 m half-depth")
	// Turned back, its long side lies along the radius, and its nearest point is 2 m in.
	p.yaw = 0
	testing.expect(t, near(piece_distance(p), 8), "x side 4 long along the radius, 2 m half-length")
	p.yaw = math.PI * 0.5
	p.size = {2, 1, 4}
	testing.expect(t, near(piece_distance(p), 8), "z side 4 long along the radius, 2 m half-length")
	// A box that contains the middle is 0 away.
	p = Piece{center = {0.5, 0, 0}, size = {4, 1, 4}}
	testing.expect_value(t, piece_distance(p), f32(0))
}

@(test)
ring_boxes_meet_their_neighbours :: proc(t: ^testing.T) {
	c := new(Coliseum)
	defer free(c)
	ring(c, 20, 1, 0, 2, 72, STONE)
	testing.expect_value(t, c.count, 72)
	chord := ring_chord(20, 72)
	for i in 0 ..< c.count {
		testing.expectf(t, c.pieces[i].size.x >= chord, "box %d is narrower than the gap it covers", i)
		// The middle of the box is on the ring.
		d := math.sqrt(c.pieces[i].center.x * c.pieces[i].center.x + c.pieces[i].center.z * c.pieces[i].center.z)
		testing.expectf(t, near(d, 20, 0.001), "box %d is %.4f m out", i, d)
	}
	// The radial side of every box points away from the middle.
	for i in 0 ..< c.count {
		p := c.pieces[i]
		outward := Vec3{p.center.x, 0, p.center.z} / 20
		radial := Vec3{math.sin(p.yaw), 0, math.cos(p.yaw)}
		testing.expectf(t, near(outward.x, radial.x, 0.001) && near(outward.z, radial.z, 0.001), "box %d faces the wrong way", i)
	}
}

@(test)
corners_of_a_turned_piece_are_a_rectangle_of_the_right_size_round_its_centre :: proc(t: ^testing.T) {
	p := Piece{center = {3, 0, -2}, size = {4, 1, 2}, yaw = 0.7}
	sum := Vec3{}
	for i in 0 ..< 4 {
		sum += piece_corner(p, i, 0)
	}
	testing.expect(t, near(sum.x / 4, 3, 0.001) && near(sum.z / 4, -2, 0.001), "the corners centre on the piece")
	a, b, c := piece_corner(p, 0, 0), piece_corner(p, 1, 0), piece_corner(p, 2, 0)
	ab := math.sqrt((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z))
	bc := math.sqrt((b.x - c.x) * (b.x - c.x) + (b.z - c.z) * (b.z - c.z))
	testing.expect(t, near(ab, 2, 0.001) && near(bc, 4, 0.001) || near(ab, 4, 0.001) && near(bc, 2, 0.001), "the sides are the size of the box")
	// The corners are round the box in order, so neighbours are a side apart, never a diagonal.
	d := piece_corner(p, 3, 0)
	diag := math.sqrt((a.x - c.x) * (a.x - c.x) + (a.z - c.z) * (a.z - c.z))
	testing.expect(t, near(diag, math.sqrt(f32(20)), 0.001), "opposite corners are a diagonal apart")
	testing.expect(t, near(math.sqrt((d.x - a.x) * (d.x - a.x) + (d.z - a.z) * (d.z - a.z)), bc, 0.001), "corners 3 and 0 share a side")
}

@(test)
the_tiers_rise_as_they_go_out :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	// The tops of the seating boxes at each radius band, taking the highest box in each.
	tops: [TIER_COUNT]f32
	for i in 0 ..< c.count {
		p := c.pieces[i]
		r := math.sqrt(p.center.x * p.center.x + p.center.z * p.center.z)
		for k in 0 ..< TIER_COUNT {
			middle := WALL_INNER + WALL_DEPTH + (f32(k) + 0.5) * TIER_DEPTH
			if near(r, middle, 0.05) && piece_top(p) > tops[k] && p.size.z == TIER_DEPTH {
				tops[k] = piece_top(p)
			}
		}
	}
	for k in 0 ..< TIER_COUNT {
		want := WALL_HEIGHT + f32(k + 1) * TIER_RISE
		testing.expectf(t, near(tops[k], want, 0.001), "tier %d tops out at %.2f, wanted %.2f", k, tops[k], want)
	}
}

@(test)
stairs_cut_every_tier_into_blocks :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	stairs := 0
	for i in 0 ..< c.count {
		if c.pieces[i].color == STAIR {
			stairs += 1
		}
	}
	testing.expect_value(t, stairs, TIER_COUNT * (RING_SEGMENTS / AISLE_EVERY))
}

@(test)
four_gates_stand_at_the_compass_points :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	found := [4]bool{}
	for i in 0 ..< c.count {
		p := c.pieces[i]
		if p.color != DOOR {
			continue
		}
		testing.expect(t, near(math.sqrt(p.center.x * p.center.x + p.center.z * p.center.z), WALL_INNER + 0.07, 0.01), "a door is in the wall")
		switch {
		case p.center.x > 19 && abs(p.center.z) < 0.01:
			found[0] = true
		case p.center.z > 19 && abs(p.center.x) < 0.01:
			found[1] = true
		case p.center.x < -19 && abs(p.center.z) < 0.01:
			found[2] = true
		case p.center.z < -19 && abs(p.center.x) < 0.01:
			found[3] = true
		}
	}
	testing.expect_value(t, found, [4]bool{true, true, true, true})
}

@(test)
the_outer_wall_is_inside_the_far_clip_and_the_fog :: proc(t: ^testing.T) {
	c := built()
	defer free(c)
	farthest := f32(0)
	for i in 0 ..< c.count {
		p := c.pieces[i]
		if p.center.y < 0 {
			continue // the sand slab is square and reaches further in its corners
		}
		for k in 0 ..< 4 {
			q := piece_corner(p, k, 0)
			farthest = max(farthest, math.sqrt(q.x * q.x + q.z * q.z))
		}
	}
	// The ledge on top of the outer wall reaches furthest: half its depth past the wall's middle,
	// and a little more at the corners of its boxes.
	testing.expect(t, farthest < 31.2, "the whole coliseum is within about 31 m of the middle")
	testing.expect(t, farthest > 31.0, "and the ledge is where the outer wall ends")
}

@(test)
building_twice_gives_the_same_coliseum :: proc(t: ^testing.T) {
	a, b := built(), built()
	defer free(a)
	defer free(b)
	testing.expect_value(t, a.count, b.count)
	for i in 0 ..< a.count {
		testing.expectf(t, a.pieces[i] == b.pieces[i], "piece %d differs", i)
	}
}

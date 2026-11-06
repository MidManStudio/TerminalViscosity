// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "character_test.odin"
// ============================================================================

package character

import "core:math"
import "core:testing"

near :: proc(a, b: f32, tolerance: f32 = 0.0001) -> bool {
	return abs(a - b) <= tolerance
}

near3 :: proc(a, b: Vec3, tolerance: f32 = 0.0001) -> bool {
	return near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) && near(a.z, b.z, tolerance)
}

cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

// The volume a closed soup wraps, by the divergence theorem. It is positive when every triangle is
// wound counter-clockwise from outside, which is what the tests of the shapes lean on.
signed_volume :: proc(s: ^Soup) -> f32 {
	v: f32
	for i := 0; i < s.count; i += 3 {
		v += dot(s.pos[i], cross(s.pos[i + 1], s.pos[i + 2])) / 6
	}
	return v
}

new_soup :: proc() -> ^Soup {
	return new(Soup)
}

@(test)
the_identity_changes_nothing_and_a_product_applies_the_right_one_first :: proc(t: ^testing.T) {
	p := Vec3{1, 2, 3}
	testing.expect(t, near3(mat_point(mat_identity(), p), p), "identity")
	// Turned a quarter about y, then moved: the move is not turned.
	m := mat_mul(mat_translate({10, 0, 0}), mat_rotate_y(math.PI * 0.5))
	testing.expect(t, near3(mat_point(m, {1, 0, 0}), {10, 0, -1}), "turn first, then move")
	m = mat_mul(mat_rotate_y(math.PI * 0.5), mat_translate({10, 0, 0}))
	testing.expect(t, near3(mat_point(m, {1, 0, 0}), {0, 0, -11}), "move first, then turn")
	testing.expect(t, near3(mat_dir(mat_translate({5, 5, 5}), {1, 2, 3}), {1, 2, 3}), "a direction is not moved")
}

@(test)
turning_about_y_is_the_turn_the_boxes_of_the_coliseum_use :: proc(t: ^testing.T) {
	a := f32(0.7)
	x := mat_dir(mat_rotate_y(a), {1, 0, 0})
	z := mat_dir(mat_rotate_y(a), {0, 0, 1})
	testing.expect(t, near3(x, {math.cos(a), 0, -math.sin(a)}), "x goes to (cos, -sin)")
	testing.expect(t, near3(z, {math.sin(a), 0, math.cos(a)}), "z goes to (sin, cos)")
}

@(test)
a_positive_swing_about_x_takes_the_end_of_a_hanging_part_forward :: proc(t: ^testing.T) {
	end := mat_dir(mat_rotate_x(0.5), {0, -1, 0})
	testing.expect(t, end.z < -0.4 && end.y < 0 && near(end.x, 0), "toward -z, which is forward")
	end = mat_dir(mat_rotate_x(-0.5), {0, -1, 0})
	testing.expect(t, end.z > 0.4, "and backward for a negative one")
}

@(test)
turning_about_z_is_a_proper_turn :: proc(t: ^testing.T) {
	d := mat_dir(mat_rotate_z(math.PI * 0.5), {1, 0, 0})
	testing.expect(t, near3(d, {0, 1, 0}), "x goes to y")
}

@(test)
a_character_at_yaw_zero_faces_minus_z_and_a_quarter_turn_faces_plus_x :: proc(t: ^testing.T) {
	front := Vec3{0, 0, -1}
	testing.expect(t, near3(mat_dir(root_matrix({3, 0, 4}, 0), front), front), "yaw 0 faces -z")
	testing.expect(t, near3(mat_dir(root_matrix({3, 0, 4}, math.PI * 0.5), front), {1, 0, 0}), "a quarter turn faces +x")
	testing.expect(t, near3(mat_dir(root_matrix({3, 0, 4}, math.PI), front), {0, 0, 1}), "a half turn faces +z")
	testing.expect(t, near3(mat_point(root_matrix({3, 0, 4}, 1.2), {0, 0, 0}), {3, 0, 4}), "the feet are where the player is")
}

@(test)
a_triangle_has_a_unit_normal_that_follows_its_winding :: proc(t: ^testing.T) {
	s := new_soup()
	defer free(s)
	soup_tri(s, {0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {1, 2, 3, 255}, 0.5)
	testing.expect_value(t, s.count, 3)
	testing.expect(t, near3(s.normal[0], {0, 0, 1}) && near3(s.normal[1], {0, 0, 1}) && near3(s.normal[2], {0, 0, 1}), "counter-clockwise faces the viewer")
	soup_tri(s, {0, 0, 0}, {0, 1, 0}, {1, 0, 0}, {1, 2, 3, 255})
	testing.expect(t, near3(s.normal[3], {0, 0, -1}), "clockwise faces away")
	testing.expect_value(t, s.color[0], [4]u8{1, 2, 3, 255})
	testing.expect_value(t, s.emissive[2], f32(0.5))
	testing.expect_value(t, s.emissive[3], f32(0))
}

@(test)
a_sliver_that_has_no_face_is_left_out_and_a_full_soup_stops_taking_more :: proc(t: ^testing.T) {
	s := new_soup()
	defer free(s)
	soup_tri(s, {0, 0, 0}, {1, 0, 0}, {2, 0, 0}, {255, 255, 255, 255})
	soup_tri(s, {0, 0, 0}, {0, 0, 0}, {0, 1, 0}, {255, 255, 255, 255})
	testing.expect_value(t, s.count, 0)
	for _ in 0 ..< MAX_SOUP {
		soup_tri(s, {0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {255, 255, 255, 255})
	}
	testing.expect_value(t, s.count, MAX_SOUP)
	soup_tri(s, {0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {255, 255, 255, 255})
	testing.expect_value(t, s.count, MAX_SOUP)
}

@(test)
a_box_is_twelve_triangles_wrapping_exactly_its_volume_with_normals_pointing_out :: proc(t: ^testing.T) {
	s := new_soup()
	defer free(s)
	soup_box(s, mat_translate({1, 2, 3}), {0.5, 1, 2}, {9, 9, 9, 255})
	testing.expect_value(t, s.count, 36)
	testing.expect(t, near(signed_volume(s), 1.0, 0.0005), "0.5 by 1 by 2 is a volume of 1, wound outward")
	for i := 0; i < s.count; i += 3 {
		centroid := (s.pos[i] + s.pos[i + 1] + s.pos[i + 2]) / 3
		testing.expectf(t, dot(s.normal[i], centroid - Vec3{1, 2, 3}) > 0, "triangle %d faces inward", i / 3)
	}
	lo, hi := Vec3{1e9, 1e9, 1e9}, Vec3{-1e9, -1e9, -1e9}
	for i in 0 ..< s.count {
		p := s.pos[i]
		lo = {min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)}
		hi = {max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)}
	}
	testing.expect(t, near3(lo, {0.75, 1.5, 2}) && near3(hi, {1.25, 2.5, 4}), "the box is where it was put")
}

@(test)
a_turned_box_keeps_its_volume_and_its_normals_turn_with_it :: proc(t: ^testing.T) {
	s := new_soup()
	defer free(s)
	m := mat_mul(mat_translate({0, 1, 0}), mat_mul(mat_rotate_y(0.6), mat_rotate_x(0.4)))
	soup_box(s, m, {0.5, 1, 2}, {9, 9, 9, 255})
	testing.expect(t, near(signed_volume(s), 1.0, 0.0005), "a turn does not change the volume or flip the winding")
	for i := 0; i < s.count; i += 3 {
		centroid := (s.pos[i] + s.pos[i + 1] + s.pos[i + 2]) / 3
		testing.expectf(t, dot(s.normal[i], centroid - Vec3{0, 1, 0}) > 0, "triangle %d faces inward", i / 3)
	}
}

@(test)
an_ellipsoid_is_closed_wound_outward_and_a_little_smaller_than_the_true_one :: proc(t: ^testing.T) {
	s := new_soup()
	defer free(s)
	center := Vec3{0.5, 1, -0.5}
	radii := Vec3{0.4, 0.6, 0.3}
	soup_ellipsoid(s, center, radii, 8, 6, {1, 1, 1, 255})
	testing.expect_value(t, s.count, (8 + 8 + 4 * 16) * 3)
	true_volume := 4.0 / 3.0 * math.PI * radii.x * radii.y * radii.z
	v := signed_volume(s)
	testing.expect(t, v > true_volume * 0.6 && v < true_volume, "a faceted ellipsoid is inside the true one")
	for i := 0; i < s.count; i += 3 {
		centroid := (s.pos[i] + s.pos[i + 1] + s.pos[i + 2]) / 3
		testing.expectf(t, dot(s.normal[i], centroid - center) > 0, "triangle %d faces inward", i / 3)
	}
	// The poles are where they should be, and every corner is on the true surface.
	top, bottom := f32(-1e9), f32(1e9)
	for i in 0 ..< s.count {
		p := (s.pos[i] - center) / radii
		testing.expectf(t, near(p.x * p.x + p.y * p.y + p.z * p.z, 1, 0.0005), "corner %d is off the surface", i)
		top, bottom = max(top, s.pos[i].y), min(bottom, s.pos[i].y)
	}
	testing.expect(t, near(top, center.y + radii.y) && near(bottom, center.y - radii.y), "the poles are at the ends of the vertical radius")
}

@(test)
a_finer_ellipsoid_is_closer_to_the_true_one :: proc(t: ^testing.T) {
	coarse, fine := new_soup(), new_soup()
	defer free(coarse)
	defer free(fine)
	soup_ellipsoid(coarse, {}, {1, 1, 1}, 6, 4, {1, 1, 1, 255})
	soup_ellipsoid(fine, {}, {1, 1, 1}, 16, 10, {1, 1, 1, 255})
	true_volume := f32(4.0 / 3.0 * math.PI)
	testing.expect(t, signed_volume(coarse) < signed_volume(fine) && signed_volume(fine) < true_volume, "more facets, more volume, never past the true one")
}

@(test)
a_cylinder_is_closed_wound_outward_and_has_the_volume_of_its_polygon :: proc(t: ^testing.T) {
	s := new_soup()
	defer free(s)
	soup_cylinder(s, mat_translate({0, 1, 0}), 0.5, 2, 8, {1, 1, 1, 255})
	testing.expect_value(t, s.count, 8 * 4 * 3)
	// An octagon of radius r has the area 0.5 * 8 * r squared * sin(45 degrees).
	area := f32(0.5 * 8 * 0.25) * math.sin(f32(2 * math.PI / 8))
	testing.expect(t, near(signed_volume(s), area * 2, 0.0005), "the area of the octagon times the height")
	for i := 0; i < s.count; i += 3 {
		centroid := (s.pos[i] + s.pos[i + 1] + s.pos[i + 2]) / 3
		testing.expectf(t, dot(s.normal[i], centroid - Vec3{0, 1, 0}) > 0, "triangle %d faces inward", i / 3)
	}
	caps_up, caps_down := 0, 0
	for i := 0; i < s.count; i += 3 {
		if near3(s.normal[i], {0, 1, 0}) {caps_up += 1}
		if near3(s.normal[i], {0, -1, 0}) {caps_down += 1}
	}
	testing.expect_value(t, caps_up, 8)
	testing.expect_value(t, caps_down, 8)
}

@(test)
a_cylinder_laid_on_its_side_has_the_same_volume :: proc(t: ^testing.T) {
	a, b := new_soup(), new_soup()
	defer free(a)
	defer free(b)
	soup_cylinder(a, mat_translate({0, 1, 0}), 0.3, 1.2, 10, {1, 1, 1, 255})
	soup_cylinder(b, mat_mul(mat_translate({0, 1, 0}), mat_rotate_x(math.PI * 0.5)), 0.3, 1.2, 10, {1, 1, 1, 255})
	testing.expect(t, near(signed_volume(a), signed_volume(b), 0.0005), "turning does not change it")
	lo_z, hi_z := f32(1e9), f32(-1e9)
	for i in 0 ..< b.count {
		lo_z, hi_z = min(lo_z, b.pos[i].z), max(hi_z, b.pos[i].z)
	}
	testing.expect(t, near(lo_z, -0.6) && near(hi_z, 0.6), "its length now runs along z")
}

// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "softbody_test.odin"
// ============================================================================

package softbody

import "core:math"
import "core:testing"

DT :: f32(1.0 / 60.0)

make_ring :: proc(count := 24) -> Ring {
	r: Ring
	ring_init(&r, {400, 200}, 80, count)
	r.floor_y = 600
	return r
}

all_finite :: proc(r: ^Ring) -> bool {
	for i in 0 ..< r.count {
		if math.is_nan(r.pos[i].x) || math.is_nan(r.pos[i].y) do return false
		if math.is_inf(r.pos[i].x) || math.is_inf(r.pos[i].y) do return false
	}
	return true
}

@(test)
init_builds_a_ring_with_expected_area :: proc(t: ^testing.T) {
	r := make_ring(24)
	expected := f32(math.PI) * 80 * 80
	testing.expect(t, r.count == 24)
	// A 24-gon inscribed in the circle has slightly less area than the circle.
	testing.expect(t, r.rest_area > expected * 0.97 && r.rest_area < expected)
}

@(test)
stays_finite_under_random_pokes :: proc(t: ^testing.T) {
	r := make_ring(32)
	seed := u32(12345)
	for step in 0 ..< 10_000 {
		if step % 7 == 0 {
			seed = seed * 1664525 + 1013904223
			x := f32(seed >> 16 & 0x1FF)
			seed = seed * 1664525 + 1013904223
			y := f32(seed >> 16 & 0x1FF)
			ring_poke(&r, {x, y}, 120, 40)
		}
		ring_step(&r, DT)
	}
	testing.expect(t, all_finite(&r))
}

@(test)
settles_on_the_floor_with_area_close_to_rest :: proc(t: ^testing.T) {
	r := make_ring(24)
	for _ in 0 ..< 900 {
		ring_step(&r, DT)
	}
	area := ring_area(&r)
	testing.expectf(
		t,
		area > r.rest_area * 0.85 && area < r.rest_area * 1.15,
		"area %v is too far from rest %v",
		area,
		r.rest_area,
	)
	for i in 0 ..< r.count {
		testing.expect(t, r.pos[i].y <= r.floor_y + 0.01)
	}
	// Nothing should still be moving fast once it has settled.
	for i in 0 ..< r.count {
		v := r.pos[i] - r.prev[i]
		testing.expect(t, abs(v.x) < 1.0 && abs(v.y) < 1.0)
	}
}

@(test)
grabbed_node_follows_the_target :: proc(t: ^testing.T) {
	r := make_ring(24)
	target := Vec2{500, 150}
	for _ in 0 ..< 60 {
		ring_step(&r, DT, 0, target)
	}
	testing.expect(t, r.pos[0] == target)
	testing.expect(t, all_finite(&r))
}

@(test)
nearest_finds_closest_node_or_none :: proc(t: ^testing.T) {
	r := make_ring(24)
	testing.expect(t, ring_nearest(&r, r.pos[5] + {1, 0}, 10) == 5)
	testing.expect(t, ring_nearest(&r, {-1000, -1000}, 10) == -1)
}

// Regression test for a blow-up found by rendering the lab: some combinations
// of step size, node count, radius, and floor height threw the ring off screen
// on impact. Every combination below must stay finite, above the floor, and
// near its rest area.
@(test)
stays_bounded_across_step_sizes_and_shapes :: proc(t: ^testing.T) {
	dts := [?]f32{1.0 / 30, 1.0 / 60, 1.0 / 120}
	counts := [?]int{12, 24, 32, 64}
	radii := [?]f32{40, 80, 110}
	floors := [?]f32{400, 640}
	for dt in dts {
		for count in counts {
			for radius in radii {
				for floor_y in floors {
					r: Ring
					ring_init(&r, {640, 100}, radius, count)
					r.floor_y = floor_y
					steps := int(5.0 / dt)
					for _ in 0 ..< steps {
						ring_step(&r, dt)
					}
					c := ring_center(&r)
					ratio := ring_area(&r) / r.rest_area
					ok := all_finite(&r) && c.y > 0 && c.y <= floor_y && ratio > 0.5 && ratio < 1.5
					testing.expectf(
						t,
						ok,
						"dt=%v count=%v radius=%v floor=%v -> center.y=%v area ratio=%v",
						dt,
						count,
						radius,
						floor_y,
						c.y,
						ratio,
					)
				}
			}
		}
	}
}

@(test)
survives_grab_and_throw :: proc(t: ^testing.T) {
	r := make_ring(32)
	// Drag a node up and sideways quickly, then let go.
	for step in 0 ..< 120 {
		target := Vec2{400 + f32(step) * 6, 200 - f32(step) * 2}
		ring_step(&r, DT, 3, target)
	}
	for _ in 0 ..< 600 {
		ring_step(&r, DT)
	}
	c := ring_center(&r)
	testing.expect(t, all_finite(&r))
	testing.expectf(t, c.y <= r.floor_y && c.y > -1000, "center ended at %v", c)
}

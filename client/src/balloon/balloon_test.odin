// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon_test.odin"
// ============================================================================

package balloon

import "core:math"
import "core:testing"

DT :: f32(1.0 / 60.0)

make_balloon :: proc(b: ^Balloon, frequency := 6, substeps := 8) {
	cfg := default_config()
	cfg.frequency = frequency
	cfg.substeps = substeps
	init(b, cfg)
}

@(test)
geodesic_counts_follow_the_formulas :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	for f in 1 ..= MAX_FREQUENCY {
		geodesic_build(b, f)
		testing.expectf(t, b.vert_count == geodesic_vertex_count(f), "f=%v vertices %v", f, b.vert_count)
		testing.expectf(t, b.face_count == geodesic_face_count(f), "f=%v faces %v", f, b.face_count)
		testing.expectf(t, b.edge_count == geodesic_edge_count(f), "f=%v edges %v", f, b.edge_count)
		euler := b.vert_count - b.edge_count + b.face_count
		testing.expectf(t, euler == 2, "f=%v Euler characteristic %v", f, euler)
	}
}

// A closed, consistently wound surface uses every directed edge exactly once
// and also uses its reverse exactly once.
@(test)
every_edge_borders_two_faces_with_opposite_winding :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	for f in ([]int{2, 5, 6, 8}) {
		geodesic_build(b, f)
		n := b.vert_count
		seen := make([]u8, n * n)
		defer delete(seen)
		for fi in 0 ..< b.face_count {
			tri := b.faces[fi]
			for e in 0 ..< 3 {
				u, v := int(tri[e]), int(tri[(e + 1) % 3])
				seen[u * n + v] += 1
			}
		}
		bad := 0
		for u in 0 ..< n {
			for v in 0 ..< n {
				if seen[u * n + v] > 1 || seen[u * n + v] != seen[v * n + u] {
					bad += 1
				}
			}
		}
		testing.expectf(t, bad == 0, "f=%v has %v edges that are shared wrongly", f, bad)
	}
}

@(test)
edges_are_unique_and_every_vertex_has_five_or_six_neighbors :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	for f in ([]int{3, 6, 8}) {
		geodesic_build(b, f)
		valence := make([]int, b.vert_count)
		defer delete(valence)
		for e in 0 ..< b.edge_count {
			a, c := b.edges[e][0], b.edges[e][1]
			testing.expect(t, a < c)
			valence[a] += 1
			valence[c] += 1
		}
		fives := 0
		for v in valence {
			testing.expectf(t, v == 5 || v == 6, "f=%v valence %v", f, v)
			if v == 5 {
				fives += 1
			}
		}
		testing.expectf(t, fives == 12, "f=%v has %v five-valent vertices", f, fives)
	}
}

@(test)
unit_directions_are_unit_length_and_the_tip_points_up :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	geodesic_build(b, 6)
	for i in 0 ..< b.vert_count {
		testing.expectf(t, abs(length3(b.unit_dir[i]) - 1) < 1e-4, "vertex %v length", i)
	}
	testing.expect(t, b.unit_dir[TIP] == Vec3{0, 1, 0})
	for i in 1 ..< b.vert_count {
		testing.expect(t, b.unit_dir[i].y < 1)
	}
}

@(test)
faces_point_outward_and_the_rest_volume_is_positive :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	for f in ([]int{2, 4, 6, 8}) {
		make_balloon(b, f)
		for fi in 0 ..< b.face_count {
			tri := b.faces[fi]
			p0, p1, p2 := b.rest_pos[tri[0]], b.rest_pos[tri[1]], b.rest_pos[tri[2]]
			outward := dot3(cross3(p1 - p0, p2 - p0), p0 + p1 + p2)
			testing.expectf(t, outward > 0, "f=%v face %v points inward", f, fi)
		}
		testing.expect(t, b.rest_volume > 0)
		testing.expectf(t, abs(volume(b) - b.rest_volume) < 1e-4, "f=%v volume drifted", f)
	}
}

@(test)
rest_shape_is_a_sphere_with_a_neck_toward_the_tip :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	lo, hi := bounds(b)
	// The tip is the highest point and sticks out past the round body.
	testing.expect(t, b.rest_pos[TIP].y == hi.y)
	testing.expect(t, hi.y > 1.2 * b.cfg.radius)
	// The bottom is round, not pushed out.
	testing.expectf(t, lo.y > -1.05 * b.cfg.radius && lo.y < -0.7 * b.cfg.radius, "bottom at %v", lo.y)
	// The widest part is close to the body radius.
	widest: f32
	for i in 0 ..< b.vert_count {
		widest = max(widest, math.sqrt(b.rest_pos[i].x * b.rest_pos[i].x + b.rest_pos[i].z * b.rest_pos[i].z))
	}
	testing.expectf(t, widest > 0.9 * b.cfg.radius && widest < 1.1 * b.cfg.radius, "widest %v", widest)
	// Vertices near the tip are narrower than vertices at the equator.
	for i in 0 ..< b.vert_count {
		if b.rest_pos[i].y > 1.1 * b.cfg.radius {
			r := math.sqrt(b.rest_pos[i].x * b.rest_pos[i].x + b.rest_pos[i].z * b.rest_pos[i].z)
			testing.expectf(t, r < 0.4 * b.cfg.radius, "vertex %v is %v wide on the neck", i, r)
		}
	}
}

@(test)
knot_weight_is_one_at_the_tip_and_zero_far_from_it :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	testing.expect(t, b.knot[TIP] == 1)
	knots := 0
	for i in 0 ..< b.vert_count {
		if b.knot[i] > 0 {
			knots += 1
		}
		testing.expect(t, b.knot[i] >= 0 && b.knot[i] <= 1)
	}
	testing.expectf(t, knots >= 6 && knots < b.vert_count / 4, "%v vertices touch the knot", knots)
	testing.expect(t, b.knot[b.vert_count - 1] == 0)
}

// Settled-balloon measurements shared by the physics tests.
Shape :: struct {
	height:     f32,
	width:      f32,
	lowest:     f32,
	volume:     f32, // share of the target volume
	widest_bin: int, // 0 is the bottom slice, 7 the top
	top_radius: f32, // radius of the top slice over the widest radius
}

measure :: proc(b: ^Balloon) -> Shape {
	lo, hi := bounds(b)
	s: Shape
	s.height = hi.y - lo.y
	s.width = max(hi.x - lo.x, hi.z - lo.z)
	s.lowest = lo.y
	s.volume = volume(b) / b.target_volume
	axis := b.pos[TIP]
	radius: [8]f32
	for i in 0 ..< b.vert_count {
		bin := min(7, int((b.pos[i].y - lo.y) / max(s.height, 1e-6) * 8))
		dx, dz := b.pos[i].x - axis.x, b.pos[i].z - axis.z
		radius[bin] = max(radius[bin], math.sqrt(dx * dx + dz * dz))
	}
	for k in 1 ..< 8 {
		if radius[k] > radius[s.widest_bin] {
			s.widest_bin = k
		}
	}
	s.top_radius = radius[7] / radius[s.widest_bin]
	return s
}

run :: proc(b: ^Balloon, seconds: f32) {
	for _ in 0 ..< int(seconds * 60) {
		step(b, DT)
	}
}

@(test)
dropped_balloon_comes_to_rest_flattened_on_the_floor :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 2.5, 0})
	run(b, 4)
	s := measure(b)
	testing.expect(t, is_finite(b))
	testing.expectf(t, max_speed(b) < 0.2, "still moving at %v", max_speed(b))
	testing.expectf(t, s.lowest > -1e-3, "sank into the floor by %v", -s.lowest)
	testing.expectf(t, abs(s.volume - 1) < 0.03, "volume is %v of the target", s.volume)
	// It sits wider than a sphere would, and its bottom is flat on the floor.
	testing.expectf(t, s.width > 2.04 * b.cfg.radius, "width %v", s.width)
	testing.expectf(t, s.lowest < 0.02, "floats %v above the floor", s.lowest)
}

@(test)
landing_splats_instead_of_bouncing :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 2.5, 0})
	landed := false
	highest_after: f32
	for _ in 0 ..< 240 {
		step(b, DT)
		c := center(b)
		if !landed && c.y < 0.9 {
			landed = true
		}
		if landed {
			highest_after = max(highest_after, c.y)
		}
	}
	// Never back above half the height it fell from.
	testing.expectf(t, landed, "never landed")
	testing.expectf(t, highest_after < 1.3, "rebounded to %v", highest_after)
}

@(test)
balloon_held_by_the_tip_hangs_as_a_teardrop :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 2, 0})
	for _ in 0 ..< 300 {
		pin(b, TIP, {0, 4.6, 0})
		step(b, DT)
	}
	s := measure(b)
	lo, hi := bounds(b)
	testing.expect(t, is_finite(b))
	testing.expectf(t, b.pos[TIP].y == hi.y, "the tip is not the highest point")
	testing.expectf(t, length3(b.pos[TIP] - Vec3{0, 4.6, 0}) < 1e-3, "the tip is not held")
	testing.expectf(t, abs(s.volume - 1) < 0.03, "volume is %v of the target", s.volume)
	// Tall and narrow compared with how it sits on the floor.
	testing.expectf(t, s.height / s.width > 1.4, "height over width is %v", s.height / s.width)
	// Widest in the lower half, narrowing toward the tip.
	testing.expectf(t, s.widest_bin < 4, "widest slice is %v of 7", s.widest_bin)
	testing.expectf(t, s.top_radius < 0.35, "top slice is %v of the widest", s.top_radius)
	// It hangs without touching the floor.
	testing.expectf(t, lo.y > 0.5, "bottom at %v", lo.y)
	testing.expectf(t, max_speed(b) < 0.6, "still moving at %v", max_speed(b))
}

@(test)
holding_the_tip_stretches_the_neck_more_than_resting_does :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 1.2, 0})
	run(b, 3)
	resting := measure(b)
	reset(b, {0, 2, 0})
	for _ in 0 ..< 300 {
		pin(b, TIP, {0, 4.6, 0})
		step(b, DT)
	}
	hanging := measure(b)
	testing.expect(t, hanging.height / hanging.width > resting.height / resting.width + 0.3)
}

@(test)
released_balloon_falls_and_settles :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 2, 0})
	for _ in 0 ..< 120 {
		pin(b, TIP, {0, 4.6, 0})
		step(b, DT)
	}
	unpin(b)
	testing.expect(t, b.pin == NO_PIN)
	run(b, 4)
	s := measure(b)
	testing.expect(t, is_finite(b))
	testing.expectf(t, s.lowest > -1e-3 && s.lowest < 0.02, "bottom at %v", s.lowest)
	testing.expectf(t, abs(s.volume - 1) < 0.03, "volume is %v of the target", s.volume)
	testing.expectf(t, max_speed(b) < 0.3, "still moving at %v", max_speed(b))
}

@(test)
pinned_vertex_follows_its_target_smoothly_and_within_the_speed_limit :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 2, 0})
	start := b.pos[TIP]
	target := start + Vec3{3, 1, 0}
	fastest: f32
	last := start
	for _ in 0 ..< 240 {
		pin(b, TIP, target)
		step(b, DT)
		fastest = max(fastest, length3(b.pos[TIP] - last) / DT)
		last = b.pos[TIP]
	}
	testing.expectf(t, length3(b.pos[TIP] - target) < 0.01, "ended %v away from the target", length3(b.pos[TIP] - target))
	testing.expectf(t, fastest <= b.pin_speed * 1.05, "moved at %v", fastest)
}

@(test)
fill_changes_the_volume_and_stays_stable :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 1.5, 0})
	for fill in ([]f32{0.6, 1.0, 1.2, 0.8}) {
		set_fill(b, fill)
		run(b, 2.5)
		s := measure(b)
		testing.expect(t, is_finite(b))
		testing.expectf(t, abs(s.volume - 1) < 0.05, "fill %v: volume is %v of the target", fill, s.volume)
		testing.expectf(t, abs(volume(b) / b.rest_volume - fill) < 0.06, "fill %v: volume is %v of the rest volume", fill, volume(b) / b.rest_volume)
	}
}

// A small deterministic generator so the rough-handling tests repeat exactly.
Lcg :: struct {
	state: u32,
}

lcg_next :: proc(r: ^Lcg) -> f32 {
	r.state = r.state * 1664525 + 1013904223
	return f32(r.state >> 8) / f32(1 << 24)
}

@(test)
survives_rough_handling :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	b.half_extent = 4
	reset(b, {0, 2, 0})
	rng := Lcg{12345}
	pinned := false
	target: Vec3
	for tick in 0 ..< 60 * 25 {
		if tick % 25 == 0 {
			if lcg_next(&rng) < 0.25 {
				unpin(b)
				pinned = false
			} else {
				pinned = true
				victim := int(lcg_next(&rng) * f32(b.vert_count)) % b.vert_count
				if lcg_next(&rng) < 0.4 {
					victim = TIP
				}
				pin(b, victim, b.pos[victim])
				target = {(lcg_next(&rng) - 0.5) * 8, 0.3 + lcg_next(&rng) * 5, (lcg_next(&rng) - 0.5) * 8}
			}
		}
		if pinned {
			pin(b, b.pin, target)
		}
		step(b, DT)
		testing.expectf(t, is_finite(b), "went non-finite at tick %v", tick)
		ratio := volume(b) / b.target_volume
		testing.expectf(t, ratio > 0.8 && ratio < 1.25, "volume is %v of the target at tick %v", ratio, tick)
		lo, hi := bounds(b)
		testing.expectf(t, lo.y > -0.05 && hi.y < 12 && hi.x < 6 && lo.x > -6 && hi.z < 6 && lo.z > -6, "left the room at tick %v", tick)
		if t.error_count > 0 {
			break
		}
	}
}

@(test)
stays_bounded_across_settings :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	for frequency in ([]int{3, 6, 8}) {
		for substeps in ([]int{4, 8}) {
			for dt in ([]f32{1.0 / 30, 1.0 / 60}) {
				for fill in ([]f32{0.7, 1.15}) {
					cfg := default_config()
					cfg.frequency = frequency
					cfg.substeps = substeps
					init(b, cfg)
					set_fill(b, fill)
					reset(b, {0, 2.5, 0})
					for tick in 0 ..< int(3 / dt) {
						if tick > int(1.2 / dt) {
							pin(b, TIP, {0, 4.5, 0})
						}
						step(b, dt)
					}
					lo, hi := bounds(b)
					ok := is_finite(b) && lo.y > -0.05 && hi.y < 8
					testing.expectf(t, ok, "frequency %v, substeps %v, dt %v, fill %v: bounds %v to %v", frequency, substeps, dt, fill, lo, hi)
					ratio := volume(b) / b.target_volume
					testing.expectf(t, ratio > 0.85 && ratio < 1.15, "frequency %v, substeps %v, dt %v, fill %v: volume %v", frequency, substeps, dt, fill, ratio)
				}
			}
		}
	}
}

@(test)
same_inputs_give_the_same_balloon :: proc(t: ^testing.T) {
	a := new(Balloon)
	defer free(a)
	b := new(Balloon)
	defer free(b)
	make_balloon(a)
	make_balloon(b)
	for balloon in ([]^Balloon{a, b}) {
		reset(balloon, {0, 2, 0})
		for tick in 0 ..< 200 {
			if tick > 40 && tick < 140 {
				pin(balloon, TIP, {0.5, 4, 0})
			} else {
				unpin(balloon)
			}
			step(balloon, DT)
		}
	}
	same := true
	for i in 0 ..< a.vert_count {
		if a.pos[i] != b.pos[i] {
			same = false
		}
	}
	testing.expect(t, same)
}

@(test)
floats_in_place_without_gravity :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	cfg := default_config()
	cfg.gravity = 0.0001
	init(b, cfg)
	reset(b, {0, 5, 0})
	run(b, 2)
	testing.expectf(t, max_speed(b) < 0.1, "moving at %v", max_speed(b))
	// With no gravity the water pressure is even and the rest shape holds,
	// apart from the neck easing back a little.
	moved: f32
	for i in 0 ..< b.vert_count {
		moved = max(moved, length3(b.pos[i] - (b.rest_pos[i] + Vec3{0, 5, 0})))
	}
	testing.expectf(t, moved < 0.15, "the shape drifted by %v", moved)
}

@(test)
tip_has_five_neighbors_and_the_tip_frame_points_away_from_the_body :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	testing.expect(t, b.tip_ring_count == 5)
	for k in 0 ..< b.tip_ring_count {
		testing.expect(t, b.tip_ring[k] != TIP)
	}
	// At rest, hanging, and flung sideways, the axis points from the body out through the tip.
	for scenario in 0 ..< 3 {
		reset(b, {0, 2, 0})
		for _ in 0 ..< 200 {
			switch scenario {
			case 1:
				pin(b, TIP, {0, 4.4, 0})
			case 2:
				pin(b, TIP, {2.5, 2.5, 0})
			}
			step(b, DT)
		}
		apex, axis, side := tip_frame(b)
		outward := dot3(axis, normalize3(apex - center(b)))
		testing.expectf(t, outward > 0.7, "scenario %v: axis points %v along the way out", scenario, outward)
		testing.expectf(t, abs(length3(axis) - 1) < 1e-4 && abs(length3(side) - 1) < 1e-4, "scenario %v: axes are not unit length", scenario)
		testing.expectf(t, abs(dot3(axis, side)) < 1e-3, "scenario %v: side is not square to the axis", scenario)
	}
}

@(test)
normals_are_unit_length_and_face_outward :: proc(t: ^testing.T) {
	b := new(Balloon)
	defer free(b)
	make_balloon(b)
	reset(b, {0, 2, 0})
	for _ in 0 ..< 200 {
		pin(b, TIP, {0, 4.4, 0})
		step(b, DT)
	}
	update_normals(b)
	c := center(b)
	inward := 0
	for i in 0 ..< b.vert_count {
		testing.expectf(t, abs(length3(b.normal[i]) - 1) < 1e-4, "vertex %v normal length", i)
		if dot3(b.normal[i], b.pos[i] - c) <= 0 {
			inward += 1
		}
	}
	testing.expectf(t, inward == 0, "%v normals point toward the center", inward)
}

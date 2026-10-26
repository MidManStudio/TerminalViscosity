// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mpm_test.odin"
// ============================================================================

package mpm

import "core:math"
import "core:testing"

// A coarse, cheap setup so the tests run in a moment: 4 cm cells and 1 ms steps.
test_params :: proc() -> Params {
	p := DEFAULT_PARAMS
	p.dx = 0.04
	p.dt = 1e-3
	return p
}

inside_domain :: proc(s: ^Sim) -> bool {
	lo := s.p.dx
	hi := s.p.dx * f32(s.n - 2)
	for i in 0 ..< s.count {
		x := s.particles[i].x
		if x.x < lo || x.x > hi || x.y < lo || x.y > hi || x.z < lo || x.z > hi {
			return false
		}
	}
	return true
}

@(test)
a_block_holds_two_particles_to_each_cell_side :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 16, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	added := sim_add_block(&s, {4 * dx, 4 * dx, 4 * dx}, {6 * dx, 7 * dx, 8 * dx})
	testing.expect_value(t, added, (2 * 2) * (2 * 3) * (2 * 4))
	testing.expect_value(t, s.count, added)
}

@(test)
a_block_is_cut_off_at_the_capacity :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 16, 50)
	defer sim_destroy(&s)
	dx := s.p.dx
	added := sim_add_block(&s, {4 * dx, 4 * dx, 4 * dx}, {8 * dx, 8 * dx, 8 * dx})
	testing.expect_value(t, added, 50)
	testing.expect_value(t, s.count, 50)
}

@(test)
the_grid_receives_all_the_mass :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 16, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	sim_add_block(&s, {5 * dx, 5 * dx, 5 * dx}, {9 * dx, 9 * dx, 9 * dx})
	sim_step(&s)
	total := f32(0)
	for m in s.grid_m {
		total += m
	}
	expected := f32(s.count) * s.p_mass
	testing.expectf(t, abs(total - expected) < expected * 1e-4, "the grid has %v kg and the particles have %v", total, expected)
}

@(test)
a_block_in_free_fall_speeds_up_at_gravity :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 24, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	sim_add_block(&s, {8 * dx, 14 * dx, 8 * dx}, {12 * dx, 18 * dx, 12 * dx})
	for _ in 0 ..< 100 {
		sim_step(&s)
	}
	mean := sim_momentum(&s).y / (f32(s.count) * s.p_mass)
	expected := s.p.gravity * s.p.dt * 100
	testing.expectf(t, abs(mean - expected) < abs(expected) * 0.03, "mean speed %v, expected %v", mean, expected)
}

@(test)
momentum_is_conserved_without_gravity :: proc(t: ^testing.T) {
	p := test_params()
	p.gravity = 0
	s: Sim
	sim_init(&s, p, 24, 1000)
	defer sim_destroy(&s)
	dx := p.dx
	sim_add_block(&s, {8 * dx, 8 * dx, 8 * dx}, {12 * dx, 12 * dx, 12 * dx}, {0.5, 0, 0.3})
	before := sim_momentum(&s)
	for _ in 0 ..< 60 {
		sim_step(&s)
	}
	after := sim_momentum(&s)
	size := math.sqrt(before.x * before.x + before.z * before.z)
	delta := after - before
	testing.expectf(t, math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) < size * 1e-3, "momentum went from %v to %v", before, after)
}

@(test)
a_tank_of_liquid_comes_to_rest :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 12, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	sim_add_block(&s, {3 * dx, 3 * dx, 3 * dx}, {9 * dx, 5 * dx, 9 * dx})
	for _ in 0 ..< 1000 {
		sim_step(&s)
	}
	testing.expect(t, sim_finite(&s))
	testing.expect(t, inside_domain(&s))
	testing.expectf(t, sim_max_speed(&s) < 0.25, "still moving at %v m/s", sim_max_speed(&s))
	// Slightly compressed by its own weight, and no more than that.
	testing.expectf(t, sim_mean_j(&s) > 0.85 && sim_mean_j(&s) < 1.0, "the mean volume ratio is %v", sim_mean_j(&s))
}

@(test)
a_dropped_block_splashes_and_stays_inside :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 14, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	sim_add_block(&s, {5 * dx, 8 * dx, 5 * dx}, {9 * dx, 11 * dx, 9 * dx})
	top_before := sim_top(&s)
	for step in 0 ..< 600 {
		sim_step(&s)
		if step % 50 == 0 {
			testing.expect(t, sim_finite(&s))
			testing.expect(t, inside_domain(&s))
		}
	}
	testing.expect(t, sim_top(&s) < top_before - 0.1)
}

@(test)
the_same_start_gives_the_same_liquid :: proc(t: ^testing.T) {
	a, b: Sim
	sim_init(&a, test_params(), 14, 1000)
	sim_init(&b, test_params(), 14, 1000)
	defer sim_destroy(&a)
	defer sim_destroy(&b)
	dx := a.p.dx
	sim_add_block(&a, {5 * dx, 6 * dx, 5 * dx}, {9 * dx, 9 * dx, 9 * dx}, {0.2, 0, 0})
	sim_add_block(&b, {5 * dx, 6 * dx, 5 * dx}, {9 * dx, 9 * dx, 9 * dx}, {0.2, 0, 0})
	for _ in 0 ..< 200 {
		sim_step(&a)
		sim_step(&b)
	}
	same := a.count == b.count
	for i in 0 ..< a.count {
		same = same && a.particles[i].x == b.particles[i].x && a.particles[i].v == b.particles[i].v
	}
	testing.expect(t, same)
}

// Angular momentum about the vertical line through (cx, cz).
spin_of :: proc(s: ^Sim, cx, cz: f32) -> f32 {
	total := f32(0)
	for i in 0 ..< s.count {
		p := s.particles[i]
		total += s.p_mass * ((p.x.z - cz) * p.v.x - (p.x.x - cx) * p.v.z)
	}
	return total
}

// The affine matrix is what lets a particle carry rotation, so a block set
// spinning with no gravity must keep its spin. This fails if the matrix is
// rebuilt at the wrong scale.
@(test)
a_spinning_block_keeps_its_spin :: proc(t: ^testing.T) {
	p := test_params()
	p.gravity = 0
	s: Sim
	sim_init(&s, p, 24, 2000)
	defer sim_destroy(&s)
	dx := p.dx
	centre := 12 * dx
	sim_add_block(&s, {8 * dx, 8 * dx, 8 * dx}, {16 * dx, 16 * dx, 16 * dx})
	omega := f32(3)
	for i in 0 ..< s.count {
		q := &s.particles[i]
		q.v = {omega * (q.x.z - centre), 0, -omega * (q.x.x - centre)}
		q.c = {0, 0, omega, 0, 0, 0, -omega, 0, 0}
	}
	before := spin_of(&s, centre, centre)
	for _ in 0 ..< 100 {
		sim_step(&s)
	}
	after := spin_of(&s, centre, centre)
	testing.expectf(t, abs(after - before) < abs(before) * 0.05, "the spin went from %v to %v", before, after)
}

@(test)
the_benchmark_liquid_has_the_stated_particle_counts :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, DEFAULT_PARAMS, BENCH_GRID, BENCH_CAPACITY)
	defer sim_destroy(&s)
	for edge in BENCH_EDGES {
		testing.expect_value(t, bench_setup(&s, edge), edge * edge * edge)
		for _ in 0 ..< 20 {
			sim_step(&s)
		}
		testing.expect(t, sim_finite(&s))
	}
}

// The first, plain version of the step: the whole grid cleared and updated, every
// access checked, the loops written out as the paper gives them. It is kept here
// to show that the faster step in mpm.odin does the same physics.
reference_step :: proc(s: ^Sim) {
	n := s.n
	dx := s.p.dx
	dt := s.p.dt
	inv_dx := 1 / dx
	m := s.p_mass
	// Section 3.3: the inverse of the moment matrix is 4 / dx^2 for quadratic weights.
	stress_scale := -dt * s.p_vol * 4 * inv_dx * inv_dx * s.p.bulk
	c_scale := 4 * inv_dx * inv_dx

	for i in 0 ..< len(s.grid_m) {
		s.grid_m[i] = 0
		s.grid_v[i] = {}
	}

	// Particles to grid.
	for pi in 0 ..< s.count {
		p := &s.particles[pi]
		gx, gy, gz := p.x.x * inv_dx, p.x.y * inv_dx, p.x.z * inv_dx
		bx, by, bz := int(gx - 0.5), int(gy - 0.5), int(gz - 0.5)
		fx, fy, fz := gx - f32(bx), gy - f32(by), gz - f32(bz)
		wx := [3]f32{0.5 * (1.5 - fx) * (1.5 - fx), 0.75 - (fx - 1) * (fx - 1), 0.5 * (fx - 0.5) * (fx - 0.5)}
		wy := [3]f32{0.5 * (1.5 - fy) * (1.5 - fy), 0.75 - (fy - 1) * (fy - 1), 0.5 * (fy - 0.5) * (fy - 0.5)}
		wz := [3]f32{0.5 * (1.5 - fz) * (1.5 - fz), 0.75 - (fz - 1) * (fz - 1), 0.5 * (fz - 0.5) * (fz - 0.5)}

		stress := stress_scale * (p.j - 1)
		a00, a01, a02 := stress + m * p.c[0], m * p.c[1], m * p.c[2]
		a10, a11, a12 := m * p.c[3], stress + m * p.c[4], m * p.c[5]
		a20, a21, a22 := m * p.c[6], m * p.c[7], stress + m * p.c[8]
		mvx, mvy, mvz := m * p.v.x, m * p.v.y, m * p.v.z

		for i in 0 ..< 3 {
			dpx := (f32(i) - fx) * dx
			for j in 0 ..< 3 {
				dpy := (f32(j) - fy) * dx
				wij := wx[i] * wy[j]
				row := ((bx + i) * n + (by + j)) * n + bz
				for k in 0 ..< 3 {
					dpz := (f32(k) - fz) * dx
					w := wij * wz[k]
					node := row + k
					s.grid_m[node] += w * m
					g := &s.grid_v[node]
					g.x += w * (mvx + a00 * dpx + a01 * dpy + a02 * dpz)
					g.y += w * (mvy + a10 * dpx + a11 * dpy + a12 * dpz)
					g.z += w * (mvz + a20 * dpx + a21 * dpy + a22 * dpz)
				}
			}
		}
	}

	// Grid update: momentum to velocity, gravity, and the walls.
	gravity_step := dt * s.p.gravity
	for i in 0 ..< n {
		for j in 0 ..< n {
			for k in 0 ..< n {
				node := (i * n + j) * n + k
				mass := s.grid_m[node]
				if mass <= 0 {
					continue
				}
				g := &s.grid_v[node]
				inv := 1 / mass
				g.x *= inv
				g.y = g.y * inv + gravity_step
				g.z *= inv
				if (i < BOUND && g.x < 0) || (i > n - BOUND && g.x > 0) {
					g.x = 0
				}
				if (j < BOUND && g.y < 0) || (j > n - BOUND && g.y > 0) {
					g.y = 0
				}
				if (k < BOUND && g.z < 0) || (k > n - BOUND && g.z > 0) {
					g.z = 0
				}
			}
		}
	}

	// Grid to particles, then the particles move.
	lo := dx
	hi := dx * f32(n - 2)
	for pi in 0 ..< s.count {
		p := &s.particles[pi]
		gx, gy, gz := p.x.x * inv_dx, p.x.y * inv_dx, p.x.z * inv_dx
		bx, by, bz := int(gx - 0.5), int(gy - 0.5), int(gz - 0.5)
		fx, fy, fz := gx - f32(bx), gy - f32(by), gz - f32(bz)
		wx := [3]f32{0.5 * (1.5 - fx) * (1.5 - fx), 0.75 - (fx - 1) * (fx - 1), 0.5 * (fx - 0.5) * (fx - 0.5)}
		wy := [3]f32{0.5 * (1.5 - fy) * (1.5 - fy), 0.75 - (fy - 1) * (fy - 1), 0.5 * (fy - 0.5) * (fy - 0.5)}
		wz := [3]f32{0.5 * (1.5 - fz) * (1.5 - fz), 0.75 - (fz - 1) * (fz - 1), 0.5 * (fz - 0.5) * (fz - 0.5)}

		vx, vy, vz: f32
		c00, c01, c02, c10, c11, c12, c20, c21, c22: f32
		for i in 0 ..< 3 {
			dpx := (f32(i) - fx) * dx
			for j in 0 ..< 3 {
				dpy := (f32(j) - fy) * dx
				wij := wx[i] * wy[j]
				row := ((bx + i) * n + (by + j)) * n + bz
				for k in 0 ..< 3 {
					dpz := (f32(k) - fz) * dx
					w := wij * wz[k]
					g := s.grid_v[row + k]
					vx += w * g.x
					vy += w * g.y
					vz += w * g.z
					cw := w * c_scale
					c00 += cw * g.x * dpx
					c01 += cw * g.x * dpy
					c02 += cw * g.x * dpz
					c10 += cw * g.y * dpx
					c11 += cw * g.y * dpy
					c12 += cw * g.y * dpz
					c20 += cw * g.z * dpx
					c21 += cw * g.z * dpy
					c22 += cw * g.z * dpz
				}
			}
		}
		p.v = {vx, vy, vz}
		p.c = {c00, c01, c02, c10, c11, c12, c20, c21, c22}
		p.x.x = clamp(p.x.x + dt * vx, lo, hi)
		p.x.y = clamp(p.x.y + dt * vy, lo, hi)
		p.x.z = clamp(p.x.z + dt * vz, lo, hi)
		p.j = clamp(p.j * (1 + dt * (c00 + c11 + c22)), J_MIN, J_MAX)
	}
}

@(test)
the_fast_step_matches_the_plain_one :: proc(t: ^testing.T) {
	a, b: Sim
	sim_init(&a, test_params(), 14, 1000)
	sim_init(&b, test_params(), 14, 1000)
	defer sim_destroy(&a)
	defer sim_destroy(&b)
	dx := a.p.dx
	sim_add_block(&a, {4 * dx, 5 * dx, 4 * dx}, {10 * dx, 9 * dx, 8 * dx}, {0.3, 0, -0.2})
	sim_add_block(&b, {4 * dx, 5 * dx, 4 * dx}, {10 * dx, 9 * dx, 8 * dx}, {0.3, 0, -0.2})
	for _ in 0 ..< 200 {
		sim_step(&a)
		reference_step(&b)
	}
	worst_x, worst_v := f32(0), f32(0)
	for i in 0 ..< a.count {
		for axis in 0 ..< 3 {
			worst_x = max(worst_x, abs(a.particles[i].x[axis] - b.particles[i].x[axis]))
			worst_v = max(worst_v, abs(a.particles[i].v[axis] - b.particles[i].v[axis]))
		}
	}
	testing.expectf(t, worst_x < 1e-3 && worst_v < 1e-2, "the two differ by %v m and %v m/s", worst_x, worst_v)
}

@(test)
only_the_block_the_liquid_touches_is_worked_on :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 24, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	sim_add_block(&s, {10 * dx, 10 * dx, 10 * dx}, {12 * dx, 12 * dx, 12 * dx})
	sim_step(&s)
	testing.expect(t, s.active_nodes > 0 && s.active_nodes < 24 * 24 * 24 / 20)
	sim_clear(&s)
	sim_step(&s)
	testing.expect_value(t, s.active_nodes, 0)
}

@(test)
a_particle_with_a_broken_velocity_stays_inside_the_grid :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 14, 1000)
	defer sim_destroy(&s)
	dx := s.p.dx
	sim_add_block(&s, {5 * dx, 5 * dx, 5 * dx}, {8 * dx, 8 * dx, 8 * dx})
	nan := math.nan_f32()
	s.particles[0].v = {nan, nan, nan}
	s.particles[1].v = {1e30, -1e30, 1e30}
	for _ in 0 ..< 20 {
		sim_step(&s) // the grid is read through plain pointers, so this would crash if a stencil left it
	}
	testing.expect(t, inside_domain(&s))
}

@(test)
particles_can_be_added_and_taken_out_one_at_a_time :: proc(t: ^testing.T) {
	s: Sim
	sim_init(&s, test_params(), 14, 3)
	defer sim_destroy(&s)
	testing.expect(t, sim_add_particle(&s, {0.2, 0.3, 0.2}, {1, 0, 0}))
	testing.expect(t, sim_add_particle(&s, {0.25, 0.3, 0.2}, {2, 0, 0}))
	testing.expect(t, sim_add_particle(&s, {-5, 99, 0.2}, {3, 0, 0})) // far outside, so it is pulled in
	testing.expect(t, !sim_add_particle(&s, {0.2, 0.3, 0.2}, {})) // full
	testing.expect(t, inside_domain(&s))
	sim_remove_particle(&s, 0)
	testing.expect_value(t, s.count, 2)
	testing.expect_value(t, s.particles[0].v.x, 3) // the last one took its place
	testing.expect_value(t, s.particles[1].v.x, 2)
	sim_remove_particle(&s, 1)
	sim_remove_particle(&s, 0)
	testing.expect_value(t, s.count, 0)
	sim_step(&s) // an empty sim steps without trouble
}

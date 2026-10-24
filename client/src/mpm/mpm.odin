// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mpm.odin"
// ============================================================================

// Package mpm is a small liquid simulator for the lab: the Moving Least Squares
// Material Point Method of Hu et al. (2018) for a weakly compressible fluid,
// with the affine particle-in-cell transfer, quadratic B-spline weights, and a
// box of walls around the grid. It has no raylib dependency, so it is tested
// and benchmarked without a window. Units are metres, kilograms, and seconds.
package mpm

import "core:math"

Vec3 :: [3]f32

BOUND :: 3 // cells at the edge of the grid that act as a wall
J_MIN :: f32(0.2) // limits on how far a particle's volume may drift
J_MAX :: f32(5.0)

// Everything that tunes the fluid. Water is about 1000 kg/m3 and 2.2e9 Pa, but
// that stiffness would need steps far too small, so `bulk` is set low, as in the
// paper, and the liquid is slightly squashy. The step must stay below about
// 0.3 * dx / (sqrt(bulk / rho) + the fastest flow).
Params :: struct {
	dx:      f32, // grid spacing
	dt:      f32, // length of one substep
	rho:     f32, // density
	bulk:    f32, // stiffness
	gravity: f32, // along y, negative is down
}

DEFAULT_PARAMS :: Params{dx = 0.01, dt = 3e-4, rho = 1000, bulk = 1e4, gravity = -9.8}

// One piece of liquid. `c` is the affine velocity matrix of the paper, row by
// row, and `j` is the ratio of the volume it now fills to the volume it started
// with.
Particle :: struct {
	x: Vec3,
	v: Vec3,
	c: [9]f32,
	j: f32,
}

Sim :: struct {
	p:         Params,
	n:         int, // grid nodes along each side
	particles: []Particle,
	count:     int,
	grid_m:    []f32, // mass at each node
	grid_v:    []Vec3, // momentum, then velocity, at each node
	p_vol:     f32, // the starting volume of one particle
	p_mass:    f32,
}

// Makes room for `capacity` particles and a grid of n x n x n nodes. Nothing is
// allocated after this, so stepping never touches the allocator.
sim_init :: proc(s: ^Sim, p: Params, n, capacity: int) {
	s.p = p
	s.n = n
	s.particles = make([]Particle, capacity)
	s.grid_m = make([]f32, n * n * n)
	s.grid_v = make([]Vec3, n * n * n)
	s.p_vol = p.dx * p.dx * p.dx / 8 // eight particles to a cell
	s.p_mass = p.rho * s.p_vol
	s.count = 0
}

sim_destroy :: proc(s: ^Sim) {
	delete(s.particles)
	delete(s.grid_m)
	delete(s.grid_v)
	s^ = {}
}

sim_clear :: proc(s: ^Sim) {
	s.count = 0
}

// Fills the box from `lo` to `hi` with particles on a lattice, two to a cell
// along each side, all moving at `v`. Returns how many were added, which is
// fewer than the box holds if the capacity runs out.
sim_add_block :: proc(s: ^Sim, lo, hi: Vec3, v: Vec3 = {}) -> int {
	step := s.p.dx * 0.5
	added := 0
	for x := lo.x + step * 0.5; x < hi.x; x += step {
		for y := lo.y + step * 0.5; y < hi.y; y += step {
			for z := lo.z + step * 0.5; z < hi.z; z += step {
				if s.count == len(s.particles) {
					return added
				}
				s.particles[s.count] = {
					x = {x, y, z},
					v = v,
					j = 1,
				}
				s.count += 1
				added += 1
			}
		}
	}
	return added
}

// Advances the liquid by one substep: particles to grid, grid update with
// gravity and walls, grid to particles. This is the paper's section 4, with the
// force of section 3.4 folded into the transfer so no kernel gradient is ever
// needed. The stress is that of a weakly compressible fluid, from the volume
// ratio alone.
sim_step :: proc(s: ^Sim) {
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

// Total momentum of the particles.
sim_momentum :: proc(s: ^Sim) -> Vec3 {
	total: Vec3
	for i in 0 ..< s.count {
		total += s.particles[i].v * s.p_mass
	}
	return total
}

sim_max_speed :: proc(s: ^Sim) -> f32 {
	fastest := f32(0)
	for i in 0 ..< s.count {
		v := s.particles[i].v
		fastest = max(fastest, math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z))
	}
	return fastest
}

sim_mean_j :: proc(s: ^Sim) -> f32 {
	if s.count == 0 {
		return 1
	}
	total := f32(0)
	for i in 0 ..< s.count {
		total += s.particles[i].j
	}
	return total / f32(s.count)
}

// Height of the highest particle.
sim_top :: proc(s: ^Sim) -> f32 {
	top := f32(0)
	for i in 0 ..< s.count {
		top = max(top, s.particles[i].x.y)
	}
	return top
}

// False if any particle has a position or velocity that is not a number.
sim_finite :: proc(s: ^Sim) -> bool {
	for i in 0 ..< s.count {
		p := s.particles[i]
		for e in p.x {
			if e != e || abs(e) > 1e6 {
				return false
			}
		}
		for e in p.v {
			if e != e || abs(e) > 1e6 {
				return false
			}
		}
	}
	return true
}

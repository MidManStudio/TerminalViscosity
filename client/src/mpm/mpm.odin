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
	active_nodes: int, // how many grid nodes the last step touched
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
					x = {clamp(x, s.p.dx, s.p.dx * f32(s.n - 2)), clamp(y, s.p.dx, s.p.dx * f32(s.n - 2)), clamp(z, s.p.dx, s.p.dx * f32(s.n - 2))},
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

// Adds one particle at `x`, moving at `v`, and says whether there was room. The
// position is forced inside the grid, the same as every step does.
sim_add_particle :: proc(s: ^Sim, x, v: Vec3) -> bool {
	if s.count == len(s.particles) {
		return false
	}
	lo := s.p.dx
	hi := s.p.dx * f32(s.n - 2)
	s.particles[s.count] = {
		x = {clamp(x.x, lo, hi), clamp(x.y, lo, hi), clamp(x.z, lo, hi)},
		v = v,
		j = 1,
	}
	s.count += 1
	return true
}

// Takes particle `i` out by moving the last one into its place, so the order of
// the particles changes.
sim_remove_particle :: proc(s: ^Sim, i: int) {
	s.count -= 1
	s.particles[i] = s.particles[s.count]
}

// Advances the liquid by one substep: particles to grid, grid update with
// gravity and walls, grid to particles. This is the paper's section 4, with the
// force of section 3.4 folded into the transfer so no kernel gradient is ever
// needed. The stress is that of a weakly compressible fluid, from the volume
// ratio alone.
//
// Two things keep a step cheap on a phone build with no optimizer. Only the
// block of the grid that the particles touch is cleared and updated, and the
// grid is read and written through plain pointers, which is safe because every
// particle position is forced into [dx, (n - 2) dx] each step, even if a
// velocity has turned into NaN, so a stencil never leaves the grid.
sim_step :: proc(s: ^Sim) {
	if s.count == 0 {
		s.active_nodes = 0
		return
	}
	n := s.n
	dx := s.p.dx
	dt := s.p.dt
	inv_dx := 1 / dx
	m := s.p_mass
	// Section 3.3: the inverse of the moment matrix is 4 / dx^2 for quadratic weights.
	stress_scale := -dt * s.p_vol * 4 * inv_dx * inv_dx * s.p.bulk
	c_scale := 4 * inv_dx * inv_dx
	gm := raw_data(s.grid_m)
	gv := raw_data(s.grid_v)

	// The block of grid nodes that any stencil reaches.
	i0, j0, k0 := n, n, n
	i1, j1, k1 := 0, 0, 0
	for pi in 0 ..< s.count {
		x := s.particles[pi].x
		bx, by, bz := int(x.x * inv_dx - 0.5), int(x.y * inv_dx - 0.5), int(x.z * inv_dx - 0.5)
		i0, i1 = min(i0, bx), max(i1, bx)
		j0, j1 = min(j0, by), max(j1, by)
		k0, k1 = min(k0, bz), max(k1, bz)
	}
	i1, j1, k1 = i1 + 2, j1 + 2, k1 + 2
	s.active_nodes = (i1 - i0 + 1) * (j1 - j0 + 1) * (k1 - k0 + 1)

	for i in i0 ..= i1 {
		for j in j0 ..= j1 {
			row := (i * n + j) * n
			for k in k0 ..= k1 {
				gm[row + k] = 0
				gv[row + k] = {}
			}
		}
	}

	// Particles to grid.
	for pi in 0 ..< s.count {
		p := &s.particles[pi]
		gx, gy, gz := p.x.x * inv_dx, p.x.y * inv_dx, p.x.z * inv_dx
		bx, by, bz := int(gx - 0.5), int(gy - 0.5), int(gz - 0.5)
		fx, fy, fz := gx - f32(bx), gy - f32(by), gz - f32(bz)
		wx := [3]f32{0.5 * (1.5 - fx) * (1.5 - fx), 0.75 - (fx - 1) * (fx - 1), 0.5 * (fx - 0.5) * (fx - 0.5)}
		wy := [3]f32{0.5 * (1.5 - fy) * (1.5 - fy), 0.75 - (fy - 1) * (fy - 1), 0.5 * (fy - 0.5) * (fy - 0.5)}
		wz0 := 0.5 * (1.5 - fz) * (1.5 - fz)
		wz1 := 0.75 - (fz - 1) * (fz - 1)
		wz2 := 0.5 * (fz - 0.5) * (fz - 0.5)
		dz0, dz1, dz2 := -fz * dx, (1 - fz) * dx, (2 - fz) * dx

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
				// What does not depend on z is worked out once for the row of three nodes.
				ux := mvx + a00 * dpx + a01 * dpy
				uy := mvy + a10 * dpx + a11 * dpy
				uz := mvz + a20 * dpx + a21 * dpy
				node := ((bx + i) * n + (by + j)) * n + bz
				w0, w1, w2 := wij * wz0, wij * wz1, wij * wz2
				gm[node] += w0 * m
				gm[node + 1] += w1 * m
				gm[node + 2] += w2 * m
				g := &gv[node]
				g.x += w0 * (ux + a02 * dz0)
				g.y += w0 * (uy + a12 * dz0)
				g.z += w0 * (uz + a22 * dz0)
				g = &gv[node + 1]
				g.x += w1 * (ux + a02 * dz1)
				g.y += w1 * (uy + a12 * dz1)
				g.z += w1 * (uz + a22 * dz1)
				g = &gv[node + 2]
				g.x += w2 * (ux + a02 * dz2)
				g.y += w2 * (uy + a12 * dz2)
				g.z += w2 * (uz + a22 * dz2)
			}
		}
	}

	// Grid update: momentum to velocity, gravity, and the walls.
	gravity_step := dt * s.p.gravity
	for i in i0 ..= i1 {
		for j in j0 ..= j1 {
			row := (i * n + j) * n
			for k in k0 ..= k1 {
				mass := gm[row + k]
				if mass <= 0 {
					continue
				}
				g := &gv[row + k]
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
		wz0 := 0.5 * (1.5 - fz) * (1.5 - fz)
		wz1 := 0.75 - (fz - 1) * (fz - 1)
		wz2 := 0.5 * (fz - 0.5) * (fz - 0.5)
		e0, e1, e2 := wz0 * -fz * dx, wz1 * (1 - fz) * dx, wz2 * (2 - fz) * dx

		vx, vy, vz: f32
		c00, c01, c02, c10, c11, c12, c20, c21, c22: f32
		for i in 0 ..< 3 {
			dpx := (f32(i) - fx) * dx
			for j in 0 ..< 3 {
				dpy := (f32(j) - fy) * dx
				wij := wx[i] * wy[j]
				node := ((bx + i) * n + (by + j)) * n + bz
				g0, g1, g2 := gv[node], gv[node + 1], gv[node + 2]
				// Sums along the row of three nodes, plain and weighted by the offset in z.
				sx := wz0 * g0.x + wz1 * g1.x + wz2 * g2.x
				sy := wz0 * g0.y + wz1 * g1.y + wz2 * g2.y
				sz := wz0 * g0.z + wz1 * g1.z + wz2 * g2.z
				tx := e0 * g0.x + e1 * g1.x + e2 * g2.x
				ty := e0 * g0.y + e1 * g1.y + e2 * g2.y
				tz := e0 * g0.z + e1 * g1.z + e2 * g2.z
				a, b := wij * dpx, wij * dpy
				vx += wij * sx
				vy += wij * sy
				vz += wij * sz
				c00 += a * sx
				c01 += b * sx
				c02 += wij * tx
				c10 += a * sy
				c11 += b * sy
				c12 += wij * ty
				c20 += a * sz
				c21 += b * sz
				c22 += wij * tz
			}
		}
		c00, c01, c02 = c00 * c_scale, c01 * c_scale, c02 * c_scale
		c10, c11, c12 = c10 * c_scale, c11 * c_scale, c12 * c_scale
		c20, c21, c22 = c20 * c_scale, c21 * c_scale, c22 * c_scale
		p.v = {vx, vy, vz}
		p.c = {c00, c01, c02, c10, c11, c12, c20, c21, c22}
		// Written so that a NaN falls to the low end, because a position must
		// always stay inside the grid.
		nx, ny, nz := p.x.x + dt * vx, p.x.y + dt * vy, p.x.z + dt * vz
		nx = nx >= lo ? (nx <= hi ? nx : hi) : lo
		ny = ny >= lo ? (ny <= hi ? ny : hi) : lo
		nz = nz >= lo ? (nz <= hi ? nz : hi) : lo
		p.x = {nx, ny, nz}
		jn := p.j * (1 + dt * (c00 + c11 + c22))
		p.j = jn >= J_MIN ? (jn <= J_MAX ? jn : J_MAX) : J_MIN
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

// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon.odin"
// ============================================================================

// Package balloon is the 3D soft body of a water balloon: a closed rubber
// membrane around a fixed volume of water, tied off at one vertex (the tip).
// It has no raylib dependency, so it can be tested and benchmarked without a
// window.
package balloon

import "core:math"

Vec3 :: [3]f32

// Largest mesh the fixed arrays can hold: a frequency 8 geodesic sphere.
MAX_FREQUENCY :: 8
MAX_VERTS :: 10 * MAX_FREQUENCY * MAX_FREQUENCY + 2
MAX_FACES :: 20 * MAX_FREQUENCY * MAX_FREQUENCY
MAX_EDGES :: 30 * MAX_FREQUENCY * MAX_FREQUENCY
MAX_VALENCE :: 6

// The vertex at the tied end of the balloon. Grab it to lift the balloon by its tip.
TIP :: 0
NO_PIN :: -1

// How hard a sudden stop or start is allowed to tilt the water, in multiples of gravity.
ACCEL_LIMIT :: 6
// Time constant of the filter on the balloon's acceleration, in seconds.
ACCEL_TAU :: 0.06
// Water pressure is never allowed to push harder than this many times the
// pressure that gravity alone would give. Beyond it a yank would turn the
// water's weight into a force strong enough to fold the membrane inside out.
HYDRO_GAIN_MAX :: 4
// Rubber stiffens with stretch. The compliance of an edge is divided by one
// plus the square of its strain over this value.
HARDEN_STRAIN :: 0.5
// How quickly the pinned vertex follows its target, in radians per second.
PIN_RESPONSE :: 40
// The balloon counts as broken when it holds less or more than this share of its volume.
HEALTHY_VOLUME_MIN :: 0.3
HEALTHY_VOLUME_MAX :: 3

Config :: struct {
	frequency:         int, // mesh detail, 2 to MAX_FREQUENCY
	radius:            f32, // radius of the round part of the rest shape
	mass:              f32, // rubber and water together, shared evenly by the vertices
	gravity:           f32, // downward acceleration
	neck_length:       f32, // how far the neck reaches past the body, in radii
	neck_pinch:        f32, // 0..1, width of the neck at its tip relative to the sphere
	neck_angle:        f32, // polar angle where the neck blends into the body
	knot_bulge:        f32, // extra width of the knot ring, as a fraction
	edge_compliance:   f32, // rubber softness, larger stretches more under load
	knot_compliance:   f32, // the same for the knot, kept much smaller
	volume_compliance: f32, // water compressibility, close to zero
	prestretch:        f32, // rest length of an edge divided by its length in the rest shape
	droop:             f32, // gain on the water's weight, 1 is physical
	damping:           f32, // per second, slows everything
	edge_damping:      f32, // per second, slows only stretching and squeezing
	shape_damping:     f32, // per second, slows every change of shape but not flying or spinning
	contact_damping:   f32, // extra shape damping while resting on the floor, so landings splat
	held_damping:      f32, // per second, drags the whole balloon against the hand while it is held
	friction:          f32, // floor friction coefficient
	substeps:          int, // solver passes per step
	fill:              f32, // target volume divided by the rest volume
}

default_config :: proc() -> Config {
	return Config {
		frequency = 6,
		radius = 1,
		mass = 1,
		gravity = 30,
		neck_length = 0.4,
		neck_pinch = 0.2,
		neck_angle = 0.7,
		knot_bulge = 0.5,
		edge_compliance = 0.02,
		knot_compliance = 0.002,
		volume_compliance = 0.00002,
		prestretch = 0.97,
		droop = 3,
		damping = 0.6,
		edge_damping = 20,
		shape_damping = 4,
		contact_damping = 30,
		held_damping = 2,
		friction = 0.6,
		substeps = 8,
		fill = 1,
	}
}

Balloon :: struct {
	cfg:           Config,
	vert_count:    int,
	edge_count:    int,
	face_count:    int,
	faces:         [MAX_FACES][3]u16, // counter-clockwise seen from outside
	edges:         [MAX_EDGES][2]u16,
	edge_rest:     [MAX_EDGES]f32,
	edge_inv_rest: [MAX_EDGES]f32,
	edge_alpha:    [MAX_EDGES]f32,
	unit_dir:      [MAX_VERTS]Vec3, // vertex directions on the unit sphere
	rest_pos:      [MAX_VERTS]Vec3, // rest shape, vertex mean at the origin
	knot:          [MAX_VERTS]f32, // 1 on the knot, fading to 0 on the neck
	pos:           [MAX_VERTS]Vec3,
	prev:          [MAX_VERTS]Vec3,
	vel:           [MAX_VERTS]Vec3,
	normal:        [MAX_VERTS]Vec3, // smooth normals, valid after update_normals
	area_vec:      [MAX_VERTS]Vec3, // volume gradient and pressure direction
	force:         [MAX_VERTS]Vec3,
	inv_mass:      [MAX_VERTS]f32, // 0 for the pinned vertex
	base_inv_mass: f32,
	center:        Vec3, // vertex mean from the last geometry pass
	rest_volume:   f32,
	target_volume: f32,
	tip_ring:       [MAX_VALENCE]u16, // the vertices that share an edge with the tip
	tip_ring_count: int,
	pin:           int,
	pin_target:    Vec3,
	pin_pos:       Vec3, // where the pinned vertex is held, trailing the target
	pin_vel:       Vec3,
	pin_speed:     f32, // fastest the pinned vertex may move
	pressure:      f32, // smoothed pressure the volume constraint is applying
	floor_y:       f32,
	half_extent:   f32, // walls at plus and minus this on x and z
	accel:         Vec3, // filtered acceleration of the balloon as a whole
	touching:      int, // most vertices pressed into the floor in one substep of this step
}

dot3 :: #force_inline proc "contextless" (a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

cross3 :: #force_inline proc "contextless" (a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

length3 :: #force_inline proc "contextless" (a: Vec3) -> f32 {
	return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
}

normalize3 :: #force_inline proc "contextless" (a: Vec3) -> Vec3 {
	l := length3(a)
	if l < 1e-12 {
		return {0, 1, 0}
	}
	return a / l
}

// Builds the mesh and the rest shape, and places the balloon at the origin at rest.
init :: proc(b: ^Balloon, cfg: Config) {
	b^ = {}
	b.cfg = cfg
	c := &b.cfg
	c.frequency = clamp(c.frequency, 2, MAX_FREQUENCY)
	c.substeps = clamp(c.substeps, 1, 32)

	geodesic_build(b, c.frequency)
	n := b.vert_count
	ring := geodesic_ring_angle(c.frequency)

	centroid: Vec3
	for i in 0 ..< n {
		p := shape_point(b.unit_dir[i], c, ring)
		b.rest_pos[i] = p
		centroid += p
	}
	centroid /= f32(n)
	for i in 0 ..< n {
		b.rest_pos[i] -= centroid
		theta := math.acos(clamp(b.unit_dir[i].y, -1, 1))
		b.knot[i] = clamp((2.2 - theta / ring) / 1.1, 0, 1)
	}

	for e in 0 ..< b.edge_count {
		ia, ib := int(b.edges[e][0]), int(b.edges[e][1])
		b.edge_rest[e] = length3(b.rest_pos[ia] - b.rest_pos[ib]) * c.prestretch
		b.edge_inv_rest[e] = 1 / b.edge_rest[e]
		k := 0.5 * (b.knot[ia] + b.knot[ib])
		b.edge_alpha[e] = c.edge_compliance + (c.knot_compliance - c.edge_compliance) * k
	}

	for e in 0 ..< b.edge_count {
		if b.edges[e][0] == TIP {
			b.tip_ring[b.tip_ring_count] = b.edges[e][1]
			b.tip_ring_count += 1
		}
	}

	b.base_inv_mass = f32(n) / c.mass
	b.floor_y = 0
	b.half_extent = 1e9
	b.pin = NO_PIN
	b.pin_speed = 40
	for i in 0 ..< n {
		b.pos[i] = b.rest_pos[i]
	}
	b.rest_volume = compute_geometry(b)
	b.target_volume = b.rest_volume * c.fill
	reset(b, {0, 0, 0})
}

// Puts the balloon back in its rest shape with its vertex mean at `center`.
reset :: proc(b: ^Balloon, center: Vec3) {
	for i in 0 ..< b.vert_count {
		p := b.rest_pos[i] + center
		b.pos[i] = p
		b.prev[i] = p
		b.vel[i] = {}
		b.inv_mass[i] = b.base_inv_mass
	}
	b.pin = NO_PIN
	b.accel = {}
	b.pressure = 0
	update_normals(b)
}

// Changes how much water the balloon holds, as a fraction of the rest volume.
set_fill :: proc(b: ^Balloon, fill: f32) {
	b.cfg.fill = max(fill, 0.05)
	b.target_volume = b.rest_volume * b.cfg.fill
}

// Holds `vertex` on its way to `target`. Call it every frame to drag.
pin :: proc(b: ^Balloon, vertex: int, target: Vec3) {
	if vertex < 0 || vertex >= b.vert_count {
		return
	}
	if b.pin != vertex {
		unpin(b)
		b.pin = vertex
		b.inv_mass[vertex] = 0
		b.pin_pos = b.pos[vertex]
		b.pin_vel = b.vel[vertex]
	}
	b.pin_target = target
}

// Lets go. The vertex keeps the velocity it had, so a drag turns into a throw.
unpin :: proc(b: ^Balloon) {
	if b.pin != NO_PIN {
		b.inv_mass[b.pin] = b.base_inv_mass
		b.pin = NO_PIN
	}
}

// Recomputes the area vector of every vertex and the enclosed volume. The area
// vector is a third of the summed area vectors of the faces around the vertex.
// It is the gradient of the volume with respect to the vertex, and the pull of
// a unit pressure on it. This and `substep` are written with plain floats
// rather than vector arithmetic because they run thousands of times a second,
// and the Android build is compiled with little optimization.
compute_geometry :: proc(b: ^Balloon) -> f32 #no_bounds_check {
	n := b.vert_count
	cx, cy, cz: f32
	for i in 0 ..< n {
		p := b.pos[i]
		cx += p.x
		cy += p.y
		cz += p.z
		b.area_vec[i] = {}
	}
	inv_n := 1 / f32(n)
	cx *= inv_n
	cy *= inv_n
	cz *= inv_n
	b.center = {cx, cy, cz}
	vol: f32
	for fi in 0 ..< b.face_count {
		t := b.faces[fi]
		ia, ib, ic := int(t[0]), int(t[1]), int(t[2])
		// Positions relative to the mean keep the sums small.
		pa, pb, pc := b.pos[ia], b.pos[ib], b.pos[ic]
		ax, ay, az := pa.x - cx, pa.y - cy, pa.z - cz
		bx, by, bz := pb.x - cx, pb.y - cy, pb.z - cz
		qx, qy, qz := pc.x - cx, pc.y - cy, pc.z - cz
		ux, uy, uz := bx - ax, by - ay, bz - az
		vx, vy, vz := qx - ax, qy - ay, qz - az
		sx := (uy * vz - uz * vy) * (1.0 / 6.0)
		sy := (uz * vx - ux * vz) * (1.0 / 6.0)
		sz := (ux * vy - uy * vx) * (1.0 / 6.0)
		area_a, area_b, area_c := b.area_vec[ia], b.area_vec[ib], b.area_vec[ic]
		b.area_vec[ia] = {area_a.x + sx, area_a.y + sy, area_a.z + sz}
		b.area_vec[ib] = {area_b.x + sx, area_b.y + sy, area_b.z + sz}
		b.area_vec[ic] = {area_c.x + sx, area_c.y + sy, area_c.z + sz}
		vol += ax * (by * qz - bz * qy) + ay * (bz * qx - bx * qz) + az * (bx * qy - by * qx)
	}
	return vol / 6
}

// Where the tip is, the way it points away from the body, and a sideways
// direction that turns with the knot as it twists.
tip_frame :: proc(b: ^Balloon) -> (apex, axis, side: Vec3) {
	apex = b.pos[TIP]
	c: Vec3
	for k in 0 ..< b.tip_ring_count {
		c += b.pos[b.tip_ring[k]]
	}
	c /= f32(b.tip_ring_count)
	axis = normalize3(apex - c)
	first := b.pos[b.tip_ring[0]] - c
	side = first - axis * dot3(first, axis)
	if length3(side) < 1e-6 {
		side = cross3(axis, {1, 0, 0})
		if length3(side) < 1e-6 {
			side = cross3(axis, {0, 0, 1})
		}
	}
	side = normalize3(side)
	return
}

// Fills `normal` with smooth outward vertex normals for rendering. Each normal
// is blended with its neighbors once, which hides the ridges that the long thin
// triangles of a stretched neck would otherwise show in the highlights.
update_normals :: proc(b: ^Balloon) {
	_ = compute_geometry(b)
	n := b.vert_count
	for i in 0 ..< n {
		b.normal[i] = normalize3(b.area_vec[i])
	}
	blended: [MAX_VERTS]Vec3
	for i in 0 ..< n {
		blended[i] = b.normal[i]
	}
	for e in 0 ..< b.edge_count {
		ia, ib := int(b.edges[e][0]), int(b.edges[e][1])
		blended[ia] += b.normal[ib] * 0.5
		blended[ib] += b.normal[ia] * 0.5
	}
	for i in 0 ..< n {
		b.normal[i] = normalize3(blended[i])
	}
}

// Advances the balloon by `dt` seconds. A step is split into cfg.substeps
// smaller ones, each with a single constraint pass.
step :: proc(b: ^Balloon, dt: f32) {
	if dt <= 0 {
		return
	}
	subs := b.cfg.substeps
	h := dt / f32(subs)
	v_start := mean_velocity(b)
	b.touching = 0
	for _ in 0 ..< subs {
		substep(b, h)
	}
	damp_edges(b, dt)
	damp_shape(b, dt)

	// The water follows the balloon's acceleration: it piles up on the side
	// the balloon is accelerating away from. Free fall cancels gravity, and a
	// hard stop adds to it.
	a_raw := (mean_velocity(b) - v_start) / dt
	limit := ACCEL_LIMIT * b.cfg.gravity
	if l := length3(a_raw); l > limit {
		a_raw *= limit / l
	}
	b.accel += (a_raw - b.accel) * min(1, dt / ACCEL_TAU)

	if !is_healthy(b) {
		pinned, target := b.pin, b.pin_target
		reset(b, {0, 1.5, 0})
		if pinned != NO_PIN {
			pin(b, pinned, target)
		}
	}
}

mean_velocity :: proc(b: ^Balloon) -> Vec3 #no_bounds_check {
	v: Vec3
	for i in 0 ..< b.vert_count {
		v += b.vel[i]
	}
	return v / f32(b.vert_count)
}

// One small step. Forces are applied to velocities, positions are predicted,
// then the edge and volume constraints pull the prediction back (XPBD), the
// floor and walls push it out, and velocities are rebuilt from the motion.
substep :: proc(b: ^Balloon, h: f32) #no_bounds_check {
	n := b.vert_count
	cfg := &b.cfg

	// Water pressure. In a frame that accelerates with the balloon, water
	// pressure grows linearly along g_eff. The sum of these forces is the
	// weight of the water, which the lumped vertex masses already carry, so
	// the net force is removed and only the redistribution is left. The area
	// vectors come from the end of the previous substep.
	g_eff := Vec3{-b.accel.x, -cfg.gravity - b.accel.y, -b.accel.z}
	if gain := cfg.droop * length3(g_eff) / cfg.gravity; gain > HYDRO_GAIN_MAX {
		g_eff *= HYDRO_GAIN_MAX / gain
	}
	rho := cfg.droop * cfg.mass / b.target_volume
	gx, gy, gz := g_eff.x * rho, g_eff.y * rho, g_eff.z * rho
	cx, cy, cz := b.center.x, b.center.y, b.center.z
	// The water cannot pull on the rubber: the total pressure stays above zero.
	least := -b.pressure
	nx, ny, nz: f32
	for i in 0 ..< n {
		p := b.pos[i]
		pressure := max(gx * (p.x - cx) + gy * (p.y - cy) + gz * (p.z - cz), least)
		a := b.area_vec[i]
		fx, fy, fz := a.x * pressure, a.y * pressure, a.z * pressure
		b.force[i] = {fx, fy, fz}
		nx += fx
		ny += fy
		nz += fz
	}
	inv_n := 1 / f32(n)
	sx, sy, sz := nx * inv_n, ny * inv_n, nz * inv_n

	damp := max(0, 1 - cfg.damping * h)
	push := b.base_inv_mass * h
	fall := cfg.gravity * h
	for i in 0 ..< n {
		f := b.force[i]
		v := b.vel[i]
		p := b.pos[i]
		vx := (v.x + (f.x - sx) * push) * damp
		vy := (v.y + (f.y - sy) * push - fall) * damp
		vz := (v.z + (f.z - sz) * push) * damp
		b.prev[i] = p
		b.pos[i] = {p.x + vx * h, p.y + vy * h, p.z + vz * h}
		b.vel[i] = {vx, vy, vz}
	}
	if b.pin != NO_PIN {
		// The held vertex follows its target like a critically damped spring,
		// so a yank is smooth and the speed is limited.
		b.pin_vel += ((b.pin_target - b.pin_pos) * (PIN_RESPONSE * PIN_RESPONSE) - b.pin_vel * (2 * PIN_RESPONSE)) * h
		if speed := length3(b.pin_vel); speed > b.pin_speed {
			b.pin_vel *= b.pin_speed / speed
		}
		b.pin_pos += b.pin_vel * h
		b.pos[b.pin] = b.pin_pos
	}

	// Rubber: one XPBD pass over the edges. The edges are ordered by color and
	// always swept in the same direction: alternating it makes a stiff, only
	// partly converged spot flip between two positions every substep.
	inv_h2 := 1 / (h * h)
	for k in 0 ..< b.edge_count {
		ia, ib := int(b.edges[k][0]), int(b.edges[k][1])
		wa, wb := b.inv_mass[ia], b.inv_mass[ib]
		wsum := wa + wb
		if wsum == 0 {
			continue
		}
		pa, pb := b.pos[ia], b.pos[ib]
		dx, dy, dz := pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
		len2 := dx * dx + dy * dy + dz * dz
		if len2 < 1e-18 {
			continue
		}
		len := math.sqrt(len2)
		strain := max(0, len * b.edge_inv_rest[k] - 1) * (1 / HARDEN_STRAIN)
		harden := 1 + strain * strain
		// Same as dividing the compliance by `harden`, with one division less.
		lambda := -(len - b.edge_rest[k]) * harden / (wsum * harden + b.edge_alpha[k] * inv_h2)
		scale := lambda / len
		ka, kb := wa * scale, wb * scale
		b.pos[ia] = {pa.x + dx * ka, pa.y + dy * ka, pa.z + dz * ka}
		b.pos[ib] = {pb.x - dx * kb, pb.y - dy * kb, pb.z - dz * kb}
	}

	// Water: one XPBD pass on the enclosed volume.
	vol := compute_geometry(b)
	denom := cfg.volume_compliance * inv_h2
	for i in 0 ..< n {
		a := b.area_vec[i]
		denom += b.inv_mass[i] * (a.x * a.x + a.y * a.y + a.z * a.z)
	}
	lambda: f32
	if denom > 1e-12 {
		lambda = -(vol - b.target_volume) / denom
		// The multiplier over h squared is the pressure holding the volume.
		b.pressure += (max(0, lambda * inv_h2) - b.pressure) * 0.2
	}

	// Apply the volume correction, then push out of the floor and walls, then
	// rebuild the velocity, in a single pass. Friction moves a vertex back
	// along the ground by at most friction times how deep it was pushed in.
	lim := b.half_extent
	floor := b.floor_y
	inv_h := 1 / h
	touching := 0
	for i in 0 ..< n {
		a := b.area_vec[i]
		k := b.inv_mass[i] * lambda
		p := b.pos[i]
		pv := b.prev[i]
		x, y, z := p.x + a.x * k, p.y + a.y * k, p.z + a.z * k
		if y < floor {
			touching += 1
			depth := floor - y
			y = floor
			dx, dz := x - pv.x, z - pv.z
			slide := math.sqrt(dx * dx + dz * dz)
			if slide > 1e-9 {
				grip := cfg.friction * depth
				back := slide if slide < grip else grip
				x -= dx / slide * back
				z -= dz / slide * back
			}
		}
		x = clamp(x, -lim, lim)
		z = clamp(z, -lim, lim)
		b.pos[i] = {x, y, z}
		b.vel[i] = {(x - pv.x) * inv_h, (y - pv.y) * inv_h, (z - pv.z) * inv_h}
	}
	b.touching = max(b.touching, touching)
	if b.pin != NO_PIN {
		b.pin_pos = b.pos[b.pin]
	}
}

// Removes a share of the speed at which edges lengthen or shorten. Rigid
// motion does not change edge lengths, so the balloon still flies and spins
// freely, while shape vibrations die out.
damp_edges :: proc(b: ^Balloon, dt: f32) #no_bounds_check {
	kd := min(1, b.cfg.edge_damping * dt)
	for e in 0 ..< b.edge_count {
		ia, ib := int(b.edges[e][0]), int(b.edges[e][1])
		wa, wb := b.inv_mass[ia], b.inv_mass[ib]
		wsum := wa + wb
		if wsum == 0 {
			continue
		}
		d := b.pos[ia] - b.pos[ib]
		len := length3(d)
		if len < 1e-9 {
			continue
		}
		dir := d / len
		closing := dot3(b.vel[ia] - b.vel[ib], dir) * kd / wsum
		b.vel[ia] -= dir * (closing * wa)
		b.vel[ib] += dir * (closing * wb)
	}
}

// Removes a share of the motion that is not rigid. The rigid part is the
// velocity of the center plus a spin about it, fitted to all vertices with
// equal weights. Whatever is left is a change of shape, and it is slowed no
// matter how large the part of the balloon that moves. Edge damping alone
// only slows small, fast wobbles.
damp_shape :: proc(b: ^Balloon, dt: f32) #no_bounds_check {
	n := b.vert_count
	c := center(b)
	v_mean := mean_velocity(b)
	ang: Vec3
	ixx, iyy, izz, ixy, ixz, iyz: f32
	for i in 0 ..< n {
		r := b.pos[i] - c
		ang += cross3(r, b.vel[i] - v_mean)
		rr := dot3(r, r)
		ixx += rr - r.x * r.x
		iyy += rr - r.y * r.y
		izz += rr - r.z * r.z
		ixy -= r.x * r.y
		ixz -= r.x * r.z
		iyz -= r.y * r.z
	}
	// Solve I * spin = ang for the 3 by 3 symmetric inertia matrix.
	c0 := Vec3{iyy * izz - iyz * iyz, ixz * iyz - ixy * izz, ixy * iyz - ixz * iyy}
	det := ixx * c0.x + ixy * c0.y + ixz * c0.z
	spin: Vec3
	if abs(det) > 1e-9 {
		c1 := Vec3{c0.y, ixx * izz - ixz * ixz, ixy * ixz - ixx * iyz}
		c2 := Vec3{c0.z, c1.z, ixx * iyy - ixy * ixy}
		spin = {dot3(c0, ang), dot3(c1, ang), dot3(c2, ang)} / det
	}
	// A landing pushes many vertices into the floor at once. Slowing the shape
	// hard then turns the impact into a splat instead of a bounce.
	contact := min(1, f32(b.touching) / (0.04 * f32(n)))
	k := min(1, (b.cfg.shape_damping + b.cfg.contact_damping * contact) * dt)
	for i in 0 ..< n {
		if i == b.pin {
			continue
		}
		rigid := v_mean + cross3(spin, b.pos[i] - c)
		b.vel[i] -= (b.vel[i] - rigid) * k
	}
	if b.pin == NO_PIN {
		return
	}
	// A held balloon would otherwise swing and twist for a long time, since
	// the held vertex only fixes a point. Drag its rigid motion against the hand.
	kh := min(1, b.cfg.held_damping * dt)
	v_hand := b.vel[b.pin]
	for i in 0 ..< n {
		if i == b.pin {
			continue
		}
		rigid := v_mean + cross3(spin, b.pos[i] - c)
		b.vel[i] -= (rigid - v_hand) * kh
	}
}

// Enclosed volume of the current shape.
volume :: proc(b: ^Balloon) -> f32 {
	return compute_geometry(b)
}

// Vertex mean of the current shape.
center :: proc(b: ^Balloon) -> Vec3 {
	c: Vec3
	for i in 0 ..< b.vert_count {
		c += b.pos[i]
	}
	return c / f32(b.vert_count)
}

// Corners of the box around all vertices.
bounds :: proc(b: ^Balloon) -> (lo, hi: Vec3) {
	lo = b.pos[0]
	hi = b.pos[0]
	for i in 1 ..< b.vert_count {
		lo = {min(lo.x, b.pos[i].x), min(lo.y, b.pos[i].y), min(lo.z, b.pos[i].z)}
		hi = {max(hi.x, b.pos[i].x), max(hi.y, b.pos[i].y), max(hi.z, b.pos[i].z)}
	}
	return
}

// Speed of the fastest vertex.
max_speed :: proc(b: ^Balloon) -> f32 {
	fastest: f32
	for i in 0 ..< b.vert_count {
		fastest = max(fastest, length3(b.vel[i]))
	}
	return fastest
}

// False if the shape has blown up: a position is not finite or far away, or
// the volume is far from the target.
is_healthy :: proc(b: ^Balloon) -> bool {
	if !is_finite(b) {
		return false
	}
	for i in 0 ..< b.vert_count {
		p := b.pos[i]
		if abs(p.x) > 1e4 || abs(p.y) > 1e4 || abs(p.z) > 1e4 {
			return false
		}
	}
	ratio := compute_geometry(b) / b.target_volume
	return ratio > HEALTHY_VOLUME_MIN && ratio < HEALTHY_VOLUME_MAX
}

// False if any position is NaN or infinite.
is_finite :: proc(b: ^Balloon) -> bool {
	sum: f32
	for i in 0 ..< b.vert_count {
		sum += b.pos[i].x + b.pos[i].y + b.pos[i].z
	}
	return !math.is_nan(sum) && !math.is_inf(sum)
}

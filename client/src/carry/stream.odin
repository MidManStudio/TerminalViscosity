// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stream.odin"
// ============================================================================

package carry

import "../lab"
import "../mpm"

STREAM_DX :: f32(0.03) // grid cell of the liquid simulation, in metres
STREAM_DT :: f32(8e-4) // length of one substep
STREAM_GRID :: 44 // cells along each side of the simulated box, 1.32 m
MAX_STREAM :: 96 // most particles in flight at once
DROP_ML :: f32(3.375) // the liquid one particle stands for: its cell cubed over eight
REST_SPEED :: f32(0.15) // below this a particle counts as lying still
PUDDLE_TIME :: f32(1.2) // seconds lying still before a particle is wiped away
DROP_LIFE :: f32(8) // seconds before any particle is wiped away
CAPTURE_PAD :: f32(0.05) // how far outside a vessel a falling drop still goes in
CAPTURE_ABOVE :: f32(0.12) // and how far above its rim, so aiming need not be exact
MAX_EVENTS :: 8

// Liquid in the air: poured from a vessel or a nozzle, falling, splashing, and
// either landing in a vessel, which takes it, or on a surface, where it is
// wiped away after a moment. The particles are simulated with the liquid
// simulation in a box that is set in the world when the first one is made.
Stream :: struct {
	sim:       mpm.Sim,
	compound:  [MAX_STREAM]u16,
	age:       [MAX_STREAM]f32,
	rest:      [MAX_STREAM]f32, // how long the particle has been lying still
	origin:    Vec3, // where the corner of the box is in the world
	air_floor: bool, // the box floor is above the real floor, so a particle reaching it falls out
}

stream_init :: proc(st: ^Stream) {
	params := mpm.Params {
		dx      = STREAM_DX,
		dt      = STREAM_DT,
		rho     = 1000,
		bulk    = 1e4,
		gravity = -9.8,
	}
	mpm.sim_init(&st.sim, params, STREAM_GRID, MAX_STREAM)
}

stream_destroy :: proc(st: ^Stream) {
	mpm.sim_destroy(&st.sim)
}

stream_remove :: proc(st: ^Stream, i: int) {
	last := st.sim.count - 1
	st.compound[i], st.age[i], st.rest[i] = st.compound[last], st.age[last], st.rest[last]
	mpm.sim_remove_particle(&st.sim, i)
}

stream_clear :: proc(st: ^Stream) {
	mpm.sim_clear(&st.sim)
}

// Makes a drop of `compound` at a place in the world, moving at `vel`. With no
// other drops in the air, the box is first set around the place, with its floor
// on whatever is under it. False if the stream is full or the place is outside
// the box.
stream_spawn :: proc(st: ^Stream, l: ^lab.Layout, world, vel: Vec3, compound: u16) -> bool {
	if st.sim.count >= MAX_STREAM {
		return false
	}
	dx := STREAM_DX
	span := f32(STREAM_GRID) * dx
	if st.sim.count == 0 {
		support := support_height(l, world.x, world.z, dx)
		floor := max(support, world.y - f32(STREAM_GRID - 8) * dx)
		st.air_floor = floor > support + 0.001
		// A particle comes to rest a little over three cells above the corner.
		st.origin = {world.x - span * 0.5, floor - 2.9 * dx, world.z - span * 0.5}
	}
	local := world - st.origin
	low := 3 * dx
	high := span - 3 * dx
	if local.x < low || local.x > high || local.y < low || local.y > high || local.z < low || local.z > high {
		return false
	}
	i := st.sim.count
	if !mpm.sim_add_particle(&st.sim, local, vel) {
		return false
	}
	st.compound[i], st.age[i], st.rest[i] = compound, 0, 0
	return true
}

// Where particle `i` is in the world.
stream_position :: proc(st: ^Stream, i: int) -> Vec3 {
	return st.origin + st.sim.particles[i].x
}

// Runs the simulation `steps` substeps, then wipes away what has fallen out of
// the box, lain still too long, or lived too long.
stream_step :: proc(st: ^Stream, steps: int) {
	if st.sim.count == 0 {
		return
	}
	for _ in 0 ..< steps {
		mpm.sim_step(&st.sim)
	}
	elapsed := f32(steps) * STREAM_DT
	for i := st.sim.count - 1; i >= 0; i -= 1 {
		p := st.sim.particles[i]
		st.age[i] += elapsed
		slow := p.v.x * p.v.x + p.v.y * p.v.y + p.v.z * p.v.z < REST_SPEED * REST_SPEED
		st.rest[i] = slow ? st.rest[i] + elapsed : 0
		fell_out := st.air_floor && p.x.y < 3.6 * STREAM_DX
		if fell_out || st.rest[i] > PUDDLE_TIME || st.age[i] > DROP_LIFE {
			stream_remove(st, i)
		}
	}
}

// Lets the vessels take the drops that have come to them. A drop inside a column
// a little wider than a vessel and reaching a little above its rim goes in. A
// vessel being poured from does not take drops, but one held upright does,
// which is how a vessel is filled under a nozzle. Reactions that need telling
// are put in `events`. Returns how many.
stream_capture :: proc(st: ^Stream, props: ^Props, eye: Vec3, events: ^[MAX_EVENTS]Mix_Result) -> int {
	n := 0
	for i := st.sim.count - 1; i >= 0; i -= 1 {
		w := stream_position(st, i)
		for v in 0 ..< props.count {
			pr := props.items[v]
			if v == props.held && pr.tilt > 0.05 {
				continue
			}
			d := kind_dims(pr.kind)
			dx, dz := w.x - pr.pos.x, w.z - pr.pos.z
			reach := d.radius + CAPTURE_PAD
			if dx * dx + dz * dz > reach * reach {
				continue
			}
			if w.y < pr.pos.y + 0.02 || w.y > pr.pos.y + d.height + CAPTURE_ABOVE {
				continue
			}
			r := apply_droplet(props, v, st.compound[i], DROP_ML, eye)
			if r.kind != .Nothing && n < MAX_EVENTS {
				events[n] = r
				n += 1
			}
			stream_remove(st, i)
			break
		}
	}
	return n
}

// The most a vessel lets out each second, in millilitres. A narrow neck is slow.
flow_max :: proc(k: Kind) -> f32 {
	switch k {
	case .Beaker:
		return 150
	case .Flask:
		return 90
	case .Bottle:
		return 70
	}
	return 100
}

// The velocity that carries a drop from `from` to `to` under gravity, in a flight
// of at least a fifth of a second and at no more than 1.5 m/s sideways. This is
// the aim assist of a pour: with the crosshair on a vessel, the stream is put
// into its mouth, however the lip happens to be placed.
arc_to :: proc(from, to: Vec3) -> Vec3 {
	flat := Vec3{to.x - from.x, 0, to.z - from.z}
	dist := sqrt_f32(dot(flat, flat))
	tau := max(0.2, dist / 1.5)
	vy := (to.y - from.y + 0.5 * 9.8 * tau * tau) / tau
	v := flat / tau + Vec3{0, vy, 0}
	speed := sqrt_f32(dot(v, v))
	if speed > 5 {
		v *= 5 / speed
	}
	return v
}

// Lets the held vessel pour. Liquid above what the tipped vessel can hold runs
// over its lip, as fast as its neck allows, and leaves as drops that start at the
// lip and move the way it faces. If the stream is full, the liquid waits at the
// lip, and the vessel pours no faster than the simulation can show.
pour_flow :: proc(props: ^Props, st: ^Stream, l: ^lab.Layout, dt: f32) {
	pour_flow_to(props, st, l, dt, {}, false)
}

// The same, and with no vessel under the crosshair to aim at, the stream is aimed at
// `mouth` when `has_mouth` is set. That is how a pour goes into the funnel of the
// balloon fill station.
pour_flow_to :: proc(props: ^Props, st: ^Stream, l: ^lab.Layout, dt: f32, mouth: Vec3, has_mouth: bool) {
	if props.held == -1 {
		return
	}
	pr := &props.items[props.held]
	if pr.tilt < 0.05 {
		// Put upright again: what was waiting at the lip runs back in.
		if pr.compound != 0 {
			pr.ml += pr.flow_acc
		}
		pr.flow_acc = 0
		return
	}
	if pr.ml <= 0 && pr.flow_acc <= 0 {
		pr.compound = 0
		return
	}
	excess := pr.ml - capacity_at_tilt(pr.kind, pr.tilt)
	if excess > 0 && pr.flow_acc < 2 * DROP_ML {
		q := min(excess, pr.ml, flow_max(pr.kind) * dt)
		pr.ml -= q
		pr.flow_acc += q
	}
	d := pour_dir(pr.yaw)
	lip := pr.pos + lip_offset(pr.kind, pr.tilt, d)
	speed := 0.3 + 0.8 * pr.tilt / TILT_MAX
	vel := d * speed + Vec3{0, -0.2, 0}
	if target := pour_target(props); target != -1 {
		t := props.items[target]
		vel = arc_to(lip, {t.pos.x, t.pos.y + kind_dims(t.kind).height + 0.03, t.pos.z})
	} else if has_mouth {
		vel = arc_to(lip, mouth)
	}
	// Drops let out in one frame are spread along their way, as if let out at
	// different moments, because two made in one place would push each other apart.
	count := int(pr.flow_acc / DROP_ML)
	for j in 0 ..< count {
		age := dt * f32(count - 1 - j) / f32(count)
		if !stream_spawn(st, l, lip + vel * age, vel, pr.compound) {
			break
		}
		pr.flow_acc -= DROP_ML
	}
	if pr.ml < 0.05 && pr.flow_acc < DROP_ML {
		pr.ml, pr.flow_acc, pr.compound = 0, 0, 0
	}
}

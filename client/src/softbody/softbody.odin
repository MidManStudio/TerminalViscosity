// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "softbody.odin"
// ============================================================================

// Package softbody is a 2D pressurized spring ring used for the balloon jiggle
// in the crafting lab. It has no raylib dependency, so it can be tested and
// benchmarked without a window.
package softbody

import "core:math/linalg"

Vec2 :: [2]f32

MAX_NODES :: 64

Ring :: struct {
	count:     int,
	pos:       [MAX_NODES]Vec2,
	prev:      [MAX_NODES]Vec2,
	rest_len:  f32, // target distance between neighbours
	rest_area: f32, // positive area the ring tries to keep
	rest_signed_area: f32, // same area with the sign of the node winding
	area_stiffness: f32, // 0..1, share of the area error corrected per constraint pass
	damping:   f32, // velocity kept per step, 1.0 means none lost
	gravity:   Vec2, // pixels per second squared
	floor_y:   f32, // nodes are kept at or above this y (screen y grows downward)
	iters:     int, // distance-constraint passes per step
}

// Builds a circle of `count` nodes in increasing angle order, which is
// clockwise on a y-down screen.
ring_init :: proc(r: ^Ring, center: Vec2, radius: f32, count := 24) {
	n := clamp(count, 3, MAX_NODES)
	r^ = {}
	r.count = n
	for i in 0 ..< n {
		a := f32(i) / f32(n) * 2 * linalg.PI
		p := center + Vec2{linalg.cos(a), linalg.sin(a)} * radius
		r.pos[i] = p
		r.prev[i] = p
	}
	r.rest_len = linalg.length(r.pos[1] - r.pos[0])
	r.rest_signed_area = ring_signed_area(r)
	r.rest_area = abs(r.rest_signed_area)
	r.area_stiffness = 0.35
	r.damping = 0.985
	r.gravity = {0, 900}
	r.floor_y = 1e9
	r.iters = 8
}

// Signed polygon area by the shoelace formula. The sign follows node winding.
ring_signed_area :: proc(r: ^Ring) -> f32 {
	sum: f32
	for i in 0 ..< r.count {
		a := r.pos[i]
		b := r.pos[(i + 1) % r.count]
		sum += a.x * b.y - b.x * a.y
	}
	return sum * 0.5
}

ring_area :: proc(r: ^Ring) -> f32 {
	return abs(ring_signed_area(r))
}

ring_center :: proc(r: ^Ring) -> Vec2 {
	c: Vec2
	for i in 0 ..< r.count {
		c += r.pos[i]
	}
	return c / f32(r.count)
}

// Index of the node closest to `p` within `max_dist`, or -1.
ring_nearest :: proc(r: ^Ring, p: Vec2, max_dist: f32) -> int {
	best := -1
	best_d := max_dist
	for i in 0 ..< r.count {
		d := linalg.length(r.pos[i] - p)
		if d <= best_d {
			best_d = d
			best = i
		}
	}
	return best
}

// Pushes nearby nodes away from `p`, like a fingertip poke.
ring_poke :: proc(r: ^Ring, p: Vec2, radius, strength: f32) {
	for i in 0 ..< r.count {
		d := r.pos[i] - p
		dist := linalg.length(d)
		if dist < radius && dist > 1e-4 {
			r.pos[i] += d / dist * strength * (1 - dist / radius)
		}
	}
}

// Position-based area constraint (Mueller et al.). Moves every node along the
// gradient of the polygon area so the area returns toward rest. Because it
// projects positions instead of applying a force, it cannot overshoot the way
// a stiff pressure force does when the ring is squashed against the floor.
apply_area_constraint :: proc(r: ^Ring) {
	n := r.count
	grads: [MAX_NODES]Vec2
	sum: f32
	for i in 0 ..< n {
		prev := r.pos[(i + n - 1) % n]
		next := r.pos[(i + 1) % n]
		g := Vec2{next.y - prev.y, prev.x - next.x} * 0.5
		grads[i] = g
		sum += g.x * g.x + g.y * g.y
	}
	if sum < 1e-9 {
		return
	}
	lambda := (ring_signed_area(r) - r.rest_signed_area) / sum * r.area_stiffness
	for i in 0 ..< n {
		r.pos[i] -= grads[i] * lambda
	}
}

// Advances the ring by `dt` seconds. Pass grab = -1 for no grabbed node;
// otherwise that node is pinned to `grab_to`.
ring_step :: proc(r: ^Ring, dt: f32, grab: int = -1, grab_to: Vec2 = {}) {
	n := r.count

	// Verlet integration. No node may travel more than one edge length per
	// step, which keeps a hard impact from throwing the ring across the screen.
	max_step := r.rest_len
	for i in 0 ..< n {
		cur := r.pos[i]
		vel := (cur - r.prev[i]) * r.damping
		if speed := linalg.length(vel); speed > max_step {
			vel *= max_step / speed
		}
		r.prev[i] = cur
		r.pos[i] = cur + vel + r.gravity * dt * dt
	}

	for _ in 0 ..< r.iters {
		// Keep neighbours at rest length by moving both ends halfway.
		for i in 0 ..< n {
			j := (i + 1) % n
			d := r.pos[j] - r.pos[i]
			dist := linalg.length(d)
			if dist < 1e-6 {
				continue
			}
			corr := d * (0.5 * (dist - r.rest_len) / dist)
			r.pos[i] += corr
			r.pos[j] -= corr
		}
		apply_area_constraint(r)
		for i in 0 ..< n {
			r.pos[i].y = min(r.pos[i].y, r.floor_y)
		}
		if grab >= 0 && grab < n {
			r.pos[grab] = grab_to
		}
	}
	if grab >= 0 && grab < n {
		r.prev[grab] = grab_to
	}
}

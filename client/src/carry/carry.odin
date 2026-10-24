// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "carry.odin"
// ============================================================================

// Package carry is everything about the things in the lab that the player can
// pick up: where they are, which one the crosshair points at, how one is held
// in front of the eyes, and where it comes to rest when let go. It also holds
// the shapes of those things and of the first-person hands. Units are metres.
// It has no raylib dependency, so it is tested without a window.
package carry

import "../lab"
import "core:math"

Vec3 :: [3]f32

MAX_PROPS :: 24
REACH :: f32(2.0) // how far from the eye a prop can be grabbed
AIM_PAD :: f32(0.05) // extra width around a prop for the crosshair test, so small things are easy to hit
HOLD_AHEAD :: f32(0.55) // where a held vessel sits, measured from the eye
HOLD_RIGHT :: f32(0.17)
HOLD_DOWN :: f32(0.20)
GRAVITY :: f32(9.8)

Kind :: enum u8 {
	Beaker,
	Flask,
	Bottle,
}

KIND_COUNT :: 3

// Footprint radius and height of a prop, in metres.
Dims :: struct {
	radius, height: f32,
}

kind_dims :: proc(k: Kind) -> Dims {
	switch k {
	case .Beaker:
		return {0.055, 0.13}
	case .Flask:
		return {0.07, 0.19}
	case .Bottle:
		return {0.045, 0.25}
	}
	return {0.05, 0.1}
}

// One thing that can be picked up. `pos` is the middle of its base.
Prop :: struct {
	kind: Kind,
	pos:  Vec3,
	yaw:  f32,
	vy:   f32, // how fast it is falling, in metres per second, while it settles
}

Props :: struct {
	items: [MAX_PROPS]Prop,
	count: int,
	held:  int, // index of the prop in the hands, or -1
	aimed: int, // index of the prop under the crosshair, or -1
}

// What the hands are doing, which also drives the crosshair and the button.
State :: enum {
	Idle, // nothing under the crosshair, nothing held
	Reaching, // something is under the crosshair and within reach
	Holding,
}

// The player's eye and the three directions of the view. `back` points toward
// the viewer, so `right`, `up` and `back` are a right-handed set, as in the
// camera's own frame.
View :: struct {
	eye, right, up, back: Vec3,
}

dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

view_of :: proc(p: ^lab.Player) -> View {
	forward := lab.player_forward(p)
	right := Vec3{math.cos(p.yaw), 0, math.sin(p.yaw)}
	back := -forward
	return {eye = {p.x, lab.EYE_HEIGHT, p.z}, right = right, up = cross(back, right), back = back}
}

props_init :: proc(props: ^Props) {
	props^ = {}
	props.held = -1
	props.aimed = -1
}

// Height of whatever a vessel at (x, z) would stand on: the counter top if any
// part of its footprint is over a counter, otherwise the floor. The layout's
// colliders are its counters.
support_height :: proc(l: ^lab.Layout, x, z, radius: f32) -> f32 {
	for i in 0 ..< l.collider_count {
		c := l.colliders[i]
		dx := x - clamp(x, c.min_x, c.max_x)
		dz := z - clamp(z, c.min_z, c.max_z)
		if dx * dx + dz * dz < radius * radius {
			return lab.COUNTER_HEIGHT
		}
	}
	return 0
}

// Adds a prop standing on whatever is under (x, z). False if the list is full.
props_add :: proc(props: ^Props, l: ^lab.Layout, kind: Kind, x, z: f32) -> bool {
	if props.count == MAX_PROPS {
		return false
	}
	d := kind_dims(kind)
	props.items[props.count] = {kind = kind, pos = {x, support_height(l, x, z, d.radius), z}}
	props.count += 1
	return true
}

// A first handful of vessels in two rows along the near edge of the island.
props_place_defaults :: proc(props: ^Props, l: ^lab.Layout) {
	front := [?]Kind{.Beaker, .Flask, .Bottle, .Beaker}
	back := [?]Kind{.Bottle, .Beaker, .Flask}
	for k, i in front {
		props_add(props, l, k, (f32(i) - 1.5) * 0.6, 0.38)
	}
	for k, i in back {
		props_add(props, l, k, (f32(i) - 1) * 0.6, -0.12)
	}
}

// Where a ray from `origin` along `dir` first enters the box from `lo` to
// `hi`. A hit behind the origin does not count.
ray_box :: proc(origin, dir, lo, hi: Vec3) -> (t: f32, hit: bool) {
	t_near := f32(0)
	t_far := f32(1e9)
	for axis in 0 ..< 3 {
		if abs(dir[axis]) < 1e-8 {
			if origin[axis] < lo[axis] || origin[axis] > hi[axis] {
				return 0, false
			}
			continue
		}
		inv := 1 / dir[axis]
		t0 := (lo[axis] - origin[axis]) * inv
		t1 := (hi[axis] - origin[axis]) * inv
		if t0 > t1 {
			t0, t1 = t1, t0
		}
		t_near = max(t_near, t0)
		t_far = min(t_far, t1)
		if t_near > t_far {
			return 0, false
		}
	}
	return t_near, true
}

// Whether a counter stands between the eye and the point `t` along the ray.
hidden_by_counter :: proc(l: ^lab.Layout, eye, dir: Vec3, t: f32) -> bool {
	for i in 0 ..< l.collider_count {
		c := l.colliders[i]
		tc, hit := ray_box(eye, dir, {c.min_x, 0, c.min_z}, {c.max_x, lab.COUNTER_HEIGHT, c.max_z})
		if hit && tc < t - 0.002 {
			return true
		}
	}
	return false
}

// The nearest prop under the crosshair within reach and not hidden behind a
// counter, or -1. The prop being held is never a candidate.
aim :: proc(props: ^Props, l: ^lab.Layout, v: View) -> int {
	dir := -v.back
	best := -1
	best_t := REACH
	for i in 0 ..< props.count {
		if i == props.held {
			continue
		}
		pr := props.items[i]
		d := kind_dims(pr.kind)
		reach := d.radius + AIM_PAD
		lo := Vec3{pr.pos.x - reach, pr.pos.y, pr.pos.z - reach}
		hi := Vec3{pr.pos.x + reach, pr.pos.y + d.height + AIM_PAD, pr.pos.z + reach}
		t, hit := ray_box(v.eye, dir, lo, hi)
		if hit && t < best_t && !hidden_by_counter(l, v.eye, dir, t) {
			best = i
			best_t = t
		}
	}
	return best
}

// Takes the prop under the crosshair, if the hands are empty.
grab :: proc(props: ^Props) -> bool {
	if props.held != -1 || props.aimed == -1 {
		return false
	}
	props.held = props.aimed
	props.items[props.held].vy = 0
	return true
}

// Lets go. The prop stays where it is and falls until something holds it up.
release :: proc(props: ^Props) {
	props.held = -1
}

// Puts the held prop at the hold point in front of the eyes, then keeps it
// out of the walls and the counters: inside the room, and never lower than the
// counter top when any of it is over a counter.
hold :: proc(pr: ^Prop, l: ^lab.Layout, v: View, yaw: f32) {
	d := kind_dims(pr.kind)
	centre := v.eye - v.back * HOLD_AHEAD + v.right * HOLD_RIGHT - v.up * HOLD_DOWN
	pos := Vec3{centre.x, centre.y - d.height * 0.5, centre.z}
	limit_x := lab.ROOM_W * 0.5 - d.radius
	limit_z := lab.ROOM_D * 0.5 - d.radius
	pos.x = clamp(pos.x, -limit_x, limit_x)
	pos.z = clamp(pos.z, -limit_z, limit_z)
	pos.y = clamp(max(pos.y, support_height(l, pos.x, pos.z, d.radius)), 0, lab.ROOM_H - d.height)
	pr.pos = pos
	pr.yaw = yaw
	pr.vy = 0
}

// Lets a prop that is not held fall until it stands on a counter or the floor.
settle :: proc(pr: ^Prop, l: ^lab.Layout, dt: f32) {
	floor := support_height(l, pr.pos.x, pr.pos.z, kind_dims(pr.kind).radius)
	if pr.pos.y <= floor + 1e-4 && pr.vy == 0 {
		pr.pos.y = floor
		return
	}
	pr.vy += GRAVITY * dt
	pr.pos.y -= pr.vy * dt
	if pr.pos.y <= floor {
		pr.pos.y = floor
		pr.vy = 0
	}
}

// One step of the carrying system. Call it after the player has moved.
update :: proc(props: ^Props, l: ^lab.Layout, p: ^lab.Player, dt: f32) {
	v := view_of(p)
	props.aimed = props.held == -1 ? aim(props, l, v) : -1
	for i in 0 ..< props.count {
		pr := &props.items[i]
		if i == props.held {
			hold(pr, l, v, p.yaw)
		} else {
			settle(pr, l, dt)
		}
	}
}

state_of :: proc(props: ^Props) -> State {
	if props.held != -1 {
		return .Holding
	}
	if props.aimed != -1 {
		return .Reaching
	}
	return .Idle
}

// Where the held vessel's middle is as seen from the eye (x right, y up, z
// toward the viewer, so ahead is negative), and how wide it is. With nothing
// held it is the spot where the hands would hold something.
grip_of :: proc(props: ^Props, v: View) -> (grip: Vec3, radius: f32) {
	if props.held != -1 {
		pr := props.items[props.held]
		d := kind_dims(pr.kind)
		c := Vec3{pr.pos.x, pr.pos.y + d.height * 0.5, pr.pos.z} - v.eye
		return {dot(c, v.right), dot(c, v.up), dot(c, v.back)}, d.radius
	}
	return {HOLD_RIGHT, -HOLD_DOWN, -HOLD_AHEAD}, 0.05
}

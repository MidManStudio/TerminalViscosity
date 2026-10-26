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

import "../chem"
import "../lab"
import "core:math"

Vec3 :: [3]f32

MAX_PROPS :: 24
REACH :: f32(2.0) // how far from the eye a prop can be grabbed
POUR_REACH :: f32(1.5) // how close a vessel must be to pour into it
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

// One thing that can be picked up. `pos` is the middle of its base. A vessel
// holds one compound at a time, as an id (0 for empty) and an amount.
Prop :: struct {
	kind:     Kind,
	pos:      Vec3,
	yaw:      f32,
	vy:       f32, // how fast it is falling, in metres per second, while it settles
	compound: u16,
	ml:       f32,
	tilt:     f32, // how far it is tipped over toward the way it faces, in radians
	flow_acc: f32, // liquid that has run over the lip and not yet left as drops, in ml
}

TILT_MAX :: f32(2.4) // about 137 degrees, nearly upside down, so a narrow neck can empty
TILT_RATE_IN :: f32(1.3) // radians a second while tipping it over
TILT_RATE_OUT :: f32(2.6) // and while putting it back

// A pour that is making two liquids meet. While drops of `src` keep arriving in
// vessel `target`, they join the product at once instead of reacting again, so a
// whole pour is one meeting. It ends when the drops stop for a moment.
Session :: struct {
	target:  int, // index of the vessel, or -1
	src:     u16,
	product: u16,
	timer:   f32, // seconds left before the pour counts as over
}

Props :: struct {
	items:   [MAX_PROPS]Prop,
	count:   int,
	held:    int, // index of the prop in the hands, or -1
	aimed:   int, // index of the prop under the crosshair, or -1
	aimed_t: f32, // how far along the view that prop is, in metres
	pouring: bool, // the pour button is down, so the held vessel is tipping over
	session: Session,
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

sqrt_f32 :: proc(x: f32) -> f32 {
	return math.sqrt(x)
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
	return {eye = {p.x, lab.player_eye_y(p), p.z}, right = right, up = cross(back, right), back = back}
}

props_init :: proc(props: ^Props) {
	props^ = {}
	props.held = -1
	props.aimed = -1
	props.session.target = -1
}

// The horizontal direction a vessel pours toward when held by a player facing `yaw`.
pour_dir :: proc(yaw: f32) -> Vec3 {
	return {math.sin(yaw), 0, -math.cos(yaw)}
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

// Adds a vessel standing on whatever is under (x, z), holding `ml` of a
// compound, which is cut down to what the vessel can hold. False if the list
// is full.
props_add :: proc(props: ^Props, l: ^lab.Layout, kind: Kind, x, z: f32, compound: u16 = 0, ml: f32 = 0) -> bool {
	if props.count == MAX_PROPS {
		return false
	}
	d := kind_dims(kind)
	amount := compound == 0 ? f32(0) : clamp(ml, 0, capacity_ml(kind))
	props.items[props.count] = {kind = kind, pos = {x, support_height(l, x, z, d.radius), z}, compound = compound, ml = amount}
	props.count += 1
	return true
}

// Takes a prop out of the list, as when a vessel breaks. The indices of the
// held and aimed props are kept pointing at the same props.
props_remove :: proc(props: ^Props, i: int) {
	for j in i ..< props.count - 1 {
		props.items[j] = props.items[j + 1]
	}
	props.count -= 1
	if props.held == i {
		props.held = -1
	} else if props.held > i {
		props.held -= 1
	}
	if props.aimed == i {
		props.aimed = -1
	} else if props.aimed > i {
		props.aimed -= 1
	}
	if props.session.target == i {
		props.session.target = -1
	} else if props.session.target > i {
		props.session.target -= 1
	}
}

// The vessels on the island: one filled with each stock liquid, in two rows
// along its near edge, and a third row and the ends of the first two left
// empty to pour into and mix in.
props_place_defaults :: proc(props: ^Props, l: ^lab.Layout) {
	id :: proc(s: chem.Id) -> u16 {
		return u16(s)
	}
	// Front row.
	props_add(props, l, .Beaker, -1.2, 0.40, id(.Water), 250)
	props_add(props, l, .Bottle, -0.6, 0.40, id(.Fizz_Acid), 600)
	props_add(props, l, .Bottle, 0, 0.40, id(.Soda_Base), 500)
	props_add(props, l, .Flask, 0.6, 0.40, id(.Ember_Oil), 450)
	props_add(props, l, .Flask, 1.2, 0.40, id(.Spark_Blue), 300)
	// Middle row.
	props_add(props, l, .Bottle, -1.2, -0.05, id(.Frost_Gel), 600)
	props_add(props, l, .Bottle, -0.6, -0.05, id(.Glue_Goo), 600)
	props_add(props, l, .Flask, 0, -0.05, id(.Slick), 400)
	props_add(props, l, .Beaker, 0.6, -0.05, id(.Dye_Red), 400)
	props_add(props, l, .Beaker, 1.2, -0.05, id(.Dye_Violet), 400)
	// Back row, all empty.
	props_add(props, l, .Beaker, -1.2, -0.50)
	props_add(props, l, .Flask, -0.6, -0.50)
	props_add(props, l, .Beaker, 0, -0.50)
	props_add(props, l, .Flask, 0.6, -0.50)
	props_add(props, l, .Beaker, 1.2, -0.50)
	// Empty ones at both ends of the front and middle rows.
	props_add(props, l, .Beaker, -1.8, 0.40)
	props_add(props, l, .Flask, 1.8, 0.40)
	props_add(props, l, .Beaker, -2.4, 0.40)
	props_add(props, l, .Bottle, 2.4, 0.40)
	props_add(props, l, .Beaker, -1.8, -0.05)
	props_add(props, l, .Beaker, 1.8, -0.05)
	props_add(props, l, .Flask, -2.4, -0.05)
	props_add(props, l, .Beaker, 2.4, -0.05)
}

// The props from the farthest to the nearest, for drawing see-through things
// in an order that blends right. Returns how many.
far_to_near :: proc(props: ^Props, eye: Vec3, out: ^[MAX_PROPS]int) -> int {
	dist: [MAX_PROPS]f32
	for i in 0 ..< props.count {
		out[i] = i
		d := props.items[i].pos - eye
		dist[i] = dot(d, d)
	}
	for i in 1 ..< props.count {
		for j := i; j > 0 && dist[out[j - 1]] < dist[out[j]]; j -= 1 {
			out[j - 1], out[j] = out[j], out[j - 1]
		}
	}
	return props.count
}

// The vessel the label should talk about: the held one, else the one under
// the crosshair, else -1.
focus :: proc(props: ^Props) -> int {
	return props.held != -1 ? props.held : props.aimed
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
aim :: proc(props: ^Props, l: ^lab.Layout, v: View) -> (index: int, distance: f32) {
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
	return best, best_t
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
	if props.held != -1 {
		props.items[props.held].tilt = 0
	}
	props.held = -1
	props.pouring = false
}

// Puts the held prop at the hold point in front of the eyes, tilted as far as
// it is, then keeps it out of the walls and the counters: inside the room, and
// never lower than the counter top when any of it is over a counter. It tips
// about its middle, so the middle stays where the hands are.
hold :: proc(pr: ^Prop, l: ^lab.Layout, v: View, yaw: f32) {
	d := kind_dims(pr.kind)
	sin_t, cos_t := math.sin(pr.tilt), math.cos(pr.tilt)
	half := d.height * 0.5
	reach_y := half * abs(cos_t) + d.radius * abs(sin_t) // how far it reaches up and down from its middle
	reach_xz := half * abs(sin_t) + d.radius * abs(cos_t) // and sideways
	centre := v.eye - v.back * HOLD_AHEAD + v.right * HOLD_RIGHT - v.up * HOLD_DOWN
	limit_x := lab.ROOM_W * 0.5 - reach_xz
	limit_z := lab.ROOM_D * 0.5 - reach_xz
	centre.x = clamp(centre.x, -limit_x, limit_x)
	centre.z = clamp(centre.z, -limit_z, limit_z)
	floor := support_height(l, centre.x, centre.z, reach_xz)
	centre.y = clamp(max(centre.y, floor + reach_y), reach_y, lab.ROOM_H - reach_y)
	axis, _ := tilt_axis(pour_dir(yaw), pr.tilt)
	pr.pos = centre - axis * half
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
	props.aimed, props.aimed_t = aim(props, l, v)
	props.session.timer -= dt
	if props.held != -1 {
		pr := &props.items[props.held]
		target := props.pouring ? TILT_MAX : 0
		if pr.tilt < target {
			pr.tilt = min(pr.tilt + TILT_RATE_IN * dt, target)
		} else {
			pr.tilt = max(pr.tilt - TILT_RATE_OUT * dt, target)
		}
	}
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

// The vessel to pour the held one into, or -1: the one under the crosshair, close
// enough, and with room in it. This is what the pour button needs to be ready.
pour_target :: proc(props: ^Props) -> int {
	if props.held == -1 || props.aimed == -1 || props.aimed_t > POUR_REACH {
		return -1
	}
	t := props.items[props.aimed]
	if t.ml >= capacity_ml(t.kind) - 0.5 {
		return -1
	}
	return props.aimed
}

// Where the held vessel's middle is as seen from the eye (x right, y up, z
// toward the viewer, so ahead is negative), and how wide it is. With nothing
// held it is the spot where the hands would hold something.
grip_of :: proc(props: ^Props, v: View) -> (grip: Vec3, radius: f32) {
	if props.held != -1 {
		pr := props.items[props.held]
		d := kind_dims(pr.kind)
		axis, _ := tilt_axis(pour_dir(pr.yaw), pr.tilt)
		c := pr.pos + axis * (d.height * 0.5) - v.eye
		return {dot(c, v.right), dot(c, v.up), dot(c, v.back)}, d.radius
	}
	return {HOLD_RIGHT, -HOLD_DOWN, -HOLD_AHEAD}, 0.05
}

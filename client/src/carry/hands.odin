// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "hands.odin"
// ============================================================================

package carry

import "core:math"

MAX_HAND_PARTS :: 12
LEFT :: 0
RIGHT :: 1

Mat3 :: matrix[3, 3]f32

// Which glove or sleeve color a part is drawn in.
Tone :: enum u8 {
	Glove,
	Sleeve,
}

// One box of a hand, in the camera's frame: x right, y up, z toward the viewer,
// so things ahead have a negative z. `size` is the full width of the box along
// each of its own axes, and `rot` turns those axes.
Part :: struct {
	center: Vec3,
	size:   Vec3,
	rot:    Mat3,
	tone:   Tone,
}

// A part placed in the world. `axes` are the box's three edges, already scaled
// by its size, and `origin` is its middle. They are a right-handed set, so the
// triangle winding of the unit cube survives.
Placed :: struct {
	axes:   [3]Vec3,
	origin: Vec3,
	tone:   Tone,
}

// How far the hands have moved toward their pose for the current state.
Hands :: struct {
	curl: [2]f32, // 0 fingers open, 1 closed in a grip
	lift: [2]f32, // 0 resting low at the bottom of the view, 1 raised to the vessel
}

rot_x :: proc(a: f32) -> Mat3 {
	c, s := math.cos(a), math.sin(a)
	return Mat3{1, 0, 0, 0, c, -s, 0, s, c}
}

rot_y :: proc(a: f32) -> Mat3 {
	c, s := math.cos(a), math.sin(a)
	return Mat3{c, 0, s, 0, 1, 0, -s, 0, c}
}

rot_z :: proc(a: f32) -> Mat3 {
	c, s := math.cos(a), math.sin(a)
	return Mat3{c, -s, 0, s, c, 0, 0, 0, 1}
}

// Turns by roll first, then pitch, then yaw. Pitch lifts the fingers when
// positive, and yaw turns the fingers toward the left when positive.
euler :: proc(e: Vec3) -> Mat3 {
	return rot_y(e.y) * rot_x(e.x) * rot_z(e.z)
}

approach :: proc(v: ^f32, target, dt: f32) {
	v^ += (target - v^) * (1 - math.exp(-14 * dt))
}

// Moves the hands toward the pose for the current state. The right hand does
// the carrying and the left one only follows a little.
hands_update :: proc(h: ^Hands, state: State, dt: f32) {
	curl := [2]f32{0.15, 0.15}
	lift := [2]f32{0, 0}
	switch state {
	case .Idle:
	case .Reaching:
		curl = {0.2, 0.3}
		lift = {0.1, 0.5}
	case .Holding:
		curl = {0.4, 1}
		lift = {0.4, 1}
	}
	for i in 0 ..< 2 {
		approach(&h.curl[i], curl[i], dt)
		approach(&h.lift[i], lift[i], dt)
	}
}

// The boxes of both hands. `grip` is where the held vessel's middle is, in the
// camera's frame, and `radius` how wide it is. Each hand is a sleeve, a palm,
// two finger segments that curl, and a thumb. The hand is built around its
// wrist and then turned and moved as one piece.
hand_parts :: proc(h: ^Hands, grip: Vec3, radius: f32, out: ^[MAX_HAND_PARTS]Part) -> int {
	n := 0
	for side in 0 ..< 2 {
		s := f32(side) * 2 - 1 // -1 for the left hand, +1 for the right
		lift, curl := h.lift[side], h.curl[side]
		rest_wrist := Vec3{s * 0.25, -0.31, -0.30}
		rest_rot := Vec3{0.35, 0, 0}
		hold_wrist, hold_rot: Vec3
		if side == RIGHT {
			// The palm against the right side of the vessel, fingers wrapping it.
			hold_wrist = grip + Vec3{radius + 0.018, 0, 0.045}
			hold_rot = {0, 0.1, -1.5}
		} else {
			hold_wrist = {-0.24, -0.29, -0.32}
			hold_rot = {0.3, 0, 0}
		}
		wrist := rest_wrist + (hold_wrist - rest_wrist) * lift
		r := euler(rest_rot + (hold_rot - rest_rot) * lift)

		// Everything below is in the hand's own frame, with the wrist at the
		// origin, the fingers toward -z and the back of the hand toward +y.
		a1 := curl * 1.25
		a2 := a1 + curl * 1.1
		f1, f2 := rot_x(-a1), rot_x(-a2)
		knuckle := Vec3{0, 0, -0.09}
		joint := knuckle + f1 * Vec3{0, 0, -0.052}
		thumb_yaw := s * (0.45 - 1.2 * curl)
		ty := rot_y(thumb_yaw)

		out[n] = {wrist + r * Vec3{0, -0.004, 0.15}, {0.07, 0.05, 0.30}, r, .Sleeve}
		out[n + 1] = {wrist + r * Vec3{0, 0, -0.045}, {0.085, 0.028, 0.09}, r, .Glove}
		out[n + 2] = {wrist + r * (knuckle + f1 * Vec3{0, 0, -0.026}), {0.082, 0.024, 0.052}, r * f1, .Glove}
		out[n + 3] = {wrist + r * (joint + f2 * Vec3{0, 0, -0.02}), {0.078, 0.022, 0.04}, r * f2, .Glove}
		out[n + 4] = {wrist + r * (Vec3{-s * 0.05, -0.004, -0.02} + ty * Vec3{0, 0, -0.026}), {0.03, 0.026, 0.052}, r * ty, .Glove}
		n += 5
	}
	return n
}

place_part :: proc(p: Part, v: View) -> Placed {
	axes: [3]Vec3
	for i in 0 ..< 3 {
		col := Vec3{p.rot[0, i], p.rot[1, i], p.rot[2, i]}
		axes[i] = (v.right * col.x + v.up * col.y + v.back * col.z) * p.size[i]
	}
	origin := v.eye + v.right * p.center.x + v.up * p.center.y + v.back * p.center.z
	return {axes, origin, p.tone}
}

// Both hands, placed in the world for drawing. Returns how many parts.
hands_place :: proc(h: ^Hands, v: View, grip: Vec3, radius: f32, out: ^[MAX_HAND_PARTS]Placed) -> int {
	parts: [MAX_HAND_PARTS]Part
	n := hand_parts(h, grip, radius, &parts)
	for i in 0 ..< n {
		out[i] = place_part(parts[i], v)
	}
	return n
}

// The three axes of a prop: to its right, along its length from base to mouth,
// and the one that completes a right-handed set. It faces the way a player
// looking along `yaw` faces, and is tipped over toward that way by `tilt`.
prop_axes :: proc(yaw, tilt: f32) -> [3]Vec3 {
	right := Vec3{math.cos(yaw), 0, math.sin(yaw)}
	axis, _ := tilt_axis(pour_dir(yaw), tilt)
	return {right, axis, cross(right, axis)}
}

// A prop in the world, turned and tipped, with its base at its position.
prop_placed :: proc(pr: ^Prop) -> Placed {
	return {axes = prop_axes(pr.yaw, pr.tilt), origin = pr.pos}
}

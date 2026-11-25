// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "input.odin"
// ============================================================================

package main

import "touch"
import rl "vendor:raylib"

MAX_POINTERS :: 5

// A finger on the screen, or the mouse while its button is held. The id stays
// the same for as long as it is down.
Pointer :: struct {
	id:  int,
	pos: [2]f32,
}

Pointers :: struct {
	items: [MAX_POINTERS]Pointer,
	count: int,
}

// Movement and look controls, from the touch package. On a phone the first finger down on
// the left half of the screen becomes a floating walking stick, wherever it lands, and the
// first finger down on the right half that is not on a button turns the view by how far it
// moves. A finger that lands on one of the on-screen buttons holds it, and a button listed in
// `aim_mask` (the throw pad) also turns the view as its finger moves. Every finger keeps the
// job it landed with until it lifts, and any number of buttons can be held at once. With a mouse
// there is no walking stick: a drag anywhere turns the view and the keyboard walks.
Controls :: struct {
	touch:        touch.State,
	stick:        [2]f32, // from -1 to 1, y is down, after the dead zone
	stick_active: bool,
	stick_anchor: [2]f32, // the middle of the ring, for drawing
	stick_knob:   [2]f32, // where the knob is, for drawing
	look_delta:   [2]f32, // pixels the view turns this frame: the look finger and any aiming button
	pressed:      u32, // bit i: a finger landed on button i this frame
	held:         u32, // bit i: a finger is down on button i
}

// Starts the controls. Any finger already down, such as the one that just tapped a button in
// the previous scene, is a spare finger until it lifts, so it cannot press anything in this scene.
controls_init :: proc(c: ^Controls, pointers: ^Pointers) {
	c^ = {}
	fingers: [MAX_POINTERS]touch.Finger
	touch.init(&c.touch, fingers_of(pointers, &fingers))
}

fingers_of :: proc(pointers: ^Pointers, fingers: ^[MAX_POINTERS]touch.Finger) -> []touch.Finger {
	for i in 0 ..< pointers.count {
		fingers[i] = {pointers.items[i].id, pointers.items[i].pos}
	}
	return fingers[:pointers.count]
}

// Whether a finger landed on button `i` this frame, and whether one is down on it.
button_pressed :: proc(c: ^Controls, i: int) -> bool {
	return c.pressed & (u32(1) << u32(i)) != 0
}

button_held :: proc(c: ^Controls, i: int) -> bool {
	return c.held & (u32(1) << u32(i)) != 0
}

// Where the finger that holds button `i` is now, if one does. It is the position the finger had in the last update.
button_finger :: proc(c: ^Controls, i: int) -> (pos: [2]f32, ok: bool) {
	for sl in c.touch.slots {
		if sl.used && sl.role == .Button && sl.button == i {
			return sl.last, true
		}
	}
	return {}, false
}

// Reads the pointers and updates the walking stick, the look and the buttons. `buttons` are boxes
// (x, y, width, height) that a finger can hold without walking or looking; the fingers on the
// ones in `aim_mask` (bit i for button i) turn the view too.
controls_update :: proc(c: ^Controls, pointers: ^Pointers, w, h: f32, buttons: [][4]f32, aim_mask: u32 = 0) {
	fingers: [MAX_POINTERS]touch.Finger
	out := touch.update(
		&c.touch,
		fingers_of(pointers, &fingers),
		{w = w, h = h, buttons = buttons, aim_mask = aim_mask, stick_enabled = ODIN_PLATFORM_SUBTARGET == .Android},
	)
	c.stick = out.stick
	c.stick_active = out.stick_active
	c.stick_anchor = out.anchor
	c.stick_knob = out.knob
	c.look_delta = out.look
	c.pressed = out.pressed
	c.held = out.held
}

// The ring where a thumb starts the walking stick, and the stick itself while held.
controls_draw :: proc(c: ^Controls, w, h: f32) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		radius := touch.stick_radius(h)
		if !c.stick_active {
			rl.DrawCircleLines(i32(w * 0.16), i32(h * 0.72), radius, {255, 255, 255, 50})
			return
		}
		ox, oy := i32(c.stick_anchor.x), i32(c.stick_anchor.y)
		rl.DrawCircle(ox, oy, radius, {255, 255, 255, 28})
		rl.DrawCircleLines(ox, oy, radius, {255, 255, 255, 90})
		rl.DrawCircle(i32(c.stick_knob.x), i32(c.stick_knob.y), radius * 0.42, {255, 255, 255, 120})
	}
}

// A small button in the top right corner for moving between scenes.
switch_button :: proc(w, h: f32) -> [4]f32 {
	size := max(f32(56), h * 0.1)
	return {w - size * 2.2 - 16, 16, size * 2.2, size}
}

draw_switch_button :: proc(w, h: f32, label: cstring) {
	b := switch_button(w, h)
	font := i32(b.w / 7)
	rl.DrawRectangle(i32(b.x), i32(b.y), i32(b.z), i32(b.w), {255, 255, 255, 36})
	rl.DrawRectangleLines(i32(b.x), i32(b.y), i32(b.z), i32(b.w), {255, 255, 255, 120})
	rl.DrawText(label, i32(b.x) + 12, i32(b.y + b.w * 0.5) - font / 2, font, rl.RAYWHITE)
}
